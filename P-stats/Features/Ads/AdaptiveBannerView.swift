import GoogleMobileAds
import SwiftUI
import UIKit

/// レイアウト用：GAD のアンカー付き適応バナー高さに合わせた枠（はみ出し・重なり防止）
enum AdaptiveBannerLayout {
    /// アンカー付きアダプティブの **SDK が返す高さ** と一致させる（これより低い枠にするとクリエイブが上下で見切れる）。
    static func slotHeight(forWidth width: CGFloat) -> CGFloat {
        let w = max(1, width)
        let raw = GADCurrentOrientationAnchoredAdaptiveBannerAdSizeWithWidth(w).size.height
        guard raw.isFinite, raw > 0 else { return 50 }
        return ceil(raw)
    }

    /// `safeAreaInset` 外でも近似余白が必要なとき用（幅はキーウィンドウ相当）
    static func referenceWindowWidth() -> CGFloat {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first
        guard let s = scene else { return 393 }
        return max(1, s.screen.bounds.width)
    }

    static func referenceSlotHeight() -> CGFloat {
        slotHeight(forWidth: referenceWindowWidth())
    }

    /// バナー直下〜タブドック手前までの隙間（`HomeView` 下端クローム積算用）
    static var chromeGapAboveTabDock: CGFloat { DesignTokens.AdaptiveBannerChrome.gapAboveTabDock }

    /// バナー枠の高さ＋ドックとの隙間（バナー非表示時は 0）
    static func bannerChromeTotalHeight(forWidth width: CGFloat, showBanner: Bool) -> CGFloat {
        guard showBanner else { return 0 }
        return slotHeight(forWidth: width) + chromeGapAboveTabDock
    }

    static func referenceBannerChromeTotalHeight(showBanner: Bool) -> CGFloat {
        guard showBanner else { return 0 }
        return referenceSlotHeight() + chromeGapAboveTabDock
    }
}

// MARK: - UIKit コンテナ（SwiftUI の高さ提案と GAD の実寸のずれによる見切れを防ぐ）

/// アンカー付きアダプティブを `layoutSubviews` で実幅に合わせ、`bounds` と一致させる。
final class AdaptiveBannerSlotContainerView: UIView, GADBannerViewDelegate {
    private let banner = GADBannerView(adSize: GADAdSizeBanner)
    private var lastSnappedLoadWidth: CGFloat = 0

    /// `true` のとき新規 `load` しない（入力フォーカス・ビュー非表示時）。既に表示中のクリエイティブはそのまま。
    var isAdLoadPaused: Bool = false {
        didSet {
            guard oldValue != isAdLoadPaused else { return }
            if oldValue, !isAdLoadPaused {
                lastSnappedLoadWidth = 0
            }
            setNeedsLayout()
        }
    }

    var adUnitID: String {
        didSet {
            guard oldValue != adUnitID else { return }
            banner.adUnitID = adUnitID
            lastSnappedLoadWidth = 0
            setNeedsLayout()
        }
    }

    init(adUnitID: String) {
        self.adUnitID = adUnitID
        super.init(frame: .zero)
        clipsToBounds = true
        /// クリエイティブより短いスロット内のレターボックスは親（SwiftUI の `.background`）に任せる
        backgroundColor = .clear
        banner.adUnitID = adUnitID
        banner.delegate = self
        banner.clipsToBounds = false
        banner.backgroundColor = .clear
        banner.rootViewController = Self.keyRootViewController()
        addSubview(banner)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil {
            lastSnappedLoadWidth = 0
            setNeedsLayout()
        }
    }

    private static func keyRootViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first
        return scene?.windows.first(where: \.isKeyWindow)?.rootViewController
    }

    private static func displayScale(for view: UIView) -> CGFloat {
        if let s = view.window?.windowScene?.screen.scale { return s }
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        if let s = scenes.first(where: {
            $0.activationState == .foregroundActive || $0.activationState == .foregroundInactive
        }) {
            return s.screen.scale
        }
        return scenes.first?.screen.scale ?? 3.0
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        banner.rootViewController = Self.keyRootViewController()
        let w = max(1, bounds.width)
        let scale = Self.displayScale(for: self)
        let snapped = (w * scale).rounded(.down) / scale
        let adSize = GADCurrentOrientationAnchoredAdaptiveBannerAdSizeWithWidth(snapped)
        let h = ceil(adSize.size.height)
        banner.adSize = adSize
        banner.frame = CGRect(x: 0, y: 0, width: w, height: h)
        guard !isAdLoadPaused, window != nil else { return }
        if abs(snapped - lastSnappedLoadWidth) >= 0.5 {
            lastSnappedLoadWidth = snapped
            banner.load(GADRequest())
        }
    }

    override var intrinsicContentSize: CGSize {
        let w = bounds.width > 1 ? bounds.width : AdaptiveBannerLayout.referenceWindowWidth()
        let h = AdaptiveBannerLayout.slotHeight(forWidth: max(1, w))
        return CGSize(width: UIView.noIntrinsicMetric, height: h)
    }

    func bannerViewDidReceiveAd(_ bannerView: GADBannerView) {
        invalidateIntrinsicContentSize()
    }
}

/// `AdaptiveBannerSlot` 用。`sizeThatFits` と UIKit レイアウトで縦幅を SDK と一致させる。
struct AdaptiveBannerSlotRepresentable: UIViewRepresentable {
    let adUnitID: String
    /// 親からの一時停止（入力フォーカス等）。SwiftUI の `onDisappear` と併用する場合は `AdaptiveBannerSlot` 側で合成する。
    var pauseAdRefresh: Bool = false

    func makeUIView(context: Context) -> AdaptiveBannerSlotContainerView {
        AdaptiveBannerSlotContainerView(adUnitID: adUnitID)
    }

    func updateUIView(_ uiView: AdaptiveBannerSlotContainerView, context: Context) {
        uiView.adUnitID = adUnitID
        uiView.isAdLoadPaused = pauseAdRefresh
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: AdaptiveBannerSlotContainerView, context: Context) -> CGSize? {
        let w: CGFloat = {
            if let pw = proposal.width, pw.isFinite, pw > 1 { return pw }
            return AdaptiveBannerLayout.referenceWindowWidth()
        }()
        let ww = max(1, w)
        let h = AdaptiveBannerLayout.slotHeight(forWidth: ww)
        return CGSize(width: ww, height: h)
    }
}

/// アンカー付きアダプティブバナー（ホームのタブバー直上など）
struct AdaptiveBannerView: UIViewRepresentable {
    let adUnitID: String
    let width: CGFloat

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> GADBannerView {
        let banner = GADBannerView(adSize: GADAdSizeBanner)
        banner.adUnitID = adUnitID
        banner.delegate = context.coordinator
        banner.rootViewController = Self.topViewController()
        /// アンカー付きアダプティブは `adSize` の高さまで描画する。`true` だと SwiftUI からの一時的な誤提案でクリエイブが欠けることがある。
        banner.clipsToBounds = false
        banner.backgroundColor = .clear
        return banner
    }

    /// SwiftUI にバナー縦幅を伝え、`frame` 提案と UIView の実寸のズレを減らす（未実装だと見切れの原因になり得る）。
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: GADBannerView, context: Context) -> CGSize? {
        let w: CGFloat = {
            if let pw = proposal.width, pw.isFinite, pw > 1 { return pw }
            return AdaptiveBannerLayout.referenceWindowWidth()
        }()
        let h = AdaptiveBannerLayout.slotHeight(forWidth: w)
        return CGSize(width: w, height: h)
    }

    func updateUIView(_ banner: GADBannerView, context: Context) {
        banner.rootViewController = Self.topViewController()
        guard width > 0 else { return }
        let scale = Self.displayScale(for: banner)
        let snapped = (width * scale).rounded(.down) / scale
        if abs(snapped - context.coordinator.lastLoadedWidth) < 0.5 { return }
        context.coordinator.lastLoadedWidth = snapped
        banner.adSize = GADCurrentOrientationAnchoredAdaptiveBannerAdSizeWithWidth(snapped)
        banner.load(GADRequest())
    }

    private static func topViewController() -> UIViewController? {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene else { return nil }
        return scene.windows.first(where: \.isKeyWindow)?.rootViewController
    }

    /// iOS 26+ では `UIScreen.main` が非推奨のため、`UIWindowScene.screen` から解決する。
    private static func displayScale(for banner: GADBannerView) -> CGFloat {
        if let screen = banner.window?.windowScene?.screen {
            return screen.scale
        }
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        if let foreground = scenes.first(where: {
            $0.activationState == .foregroundActive || $0.activationState == .foregroundInactive
        }) {
            return foreground.screen.scale
        }
        if let any = scenes.first {
            return any.screen.scale
        }
        return 3.0
    }

    final class Coordinator: NSObject, GADBannerViewDelegate {
        var lastLoadedWidth: CGFloat = 0
    }
}

/// ホーム下端・オーバーレイ等で使うバナー枠（UIKit で実寸レイアウトし見切れを防ぐ）。
struct AdaptiveBannerSlot: View {
    let adUnitID: String
    /// 親画面の状態に応じた一時停止（例: 実戦でインサイト・シート表示中）
    var pauseAdRefresh: Bool = false

    /// SwiftUI ツリー上で非表示になった間は読み込みを止める（`pauseAdRefresh` と合成）
    @State private var isAttachedInSwiftUITree = true

    private var effectivePauseAdRefresh: Bool {
        pauseAdRefresh || !isAttachedInSwiftUITree
    }

    var body: some View {
        AdaptiveBannerSlotRepresentable(adUnitID: adUnitID, pauseAdRefresh: effectivePauseAdRefresh)
            .frame(maxWidth: .infinity)
            .onAppear {
                isAttachedInSwiftUITree = true
            }
            .onDisappear {
                isAttachedInSwiftUITree = false
            }
    }
}

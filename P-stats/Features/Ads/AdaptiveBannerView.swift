import GoogleMobileAds
import SwiftUI
import UIKit

/// レイアウト用：GAD のアンカー付き適応バナー高さに合わせた枠（はみ出し・重なり防止）
enum AdaptiveBannerLayout {
    /// 縦を抑えつつクリップ許容する上限（pt）。省スペース優先。
    static let maxSlotHeight: CGFloat = 56

    static func slotHeight(forWidth width: CGFloat) -> CGFloat {
        let w = max(1, width)
        let raw = GADCurrentOrientationAnchoredAdaptiveBannerAdSizeWithWidth(w).size.height
        var h = raw.isFinite && raw > 0 ? ceil(raw) : 50
        h = min(h, maxSlotHeight)
        return h
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
        banner.clipsToBounds = true
        banner.backgroundColor = .clear
        return banner
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

/// 広告を指定高の枠に収め、他ビューの上へはみ出さない（`safeAreaInset` 内で使用）
struct AdaptiveBannerSlot: View {
    let adUnitID: String

    @State private var slotHeight: CGFloat = AdaptiveBannerLayout.referenceSlotHeight()

    var body: some View {
        Color.clear
            .frame(height: slotHeight)
            .frame(maxWidth: .infinity)
            .clipped()
            .overlay {
                GeometryReader { geo in
                    let w = max(1, geo.size.width)
                    let h = AdaptiveBannerLayout.slotHeight(forWidth: w)
                    AdaptiveBannerView(adUnitID: adUnitID, width: w)
                        .frame(width: w, height: h, alignment: .center)
                        .clipped()
                        .frame(width: geo.size.width, height: h, alignment: .center)
                }
            }
            .clipped()
            .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { _, newWidth in
                slotHeight = AdaptiveBannerLayout.slotHeight(forWidth: newWidth)
            }
    }
}

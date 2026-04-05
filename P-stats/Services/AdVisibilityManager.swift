import Combine
import Foundation

/// バナー広告の表示可否（`EntitlementsStore` と同期）。レイアウト用の余白高さもここから参照する。
@MainActor
final class AdVisibilityManager: ObservableObject {
    static let shared = AdVisibilityManager()

    /// `EntitlementsStore.shouldShowAds` と同値
    @Published private(set) var shouldShowBanner: Bool = true

    /// バナー枠＋タブドック直上の隙間（ホーム下端クロームと同じ積算）
    var bannerReserveHeight: CGFloat {
        AdaptiveBannerLayout.referenceBannerChromeTotalHeight(showBanner: shouldShowBanner)
    }

    private init() {
        syncFromEntitlements()
    }

    func syncFromEntitlements() {
        let next = EntitlementsStore.shared.shouldShowAds
        if shouldShowBanner != next {
            shouldShowBanner = next
        }
    }
}

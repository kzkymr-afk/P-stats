import SwiftUI

/// タブバーが無いモーダル（実戦から開く履歴・分析など）の下にバナーのみ載せる
private struct PlayOverlayBottomBannerInsetModifier: ViewModifier {
    @ObservedObject private var adVisibility = AdVisibilityManager.shared

    func body(content: Content) -> some View {
        content.safeAreaInset(edge: .bottom, spacing: 0) {
            if adVisibility.shouldShowBanner {
                AdaptiveBannerSlot(adUnitID: AdMobConfig.bannerUnitID)
                    .frame(maxWidth: .infinity)
                    .background(Color.black)
            }
        }
    }
}

extension View {
    /// 実戦の `fullScreenCover` 内で、ホームのドック直上バナーに相当するスペースを確保する
    func playOverlayBottomAdInset() -> some View {
        modifier(PlayOverlayBottomBannerInsetModifier())
    }
}

import GoogleMobileAds
import UIKit

/// 遊技保存完了後のインタースティシャル（`AdMobConfig.interstitialUnitID`）。
@MainActor
enum SessionEndInterstitialPresenter {
    private final class InterstitialFlow: NSObject, GADFullScreenContentDelegate {
        private var interstitial: GADInterstitialAd?
        private var done: (() -> Void)?

        func start(adUnitID: String, onComplete: @escaping () -> Void) {
            done = onComplete
            GADInterstitialAd.load(withAdUnitID: adUnitID, request: GADRequest()) { ad, error in
                Task { @MainActor in
                    if error != nil {
                        self.finish()
                        return
                    }
                    guard let ad else {
                        self.finish()
                        return
                    }
                    self.interstitial = ad
                    ad.fullScreenContentDelegate = self
                    guard let root = InterstitialFlow.keyRootViewController() else {
                        self.finish()
                        return
                    }
                    ad.present(fromRootViewController: root)
                }
            }
        }

        func adDidDismissFullScreenContent(_ ad: GADFullScreenPresentingAd) {
            interstitial = nil
            finish()
        }

        func ad(_ ad: GADFullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: Error) {
            interstitial = nil
            finish()
        }

        private func finish() {
            done?()
            done = nil
            interstitial = nil
        }

        fileprivate static func keyRootViewController() -> UIViewController? {
            let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            let scene = scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first
            return scene?.windows.first(where: \.isKeyWindow)?.rootViewController
        }
    }

    private static var current: InterstitialFlow?

    static func presentAfterSaveIfNeeded(onComplete: @escaping () -> Void) {
        guard AdVisibilityManager.shared.shouldShowBanner else {
            onComplete()
            return
        }
        guard AdFrequencyCoordinator.canPresentSessionEndInterstitial() else {
            onComplete()
            return
        }
        let flow = InterstitialFlow()
        current = flow
        let unitID = AdMobConfig.interstitialUnitID
        flow.start(adUnitID: unitID) {
            current = nil
            AdFrequencyCoordinator.markInterstitialFlowEnded()
            onComplete()
        }
    }
}

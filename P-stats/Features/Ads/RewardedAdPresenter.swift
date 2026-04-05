import GoogleMobileAds
import UIKit

/// 分析トライアル用リワード広告（`AdMobConfig.rewardedAdUnitID`）。
@MainActor
enum RewardedAdPresenter {
    private final class RewardFlow: NSObject, GADFullScreenContentDelegate {
        private var rewarded: GADRewardedAd?
        private var onComplete: ((Bool) -> Void)?
        private var userEarnedReward = false
        private var reported = false

        func loadAndPresent(onComplete: @escaping (Bool) -> Void) {
            self.onComplete = onComplete
            userEarnedReward = false
            reported = false
            GADRewardedAd.load(withAdUnitID: AdMobConfig.rewardedAdUnitID, request: GADRequest()) { ad, error in
                Task { @MainActor in
                    if error != nil || ad == nil {
                        self.report(earned: false)
                        return
                    }
                    guard let ad else {
                        self.report(earned: false)
                        return
                    }
                    self.rewarded = ad
                    ad.fullScreenContentDelegate = self
                    guard let root = Self.keyRootViewController() else {
                        self.report(earned: false)
                        return
                    }
                    ad.present(fromRootViewController: root, userDidEarnRewardHandler: {
                        self.userEarnedReward = true
                        RewardedAnalyticsTrialController.shared.grantAdditionalTrialFromReward()
                    })
                }
            }
        }

        func adDidDismissFullScreenContent(_ ad: GADFullScreenPresentingAd) {
            rewarded = nil
            report(earned: userEarnedReward)
        }

        func ad(_ ad: GADFullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: Error) {
            rewarded = nil
            report(earned: false)
        }

        private func report(earned: Bool) {
            guard !reported else { return }
            reported = true
            let cb = onComplete
            onComplete = nil
            rewarded = nil
            cb?(earned)
        }

        fileprivate static func keyRootViewController() -> UIViewController? {
            let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            let scene = scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first
            return scene?.windows.first(where: \.isKeyWindow)?.rootViewController
        }
    }

    private static var current: RewardFlow?

    /// `onComplete(true)` は報酬コールバックが実行された場合（トライアル付与済み）。
    static func presentForAnalyticsTrialReward(onComplete: @escaping (Bool) -> Void) {
        let flow = RewardFlow()
        current = flow
        flow.loadAndPresent { earned in
            current = nil
            onComplete(earned)
        }
    }
}

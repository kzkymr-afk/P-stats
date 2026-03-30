import Foundation
import GoogleMobileAds
import UIKit

/// アプリ起動広告（App Open）。冷起動はプロセス内 1 回まで、バックグラウンド復帰は最低間隔を空けて試行。
/// 遊技 fullScreen 中・インタースティシャル直後は表示しない。
@MainActor
enum AppOpenAdPresenter {
    private static let lastPresentedKey = "AdAppOpenLastPresentationAt"

    private final class Flow: NSObject, GADFullScreenContentDelegate {
        private var appOpenAd: GADAppOpenAd?
        private var onReleased: (() -> Void)?
        private let recordResumeThrottleOnClose: Bool

        init(recordResumeThrottleOnClose: Bool) {
            self.recordResumeThrottleOnClose = recordResumeThrottleOnClose
            super.init()
        }

        func loadAndPresent(onReleased: @escaping () -> Void) {
            self.onReleased = onReleased
            GADAppOpenAd.load(withAdUnitID: AdMobConfig.appOpenUnitID, request: GADRequest()) { ad, error in
                Task { @MainActor in
                    if error != nil {
                        self.releaseFlow(recordResumeThrottle: false)
                        return
                    }
                    guard let ad else {
                        self.releaseFlow(recordResumeThrottle: false)
                        return
                    }
                    self.appOpenAd = ad
                    ad.fullScreenContentDelegate = self
                    guard let root = Flow.keyRootViewController() else {
                        self.releaseFlow(recordResumeThrottle: false)
                        return
                    }
                    ad.present(fromRootViewController: root)
                }
            }
        }

        func presentPreloaded(_ ad: GADAppOpenAd, onReleased: @escaping () -> Void) {
            self.onReleased = onReleased
            appOpenAd = ad
            ad.fullScreenContentDelegate = self
            guard let root = Flow.keyRootViewController() else {
                releaseFlow(recordResumeThrottle: false)
                return
            }
            ad.present(fromRootViewController: root)
        }

        func adDidDismissFullScreenContent(_ ad: GADFullScreenPresentingAd) {
            appOpenAd = nil
            releaseFlow(recordResumeThrottle: true)
        }

        func ad(_ ad: GADFullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: Error) {
            appOpenAd = nil
            releaseFlow(recordResumeThrottle: true)
        }

        private func releaseFlow(recordResumeThrottle: Bool) {
            if recordResumeThrottle, recordResumeThrottleOnClose {
                UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: lastPresentedKey)
            }
            onReleased?()
            onReleased = nil
            appOpenAd = nil
        }

        fileprivate static func keyRootViewController() -> UIViewController? {
            let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            let scene = scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first
            return scene?.windows.first(where: \.isKeyWindow)?.rootViewController
        }
    }

    private static var activeFlow: Flow?
    private static var preloaded: GADAppOpenAd?
    private static var coldStartConsumedThisProcess = false
    private static var isPresenting = false

    private static func shouldBlockPresentation() -> Bool {
        if AdPresentationGate.shared.isPlaySessionBlockingAppOpen { return true }
        if AdFrequencyCoordinator.shouldSuppressAppOpenForInterstitialCooldown() { return true }
        return false
    }

    /// 広告 SDK 初期化後など、ホーム表示前に先行ロードする。
    static func preload() {
        guard AdVisibilityManager.shared.shouldShowBanner else { return }
        guard preloaded == nil, activeFlow == nil else { return }
        GADAppOpenAd.load(withAdUnitID: AdMobConfig.appOpenUnitID, request: GADRequest()) { ad, error in
            Task { @MainActor in
                guard error == nil, let ad else { return }
                guard preloaded == nil else { return }
                preloaded = ad
            }
        }
    }

    /// スプラッシュ後・ロック解除後に 1 度だけ。
    static func requestColdStartIfNeeded() {
        guard !coldStartConsumedThisProcess else { return }
        guard AdVisibilityManager.shared.shouldShowBanner else {
            coldStartConsumedThisProcess = true
            return
        }
        if AdPresentationGate.shared.isPlaySessionBlockingAppOpen {
            return
        }
        if AdFrequencyCoordinator.shouldSuppressAppOpenForInterstitialCooldown() {
            coldStartConsumedThisProcess = true
            return
        }
        coldStartConsumedThisProcess = true
        startPresentation(recordResumeThrottleOnClose: true)
    }

    /// バックグラウンドからの復帰。前回表示から `AdPolicy.appOpenResumeMinIntervalSeconds` 以上経過していれば試行。
    static func tryPresentAfterResumeFromBackgroundIfNeeded() {
        guard AdVisibilityManager.shared.shouldShowBanner else { return }
        guard !shouldBlockPresentation() else { return }
        let last = UserDefaults.standard.double(forKey: lastPresentedKey)
        guard last > 0 else { return }
        guard Date().timeIntervalSince1970 - last >= AdPolicy.appOpenResumeMinIntervalSeconds else { return }
        startPresentation(recordResumeThrottleOnClose: true)
    }

    private static func startPresentation(recordResumeThrottleOnClose: Bool) {
        guard !isPresenting else { return }
        isPresenting = true

        let finish: () -> Void = {
            isPresenting = false
            activeFlow = nil
            preload()
        }

        if let ad = preloaded {
            preloaded = nil
            let flow = Flow(recordResumeThrottleOnClose: recordResumeThrottleOnClose)
            activeFlow = flow
            flow.presentPreloaded(ad, onReleased: finish)
            return
        }

        let flow = Flow(recordResumeThrottleOnClose: recordResumeThrottleOnClose)
        activeFlow = flow
        flow.loadAndPresent(onReleased: finish)
    }
}

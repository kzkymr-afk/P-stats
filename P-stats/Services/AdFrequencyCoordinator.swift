import Foundation

/// フルスクリーン広告の頻度・連鎖防止（インタースティシャル終了直後の App Open 抑止など）。
@MainActor
enum AdFrequencyCoordinator {
    private static var lastInterstitialFlowEndKey: String { UserDefaultsKey.adFreqLastInterstitialFlowEndAt.rawValue }

    /// インタースティシャルのロード〜終了までの一式が完了したときに呼ぶ（ロード失敗も含む）。
    static func markInterstitialFlowEnded() {
        let t = Date().timeIntervalSince1970
        UserDefaults.standard.set(t, forKey: lastInterstitialFlowEndKey)
    }

    static func canPresentSessionEndInterstitial() -> Bool {
        let last = UserDefaults.standard.double(forKey: lastInterstitialFlowEndKey)
        guard last > 0 else { return true }
        return Date().timeIntervalSince1970 - last >= AdPolicy.interstitialMinimumIntervalSeconds
    }

    /// 直近にインタースティシャル系が終了していて、App Open を抑止すべきか。
    static func shouldSuppressAppOpenForInterstitialCooldown() -> Bool {
        let last = UserDefaults.standard.double(forKey: lastInterstitialFlowEndKey)
        guard last > 0 else { return false }
        return Date().timeIntervalSince1970 - last < AdPolicy.appOpenAfterInterstitialCooldownSeconds
    }
}

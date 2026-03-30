import Foundation

/// 広告の間隔・密度。`UserDefaults` で上書き可能（未設定時は既定値）。
enum AdPolicy {
    private static let defaults = UserDefaults.standard

    private enum Key {
        static let nativeSessionsBeforeNative = "adPolicy.nativeSessionsBeforeNative"
        static let nativeHideWhenSessionCountAtMost = "adPolicy.nativeHideWhenSessionCountAtMost"
        static let appOpenResumeSeconds = "adPolicy.appOpenResumeSeconds"
        static let appOpenAfterInterstitialCooldown = "adPolicy.appOpenAfterInterstitialCooldown"
        static let interstitialMinimumInterval = "adPolicy.interstitialMinimumInterval"
    }

    /// セッションカード何枚ごとにネイティブを 1 枠挿入するか（≥1）
    static var nativeSessionsBeforeNative: Int {
        get {
            let v = defaults.integer(forKey: Key.nativeSessionsBeforeNative)
            return v >= 1 ? v : 5
        }
        set { defaults.set(max(1, newValue), forKey: Key.nativeSessionsBeforeNative) }
    }

    /// この枚数以下のセクションではネイティブを入れない（ノイズ抑制）
    static var nativeHideWhenSessionCountAtMost: Int {
        get {
            if defaults.object(forKey: Key.nativeHideWhenSessionCountAtMost) == nil { return 2 }
            return max(0, defaults.integer(forKey: Key.nativeHideWhenSessionCountAtMost))
        }
        set { defaults.set(newValue, forKey: Key.nativeHideWhenSessionCountAtMost) }
    }

    /// App Open を再表示するまでの最短間隔（秒）：復帰用
    static var appOpenResumeMinIntervalSeconds: TimeInterval {
        get {
            let v = defaults.double(forKey: Key.appOpenResumeSeconds)
            return v > 60 ? v : 4 * 3600
        }
        set { defaults.set(max(60, newValue), forKey: Key.appOpenResumeSeconds) }
    }

    /// インタースティシャル終了後、この秒数は App Open を出さない
    static var appOpenAfterInterstitialCooldownSeconds: TimeInterval {
        get {
            let v = defaults.double(forKey: Key.appOpenAfterInterstitialCooldown)
            return v > 0 ? v : 45
        }
        set { defaults.set(max(1, newValue), forKey: Key.appOpenAfterInterstitialCooldown) }
    }

    /// 遊技保存インタースティシャルの最短間隔（秒）
    static var interstitialMinimumIntervalSeconds: TimeInterval {
        get {
            let v = defaults.double(forKey: Key.interstitialMinimumInterval)
            return v > 0 ? v : 180
        }
        set { defaults.set(max(30, newValue), forKey: Key.interstitialMinimumInterval) }
    }
}

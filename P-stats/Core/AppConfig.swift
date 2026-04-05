import Foundation

// MARK: - UserDefaults キー（`@AppStorage` / `UserDefaults.standard` 共通）

/// アプリ設定の保存キーを一箇所で管理する。リネーム時は `rawValue` のみ変更すれば既存ユーザーデータと互換を保てる。
enum UserDefaultsKey: String {
    // MARK: 背景・テーマ
    case homeBackgroundStyle
    case homeBackgroundImagePath
    case appTheme
    case playViewBackgroundStyle
    case playViewBackgroundImagePath

    // MARK: ホーム情報パネル・統計
    case homeInfoPanelOrder
    case homeInfoPanelHidden
    case homeStatsLookbackDays

    // MARK: 実戦・操作
    case alwaysShowBothInvestmentButtons
    case playViewRightHandMode
    /// 旧「プロモードで開始」フラグ（移行用）
    case playViewStartWithPowerSaving
    case playStartMode
    case playDisableIdleTimerDuringPlay
    case bigHitHoldingsEntryDefault
    case playInfoPanelOrder
    case playInfoPanelHidden
    case playHourlyWageBasis

    // MARK: 機種・店舗・マスタ URL
    case machineDetailBaseURL
    case machineMasterDataURL
    case machineMasterListURL
    case machineDisplayOrder
    case shopDisplayOrder
    case defaultMachineName
    case defaultShopName
    case defaultExchangeRate
    case defaultBallsPerCash

    // MARK: その他設定
    case initialHoldingsGatePolicy
    case hapticEnabled
    case unitDisplaySuffix
    case appLockEnabled
    case appLockUseBiometric

    // MARK: リワード分析トライアル
    case rewardedAnalyticsTrialEndAt
    case rewardedAnalyticsRewardsDayStart
    case rewardedAnalyticsRewardsCountToday

    // MARK: 広告・頻度
    case adFreqLastInterstitialFlowEndAt = "AdFreq.lastInterstitialFlowEndAt"
    case adAppOpenLastPresentationAt = "AdAppOpenLastPresentationAt"

    // MARK: 移行・デバッグ・テスト
    /// 旧 `InitialHoldingsGatePolicy` 移行元
    case startWithZeroHoldings
    case devDebugPremiumEntitlementMode
    case devDebugRewardTrialMode
    /// AdMob テスト端末 ID（カンマ区切り等）
    case gadTestDeviceIDs = "GADTestDeviceIDs"
}

extension UserDefaults {
    func string(for key: UserDefaultsKey) -> String? {
        string(forKey: key.rawValue)
    }

    func set(_ value: Any?, forKey key: UserDefaultsKey) {
        set(value, forKey: key.rawValue)
    }

    func object(forKey key: UserDefaultsKey) -> Any? {
        object(forKey: key.rawValue)
    }

    func integer(forKey key: UserDefaultsKey) -> Int {
        integer(forKey: key.rawValue)
    }

    func double(forKey key: UserDefaultsKey) -> Double {
        double(forKey: key.rawValue)
    }
}

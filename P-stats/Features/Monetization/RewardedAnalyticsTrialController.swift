import Combine
import Foundation

/// リワード視聴で付与する「分析フル」と同等機能の時間制トライアル（1 日最大回数あり）。
@MainActor
final class RewardedAnalyticsTrialController: ObservableObject {
    static let shared = RewardedAnalyticsTrialController()

    /// 1 回のリワードで延長する時間（時間）。UI 文言と AdMob の報酬説明と揃える。
    static let trialHoursPerReward = 3

    private let trialEndKey = "rewardedAnalyticsTrialEndAt"
    private let rewardsDayStartKey = "rewardedAnalyticsRewardsDayStart"
    private let rewardsCountKey = "rewardedAnalyticsRewardsCountToday"

    /// 1 暦日あたりのリワード付与上限
    static let maxRewardsPerCalendarDay = 2

    @Published private(set) var trialEndTimestamp: TimeInterval

    private init() {
        trialEndTimestamp = UserDefaults.standard.double(forKey: trialEndKey)
    }

    var trialEndDate: Date? {
        trialEndTimestamp > 0 ? Date(timeIntervalSince1970: trialEndTimestamp) : nil
    }

    var isTrialActive: Bool {
        guard let end = trialEndDate else { return false }
        return end > Date()
    }

    func canOfferRewardToday() -> Bool {
        refreshDayCounterIfNeeded()
        return UserDefaults.standard.integer(forKey: rewardsCountKey) < Self.maxRewardsPerCalendarDay
    }

    var rewardsUsedToday: Int {
        refreshDayCounterIfNeeded()
        return UserDefaults.standard.integer(forKey: rewardsCountKey)
    }

    /// 本日まだ視聴できる残り回数（UI 用）。
    var remainingRewardOffersToday: Int {
        max(0, Self.maxRewardsPerCalendarDay - rewardsUsedToday)
    }

    /// 設定・ハーフシートのリワードボタン文言。
    static func videoRewardUnlockButtonTitle(remainingToday: Int) -> String {
        "動画視聴で\(trialHoursPerReward)時間機能解放（残り\(remainingToday)回）"
    }

    /// 報酬獲得コールバックからのみ呼ぶ。既存試用があればそこから延長。
    func grantAdditionalTrialFromReward() {
        let now = Date()
        let base = max(now, trialEndDate ?? .distantPast)
        let newEnd = base.addingTimeInterval(TimeInterval(Self.trialHoursPerReward) * 3600)
        let ts = newEnd.timeIntervalSince1970
        UserDefaults.standard.set(ts, forKey: trialEndKey)
        trialEndTimestamp = ts

        refreshDayCounterIfNeeded()
        let c = UserDefaults.standard.integer(forKey: rewardsCountKey)
        UserDefaults.standard.set(c + 1, forKey: rewardsCountKey)

        EntitlementsStore.shared.notifyAnalyticsAccessChanged()
    }

    private func refreshDayCounterIfNeeded() {
        let cal = Calendar.current
        let todayStart = cal.startOfDay(for: Date()).timeIntervalSince1970
        let stored = UserDefaults.standard.double(forKey: rewardsDayStartKey)
        if abs(stored - todayStart) > 0.5 {
            UserDefaults.standard.set(todayStart, forKey: rewardsDayStartKey)
            UserDefaults.standard.set(0, forKey: rewardsCountKey)
        }
    }
}

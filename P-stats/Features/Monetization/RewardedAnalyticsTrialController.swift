import Combine
import Foundation

/// リワード視聴で付与する「分析フル」と同等機能の 24h トライアル（1 日最大回数あり）。
@MainActor
final class RewardedAnalyticsTrialController: ObservableObject {
    static let shared = RewardedAnalyticsTrialController()

    private let trialEndKey = "rewardedAnalyticsTrialEndAt"
    private let rewardsDayStartKey = "rewardedAnalyticsRewardsDayStart"
    private let rewardsCountKey = "rewardedAnalyticsRewardsCountToday"

    /// 1 暦日あたりのリワード付与上限
    static let maxRewardsPerCalendarDay = 3

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

    /// 報酬獲得コールバックからのみ呼ぶ。既存試用があればそこから延長。
    func grantAdditional24HoursFromReward() {
        let now = Date()
        let base = max(now, trialEndDate ?? .distantPast)
        let newEnd = base.addingTimeInterval(24 * 3600)
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

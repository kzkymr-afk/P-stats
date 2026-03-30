import Foundation

/// ホーム統合パネル用の集計（`GameSession`）
enum HomeInsightMetrics {
    private static let calendar = Calendar.current
    private static let shortDayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "M/d"
        f.locale = Locale(identifier: "ja_JP")
        return f
    }()

    static func sessions(in period: EarningsPeriod, from sessions: [GameSession]) -> [GameSession] {
        sessions.filter { calendar.isDate($0.date, equalTo: Date(), toGranularity: period.calendarComponent) }
    }

    static func sessions(inLastDays days: Int, from sessions: [GameSession]) -> [GameSession] {
        guard days > 0 else { return [] }
        let end = Date()
        guard let start = calendar.date(byAdding: .day, value: -days, to: end) else { return [] }
        return sessions.filter { $0.date >= start && $0.date <= end }
    }

    static func periodProfit(in period: EarningsPeriod, sessions: [GameSession]) -> Int {
        Self.sessions(in: period, from: sessions).reduce(0) { $0 + $1.performance }
    }

    static func periodDeficitSurplus(in period: EarningsPeriod, sessions: [GameSession]) -> Int {
        Self.sessions(in: period, from: sessions).reduce(0) { $0 + $1.deficitSurplus }
    }

    static func periodTheoreticalSum(in period: EarningsPeriod, sessions: [GameSession]) -> Int {
        Self.sessions(in: period, from: sessions).reduce(0) { $0 + $1.theoreticalValue }
    }

    /// 初当たりまでの平均実質投入（pt）。記録があるセッションのみ平均。
    static func averageFirstHitInvestment(in period: EarningsPeriod, sessions: [GameSession]) -> Double? {
        let list = Self.sessions(in: period, from: sessions).filter {
            $0.rushWinCount + $0.normalWinCount + $0.ltWinCount > 0
        }
        let costs = list.compactMap(\.firstHitRealCostPt)
        guard !costs.isEmpty else { return nil }
        return costs.reduce(0, +) / Double(costs.count)
    }

    /// 新しい順に最大7件
    static func lastUpToSevenSessions(newestFirst sessions: [GameSession]) -> [GameSession] {
        Array(sessions.sorted { $0.date > $1.date }.prefix(7))
    }

    /// 表示用：古い順の累積収支ステップ（ミニチャート）
    static func cumulativePerformanceSteps(in period: EarningsPeriod, sessions: [GameSession]) -> [Int] {
        let scoped = Self.sessions(in: period, from: sessions)
        switch period {
        case .day:
            let byDay = Dictionary(grouping: scoped) { calendar.startOfDay(for: $0.date) }
            let keys = byDay.keys.sorted()
            var c = 0
            return keys.map { d in
                c += byDay[d]!.reduce(0) { $0 + $1.performance }
                return c
            }
        case .week:
            let byDay = Dictionary(grouping: scoped) { calendar.startOfDay(for: $0.date) }
            let keys = byDay.keys.sorted()
            var c = 0
            return keys.map { d in
                c += byDay[d]!.reduce(0) { $0 + $1.performance }
                return c
            }
        case .month:
            let byDay = Dictionary(grouping: scoped) { calendar.startOfDay(for: $0.date) }
            let keys = byDay.keys.sorted()
            var c = 0
            return keys.map { d in
                c += byDay[d]!.reduce(0) { $0 + $1.performance }
                return c
            }
        case .year:
            let y = calendar.component(.year, from: Date())
            let inYear = scoped.filter { calendar.component(.year, from: $0.date) == y }
            let byMonth = Dictionary(grouping: inYear) { AnalyticsEngine.monthKey(from: $0.date) }
            let keys = byMonth.keys.sorted()
            var c = 0
            return keys.map { k in
                c += byMonth[k]!.reduce(0) { $0 + $1.performance }
                return c
            }
        }
    }

    /// 直近N日・理論値に対する余剰が大きい機種上位3（同一機種は集計済み想定で `AnalyticsEngine` を利用）
    static func affinityTop3(sessionsInWindow: [GameSession]) -> [(name: String, deficitSurplus: Int)] {
        let groups = AnalyticsEngine.byMachine(sessionsInWindow)
        let ranked = groups.filter { $0.sessionCount > 0 }
            .sorted {
                if $0.totalDeficitSurplus != $1.totalDeficitSurplus {
                    return $0.totalDeficitSurplus > $1.totalDeficitSurplus
                }
                return $0.totalProfit > $1.totalProfit
            }
        return Array(ranked.prefix(3).map { ($0.label, $0.totalDeficitSurplus) })
    }

    struct RotationLeader: Identifiable {
        let id: String
        let name: String
        /// 実戦回転率（回/1k）
        let avgRotationPer1k: Double
        /// 公式基準値との差の平均（回/1k）。nil は比較不可
        let avgDiffFromFormula: Double?
    }

    /// 回転数（合計）が多い機種上位3。表示は平均回転率とボーダー差。
    static func rotationLeadersTop3(sessionsInWindow: [GameSession]) -> [RotationLeader] {
        let g = Dictionary(grouping: sessionsInWindow) { $0.machineName.trimmingCharacters(in: .whitespaces).isEmpty ? "未設定" : $0.machineName }
        let scored: [(String, Int, Double, Double?)] = g.map { name, list in
            let rotList = list.filter(\.participatesInRotationRateAnalytics)
            let rots = rotList.reduce(0) { $0 + $1.normalRotations }
            let cost = rotList.reduce(0.0) { $0 + $1.rotationRateDenominatorPt }
            let rate = cost > 0 ? Double(rots) / cost * 1000 : 0
            let borderList = list.filter(\.participatesInFormulaBorderDiffAnalytics)
            let avgDiff: Double? = borderList.isEmpty ? nil : {
                let sum = borderList.reduce(0.0) { acc, s in
                    let r = (Double(s.normalRotations) / s.totalRealCost) * 1000
                    return acc + (r - s.formulaBorderPer1k)
                }
                return sum / Double(borderList.count)
            }()
            return (name, rots, rate, avgDiff)
        }
        .sorted { $0.1 > $1.1 }
        return Array(scored.prefix(3).map {
            RotationLeader(id: $0.0, name: $0.0, avgRotationPer1k: $0.2, avgDiffFromFormula: $0.3)
        })
    }
}

// MARK: - 設定用：表示順・非表示

enum HomeInfoPanelSectionID: Int, CaseIterable {
    case balance = 1
    case theoretical = 2
    case firstHitAvg = 3
    case last7Streak = 4
    case miniTrend = 5
    case affinityTop3 = 6
    case rotationTop3 = 7

    var settingsLabel: String {
        switch self {
        case .balance: return "収支・欠損／余剰"
        case .theoretical: return "理論値の積み上げ"
        case .firstHitAvg: return "初当たりまでの平均投資"
        case .last7Streak: return "直近7実戦の星取り"
        case .miniTrend: return "累積収支ミニチャート"
        case .affinityTop3: return "相性の良い台 Top3"
        case .rotationTop3: return "主力機種の回転率（基準値差）"
        }
    }
}

enum HomeInfoPanelSettings {
    static let defaultOrderCSV = "1,2,3,4,5,6,7"

    static func normalizedOrder(from raw: String) -> [Int] {
        let parts = raw.split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
        let valid = Set(HomeInfoPanelSectionID.allCases.map(\.rawValue))
        var seen = Set<Int>()
        var out: [Int] = []
        for p in parts where valid.contains(p) && !seen.contains(p) {
            out.append(p)
            seen.insert(p)
        }
        for id in HomeInfoPanelSectionID.allCases.map(\.rawValue) where !seen.contains(id) {
            out.append(id)
        }
        return out
    }

    static func hiddenSet(from raw: String) -> Set<Int> {
        Set(raw.split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
            .filter { HomeInfoPanelSectionID(rawValue: $0) != nil })
    }

    static func persistHidden(_ set: Set<Int>) -> String {
        set.sorted().map(String.init).joined(separator: ",")
    }
}

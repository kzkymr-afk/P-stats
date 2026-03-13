import Foundation
import SwiftData

// MARK: - 特定日判定（Date の末尾数字・ゾロ目）

/// 店舗ごとの特定日ルール（毎月N日・Nのつく日。追加順で最大4つ）
struct SpecificDayRules {
    /// 毎月この日（例: [3, 15] → 毎月3日・毎月15日）
    var dayOfMonth: [Int] = []
    /// 日の下一桁がこの数字（例: [7, 8] → 7のつく日・8のつく日）
    var lastDigits: [Int] = []

    static let `default`: SpecificDayRules = SpecificDayRules(lastDigits: [7])

    /// Shop の Storage から生成。specificDayRulesStorage 優先（"M13,L5" 形式）。空なら旧2フィールドから
    static func from(dayOfMonthString: String, lastDigitsString: String, rulesStorage: String = "") -> SpecificDayRules {
        if !rulesStorage.isEmpty {
            var dayOfMonth: [Int] = []
            var lastDigits: [Int] = []
            for part in rulesStorage.split(separator: ",").map({ String($0).trimmingCharacters(in: .whitespaces) }) {
                guard part.count >= 2, let num = Int(part.dropFirst()) else { continue }
                if part.hasPrefix("M"), (1...31).contains(num) { dayOfMonth.append(num) }
                else if part.hasPrefix("L"), (0...9).contains(num) { lastDigits.append(num) }
            }
            return SpecificDayRules(dayOfMonth: dayOfMonth, lastDigits: lastDigits)
        }
        let dayOfMonth = dayOfMonthString.split(separator: ",")
            .compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
            .filter { (1...31).contains($0) }
        let lastDigits = lastDigitsString.split(separator: ",")
            .compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
            .filter { (0...9).contains($0) }
        return SpecificDayRules(dayOfMonth: dayOfMonth, lastDigits: lastDigits)
    }

    /// 店舗の specificDayRulesStorage から「追加順」ラベル列を取得（個別店舗分析の特定日表示用）。最大4つ
    static func orderedLabels(rulesStorage: String, dayOfMonthFallback: String, lastDigitsFallback: String) -> [String] {
        if !rulesStorage.isEmpty {
            return rulesStorage.split(separator: ",")
                .compactMap { part -> String? in
                    let s = String(part).trimmingCharacters(in: .whitespaces)
                    guard s.count >= 2, let num = Int(s.dropFirst()) else { return nil }
                    if s.hasPrefix("M"), (1...31).contains(num) { return "毎月\(num)日" }
                    if s.hasPrefix("L"), (0...9).contains(num) { return "\(num)のつく日" }
                    return nil
                }
        }
        let dm = dayOfMonthFallback.split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }.filter { (1...31).contains($0) }
        let ld = lastDigitsFallback.split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }.filter { (0...9).contains($0) }
        return dm.map { "毎月\($0)日" } + ld.map { "\($0)のつく日" }
    }
}

/// Date から特定日関連を判定する共通関数
enum SpecificDateUtils {
    private static let calendar = Calendar.current

    /// 日の下一桁（1〜9）。10,20,30 は 0
    static func dayLastDigit(from date: Date) -> Int {
        let day = calendar.component(.day, from: date)
        return day % 10
    }

    /// ゾロ目か（月と日が同じ：1/1, 2/2, …, 12/12）
    static func isZoroMe(from date: Date) -> Bool {
        let month = calendar.component(.month, from: date)
        let day = calendar.component(.day, from: date)
        return month == day
    }

    /// ルールを適用して分析用ラベルを返す。毎月この日→「毎月N日」、Nのつく日→「Nのつく日」。未入力ルールの区分は出さない。
    static func attributeLabel(for date: Date, rules: SpecificDayRules?) -> String {
        let rules = rules ?? .default
        let day = calendar.component(.day, from: date)
        let lastD = day % 10

        if isZoroMe(from: date) { return "ゾロ目" }
        if rules.dayOfMonth.contains(day) { return "毎月\(day)日" }
        if rules.lastDigits.contains(lastD) { return "\(lastD)のつく日" }
        return "通常日"
    }
}

/// 特定日ラベルの表示順（通常日 → 毎月N日 → Nのつく日 → ゾロ目）
private func specificDayLabelSortOrder(_ label: String) -> Int {
    if label == "通常日" { return 0 }
    if label.hasPrefix("毎月"), label.hasSuffix("日"), let n = Int(label.dropFirst(2).dropLast(1)) { return 1000 + n }
    if label.hasSuffix("のつく日"), let n = Int(label.dropLast(4)) { return 2000 + n }
    if label == "ゾロ目" { return 3000 }
    return 4000
}

/// 実戦データの多角的集計結果（1グループあたり）
struct AnalyticsGroup: Identifiable {
    let id: String
    let label: String
    let sessionCount: Int
    let avgRotationRate: Double       // 平均実践回転率（回転/1000円）
    let totalTheoreticalProfit: Int   // 合計理論期待値（円）
    let totalProfit: Int              // 合計実収支（円）
    let totalDeficitSurplus: Int      // 合計欠損・余剰（円）= 実収支 - 理論
    /// 総投資（円・実質投資の合計）。店舗分析のグラデーション色に使用
    let totalInvestment: Int
    /// 欠損・余剰率（理論期待値に対する。0で一致、正で上振れ）
    var deficitSurplusRate: Double {
        guard totalTheoreticalProfit != 0 else { return 0 }
        return Double(totalDeficitSurplus) / Double(abs(totalTheoreticalProfit))
    }
    /// 平均ボーダー比（期待値仕事量の傾向）
    let avgExpectationRatio: Double
    /// 公式ボーダーとの差の平均（回/千円）。実践回転率 − 公式ボーダー。nil は対象セッションなし
    let avgDiffFromFormulaBorder: Double?
    /// 並び順用（月別・年別は日付の新しい順）
    var sortKey: String { id }
}

/// 保存された実戦データから機種別・メーカー別・店舗別に集計するエンジン
enum AnalyticsEngine {
    /// 機種別集計
    static func byMachine(_ sessions: [GameSession]) -> [AnalyticsGroup] {
        let grouped = Dictionary(grouping: sessions) { $0.machineName }
        return grouped.map { name, list in
            aggregate(label: name.isEmpty ? "未設定" : name, sessions: list)
        }
        .sorted { abs($0.totalProfit) > abs($1.totalProfit) }
    }

    /// メーカー別集計（manufacturerName。空は「未設定」にまとめる）
    static func byManufacturer(_ sessions: [GameSession]) -> [AnalyticsGroup] {
        let grouped = Dictionary(grouping: sessions) { s in
            s.manufacturerName.trimmingCharacters(in: .whitespaces).isEmpty ? "未設定" : s.manufacturerName
        }
        return grouped.map { name, list in
            aggregate(label: name, sessions: list)
        }
        .sorted { abs($0.totalProfit) > abs($1.totalProfit) }
    }

    /// 店舗別集計。並び順は最後にプレイした順（その店舗の直近セッション日が新しい順）
    static func byShop(_ sessions: [GameSession]) -> [AnalyticsGroup] {
        let grouped = Dictionary(grouping: sessions) { $0.shopName.isEmpty ? "未設定" : $0.shopName }
        return grouped
            .map { (name: $0.key, list: $0.value) }
            .sorted { ($0.list.map(\.date).max() ?? .distantPast) > ($1.list.map(\.date).max() ?? .distantPast) }
            .map { aggregate(label: $0.name, sessions: $0.list) }
    }

    private static let calendar = Calendar.current
    private static let weekdayLabels = ["日曜", "月曜", "火曜", "水曜", "木曜", "金曜", "土曜"]
    private static let monthFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy/MM"
        f.locale = Locale(identifier: "ja_JP")
        return f
    }()
    private static let yearFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy"
        return f
    }()
    /// セッション一覧のフィルタ用：日付から月キー（yyyy/MM）を返す
    static func monthKey(from date: Date) -> String { monthFormatter.string(from: date) }
    /// セッション一覧のフィルタ用：日付から年ラベル（yyyy年）を返す
    static func yearLabel(from date: Date) -> String { yearFormatter.string(from: date) + "年" }
    /// セッション一覧のフィルタ用：日付から曜日ラベルを返す
    static func weekdayLabel(from date: Date) -> String {
        let idx = calendar.component(.weekday, from: date) - 1
        return weekdayLabels[idx]
    }

    /// 月別集計（yyyy/MM）。新しい月が先
    static func byMonth(_ sessions: [GameSession]) -> [AnalyticsGroup] {
        let grouped = Dictionary(grouping: sessions) { monthKey(from: $0.date) }
        return grouped.map { key, list in
            aggregate(label: key, sessions: list)
        }
        .sorted { $0.sortKey > $1.sortKey }
    }

    /// 年別集計（yyyy）。新しい年が先
    static func byYear(_ sessions: [GameSession]) -> [AnalyticsGroup] {
        let grouped = Dictionary(grouping: sessions) { yearLabel(from: $0.date) }
        return grouped.map { label, list in
            aggregate(label: label, sessions: list)
        }
        .sorted { $0.sortKey > $1.sortKey }
    }

    /// 曜日別集計（日〜土）。月曜始まりで並べる
    static func byWeekday(_ sessions: [GameSession]) -> [AnalyticsGroup] {
        let grouped = Dictionary(grouping: sessions) { session in
            let comp = calendar.component(.weekday, from: session.date)
            let idx = comp - 1 // 1=日...7=土
            return weekdayLabels[idx]
        }
        let order = ["月曜", "火曜", "水曜", "木曜", "金曜", "土曜", "日曜"]
        return order.compactMap { day in
            grouped[day].map { list in aggregate(label: day, sessions: list) }
        }
    }

    /// 特定日属性別集計。ラベルは「毎月N日」「Nのつく日」など数値代入済み。入力されていないルールの区分は含めない。
    static func bySpecificDayAttribute(
        _ sessions: [GameSession],
        rulesByShopName: [String: SpecificDayRules]
    ) -> [AnalyticsGroup] {
        let grouped = Dictionary(grouping: sessions) { session in
            let name = session.shopName.isEmpty ? "未設定" : session.shopName
            let rules = rulesByShopName[name]
            return SpecificDateUtils.attributeLabel(for: session.date, rules: rules)
        }
        let order = grouped.keys.sorted { specificDayLabelSortOrder($0) < specificDayLabelSortOrder($1) }
        return order.map { label in
            aggregate(label: label, sessions: grouped[label] ?? [])
        }
    }

    /// チャート用：対象セッションに登場する店舗のルールから「表示すべき特定日ラベル」を全て返す（通常日・毎月N日・Nのつく日・ゾロ目）
    static func allSpecificDayLabels(rulesByShopName: [String: SpecificDayRules], shopNamesInSessions: Set<String>) -> [String] {
        var labels = Set<String>()
        labels.insert("通常日")
        labels.insert("ゾロ目")
        for shopName in shopNamesInSessions {
            guard let rules = rulesByShopName[shopName] else { continue }
            for d in rules.dayOfMonth { labels.insert("毎月\(d)日") }
            for n in rules.lastDigits { labels.insert("\(n)のつく日") }
        }
        return labels.sorted { specificDayLabelSortOrder($0) < specificDayLabelSortOrder($1) }
    }

    /// セッション0件のグループ（特定日チャートで「設定した日」を表示するため）
    static func emptyGroup(label: String) -> AnalyticsGroup {
        aggregate(label: label, sessions: [])
    }

    /// 全般タブ用：指定セッションを「全体」1グループとして集計
    static func overviewGroup(_ sessions: [GameSession]) -> AnalyticsGroup {
        aggregate(label: "全体", sessions: sessions)
    }

    private static func aggregate(label: String, sessions: [GameSession]) -> AnalyticsGroup {
        let count = sessions.count
        var sumRate: Double = 0
        var sumTheoretical: Int = 0
        var sumProfit: Int = 0
        var sumRatio: Double = 0
        var ratioCount = 0
        for s in sessions {
            if s.totalRealCost > 0 {
                sumRate += (Double(s.normalRotations) / s.totalRealCost) * 1000.0
            }
            sumTheoretical += s.theoreticalValue
            sumProfit += s.performance
            if s.expectationRatioAtSave > 0 {
                sumRatio += s.expectationRatioAtSave
                ratioCount += 1
            }
        }
        let avgRate = count > 0 ? sumRate / Double(count) : 0
        let avgRatio = ratioCount > 0 ? sumRatio / Double(ratioCount) : 0
        let totalDS = sessions.reduce(0) { $0 + $1.deficitSurplus }
        let totalInv = sessions.reduce(0) { $0 + Int(round($1.totalRealCost)) }
        let borderList = sessions.filter { $0.formulaBorderPer1k > 0 }
        let avgBorderDiff: Double? = borderList.isEmpty ? nil : {
            let sum = borderList.reduce(0.0) { acc, s in
                let rate = s.totalRealCost > 0 ? (Double(s.normalRotations) / s.totalRealCost) * 1000.0 : 0
                return acc + (rate - s.formulaBorderPer1k)
            }
            return sum / Double(borderList.count)
        }()
        return AnalyticsGroup(
            id: label,
            label: label,
            sessionCount: count,
            avgRotationRate: avgRate,
            totalTheoreticalProfit: sumTheoretical,
            totalProfit: sumProfit,
            totalDeficitSurplus: totalDS,
            totalInvestment: totalInv,
            avgExpectationRatio: avgRatio,
            avgDiffFromFormulaBorder: avgBorderDiff
        )
    }

    /// 月別累計（収支トレンドグラフ用）。月キー昇順で、各月までの累計実収支・累計理論期待値を返す
    static func monthlyCumulativeTrend(_ sessions: [GameSession]) -> [(month: String, cumulativeProfit: Int, cumulativeTheoretical: Int)] {
        let byMonth = Dictionary(grouping: sessions) { monthKey(from: $0.date) }
        let sortedKeys = byMonth.keys.sorted()
        var cumProfit = 0
        var cumTheoretical = 0
        return sortedKeys.map { key in
            let list = byMonth[key] ?? []
            cumProfit += list.reduce(0) { $0 + $1.performance }
            cumTheoretical += list.reduce(0) { $0 + $1.theoreticalValue }
            return (month: key, cumulativeProfit: cumProfit, cumulativeTheoretical: cumTheoretical)
        }
    }

    /// 機種タイプ別集計（ST vs 確変）。machineTypeByMachineName: 機種名 → "st" or "kakugen"（Machine.machineTypeRaw）
    static func byMachineType(_ sessions: [GameSession], machineTypeByMachineName: [String: String]) -> [AnalyticsGroup] {
        let grouped = Dictionary(grouping: sessions) { session in
            let name = session.machineName.isEmpty ? "未設定" : session.machineName
            return machineTypeByMachineName[name] ?? "kakugen"
        }
        let order: [(String, String)] = [("st", "ST"), ("kakugen", "確変")]
        return order.compactMap { raw, label in
            guard let list = grouped[raw], !list.isEmpty else { return nil }
            return aggregate(label: label, sessions: list)
        }
    }
}

import Foundation
import SwiftData

// MARK: - 特定日判定（Date の末尾数字・ゾロ目）

/// 店舗ごとの特定日ルール（毎月N日・Nのつく日。追加順で最大6つ）
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

    /// 店舗の specificDayRulesStorage から「追加順」ラベル列を取得（個別店舗分析の特定日表示用）。最大6つ
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

/// クロス分析の並び替え（全般タブ）
enum CrossAnalysisSortAxis: String, CaseIterable, Identifiable {
    case sessionsDesc = "実戦件数"
    case rotationDesc = "回転率"
    case borderDiffDesc = "ボーダー差"
    case profitAbsDesc = "実成績（変動）"
    case profitDesc = "実成績（プラス优先）"

    var id: String { rawValue }

    /// メニュー用の短い説明
    var menuLabel: String {
        switch self {
        case .sessionsDesc: return "実戦件数（多い順）"
        case .rotationDesc: return "回転率（高い順）"
        case .borderDiffDesc: return "ボーダー差（高い順・未設定は後ろ）"
        case .profitAbsDesc: return "実成績（絶対値が大きい順）"
        case .profitDesc: return "実成績（プラスが上）"
        }
    }
}

/// 店舗 × メーカー / 店舗 × 機種 の切り替え
enum CrossAnalysisDimension: String, CaseIterable, Identifiable {
    case manufacturer = "店×メーカー"
    case machine = "店×機種"

    var id: String { rawValue }
}

/// 店舗 × メーカー の組み合わせ別集計（クロス分析用）
struct ShopManufacturerCrossRow: Identifiable {
    let id: String
    let shop: String
    let manufacturer: String
    let sessionCount: Int
    /// 実戦回転率（回/1k）のセッション平均
    let avgRotationPer1k: Double
    let totalProfit: Int
    let avgBorderDiffPer1k: Double?
}

/// 店舗 × 機種 の組み合わせ別集計（クロス分析用）
struct ShopMachineCrossRow: Identifiable {
    let id: String
    let shop: String
    let machine: String
    let sessionCount: Int
    let avgRotationPer1k: Double
    let totalProfit: Int
    let avgBorderDiffPer1k: Double?
}

private protocol _CrossAnalysisSortFields {
    var sessionCount: Int { get }
    var avgRotationPer1k: Double { get }
    var avgBorderDiffPer1k: Double? { get }
    var totalProfit: Int { get }
}

extension ShopManufacturerCrossRow: _CrossAnalysisSortFields {}
extension ShopMachineCrossRow: _CrossAnalysisSortFields {}

/// 実戦データの多角的集計結果（1グループあたり）
struct AnalyticsGroup: Identifiable {
    let id: String
    let label: String
    let sessionCount: Int
    let avgRotationRate: Double       // 平均実戦回転率（回転/1000円）
    let totalTheoreticalProfit: Int   // 合計期待値（円）
    let totalProfit: Int              // 合計実収支（円）
    let totalDeficitSurplus: Int      // 合計欠損・余剰（円）= 実収支 - 期待値
    /// 総投資（円・実質投資の合計）。店舗分析のグラデーション色に使用
    let totalInvestment: Int
    /// 欠損・余剰率（期待値に対する。0で一致、正で上振れ）
    var deficitSurplusRate: Double {
        guard totalTheoreticalProfit != 0 else { return 0 }
        return Double(totalDeficitSurplus) / Double(abs(totalTheoreticalProfit))
    }
    /// 平均ボーダー比（期待値仕事量の傾向）
    let avgExpectationRatio: Double
    /// ボーダーとの差（回/1k・グループ内を通常回転数で加重平均）。実質回転率 − 店補正後のボーダー（保存値があれば）。nil は対象セッションなし／重み0
    let avgBorderDiffPer1k: Double?
    /// `snapshotData` があり、期待値を当時スペックで再計算できるセッション件数
    let snapshotBackedSessionCount: Int
    /// スナップショットと同名の現在マスタを比較し、スペック差があるセッション件数
    let masterSpecDriftSessionCount: Int
    /// 並び順用（月別・年別は日付の新しい順）
    var sortKey: String { id }
}

/// 保存された実戦データから機種別・メーカー別・店舗別に集計するエンジン
enum AnalyticsEngine {
    /// 店×メーカー／店×機種の複合キー区切り（ASCII Unit Separator U+001F）
    private static let crossGroupKeySeparator: Character = {
        guard let u = UnicodeScalar(31) else { return "?" }
        return Character(u)
    }()

    /// ボーダーとの差（回/1k）を通常回転数で加重平均。同一機種でも店でボーダーが違うとき、回転の多い店・実戦ほど集約値に反映される。重み0のセッションは除く。
    static func weightedAverageBorderDiffPer1k(sessions: [GameSession]) -> Double? {
        var weightedSum = 0.0
        var weightTotal = 0.0
        for s in sessions where s.participatesInBorderDiffAnalytics {
            guard let d = s.sessionBorderDiffPer1k else { continue }
            let w = Double(s.normalRotations)
            guard w > 0 else { continue }
            weightedSum += d * w
            weightTotal += w
        }
        guard weightTotal > 0 else { return nil }
        return weightedSum / weightTotal
    }

    /// 機種別集計
    static func byMachine(_ sessions: [GameSession], machinesByName: [String: Machine]? = nil) -> [AnalyticsGroup] {
        let grouped = Dictionary(grouping: sessions) { $0.machineName }
        return grouped.map { name, list in
            aggregate(label: name.isEmpty ? "未設定" : name, sessions: list, machinesByName: machinesByName)
        }
        .sorted { abs($0.totalProfit) > abs($1.totalProfit) }
    }

    /// メーカー別集計（manufacturerName。空は「未設定」にまとめる）
    static func byManufacturer(_ sessions: [GameSession], machinesByName: [String: Machine]? = nil) -> [AnalyticsGroup] {
        let grouped = Dictionary(grouping: sessions) { s in
            s.manufacturerName.trimmingCharacters(in: .whitespaces).isEmpty ? "未設定" : s.manufacturerName
        }
        return grouped.map { name, list in
            aggregate(label: name, sessions: list, machinesByName: machinesByName)
        }
        .sorted { abs($0.totalProfit) > abs($1.totalProfit) }
    }

    /// 店舗別集計。並び順は最後にプレイした順（その店舗の直近セッション日が新しい順）
    static func byShop(_ sessions: [GameSession], machinesByName: [String: Machine]? = nil) -> [AnalyticsGroup] {
        let grouped = Dictionary(grouping: sessions) { $0.shopName.isEmpty ? "未設定" : $0.shopName }
        return grouped
            .map { (name: $0.key, list: $0.value) }
            .sorted { ($0.list.map(\.date).max() ?? .distantPast) > ($1.list.map(\.date).max() ?? .distantPast) }
            .map { aggregate(label: $0.name, sessions: $0.list, machinesByName: machinesByName) }
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
    private static let weekStartIdFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = calendar.timeZone
        return f
    }()
    private static let weekAxisLabelFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "M/d"
        f.locale = Locale(identifier: "ja_JP")
        f.timeZone = calendar.timeZone
        return f
    }()
    private static let dayInMonthFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "M/d"
        f.locale = Locale(identifier: "ja_JP")
        f.timeZone = calendar.timeZone
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
    static func byMonth(_ sessions: [GameSession], machinesByName: [String: Machine]? = nil) -> [AnalyticsGroup] {
        let grouped = Dictionary(grouping: sessions) { monthKey(from: $0.date) }
        return grouped.map { key, list in
            aggregate(label: key, sessions: list, machinesByName: machinesByName)
        }
        .sorted { $0.sortKey > $1.sortKey }
    }

    /// 日別集計（期間タブ・月別フィルタ内の日ごと）。`id` はその日 0:00 の `timeIntervalSince1970` 文字列
    static func byCalendarDay(_ sessions: [GameSession], machinesByName: [String: Machine]? = nil) -> [AnalyticsGroup] {
        let grouped = Dictionary(grouping: sessions) { calendar.startOfDay(for: $0.date) }
        return grouped.map { dayStart, list in
            let label = dayInMonthFormatter.string(from: dayStart)
            let id = String(dayStart.timeIntervalSince1970)
            return aggregateGroup(id: id, label: label, sessions: list, machinesByName: machinesByName)
        }
        .sorted { a, b in
            let ta = TimeInterval(a.id) ?? 0
            let tb = TimeInterval(b.id) ?? 0
            return ta > tb
        }
    }

    /// 年別集計（yyyy）。新しい年が先
    static func byYear(_ sessions: [GameSession], machinesByName: [String: Machine]? = nil) -> [AnalyticsGroup] {
        let grouped = Dictionary(grouping: sessions) { yearLabel(from: $0.date) }
        return grouped.map { label, list in
            aggregate(label: label, sessions: list, machinesByName: machinesByName)
        }
        .sorted { $0.sortKey > $1.sortKey }
    }

    /// 曜日別集計（日〜土）。月曜始まりで並べる
    static func byWeekday(_ sessions: [GameSession], machinesByName: [String: Machine]? = nil) -> [AnalyticsGroup] {
        let grouped = Dictionary(grouping: sessions) { session in
            let comp = calendar.component(.weekday, from: session.date)
            let idx = comp - 1 // 1=日...7=土
            return weekdayLabels[idx]
        }
        let order = ["月曜", "火曜", "水曜", "木曜", "金曜", "土曜", "日曜"]
        return order.compactMap { day in
            grouped[day].map { list in aggregate(label: day, sessions: list, machinesByName: machinesByName) }
        }
    }

    /// 特定日属性別集計。ラベルは「毎月N日」「Nのつく日」など数値代入済み。入力されていないルールの区分は含めない。
    static func bySpecificDayAttribute(
        _ sessions: [GameSession],
        rulesByShopName: [String: SpecificDayRules],
        machinesByName: [String: Machine]? = nil
    ) -> [AnalyticsGroup] {
        let grouped = Dictionary(grouping: sessions) { session in
            let name = session.shopName.isEmpty ? "未設定" : session.shopName
            let rules = rulesByShopName[name]
            return SpecificDateUtils.attributeLabel(for: session.date, rules: rules)
        }
        let order = grouped.keys.sorted { specificDayLabelSortOrder($0) < specificDayLabelSortOrder($1) }
        return order.map { label in
            aggregate(label: label, sessions: grouped[label] ?? [], machinesByName: machinesByName)
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
    static func overviewGroup(_ sessions: [GameSession], machinesByName: [String: Machine]? = nil) -> AnalyticsGroup {
        aggregate(label: "全体", sessions: sessions, machinesByName: machinesByName)
    }

    /// 店舗とメーカーの組み合わせごとに集計（クロス分析）。`minimumSessions` 未満はノイズ削減のため除外。
    static func shopManufacturerCrossRows(
        _ sessions: [GameSession],
        minimumSessions: Int = 2,
        sortBy sortAxis: CrossAnalysisSortAxis = .sessionsDesc,
        machinesByName: [String: Machine]? = nil
    ) -> [ShopManufacturerCrossRow] {
        let sep = "\u{001F}"
        let grouped = Dictionary(grouping: sessions) { s -> String in
            let shop = s.shopName.isEmpty ? "未設定" : s.shopName
            let mfr = s.manufacturerName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "未設定"
                : s.manufacturerName.trimmingCharacters(in: .whitespacesAndNewlines)
            return shop + sep + mfr
        }
        let rows: [ShopManufacturerCrossRow] = grouped.compactMap { compoundKey, list -> ShopManufacturerCrossRow? in
            guard list.count >= minimumSessions else { return nil }
            let parts = compoundKey.split(separator: Self.crossGroupKeySeparator, maxSplits: 1).map(String.init)
            guard parts.count == 2 else { return nil }
            let shop = parts[0]
            let mfr = parts[1]
            let g = aggregate(label: "\(shop) × \(mfr)", sessions: list, machinesByName: machinesByName)
            return ShopManufacturerCrossRow(
                id: compoundKey,
                shop: shop,
                manufacturer: mfr,
                sessionCount: g.sessionCount,
                avgRotationPer1k: g.avgRotationRate,
                totalProfit: g.totalProfit,
                avgBorderDiffPer1k: g.avgBorderDiffPer1k
            )
        }
        return sortedCrossRows(rows, by: sortAxis)
    }

    /// 店舗と機種の組み合わせごとに集計（クロス分析）
    static func shopMachineCrossRows(
        _ sessions: [GameSession],
        minimumSessions: Int = 2,
        sortBy sortAxis: CrossAnalysisSortAxis = .sessionsDesc,
        machinesByName: [String: Machine]? = nil
    ) -> [ShopMachineCrossRow] {
        let sep = "\u{001F}"
        let grouped = Dictionary(grouping: sessions) { s -> String in
            let shop = s.shopName.isEmpty ? "未設定" : s.shopName
            let machine = s.machineName.isEmpty ? "未設定" : s.machineName
            return shop + sep + machine
        }
        let rows: [ShopMachineCrossRow] = grouped.compactMap { compoundKey, list -> ShopMachineCrossRow? in
            guard list.count >= minimumSessions else { return nil }
            let parts = compoundKey.split(separator: Self.crossGroupKeySeparator, maxSplits: 1).map(String.init)
            guard parts.count == 2 else { return nil }
            let shop = parts[0]
            let machine = parts[1]
            let g = aggregate(label: "\(shop) × \(machine)", sessions: list, machinesByName: machinesByName)
            return ShopMachineCrossRow(
                id: compoundKey,
                shop: shop,
                machine: machine,
                sessionCount: g.sessionCount,
                avgRotationPer1k: g.avgRotationRate,
                totalProfit: g.totalProfit,
                avgBorderDiffPer1k: g.avgBorderDiffPer1k
            )
        }
        return sortedCrossRows(rows, by: sortAxis)
    }

    private static func sortedCrossRows<T: _CrossAnalysisSortFields>(_ rows: [T], by axis: CrossAnalysisSortAxis) -> [T] {
        rows.sorted { a, b in
            switch axis {
            case .sessionsDesc:
                if a.sessionCount != b.sessionCount { return a.sessionCount > b.sessionCount }
                return abs(a.totalProfit) > abs(b.totalProfit)
            case .rotationDesc:
                if abs(a.avgRotationPer1k - b.avgRotationPer1k) > 0.01 {
                    return a.avgRotationPer1k > b.avgRotationPer1k
                }
                if a.sessionCount != b.sessionCount { return a.sessionCount > b.sessionCount }
                return abs(a.totalProfit) > abs(b.totalProfit)
            case .borderDiffDesc:
                let an = a.avgBorderDiffPer1k != nil
                let bn = b.avgBorderDiffPer1k != nil
                if an != bn { return an && !bn }
                let av = a.avgBorderDiffPer1k ?? 0
                let bv = b.avgBorderDiffPer1k ?? 0
                if abs(av - bv) > 0.01 { return av > bv }
                if a.sessionCount != b.sessionCount { return a.sessionCount > b.sessionCount }
                return abs(a.totalProfit) > abs(b.totalProfit)
            case .profitAbsDesc:
                if abs(a.totalProfit) != abs(b.totalProfit) { return abs(a.totalProfit) > abs(b.totalProfit) }
                if a.sessionCount != b.sessionCount { return a.sessionCount > b.sessionCount }
                return a.avgRotationPer1k > b.avgRotationPer1k
            case .profitDesc:
                if a.totalProfit != b.totalProfit { return a.totalProfit > b.totalProfit }
                if a.sessionCount != b.sessionCount { return a.sessionCount > b.sessionCount }
                return a.avgRotationPer1k > b.avgRotationPer1k
            }
        }
    }

    /// スナップショット件数・マスタ差分件数（集計グループ用）
    private static func specHistogram(sessions: [GameSession], machinesByName: [String: Machine]?) -> (snap: Int, drift: Int) {
        let snap = sessions.filter { $0.snapshotData != nil }.count
        guard let map = machinesByName, !map.isEmpty else { return (snap, 0) }
        let drift = sessions.filter { s in
            guard s.snapshotData != nil else { return false }
            let k = s.machineName.trimmingCharacters(in: .whitespacesAndNewlines)
            return s.detailedAnalyticsMetrics(currentMachine: map[k]).isSpecChanged
        }.count
        return (snap, drift)
    }

    private static func aggregate(label: String, sessions: [GameSession], machinesByName: [String: Machine]? = nil) -> AnalyticsGroup {
        aggregateGroup(id: label, label: label, sessions: sessions, machinesByName: machinesByName)
    }

    private static func aggregateGroup(
        id: String,
        label: String,
        sessions: [GameSession],
        machinesByName: [String: Machine]? = nil
    ) -> AnalyticsGroup {
        let count = sessions.count
        var sumRate: Double = 0
        let rotationEligible = sessions.filter(\.participatesInRotationRateAnalytics)
        var rotationRateSampleCount = 0
        for s in rotationEligible {
            let denom = s.rotationRateDenominatorPt
            guard denom > 0, denom.isFinite else { continue }
            sumRate += (Double(s.normalRotations) / denom) * 1000.0
            rotationRateSampleCount += 1
        }
        var sumTheoretical: Int = 0
        var sumProfit: Int = 0
        var sumRatio: Double = 0
        var ratioCount = 0
        for s in sessions {
            sumTheoretical += s.analyticsTheoreticalValuePt
            sumProfit += s.performance
            if s.participatesInExpectationRatioAggregate {
                sumRatio += s.analyticsExpectationRatio
                ratioCount += 1
            }
        }
        let avgRate = rotationRateSampleCount > 0 ? sumRate / Double(rotationRateSampleCount) : 0
        let avgRatio = ratioCount > 0 ? sumRatio / Double(ratioCount) : 0
        let totalDS = sessions.reduce(0) { $0 + $1.deficitSurplus }
        let totalInv = sessions.reduce(0) { $0 + Int(round($1.totalRealCost)) }
        let avgBorderDiff = weightedAverageBorderDiffPer1k(sessions: sessions)
        let specHist = specHistogram(sessions: sessions, machinesByName: machinesByName)
        return AnalyticsGroup(
            id: id,
            label: label,
            sessionCount: count,
            avgRotationRate: avgRate,
            totalTheoreticalProfit: sumTheoretical,
            totalProfit: sumProfit,
            totalDeficitSurplus: totalDS,
            totalInvestment: totalInv,
            avgExpectationRatio: avgRatio,
            avgBorderDiffPer1k: avgBorderDiff,
            snapshotBackedSessionCount: specHist.snap,
            masterSpecDriftSessionCount: specHist.drift
        )
    }

    /// 週の開始日（カレンダーの週単位。`Calendar.current` の週の並びに従う）
    static func weekIntervalStart(for date: Date) -> Date {
        calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? calendar.startOfDay(for: date)
    }

    /// 全般の収支トレンド：切替は 12ヶ月 / 12週 / 30日いずれも **同じ本数のバケットを常に生成**（実戦が無い期間は 0）
    enum ProfitTrendDisplayMode: Int, CaseIterable {
        case twelveMonths
        case twelveWeeks
        case thirtyDays

        var panelTitle: String {
            switch self {
            case .twelveMonths: return "収支トレンド（直近12ヶ月）"
            case .twelveWeeks: return "収支トレンド（直近12週）"
            case .thirtyDays: return "収支トレンド（直近30日）"
            }
        }

        var next: ProfitTrendDisplayMode {
            switch self {
            case .twelveMonths: return .twelveWeeks
            case .twelveWeeks: return .thirtyDays
            case .thirtyDays: return .twelveMonths
            }
        }

        var bucketCount: Int {
            switch self {
            case .twelveMonths, .twelveWeeks: return 12
            case .thirtyDays: return 30
            }
        }
    }

    /// 1バケットあたりの期間内合計と、左から右へ走査した累計（折れ線用）
    struct ProfitTrendPoint: Identifiable, Equatable {
        let id: String
        let xIndex: Int
        let axisLabel: String
        /// 当該バケット内の実成績合計
        let periodProfit: Int
        /// 当該バケット内の期待値合計（棒グラフ用）
        let periodTheoretical: Int
        let cumulativeProfit: Int
        let cumulativeTheoretical: Int
    }

    private static func startOfMonth(for date: Date) -> Date {
        let c = calendar.dateComponents([.year, .month], from: date)
        return calendar.date(from: c) ?? calendar.startOfDay(for: date)
    }

    /// `referenceEnd` を含む期間を右端とし、指モードで固定本数のトレンド点を返す。
    static func profitTrendSeries(
        sessions: [GameSession],
        mode: ProfitTrendDisplayMode,
        referenceEnd: Date
    ) -> [ProfitTrendPoint] {
        let ref = calendar.startOfDay(for: referenceEnd)
        var periodProfit: [Int] = []
        var periodTheoretical: [Int] = []
        var ids: [String] = []
        var labels: [String] = []

        switch mode {
        case .twelveMonths:
            let endMonth = startOfMonth(for: ref)
            var monthStarts: [Date] = []
            for i in 0..<12 {
                guard let monthStart = calendar.date(byAdding: .month, value: -(11 - i), to: endMonth) else { continue }
                monthStarts.append(monthStart)
            }
            let spansMultipleYears = Set(monthStarts.map { calendar.component(.year, from: $0) }).count > 1
            for monthStart in monthStarts {
                let y = calendar.component(.year, from: monthStart)
                let m = calendar.component(.month, from: monthStart)
                ids.append(monthFormatter.string(from: monthStart))
                labels.append(spansMultipleYears ? "\(y)/\(m)" : "\(m)月")
                let list = sessions.filter { calendar.isDate($0.date, equalTo: monthStart, toGranularity: .month) }
                periodProfit.append(list.reduce(0) { $0 + $1.performance })
                periodTheoretical.append(list.reduce(0) { $0 + $1.analyticsTheoreticalValuePt })
            }
        case .twelveWeeks:
            let anchor = weekIntervalStart(for: ref)
            for i in 0..<12 {
                guard let ws = calendar.date(byAdding: .weekOfYear, value: -(11 - i), to: anchor),
                      let interval = calendar.dateInterval(of: .weekOfYear, for: ws)
                else { continue }
                ids.append(weekStartIdFormatter.string(from: interval.start))
                labels.append(weekAxisLabelFormatter.string(from: interval.start) + "〜")
                let list = sessions.filter { $0.date >= interval.start && $0.date < interval.end }
                periodProfit.append(list.reduce(0) { $0 + $1.performance })
                periodTheoretical.append(list.reduce(0) { $0 + $1.analyticsTheoreticalValuePt })
            }
        case .thirtyDays:
            for i in 0..<30 {
                let dayStart = calendar.date(byAdding: .day, value: -(29 - i), to: ref)!
                ids.append("day-\(weekStartIdFormatter.string(from: dayStart))")
                labels.append(dayInMonthFormatter.string(from: dayStart))
                let list = sessions.filter { calendar.isDate($0.date, inSameDayAs: dayStart) }
                periodProfit.append(list.reduce(0) { $0 + $1.performance })
                periodTheoretical.append(list.reduce(0) { $0 + $1.analyticsTheoreticalValuePt })
            }
        }

        var cumP = 0
        var cumT = 0
        var out: [ProfitTrendPoint] = []
        for i in periodProfit.indices {
            cumP += periodProfit[i]
            cumT += periodTheoretical[i]
            out.append(
                ProfitTrendPoint(
                    id: ids[i],
                    xIndex: i,
                    axisLabel: labels[i],
                    periodProfit: periodProfit[i],
                    periodTheoretical: periodTheoretical[i],
                    cumulativeProfit: cumP,
                    cumulativeTheoretical: cumT
                )
            )
        }
        return out
    }

    /// 機種タイプ別集計（ST vs 確変）。machineTypeByMachineName: 機種名 → "st" or "kakugen"（Machine.machineTypeRaw）
    static func byMachineType(
        _ sessions: [GameSession],
        machineTypeByMachineName: [String: String],
        machinesByName: [String: Machine]? = nil
    ) -> [AnalyticsGroup] {
        let grouped = Dictionary(grouping: sessions) { session in
            let name = session.machineName.isEmpty ? "未設定" : session.machineName
            return machineTypeByMachineName[name] ?? "kakugen"
        }
        let order: [(String, String)] = [("st", "ST"), ("kakugen", "確変")]
        return order.compactMap { raw, label in
            guard let list = grouped[raw], !list.isEmpty else { return nil }
            return aggregate(label: label, sessions: list, machinesByName: machinesByName)
        }
    }
}

// MARK: - 機種分析：複数当選の実戦統計

/// 機種サマリー用。記録された当選（通常・RUSH の合計）に基づき、スペックの突入率%とは別物。
struct MachineMultiHitSummary: Equatable {
    /// 当選が2回以上あった実戦 ÷ 対象の全実戦（%）
    let multiHitSessionRatePercent: Double?
    /// 上記の「2回以上」実戦に限る、1実戦あたりの平均当選回数
    let avgWinCountAmongMultiHitSessions: Double?

    static func compute(from sessions: [GameSession]) -> MachineMultiHitSummary {
        let total = sessions.count
        guard total > 0 else {
            return MachineMultiHitSummary(multiHitSessionRatePercent: nil, avgWinCountAmongMultiHitSessions: nil)
        }
        let multi = sessions.filter { $0.totalRecordedWinCount >= 2 }
        let rate = Double(multi.count) / Double(total) * 100.0
        let avgAmong: Double? = multi.isEmpty
            ? nil
            : Double(multi.reduce(0) { $0 + $1.totalRecordedWinCount }) / Double(multi.count)
        return MachineMultiHitSummary(multiHitSessionRatePercent: rate, avgWinCountAmongMultiHitSessions: avgAmong)
    }
}

// MARK: - 全般「通算サマリー」（分析ダッシュボード・全般タブ専用）

/// 全般タブ上部の「通算サマリー」カード用。`sessions` は期間フィルタ済み。
struct AnalyticsOverviewTotalSummary {
    let sessionCount: Int
    let totalPerformance: Int
    let totalInputCash: Int
    let totalRecoveryPt: Int
    let winCount: Int
    let loseCount: Int
    let winRatePercent: Double?
    let avgFirstHitProbabilityText: String?
    let totalTheoretical: Int
    let totalExpectationDiff: Int
    let avgRotationPer1k: Double?
    let avgBorderDiffPer1k: Double?
    let maxDailyInput: Int
    let maxDailyRecovery: Int
    let maxDailyPerformance: Int
    let avgPerformancePerSession: Double?
    let totalPlayMinutes: Int?
    let hourlyWagePt: Double?
    /// 期間内で `snapshotData` があるセッション件数
    let snapshotBackedSessionCount: Int
    /// スナップショットと現在マスタのスペックが異なるセッション件数
    let masterSpecDriftSessionCount: Int

    static func compute(sessions: [GameSession], machinesByName: [String: Machine]) -> AnalyticsOverviewTotalSummary {
        let cal = Calendar.current
        let sessionCount = sessions.count
        let totalPerformance = sessions.reduce(0) { $0 + $1.performance }
        let totalInputCash = sessions.reduce(0) { $0 + $1.inputCash }
        let totalRecoveryPt = sessions.reduce(0) { acc, s in
            acc + PStatsCalculator.recoveryPt(
                totalHoldingsBalls: max(0, s.totalHoldings),
                payoutCoefficientPtPerBall: s.payoutCoefficient
            )
        }
        let winCount = sessions.filter { $0.performance > 0 }.count
        let loseCount = sessions.filter { $0.performance < 0 }.count
        let winRatePercent: Double? = sessionCount > 0 ? Double(winCount) / Double(sessionCount) * 100 : nil

        var denomSum = 0.0
        var denomCount = 0
        for s in sessions {
            let key = s.machineName.trimmingCharacters(in: .whitespacesAndNewlines)
            let denom: Double
            if let snap = s.decodedGameSessionSnapshot {
                let d = SessionSpecAnalytics.probabilityDenominator(fromProbabilityString: snap.spec.probability)
                guard d > 0 else { continue }
                denom = d
            } else if let m = machinesByName[key], m.probabilityDenominator > 0 {
                denom = m.probabilityDenominator
            } else {
                continue
            }
            denomSum += denom
            denomCount += 1
        }
        let avgFirstHitProbabilityText: String? = {
            guard denomCount > 0 else { return nil }
            let avgDenom = denomSum / Double(denomCount)
            guard avgDenom.isValidForNumericDisplay else { return nil }
            return "1/\(avgDenom.displayFormat("%.1f"))"
        }()

        let totalTheoretical = sessions.reduce(0) { $0 + $1.analyticsTheoreticalValuePt }
        let totalExpectationDiff = sessions.reduce(0) { $0 + $1.deficitSurplus }
        let snapshotBackedSessionCount = sessions.filter { $0.snapshotData != nil }.count
        let masterSpecDriftSessionCount = sessions.filter { s in
            guard s.snapshotData != nil else { return false }
            let k = s.machineName.trimmingCharacters(in: .whitespacesAndNewlines)
            return s.detailedAnalyticsMetrics(currentMachine: machinesByName[k]).isSpecChanged
        }.count

        let rotList = sessions.filter(\.participatesInRotationRateAnalytics)
        let totalRotations = rotList.reduce(0) { $0 + $1.normalRotations }
        let totalCost = rotList.reduce(0.0) { $0 + $1.rotationRateDenominatorPt }
        let avgRotationPer1k: Double? = {
            guard totalCost > 0, totalCost.isFinite else { return nil }
            let v = Double(totalRotations) / (totalCost / 1000.0)
            return v.isFinite ? v : nil
        }()

        let avgBorderDiffPer1k = AnalyticsEngine.weightedAverageBorderDiffPer1k(sessions: sessions)

        let byDay = Dictionary(grouping: sessions) { cal.startOfDay(for: $0.date) }
        let maxDailyInput = byDay.values.map { $0.reduce(0) { $0 + $1.inputCash } }.max() ?? 0
        let maxDailyRecovery = byDay.values.map { daySessions in
            daySessions.reduce(0) { acc, s in
                acc + PStatsCalculator.recoveryPt(
                    totalHoldingsBalls: max(0, s.totalHoldings),
                    payoutCoefficientPtPerBall: s.payoutCoefficient
                )
            }
        }.max() ?? 0
        let maxDailyPerformance = byDay.values.map { $0.reduce(0) { $0 + $1.performance } }.max() ?? 0
        let avgPerformancePerSession: Double? = sessionCount > 0 ? Double(totalPerformance) / Double(sessionCount) : nil

        // 時給：開始/終了があるセッションのみ合算（旧データは除外）
        var totalSeconds = 0.0
        for s in sessions {
            if let sec = s.playDurationSeconds, sec.isFinite, sec > 0 { totalSeconds += sec }
        }
        let totalPlayMinutes: Int? = {
            guard totalSeconds.isFinite, totalSeconds > 0 else { return nil }
            return Int((totalSeconds / 60).rounded())
        }()
        let hourlyWagePt: Double? = {
            guard totalSeconds.isFinite, totalSeconds > 0 else { return nil }
            let hours = totalSeconds / 3600.0
            guard hours > 0, hours.isFinite else { return nil }
            let v = Double(totalPerformance) / hours
            return v.isFinite ? v : nil
        }()

        return AnalyticsOverviewTotalSummary(
            sessionCount: sessionCount,
            totalPerformance: totalPerformance,
            totalInputCash: totalInputCash,
            totalRecoveryPt: totalRecoveryPt,
            winCount: winCount,
            loseCount: loseCount,
            winRatePercent: winRatePercent,
            avgFirstHitProbabilityText: avgFirstHitProbabilityText,
            totalTheoretical: totalTheoretical,
            totalExpectationDiff: totalExpectationDiff,
            avgRotationPer1k: avgRotationPer1k,
            avgBorderDiffPer1k: avgBorderDiffPer1k,
            maxDailyInput: maxDailyInput,
            maxDailyRecovery: maxDailyRecovery,
            maxDailyPerformance: maxDailyPerformance,
            avgPerformancePerSession: avgPerformancePerSession,
            totalPlayMinutes: totalPlayMinutes,
            hourlyWagePt: hourlyWagePt,
            snapshotBackedSessionCount: snapshotBackedSessionCount,
            masterSpecDriftSessionCount: masterSpecDriftSessionCount
        )
    }
}

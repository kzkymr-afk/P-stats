import Foundation

/// 実戦（PlayView）右側の情報パネル（最大5行）の表示・並び設定
enum PlayInfoPanelSettings {
    static let orderKey = "playInfoPanelOrder"
    static let hiddenKey = "playInfoPanelHidden"
    /// 時給の基準（実収支 vs 期待値理論）。`PlayHourlyWageBasis.rawValue`
    static let hourlyWageBasisKey = "playHourlyWageBasis"

    /// デフォルト：期待値 / 総回転数 / 現在損益 / 持ち玉 / 時給（実収支）
    static let defaultOrder: [PlayInfoPanelRowID] = [.expectationPercent, .normalRotations, .currentProfit, .holdings, .hourlyWage]

    /// 設定画面「メイン」区分に並べる行
    static let settingsPrimaryRowIDs: Set<PlayInfoPanelRowID> = [
        .expectationPercent, .normalRotations, .currentProfit, .holdings, .hourlyWage
    ]
    /// 設定画面「ほかに選べる項目」区分（入れ替え候補）
    static let settingsAlternateRowIDs: Set<PlayInfoPanelRowID> = [
        .hourlyWageExpected, .totalInput, .borderDiff,
        .holdingsSegmentSyntheticPer1k, .holdingsSegmentExpectationPerK
    ]

    static var defaultOrderCSV: String {
        defaultOrder.map { String($0.rawValue) }.joined(separator: ",")
    }

    static func normalizedOrder(from csv: String) -> [PlayInfoPanelRowID] {
        let raw = csv.split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
        var ids = raw.compactMap { PlayInfoPanelRowID(rawValue: $0) }
        // 重複排除しつつ順序維持
        var seen: Set<Int> = []
        ids = ids.filter { seen.insert($0.rawValue).inserted }
        // 足りない分を末尾に補完
        for d in PlayInfoPanelRowID.allCases where !seen.contains(d.rawValue) {
            ids.append(d)
        }
        return ids
    }

    static func hiddenSet(from csv: String) -> Set<Int> {
        Set(csv.split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) })
    }

    static func persistHidden(_ set: Set<Int>) -> String {
        set.sorted().map(String.init).joined(separator: ",")
    }
}

enum PlayInfoPanelRowID: Int, CaseIterable {
    case expectationPercent = 1
    case borderDiff = 2
    case realRate = 3
    case normalRotations = 4
    case currentProfit = 5
    case totalInput = 6
    case holdings = 7
    case hourlyWage = 8
    /// 時給（期待値）。`hourlyWage`（実収支）とは別行として並べ替え可能。
    case hourlyWageExpected = 9
    /// 持ち玉区間のみの実質回転率（1000pt相当・通算の実質回転率とは別）
    case holdingsSegmentSyntheticPer1k = 10
    /// 持ち玉区間のみの理論収支を1000pt投資あたりで表示（/k）
    case holdingsSegmentExpectationPerK = 11

    /// 設定画面の行名。`unitSuffix` は「単位の設定」のラベル（空なら括弧省略など）。
    func settingsLabel(unitSuffix: String) -> String {
        let u = unitSuffix.trimmingCharacters(in: .whitespacesAndNewlines)
        let unitParen: String = {
            if u.isEmpty { return "" }
            return "（\(u)）"
        }()
        let hourlySuffix: String = {
            if u.isEmpty { return "/h" }
            return "（\(u)/h）"
        }()
        switch self {
        case .expectationPercent: return "期待値（%）"
        case .borderDiff: return "ボーダー差（回/1k）"
        case .realRate: return "実質回転率（回/1k）"
        case .normalRotations: return "総回転数（通常）"
        case .currentProfit: return "現在損益\(unitParen)"
        case .totalInput: return "総投資\(unitParen)"
        case .holdings: return "持ち玉（玉）"
        case .hourlyWage: return "時給（実収支）\(hourlySuffix)"
        case .hourlyWageExpected: return "時給（期待値）\(hourlySuffix)"
        case .holdingsSegmentSyntheticPer1k: return "持ち玉実質（1k換算・区間）"
        case .holdingsSegmentExpectationPerK: return "持ち玉理論/k（区間・通算と別）"
        }
    }
}


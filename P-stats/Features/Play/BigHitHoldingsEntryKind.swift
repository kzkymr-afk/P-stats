import Foundation

/// 大当たり突入フォームでの持ち玉入力モード（投資玉数か残り玉のどちらか一方を1フィールドで入力）
enum BigHitHoldingsEntryKind: String, CaseIterable, Identifiable {
    /// 当選までに使った持ち玉（玉数）
    case investedAtWin
    /// 当選時点の残り持ち玉（玉数）
    case remainingAtWin

    var id: String { rawValue }

    /// `AppStorage` 用の既定rawValue
    static let appStorageDefaultRawValue = investedAtWin.rawValue

    var settingsLabel: String {
        switch self {
        case .investedAtWin: return "当選までの投資（玉）"
        case .remainingAtWin: return "当選時点の残り玉"
        }
    }

    var sheetSegmentLabel: String {
        switch self {
        case .investedAtWin: return "投資（玉）"
        case .remainingAtWin: return "残り玉"
        }
    }

    var sheetFieldTitle: String {
        switch self {
        case .investedAtWin: return "持ち玉：当選までの投資（玉数）"
        case .remainingAtWin: return "持ち玉：当選時点の残り玉"
        }
    }

    var sheetFootnote: String {
        switch self {
        case .investedAtWin:
            return "当選に至るまでに使った持ち玉の合計。省略可。上の切替で「残り玉」に変えられます。"
        case .remainingAtWin:
            return "当選した瞬間の残り持ち玉。省略可。上の切替で「投資（玉）」に変えられます。"
        }
    }
}

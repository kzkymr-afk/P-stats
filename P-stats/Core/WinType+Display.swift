import Foundation

// MARK: - 履歴・UI 用の短い表示（永続化の rawValue「確変/RUSH」と区別）

extension WinType {
    /// 一覧・セグメント上の短い表記（マジックストリングを View 側に散らさない）
    var compactHistoryLabel: String {
        switch self {
        case .rush:
            return PlayRuntimeModeVocabulary.fallbackRush
        case .normal:
            return PlayRuntimeModeVocabulary.fallbackNormal
        }
    }
}

extension LendingType {
    /// 履歴行のラベル（`rawValue` と同一だが、switch で網羅性を明示）
    var compactHistoryLabel: String {
        switch self {
        case .cash: return rawValue
        case .holdings: return rawValue
        }
    }
}

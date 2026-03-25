import Foundation

// MARK: - 遊技状態（滞在モード）の表示名

/// `GameLog` の `currentModeID` / `currentState` / `isTimeShortMode` に対応するユーザー向け表示名。
/// マスタ JSON の `modes[].name` があれば最優先（`WinInputSheetView` のタイトルと整合）。
enum PlayRuntimeModeVocabulary {
    static let fallbackNormal = "通常"
    static let fallbackRush = "RUSH"
    static let fallbackLt = "LT"
    static let fallbackTimeShort = "時短"
    static let fallbackDenSapo = "電サポ"

    static func stayModeTitle(
        modeId: Int,
        currentState: PlayState,
        isTimeShort: Bool,
        master: MachineFullMaster?
    ) -> String {
        if let raw = master?.modes.first(where: { $0.modeId == modeId })?.name {
            let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty { return name }
        }
        switch modeId {
        case 2: return fallbackLt
        case 1: return fallbackRush
        default:
            if currentState == .support {
                return isTimeShort ? fallbackTimeShort : fallbackDenSapo
            }
            return fallbackNormal
        }
    }
}

extension GameLog {
    /// ヘッダー等に出す「滞在モード」表示名。マスタに `modes[].name` があればそれを優先。
    func stayModeDisplayName(machineMaster: MachineFullMaster?) -> String {
        PlayRuntimeModeVocabulary.stayModeTitle(
            modeId: currentModeID,
            currentState: currentState,
            isTimeShort: isTimeShortMode,
            master: machineMaster
        )
    }
}

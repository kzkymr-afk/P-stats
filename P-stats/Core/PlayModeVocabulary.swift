import Foundation

// MARK: - プレイ周りの「画面オーバーレイ」（用語・コード・安定IDの対応）

/// `PlayView` から開く全画面／主要オーバーレイの種別。
/// - `rawValue` はログ出力・デバッグ・将来の設定キー用に安定させる。
enum PlayPresentationSurface: String, CaseIterable {
    /// メインの実戦入力（オーバーレイではないが、他と並べて識別する）
    case main = "main"
    case powerSaving = "power_saving"
    case rushFocus = "rush_focus"
    /// 現状 `PlayView` からは未接続だが、型と用語をコード上で揃える
    case ltFocus = "lt_focus"
    case chanceMode = "chance_mode"
    case bonusMonitor = "bonus_monitor"
    case chainResult = "chain_result"
    case historyFromPlay = "history_from_play"
    case playEventHistory = "play_event_history"
    case analyticsFromPlay = "analytics_from_play"

    /// 用語定義・UIで使う日本語の短い呼び名
    var userFacingTitle: String {
        switch self {
        case .main: return "通常モード"
        case .powerSaving: return "省エネモード"
        case .rushFocus: return "RUSHフォーカス"
        case .ltFocus: return "LTフォーカス"
        case .chanceMode: return "チャンスモード"
        case .bonusMonitor: return "期待値モニター"
        case .chainResult: return "連荘収支"
        case .historyFromPlay: return "履歴"
        case .playEventHistory: return "操作履歴"
        case .analyticsFromPlay: return "分析"
        }
    }

    /// 実装している Swift の型名（用語定義の「英語名」欄と揃える）
    var swiftStructName: String {
        switch self {
        case .main: return "PlayView"
        case .powerSaving: return "PowerSavingModeView"
        case .rushFocus: return "RushFocusView"
        case .ltFocus: return "LtFocusView"
        case .chanceMode: return "ChanceModeView"
        case .bonusMonitor: return "BonusMonitorView"
        case .chainResult: return "ChainResultInputView"
        case .historyFromPlay: return "HistoryListView"
        case .playEventHistory: return "PlayEventHistoryView"
        case .analyticsFromPlay: return "AnalyticsDashboardView"
        }
    }
}

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

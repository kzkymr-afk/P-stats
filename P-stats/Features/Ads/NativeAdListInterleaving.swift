import Foundation

/// セッションカード列へネイティブ広告を規則的に差し込む（同一日・同一グループ単位で間隔リセット）。
enum NativeAdListInterleaving {
    enum Row: Identifiable {
        case session(GameSession)
        case native(placementKey: String)

        var id: String {
            switch self {
            case .session(let s): return "s-\(s.id.uuidString)"
            case .native(let key): return "n-\(key)"
            }
        }
    }

    /// 実戦履歴・分析の「1 日分（または 1 つの日付グループ）」のカード列用。
    static func rowsForSessionGroup(daySessions: [GameSession], placementPrefix: String) -> [Row] {
        if daySessions.count <= AdPolicy.nativeHideWhenSessionCountAtMost {
            return daySessions.map { .session($0) }
        }
        return interleave(daySessions, placementPrefix: placementPrefix)
    }

    private static func interleave(_ sessions: [GameSession], placementPrefix: String) -> [Row] {
        let n = AdPolicy.nativeSessionsBeforeNative
        var rows: [Row] = []
        var sinceLastNative = 0
        var nativeIndex = 0
        for session in sessions {
            if sinceLastNative >= n {
                nativeIndex += 1
                rows.append(.native(placementKey: "\(placementPrefix)-\(nativeIndex)"))
                sinceLastNative = 0
            }
            rows.append(.session(session))
            sinceLastNative += 1
        }
        return rows
    }
}

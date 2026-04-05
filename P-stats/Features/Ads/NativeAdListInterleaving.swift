import Foundation
import SwiftData

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

    // MARK: 機種・店舗管理（2 行目からネイティブ、その後コンテンツ 7 件ごと）

    enum MachineManagementRow: Identifiable {
        case machine(Machine)
        case native(placementKey: String)

        var id: String {
            switch self {
            case .machine(let m): return "m-\(m.persistentModelID)"
            case .native(let k): return "n-\(k)"
            }
        }
    }

    enum ShopManagementRow: Identifiable {
        case shop(Shop)
        case native(placementKey: String)

        var id: String {
            switch self {
            case .shop(let s): return "s-\(s.persistentModelID)"
            case .native(let k): return "n-\(k)"
            }
        }
    }

    private enum ManagementNativePolicy {
        /// この件数未満はネイティブを混ぜない
        static let minItems: Int = 2
        /// 先頭ネイティブの直後から数えて、この件数のコンテンツのあとに次のネイティブ
        static let contentBetweenNatives: Int = 7
    }

    static func machineManagementRows(_ machines: [Machine]) -> [MachineManagementRow] {
        guard machines.count >= ManagementNativePolicy.minItems else {
            return machines.map { .machine($0) }
        }
        var rows: [MachineManagementRow] = []
        var contentSinceNative = 0
        for (i, m) in machines.enumerated() {
            if i == 1 {
                rows.append(.native(placementKey: "mgmt-mac-head"))
                contentSinceNative = 0
            } else if i >= 2, contentSinceNative >= ManagementNativePolicy.contentBetweenNatives {
                rows.append(.native(placementKey: "mgmt-mac-\(i)"))
                contentSinceNative = 0
            }
            rows.append(.machine(m))
            contentSinceNative += 1
        }
        return rows
    }

    static func shopManagementRows(_ shops: [Shop]) -> [ShopManagementRow] {
        guard shops.count >= ManagementNativePolicy.minItems else {
            return shops.map { .shop($0) }
        }
        var rows: [ShopManagementRow] = []
        var contentSinceNative = 0
        for (i, s) in shops.enumerated() {
            if i == 1 {
                rows.append(.native(placementKey: "mgmt-shop-head"))
                contentSinceNative = 0
            } else if i >= 2, contentSinceNative >= ManagementNativePolicy.contentBetweenNatives {
                rows.append(.native(placementKey: "mgmt-shop-\(i)"))
                contentSinceNative = 0
            }
            rows.append(.shop(s))
            contentSinceNative += 1
        }
        return rows
    }
}

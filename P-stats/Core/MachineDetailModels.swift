import Foundation

// MARK: - フェーズ1 JSON 用（index.json / machines/[id].json）読み取り専用モデル
// 既存の Machine（SwiftData）とは別。遊技中のモード・当たり一覧参照用。

/// index.json の1件。機種一覧用。
struct MachineDetailIndexEntry: Decodable, Identifiable {
    var machineId: String
    var name: String
    var id: String { machineId }

    enum CodingKeys: String, CodingKey {
        case machineId = "machine_id"
        case name
    }
}

/// 機種ごと詳細 JSON（machines/[id].json）のルート。
struct MachineDetail: Decodable {
    var machineId: String
    var name: String
    var modes: [ModeDetail]

    enum CodingKeys: String, CodingKey {
        case machineId = "machine_id"
        case name
        case modes
    }
}

/// 1つの滞在モード（通常 / RUSH / LT など）。
struct ModeDetail: Decodable, Identifiable {
    var modeId: Int
    var name: String
    var bonuses: [BonusDetail]
    var id: Int { modeId }

    enum CodingKeys: String, CodingKey {
        case modeId = "mode_id"
        case name
        case bonuses
    }
}

/// そのモードで発生しうる1種類の当たり。
struct BonusDetail: Decodable, Identifiable {
    var name: String
    var payout: Int
    var ratio: Double
    var densapo: Int
    var nextModeId: Int

    /// 同一モード内で名前で一意にしたい場合の id（リスト表示用）。
    var id: String { "\(name)_\(payout)_\(nextModeId)" }

    enum CodingKeys: String, CodingKey {
        case name
        case payout
        case ratio
        case densapo
        case nextModeId = "next_mode_id"
    }

    /// JSON で ratio が整数のときのため（例: 50 → 50.0）
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        payout = try c.decode(Int.self, forKey: .payout)
        densapo = try c.decode(Int.self, forKey: .densapo)
        nextModeId = try c.decode(Int.self, forKey: .nextModeId)
        if let d = try? c.decode(Double.self, forKey: .ratio) {
            ratio = d
        } else if let i = try? c.decode(Int.self, forKey: .ratio) {
            ratio = Double(i)
        } else {
            ratio = 0
        }
    }
}

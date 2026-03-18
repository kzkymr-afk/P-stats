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
    var ratio: Double
    var densapo: Int
    var nextModeId: Int
    /// ユニット連結型対応: 初回タップで加算される基本出玉
    var baseOut: Int
    /// ユニット連結型対応: 追撃1回あたりの加算出玉（0なら完結型）
    var unitOut: Int
    /// ユニット連結型対応: 追撃の最大回数（unitOut==0でも1）
    var maxStack: Int

    /// 既存コード互換: 完結型の出玉（基本出玉）
    var payout: Int { baseOut }

    /// 同一モード内で名前で一意にしたい場合の id（リスト表示用）。
    var id: String { "\(name)_\(baseOut)_\(unitOut)_\(maxStack)_\(nextModeId)" }

    enum CodingKeys: String, CodingKey {
        case name
        case ratio
        case densapo
        case nextModeId = "next_mode_id"
        // 新形式（ユニット連結型）
        case baseOut
        case unitOut
        case maxStack
        // 旧形式互換
        case payout
    }

    /// JSON で ratio が整数のときのため（例: 50 → 50.0）
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        densapo = (try? c.decode(Int.self, forKey: .densapo)) ?? 0
        nextModeId = (try? c.decode(Int.self, forKey: .nextModeId)) ?? 0

        // baseOut/unitOut/maxStack があればそれを優先。なければ旧 payout から補完。
        if let b = try? c.decode(Int.self, forKey: .baseOut) {
            baseOut = b
        } else if let p = try? c.decode(Int.self, forKey: .payout) {
            baseOut = p
        } else {
            baseOut = 0
        }
        unitOut = (try? c.decode(Int.self, forKey: .unitOut)) ?? 0
        let ms = (try? c.decode(Int.self, forKey: .maxStack)) ?? 1
        maxStack = max(1, ms)

        if let d = try? c.decode(Double.self, forKey: .ratio) {
            ratio = d
        } else if let i = try? c.decode(Int.self, forKey: .ratio) {
            ratio = Double(i)
        } else {
            ratio = 0
        }
    }

    init(
        name: String,
        baseOut: Int,
        unitOut: Int,
        maxStack: Int,
        ratio: Double = 0,
        densapo: Int = 0,
        nextModeId: Int
    ) {
        self.name = name
        self.baseOut = baseOut
        self.unitOut = unitOut
        self.maxStack = max(1, maxStack)
        self.ratio = ratio
        self.densapo = densapo
        self.nextModeId = nextModeId
    }
}

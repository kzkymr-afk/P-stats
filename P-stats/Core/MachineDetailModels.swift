import Foundation

// MARK: - 遊技中の当たり詳細（recordHit 用）

/// そのモードで発生しうる1種類の当たり。
struct BonusDetail: Decodable, Identifiable {
    var name: String
    var ratio: Double
    var densapo: Int
    var nextModeId: Int
    /// 移行先モードの UI ロール（0=通常系, 1=RUSH系, 2=LT）
    var nextUiRole: Int?
    var baseOut: Int
    var unitOut: Int
    var maxStack: Int

    var payout: Int { baseOut }

    var id: String { "\(name)_\(baseOut)_\(unitOut)_\(maxStack)_\(nextModeId)" }

    enum CodingKeys: String, CodingKey {
        case name
        case ratio
        case densapo
        case nextModeId = "next_mode_id"
        case nextUiRole = "next_ui_role"
        case baseOut
        case unitOut
        case maxStack
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        densapo = (try? c.decode(Int.self, forKey: .densapo)) ?? 0
        nextModeId = (try? c.decode(Int.self, forKey: .nextModeId)) ?? 0
        nextUiRole = try? c.decode(Int.self, forKey: .nextUiRole)
        baseOut = (try? c.decode(Int.self, forKey: .baseOut)) ?? 0
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
        nextModeId: Int,
        nextUiRole: Int? = nil
    ) {
        self.name = name
        self.baseOut = baseOut
        self.unitOut = unitOut
        self.maxStack = max(1, maxStack)
        self.ratio = ratio
        self.densapo = densapo
        self.nextModeId = nextModeId
        self.nextUiRole = nextUiRole
    }

    var resolvedNextUiRole: Int {
        if let r = nextUiRole { return r }
        switch nextModeId {
        case 0: return 0
        case 1: return 1
        case 2: return 2
        default: return 2
        }
    }
}

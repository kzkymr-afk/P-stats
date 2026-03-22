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
    /// 上乗せ1回あたりの出玉候補（複数なら UI で [+300][+1500] のように並べる）
    var unitOuts: [Int]
    var maxStack: Int

    var payout: Int { baseOut }

    /// 後方互換・単一ユニット時の代表値
    var unitOut: Int { unitOuts.first ?? 0 }

    /// 複数ユニット（カンマ区切りマスタ）かどうか
    var hasMultipleUnitOuts: Bool { unitOuts.filter { $0 > 0 }.count > 1 }

    /// 追撃 UI 用の正のユニット一覧
    var positiveUnitOuts: [Int] { unitOuts.filter { $0 > 0 } }

    var id: String {
        let u = unitOuts.map(String.init).joined(separator: "-")
        return "\(name)_\(baseOut)_\(u)_\(maxStack)_\(nextModeId)"
    }

    enum CodingKeys: String, CodingKey {
        case name
        case ratio
        case densapo
        case nextModeId = "next_mode_id"
        case nextUiRole = "next_ui_role"
        case baseOut
        case unitOut
        case unitOuts = "unit_outs"
        case maxStack
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        densapo = (try? c.decode(Int.self, forKey: .densapo)) ?? 0
        nextModeId = (try? c.decode(Int.self, forKey: .nextModeId)) ?? 0
        nextUiRole = try? c.decode(Int.self, forKey: .nextUiRole)
        baseOut = (try? c.decode(Int.self, forKey: .baseOut)) ?? 0
        if let arr = try c.decodeIfPresent([Int].self, forKey: .unitOuts) {
            unitOuts = arr.filter { $0 > 0 }
        } else {
            let u = (try? c.decode(Int.self, forKey: .unitOut)) ?? 0
            unitOuts = u > 0 ? [u] : []
        }
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
        self.unitOuts = unitOut > 0 ? [unitOut] : []
        self.maxStack = max(1, maxStack)
        self.ratio = ratio
        self.densapo = densapo
        self.nextModeId = nextModeId
        self.nextUiRole = nextUiRole
    }

    init(
        name: String,
        baseOut: Int,
        unitOuts: [Int],
        maxStack: Int,
        ratio: Double = 0,
        densapo: Int = 0,
        nextModeId: Int,
        nextUiRole: Int? = nil
    ) {
        self.name = name
        self.baseOut = baseOut
        self.unitOuts = unitOuts.filter { $0 > 0 }
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

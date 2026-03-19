import Foundation

// MARK: - マスターJSON（MachineFullMaster）

struct MachineMasterIndexEntry: Decodable, Identifiable {
    var machineId: String
    var name: String
    var manufacturer: String?
    var probability: String?
    var machineType: String?
    var introStart: String?
    var status: String?

    var id: String { machineId }

    enum CodingKeys: String, CodingKey {
        case machineId = "machine_id"
        case name
        case manufacturer
        case probability
        case machineType = "machine_type"
        case introStart = "intro_start"
        case status
    }
}

struct MachineFullMaster: Decodable {
    var machineId: String
    var name: String
    var manufacturer: String?
    var probability: String?
    var machineType: String?
    var introStart: String?
    var spec: String?
    var tags: String?
    var modes: [MasterMode]
    var bonuses: [MasterBonus]

    enum CodingKeys: String, CodingKey {
        case machineId = "machine_id"
        case name
        case manufacturer
        case probability
        case machineType = "machine_type"
        case introStart = "intro_start"
        case spec
        case tags
        case modes
        case bonuses
    }

    func bonuses(forStayModeId modeId: Int) -> [MasterBonus] {
        bonuses.filter { $0.stayModeId == modeId }
    }
}

struct MasterMode: Decodable, Identifiable {
    var modeId: Int
    var name: String
    var densapo: MasterDensapo
    /// 0=通常系, 1=RUSH系, 2=LT。JSON 省略時: mode_0→0、それ以外→1（mode_id==2 のみ 2）
    var uiRole: Int
    var id: Int { modeId }

    enum CodingKeys: String, CodingKey {
        case modeId = "mode_id"
        case name
        case densapo
        case uiRole = "ui_role"
    }

    init(modeId: Int, name: String, densapo: MasterDensapo, uiRole: Int? = nil) {
        self.modeId = modeId
        self.name = name
        self.densapo = densapo
        if let uiRole {
            self.uiRole = uiRole
        } else {
            switch modeId {
            case 0: self.uiRole = 0
            case 2: self.uiRole = 2
            default: self.uiRole = 1
            }
        }
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        modeId = try c.decode(Int.self, forKey: .modeId)
        name = try c.decode(String.self, forKey: .name)
        densapo = try c.decode(MasterDensapo.self, forKey: .densapo)
        if let r = try c.decodeIfPresent(Int.self, forKey: .uiRole) {
            uiRole = r
        } else {
            switch modeId {
            case 0: uiRole = 0
            case 2: uiRole = 2
            default: uiRole = 1
            }
        }
    }
}

enum MasterDensapo: Decodable, Equatable {
    case finite(Int)
    case infinite

    var displayText: String {
        switch self {
        case .finite(let v): return "\(v)"
        case .infinite: return "∞"
        }
    }

    var intValueOrZero: Int {
        switch self {
        case .finite(let v): return v
        case .infinite: return 0
        }
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let i = try? c.decode(Int.self) {
            self = .finite(i)
            return
        }
        if let s = try? c.decode(String.self) {
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if t == "inf" || t == "∞" {
                self = .infinite
            } else if let i = Int(t) {
                self = .finite(i)
            } else {
                self = .finite(0)
            }
            return
        }
        self = .finite(0)
    }
}

struct MasterBonus: Decodable, Identifiable, Hashable {
    var bonusId: String
    var name: String
    var basePayout: Int
    var unitPayout: Int
    var maxConcat: Int
    var stayModeId: Int
    var nextModeId: Int
    var branchLabel: String?
    var promotionTargetBonusId: String?
    var nextUiRole: Int?

    var id: String { bonusId }

    enum CodingKeys: String, CodingKey {
        case bonusId = "bonus_id"
        case name
        case basePayout = "base_payout"
        case unitPayout = "unit_payout"
        case maxConcat = "max_concat"
        case stayModeId = "stay_mode_id"
        case nextModeId = "next_mode_id"
        case branchLabel = "branch_label"
        case promotionTargetBonusId = "promotion_id"
        case nextUiRole = "next_ui_role"
    }

    var hasUnit: Bool { unitPayout > 0 && maxConcat > 0 }
    var maxUnitCount: Int { max(0, maxConcat) }

    init(
        bonusId: String,
        name: String,
        basePayout: Int,
        unitPayout: Int,
        maxConcat: Int,
        stayModeId: Int,
        nextModeId: Int,
        branchLabel: String? = nil,
        promotionTargetBonusId: String? = nil,
        nextUiRole: Int? = nil
    ) {
        self.bonusId = bonusId
        self.name = name
        self.basePayout = basePayout
        self.unitPayout = max(0, unitPayout)
        self.maxConcat = max(1, maxConcat)
        self.stayModeId = stayModeId
        self.nextModeId = nextModeId
        self.branchLabel = branchLabel
        self.promotionTargetBonusId = promotionTargetBonusId
        self.nextUiRole = nextUiRole
    }

    init(from decoder: Decoder) throws {
        func parseModeToken(_ token: String) -> Int {
            let t = token.trimmingCharacters(in: .whitespacesAndNewlines)
            if let i = Int(t) { return i }
            let prefix = "mode_"
            if t.lowercased().hasPrefix(prefix) {
                let rest = t.dropFirst(prefix.count)
                let num = rest.prefix(while: \.isNumber)
                return Int(num) ?? 0
            }
            let digits = t.filter { $0.isNumber || $0 == "-" }
            return Int(digits) ?? 0
        }

        let c = try decoder.container(keyedBy: CodingKeys.self)
        bonusId = try c.decode(String.self, forKey: .bonusId)
        name = try c.decode(String.self, forKey: .name)
        basePayout = try c.decode(Int.self, forKey: .basePayout)
        unitPayout = try c.decodeIfPresent(Int.self, forKey: .unitPayout) ?? 0
        maxConcat = max(1, try c.decodeIfPresent(Int.self, forKey: .maxConcat) ?? 1)
        if let i = try c.decodeIfPresent(Int.self, forKey: .stayModeId) {
            stayModeId = i
        } else if let s = try c.decodeIfPresent(String.self, forKey: .stayModeId) {
            stayModeId = parseModeToken(s)
        } else {
            stayModeId = 0
        }
        if let i = try c.decodeIfPresent(Int.self, forKey: .nextModeId) {
            nextModeId = i
        } else if let s = try c.decodeIfPresent(String.self, forKey: .nextModeId) {
            nextModeId = parseModeToken(s)
        } else {
            nextModeId = 0
        }
        branchLabel = try c.decodeIfPresent(String.self, forKey: .branchLabel)
        promotionTargetBonusId = try c.decodeIfPresent(String.self, forKey: .promotionTargetBonusId)
        nextUiRole = try c.decodeIfPresent(Int.self, forKey: .nextUiRole)
    }
}

extension MachineFullMaster {
    func densapoInt(forNextModeId nextId: Int) -> Int {
        modes.first(where: { $0.modeId == nextId })?.densapo.intValueOrZero ?? 0
    }
}

extension MasterBonus {
    func asBonusDetail(using master: MachineFullMaster?) -> BonusDetail {
        let d = master?.densapoInt(forNextModeId: nextModeId) ?? 0
        let role = nextUiRole ?? master?.modes.first(where: { $0.modeId == nextModeId })?.uiRole
        return BonusDetail(
            name: name,
            baseOut: basePayout,
            unitOut: unitPayout,
            maxStack: maxConcat,
            ratio: 0,
            densapo: d,
            nextModeId: nextModeId,
            nextUiRole: role
        )
    }
}

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
    /// CSV「更新対象」列（`index.json` に含まれる場合のみ）
    var updateTarget: String?

    var id: String { machineId }

    enum CodingKeys: String, CodingKey {
        case machineId = "machine_id"
        case name
        case manufacturer
        case probability
        case machineType = "machine_type"
        case introStart = "intro_start"
        case status
        case updateTarget = "update_target"
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
    /// マスタ1シート仕様では空配列のみ（旧JSON互換のため省略時も空）
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

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        machineId = try c.decode(String.self, forKey: .machineId)
        name = try c.decode(String.self, forKey: .name)
        manufacturer = try c.decodeIfPresent(String.self, forKey: .manufacturer)
        probability = try c.decodeIfPresent(String.self, forKey: .probability)
        machineType = try c.decodeIfPresent(String.self, forKey: .machineType)
        introStart = try c.decodeIfPresent(String.self, forKey: .introStart)
        spec = try c.decodeIfPresent(String.self, forKey: .spec)
        tags = try c.decodeIfPresent(String.self, forKey: .tags)
        modes = try c.decodeIfPresent([MasterMode].self, forKey: .modes) ?? []
        bonuses = try c.decodeIfPresent([MasterBonus].self, forKey: .bonuses) ?? []
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
    /// 電サポ中だが当たり確率は通常と同じ（時短）。JSON 省略時は false。
    var isTimeShort: Bool
    var id: Int { modeId }

    enum CodingKeys: String, CodingKey {
        case modeId = "mode_id"
        case name
        case densapo
        case uiRole = "ui_role"
        case isTimeShort = "is_time_short"
    }

    init(modeId: Int, name: String, densapo: MasterDensapo, uiRole: Int? = nil, isTimeShort: Bool = false) {
        self.modeId = modeId
        self.name = name
        self.densapo = densapo
        self.isTimeShort = isTimeShort
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
        isTimeShort = try c.decodeIfPresent(Bool.self, forKey: .isTimeShort) ?? false
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
    /// 上乗せ候補（カンマ区切りマスタ → 複数要素）。JSON は `unit_payouts` 優先。
    var unitPayouts: [Int]
    var maxConcat: Int
    var stayModeId: Int
    var nextModeId: Int
    var branchLabel: String?
    var promotionTargetBonusId: String?
    var nextUiRole: Int?

    var id: String { bonusId }

    /// 後方互換・代表値（先頭のユニット）
    var unitPayout: Int { unitPayouts.first ?? 0 }

    /// 追撃 UI 用
    var positiveUnitPayouts: [Int] { unitPayouts.filter { $0 > 0 } }

    enum CodingKeys: String, CodingKey {
        case bonusId = "bonus_id"
        case name
        case basePayout = "base_payout"
        case unitPayout = "unit_payout"
        case unitPayouts = "unit_payouts"
        case maxConcat = "max_concat"
        case stayModeId = "stay_mode_id"
        case nextModeId = "next_mode_id"
        case branchLabel = "branch_label"
        case promotionTargetBonusId = "promotion_id"
        case nextUiRole = "next_ui_role"
    }

    var hasUnit: Bool { maxConcat > 0 && unitPayouts.contains(where: { $0 > 0 }) }
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
        let u = max(0, unitPayout)
        self.unitPayouts = u > 0 ? [u] : []
        self.maxConcat = max(1, maxConcat)
        self.stayModeId = stayModeId
        self.nextModeId = nextModeId
        self.branchLabel = branchLabel
        self.promotionTargetBonusId = promotionTargetBonusId
        self.nextUiRole = nextUiRole
    }

    init(
        bonusId: String,
        name: String,
        basePayout: Int,
        unitPayouts: [Int],
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
        self.unitPayouts = unitPayouts.filter { $0 > 0 }
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
        if let arr = try c.decodeIfPresent([Int].self, forKey: .unitPayouts) {
            unitPayouts = arr.filter { $0 > 0 }
        } else {
            let u = try c.decodeIfPresent(Int.self, forKey: .unitPayout) ?? 0
            unitPayouts = u > 0 ? [u] : []
        }
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

extension MasterBonus {
    /// JSON `promotion_id` はカンマ区切りで複数の bonus_id を格納可能（例: `bonus_2,bonus_5`）
    var promotionTargetBonusIds: [String] {
        guard let s = promotionTargetBonusId?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return [] }
        return s.split(separator: ",").compactMap { token -> String? in
            let n = Self.normalizeBonusIdToken(String(token))
            return n.isEmpty ? nil : n
        }
    }

    private static func normalizeBonusIdToken(_ token: String) -> String {
        let t = token.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return "" }
        if t.lowercased().hasPrefix("bonus_") { return t }
        if t.allSatisfy(\.isNumber) { return "bonus_\(t)" }
        return t
    }
}

import Foundation

// MARK: - 新マスターJSON（スペック駆動UI用）

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

    /// 旧形式（MachineDetail: modes[].bonuses）をフラット bonuses に変換して統一的に扱う
    static func fromLegacy(_ legacy: MachineDetail) -> MachineFullMaster {
        let flat: [MasterBonus] = legacy.modes.flatMap { m in
            m.bonuses.map { b in
                MasterBonus(
                    name: b.name,
                    basePayout: b.baseOut,
                    unitPayout: b.unitOut,
                    maxConcat: b.maxStack,
                    stayModeId: m.modeId,
                    nextModeId: b.nextModeId,
                    branchLabel: nil
                )
            }
        }
        let modes: [MasterMode] = legacy.modes.map { m in
            // 旧形式は densapo が Int 固定のため、MasterDensapo.finite に変換する
            let maxDensapo = m.bonuses.map(\.densapo).max() ?? 0
            return MasterMode(modeId: m.modeId, name: m.name, densapo: .finite(maxDensapo))
        }
        return MachineFullMaster(
            machineId: legacy.machineId,
            name: legacy.name,
            manufacturer: nil,
            probability: nil,
            machineType: nil,
            introStart: nil,
            spec: nil,
            tags: nil,
            modes: modes,
            bonuses: flat
        )
    }

    func bonuses(forStayModeId modeId: Int) -> [MasterBonus] {
        bonuses.filter { $0.stayModeId == modeId }
    }
}

struct MasterMode: Decodable, Identifiable {
    var modeId: Int
    var name: String
    /// densapo は Int または "INF"/"∞" を許容する（将来拡張）
    var densapo: MasterDensapo
    var id: Int { modeId }

    enum CodingKeys: String, CodingKey {
        case modeId = "mode_id"
        case name
        case densapo
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
    var name: String
    var basePayout: Int
    var unitPayout: Int
    var maxConcat: Int
    var stayModeId: Int
    var nextModeId: Int
    var branchLabel: String?

    var id: String { "\(stayModeId)|\(name)|\(nextModeId)|\(branchLabel ?? "")|\(basePayout)|\(unitPayout)|\(maxConcat)" }

    enum CodingKeys: String, CodingKey {
        case name
        case basePayout = "base_payout"
        case unitPayout = "unit_payout"
        case maxConcat = "max_concat"
        case stayModeId = "stay_mode_id"
        case nextModeId = "next_mode_id"
        case branchLabel = "branch_label"
    }

    var hasUnit: Bool { unitPayout > 0 && maxConcat > 0 }
    var maxUnitCount: Int { max(0, maxConcat) }
}


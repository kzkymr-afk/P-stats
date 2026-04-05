import Foundation

/// シンプル入力の「通常時／セッション」交互タイムライン（`GameSession.simplePlayTimelineJSON`）
enum SimplePlayTimelineRowKind: String, Codable, Sendable {
    case normal
    case bonusSession
}

struct SimplePlayTimelineRowStored: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var kind: SimplePlayTimelineRowKind
    /// 通常時ブロック：この区間の投資（通常）回転数
    var investmentNormalRotations: Int
    /// セッション：あたり回数
    var hitCount: Int
    /// セッション：獲得出玉（玉）
    var prizeBalls: Int

    init(
        id: UUID = UUID(),
        kind: SimplePlayTimelineRowKind,
        investmentNormalRotations: Int = 0,
        hitCount: Int = 0,
        prizeBalls: Int = 0
    ) {
        self.id = id
        self.kind = kind
        self.investmentNormalRotations = investmentNormalRotations
        self.hitCount = hitCount
        self.prizeBalls = prizeBalls
    }
}

enum GameSessionSimpleTimelineStorage {
    static func decode(_ json: String) -> [SimplePlayTimelineRowStored] {
        guard !json.isEmpty, let data = json.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([SimplePlayTimelineRowStored].self, from: data)) ?? []
    }

    static func encode(_ rows: [SimplePlayTimelineRowStored]) -> String {
        guard let data = try? JSONEncoder().encode(rows) else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }

    static func sumNormalRotations(_ rows: [SimplePlayTimelineRowStored]) -> Int {
        rows.filter { $0.kind == .normal }.reduce(0) { $0 + max(0, $1.investmentNormalRotations) }
    }

    static func sumHitCounts(_ rows: [SimplePlayTimelineRowStored]) -> Int {
        rows.filter { $0.kind == .bonusSession }.reduce(0) { $0 + max(0, $1.hitCount) }
    }

    static func sumPrizeBalls(_ rows: [SimplePlayTimelineRowStored]) -> Int {
        rows.filter { $0.kind == .bonusSession }.reduce(0) { $0 + max(0, $1.prizeBalls) }
    }

    static func hasAnyUserValue(_ rows: [SimplePlayTimelineRowStored]) -> Bool {
        rows.contains { r in
            switch r.kind {
            case .normal: return r.investmentNormalRotations > 0
            case .bonusSession: return r.hitCount > 0 || r.prizeBalls > 0
            }
        }
    }
}

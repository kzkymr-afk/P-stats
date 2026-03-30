import Foundation

/// 履歴編集の「初当たりブロック」（JSON で `GameSession.editSessionPhasesJSON` に保存）
struct GameSessionEditPhaseStored: Codable, Equatable, Identifiable {
    var id: UUID
    /// N 度目の「その初当たりまで」の通常回転数
    var rotationsUntilFirstHit: Int
    /// 現金投入（pt）その区間
    var investmentCashPt: Int
    /// 持ち玉投資（玉）
    var investmentHoldingsBalls: Int
    /// その区間の大当たり回数（合算を rush に載せる）
    var bigHitCount: Int
    /// その区間の回収出玉
    var recoveryHoldingsBalls: Int

    init(
        id: UUID = UUID(),
        rotationsUntilFirstHit: Int = 0,
        investmentCashPt: Int = 0,
        investmentHoldingsBalls: Int = 0,
        bigHitCount: Int = 0,
        recoveryHoldingsBalls: Int = 0
    ) {
        self.id = id
        self.rotationsUntilFirstHit = rotationsUntilFirstHit
        self.investmentCashPt = investmentCashPt
        self.investmentHoldingsBalls = investmentHoldingsBalls
        self.bigHitCount = bigHitCount
        self.recoveryHoldingsBalls = recoveryHoldingsBalls
    }
}

enum GameSessionEditPhasesStorage {
    static func decode(_ json: String) -> [GameSessionEditPhaseStored] {
        guard !json.isEmpty, let data = json.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([GameSessionEditPhaseStored].self, from: data)) ?? []
    }

    static func encode(_ phases: [GameSessionEditPhaseStored]) -> String {
        guard let data = try? JSONEncoder().encode(phases) else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }

    /// 区間コストの素の合計（pt 換算）。加重係数適用前。
    static func rawTotalRealCost(phases: [GameSessionEditPhaseStored], payoutPerBall: Double) -> Double {
        phases.reduce(0) { $0 + Double($1.investmentCashPt) + Double($1.investmentHoldingsBalls) * payoutPerBall }
    }

    /// 回転数の合計
    static func sumRotations(_ phases: [GameSessionEditPhaseStored]) -> Int {
        phases.reduce(0) { $0 + $1.rotationsUntilFirstHit }
    }

    /// `sum(区間回転)` と最終保存する `normalRotations` の差を、区間への投資配分に比例（回転加重）して `totalRealCost` に吸収する係数。
    static func realCostScaleFactor(phases: [GameSessionEditPhaseStored], targetRotations: Int) -> Double {
        let s = sumRotations(phases)
        guard s > 0, targetRotations > 0 else { return 1 }
        return Double(targetRotations) / Double(s)
    }
}

import Foundation

// MARK: - 実戦保存時点の機種スペック（SwiftData 外の純粋データ）

/// セッション保存時点の機種パラメータ。`Machine` の主要フィールドを値型で複製する。
struct MachineSpecSnapshot: Codable, Equatable, Sendable {
    /// 当選確率の表示文字列（例: `"1/319.5"`）
    var probability: String
    /// ボーダー表示文字列（メーカー公表の等価ボーダー等）
    var border: String
    /// 平均出玉の代表値（先頭当たりの払出玉数・`Machine.effectivePayoutDisplay` に相当）
    var payout: Int
    /// 1Rあたり純増出玉の平均（`Machine.averageNetPerRound` のスナップショット）
    var averageNetPerRound: Double
    /// 賞球数（打ち出しカウント）
    var countPerRound: Int
    /// 電サポ回数（ST 規定）
    var supportLimit: Int
    /// 通常後の時短ゲーム数
    var timeShortRotations: Int
    /// `"st"` / `"kakugen"`
    var machineTypeRaw: String
    /// 外部マスタ連携用。未設定は nil
    var masterID: String?
}

// MARK: - 実戦1件の「その瞬間」DTO

/// `GameSession` に JSON で載せる、保存時点の店レート・換金係数・機種スペック。
struct GameSessionSnapshot: Codable, Equatable, Sendable {
    /// 対応する `GameSession.id`
    var sessionID: UUID
    /// その時の店舗レート（例: `Shop.ballsPerCashUnit`＝500pt あたりの貸玉数を `Double` で保持）
    var appliedRate: Double
    /// その時の換金・払出係数（`Shop.payoutCoefficient` と同定義・1玉あたり pt）
    var appliedExchangeRate: Double
    var spec: MachineSpecSnapshot
}

// MARK: - Machine からスナップショット生成（任意・保存処理から呼び出し可能）

extension Machine {
    /// 現在の `Machine` から `MachineSpecSnapshot` を生成する。
    func makeSpecSnapshot() -> MachineSpecSnapshot {
        MachineSpecSnapshot(
            probability: probability,
            border: border,
            payout: effectivePayoutDisplay,
            averageNetPerRound: averageNetPerRound,
            countPerRound: countPerRound,
            supportLimit: supportLimit,
            timeShortRotations: timeShortRotations,
            machineTypeRaw: machineTypeRaw,
            masterID: masterID
        )
    }
}

// MARK: - JSON 変換

extension GameSessionSnapshot {
    /// 標準の `JSONEncoder`（キーはキャメルケースのまま）でエンコード。
    func jsonData(using encoder: JSONEncoder = JSONEncoder()) throws -> Data {
        try encoder.encode(self)
    }

    static func decode(from data: Data, using decoder: JSONDecoder = JSONDecoder()) throws -> GameSessionSnapshot {
        try decoder.decode(GameSessionSnapshot.self, from: data)
    }
}

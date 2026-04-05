import Foundation
import SwiftData

// MARK: - スナップショット由来の期待値再計算（`GameLog.dynamicBorder` と同式）

/// 保存済み `GameSessionSnapshot` から、マスタ変更の影響を受けない期待値計算のための純粋関数。
enum SessionSpecAnalytics {
    /// ボーダー文字列を数値化（`GameLog` の `formulaBorderAsNumber` と同趣旨）
    static func formulaBorderNumeric(fromBorderString s: String) -> Double {
        let t = s.trimmingCharacters(in: .whitespaces)
        if let v = Double(t), v > 0 { return v }
        let numStr = t.filter { $0.isNumber || $0 == "." }
        if !numStr.isEmpty, let v = Double(numStr), v > 0 { return v }
        return 0
    }

    /// `"1/319.5"` 形式の分母（`Machine.probabilityDenominator` と同趣旨）
    static func probabilityDenominator(fromProbabilityString s: String) -> Double {
        let trimmed = s.trimmingCharacters(in: .whitespaces)
        guard let slash = trimmed.firstIndex(of: "/") else { return 0 }
        let after = trimmed[trimmed.index(after: slash)...].trimmingCharacters(in: .whitespaces)
        return Double(after) ?? 0
    }

    /// 店補正後ボーダー（回/千pt実費）。`GameLog.dynamicBorder` と同式。
    static func dynamicBorderPer1kFromSnapshotSpec(
        spec: MachineSpecSnapshot,
        appliedBallsPer500Pt: Double,
        appliedPayoutCoefficientPerBall: Double
    ) -> Double {
        let rate = appliedPayoutCoefficientPerBall
        guard rate > 0, rate.isFinite else { return 0 }
        let balls500 = max(0, appliedBallsPer500Pt)
        let ballsPer1000 = balls500 * 2
        guard ballsPer1000 > 0, ballsPer1000.isFinite else { return 0 }
        let formula = formulaBorderNumeric(fromBorderString: spec.border)
        let oneR = spec.averageNetPerRound
        guard oneR.isFinite else { return 0 }
        let loanCorrection = 250.0 / ballsPer1000
        let exchangeCorrection = 4.0 / rate
        let raw: Double
        if formula > 0 {
            raw = formula * loanCorrection * exchangeCorrection
        } else if oneR > 0 {
            let prob = probabilityDenominator(fromProbabilityString: spec.probability)
            if prob > 0, prob.isFinite {
                raw = prob * 250.0 / oneR * loanCorrection * exchangeCorrection
            } else {
                raw = 1000.0 / (oneR * rate)
            }
        } else {
            return 0
        }
        guard raw.isFinite, !raw.isNaN, raw > 0 else { return 0 }
        return raw
    }

    /// スナップショットの店レート・機種スペックと、保存済み回転・実費から期待値比を再現。
    static func expectationRatioFromSnapshot(session: GameSession, snapshot: GameSessionSnapshot) -> Double? {
        guard let realRate = PStatsCalculator.realRotationRatePer1k(
            normalRotations: session.normalRotations,
            totalRealCostPt: session.totalRealCost,
            fallbackRateAtSave: session.realRotationRateAtSave
        ), realRate > 0 else { return nil }
        let dyn = dynamicBorderPer1kFromSnapshotSpec(
            spec: snapshot.spec,
            appliedBallsPer500Pt: snapshot.appliedRate,
            appliedPayoutCoefficientPerBall: snapshot.appliedExchangeRate
        )
        guard dyn > 0 else { return nil }
        let q = realRate / dyn
        guard q.isFinite, !q.isNaN, q >= 0 else { return nil }
        return q
    }
}

// MARK: - 当時スペック vs 現在マスタ（分析 UI・差分取得用）

/// 実戦1件について「打ち込んだ当時」と「いまのマスタ」の比較。
struct SessionDetailedAnalyticsMetrics: Equatable, Sendable {
    /// 等価ボーダー数値の差（当時スナップショット − 現在マスタ）。両方とも正の数値に解釈できたときのみ。
    var borderDeviation: Double?
    /// スナップショットがあり、同名マスタのスペックが当時と異なる
    var isSpecChanged: Bool
}

extension GameSession {
    /// デコード済みスナップショット（失敗時は nil）
    var decodedGameSessionSnapshot: GameSessionSnapshot? {
        guard let data = snapshotData else { return nil }
        return try? GameSessionSnapshot.decode(from: data)
    }

    /// 分析・欠損余剰用の期待値比。`snapshotData` があるときはスナップショットから再計算（マスタ変更の影響を受けない）。
    var analyticsExpectationRatio: Double {
        if let snap = decodedGameSessionSnapshot,
           let r = SessionSpecAnalytics.expectationRatioFromSnapshot(session: self, snapshot: snap) {
            return r
        }
        return expectationRatioAtSave
    }

    /// 分析・欠損余剰用の期待値（pt）。スナップショットがあるときは `analyticsExpectationRatio` から算出。
    var analyticsTheoreticalValuePt: Int {
        if let snap = decodedGameSessionSnapshot,
           let r = SessionSpecAnalytics.expectationRatioFromSnapshot(session: self, snapshot: snap) {
            return PStatsCalculator.theoreticalValuePt(totalRealCostPt: totalRealCost, expectationRatio: r)
        }
        return theoreticalValue
    }

    /// 現在の `Machine`（同名）とスナップショット `spec` を比較。
    func detailedAnalyticsMetrics(currentMachine: Machine?) -> SessionDetailedAnalyticsMetrics {
        guard let snap = decodedGameSessionSnapshot else {
            return SessionDetailedAnalyticsMetrics(borderDeviation: nil, isSpecChanged: false)
        }
        let snapSpec = snap.spec
        let nameKey = machineName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let m = currentMachine,
              m.name.trimmingCharacters(in: .whitespacesAndNewlines) == nameKey
        else {
            return SessionDetailedAnalyticsMetrics(borderDeviation: nil, isSpecChanged: false)
        }
        let snapF = SessionSpecAnalytics.formulaBorderNumeric(fromBorderString: snapSpec.border)
        let masterF = SessionSpecAnalytics.formulaBorderNumeric(fromBorderString: m.border)
        let borderDeviation: Double? = {
            guard snapF > 0, masterF > 0 else { return nil }
            return snapF - masterF
        }()
        let specChanged =
            snapSpec.probability != m.probability
            || snapSpec.border != m.border
            || snapSpec.payout != m.effectivePayoutDisplay
            || abs(snapSpec.averageNetPerRound - m.averageNetPerRound) > 1e-5
            || snapSpec.countPerRound != m.countPerRound
            || snapSpec.supportLimit != m.supportLimit
            || snapSpec.timeShortRotations != m.timeShortRotations
            || snapSpec.machineTypeRaw != m.machineTypeRaw
            || snapSpec.masterID != m.masterID
        return SessionDetailedAnalyticsMetrics(borderDeviation: borderDeviation, isSpecChanged: specChanged)
    }
}

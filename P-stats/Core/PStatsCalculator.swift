import Foundation

/// P-stats の計算ロジック「真実のソース」。
/// - UI / 分析 / 永続化の各層から同じ定義を参照できるよう、状態を持たない純粋関数として提供する（シングルトン不要）。
/// - ライブ実戦の `GameLog` は内部状態から比率を求めるが、**保存時の期待値・回転率**はここ経由に寄せる。
/// - 永続モデルとドメインの分離・Play の一方向データ流は別途段階的に（`PStatsSchemaVersions`・ViewModel 化）。
enum PStatsCalculator {
    // MARK: - Cashflow

    static func recoveryPt(totalHoldingsBalls: Int, payoutCoefficientPtPerBall: Double) -> Int {
        guard totalHoldingsBalls > 0, payoutCoefficientPtPerBall.isFinite, payoutCoefficientPtPerBall > 0 else { return 0 }
        let v = Double(totalHoldingsBalls) * payoutCoefficientPtPerBall
        return v.isFinite ? Int(v.rounded()) : 0
    }

    static func performancePt(inputCashPt: Int, totalHoldingsBalls: Int, payoutCoefficientPtPerBall: Double) -> Int {
        recoveryPt(totalHoldingsBalls: totalHoldingsBalls, payoutCoefficientPtPerBall: payoutCoefficientPtPerBall) - max(0, inputCashPt)
    }

    // MARK: - Rotation / Border

    /// 実質回転率（回/千pt実費）。
    static func realRotationRatePer1k(
        normalRotations: Int,
        totalRealCostPt: Double,
        fallbackRateAtSave: Double
    ) -> Double? {
        if totalRealCostPt.isFinite, totalRealCostPt > 0, normalRotations > 0 {
            let v = (Double(normalRotations) * 1000.0) / totalRealCostPt
            if v.isFinite, v > 0 { return v }
        }
        if fallbackRateAtSave.isFinite, fallbackRateAtSave > 0 { return fallbackRateAtSave }
        return nil
    }

    /// ボーダーとの差（回/1k） = 実質回転率 − 店補正後ボーダー（あれば）／無ければ等価ボーダー。
    static func borderDiffPer1k(
        excludesFromRotationExpectationAnalytics: Bool,
        realRotationRatePer1k: Double?,
        effectiveBorderPer1kAtSave: Double,
        formulaBorderPer1k: Double
    ) -> Double? {
        guard !excludesFromRotationExpectationAnalytics else { return nil }
        guard let rate = realRotationRatePer1k, rate.isFinite else { return nil }
        if effectiveBorderPer1kAtSave.isFinite, effectiveBorderPer1kAtSave > 0 {
            return rate - effectiveBorderPer1kAtSave
        }
        if formulaBorderPer1k.isFinite, formulaBorderPer1k > 0 {
            return rate - formulaBorderPer1k
        }
        return nil
    }

    /// 保存済みセッションのボーダー差（回/1k）。`GameSession.sessionBorderDiffPer1k` と同一の分岐。
    static func sessionBorderDiffPer1k(
        excludesFromRotationExpectationAnalytics: Bool,
        normalRotations: Int,
        totalRealCost: Double,
        realRotationRateAtSave: Double,
        effectiveBorderPer1kAtSave: Double,
        formulaBorderPer1k: Double
    ) -> Double? {
        if excludesFromRotationExpectationAnalytics { return nil }
        let displayRate = realRotationRatePer1k(
            normalRotations: normalRotations,
            totalRealCostPt: totalRealCost,
            fallbackRateAtSave: realRotationRateAtSave
        )
        if effectiveBorderPer1kAtSave > 0, let rate = displayRate {
            return rate - effectiveBorderPer1kAtSave
        }
        guard formulaBorderPer1k > 0, totalRealCost > 0, normalRotations > 0 else { return nil }
        let rate = (Double(normalRotations) / totalRealCost) * 1000.0
        return rate - formulaBorderPer1k
    }

    /// 回転率の加重平均に用いる分母（pt）。
    static func rotationRateDenominatorPt(totalRealCostPt: Double, inputCashPt: Int) -> Double {
        if totalRealCostPt.isFinite, totalRealCostPt > 0 { return totalRealCostPt }
        return Double(max(0, inputCashPt))
    }

    // MARK: - Expectation

    /// 期待値（pt） = 実質投資 × (期待値比 − 1)
    static func theoreticalValuePt(totalRealCostPt: Double, expectationRatio: Double) -> Int {
        guard totalRealCostPt.isFinite, totalRealCostPt > 0 else { return 0 }
        guard expectationRatio.isFinite else { return 0 }
        let raw = totalRealCostPt * (expectationRatio - 1.0)
        guard raw.isFinite, !raw.isNaN else { return 0 }
        return Int(raw.rounded())
    }

    static func deficitSurplusPt(performancePt: Int, theoreticalValuePt: Int) -> Int {
        performancePt - theoreticalValuePt
    }
}


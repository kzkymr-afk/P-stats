import Testing
@testable import P_stats

@Suite("PStatsCalculator")
struct PStatsCalculatorTests {
    @Test func theoreticalValuePt_positiveExpectation() {
        let v = PStatsCalculator.theoreticalValuePt(totalRealCostPt: 10_000, expectationRatio: 1.1)
        #expect(v == 1_000)
    }

    @Test func theoreticalValuePt_zeroCost() {
        #expect(PStatsCalculator.theoreticalValuePt(totalRealCostPt: 0, expectationRatio: 1.2) == 0)
    }

    @Test func realRotationRatePer1k_basic() {
        let r = PStatsCalculator.realRotationRatePer1k(
            normalRotations: 200,
            totalRealCostPt: 10_000,
            fallbackRateAtSave: 0
        )
        #expect(abs((r ?? 0) - 20) < 0.0001)
    }

    @Test func deficitSurplusPt() {
        #expect(PStatsCalculator.deficitSurplusPt(performancePt: 500, theoreticalValuePt: 300) == 200)
    }

    @Test func sessionBorderDiffPer1k_effectiveBorder() {
        let d = PStatsCalculator.sessionBorderDiffPer1k(
            excludesFromRotationExpectationAnalytics: false,
            normalRotations: 1000,
            totalRealCost: 10_000,
            realRotationRateAtSave: 0,
            effectiveBorderPer1kAtSave: 90,
            formulaBorderPer1k: 100
        )
        #expect(abs((d ?? 0) - 10) < 0.0001)
    }

    @Test func sessionBorderDiffPer1k_excluded() {
        #expect(PStatsCalculator.sessionBorderDiffPer1k(
            excludesFromRotationExpectationAnalytics: true,
            normalRotations: 100,
            totalRealCost: 10_000,
            realRotationRateAtSave: 0,
            effectiveBorderPer1kAtSave: 90,
            formulaBorderPer1k: 100
        ) == nil)
    }

    @Test func sessionBorderDiffPer1k_nanTotalRealCost_noCrash() {
        let d = PStatsCalculator.sessionBorderDiffPer1k(
            excludesFromRotationExpectationAnalytics: false,
            normalRotations: 100,
            totalRealCost: Double.nan,
            realRotationRateAtSave: 0,
            effectiveBorderPer1kAtSave: 0,
            formulaBorderPer1k: 20
        )
        #expect(d == nil)
    }

    @Test func performancePt_negativeHoldingsTreatsRecoveryAsZero() {
        let p = PStatsCalculator.performancePt(
            inputCashPt: 1000,
            totalHoldingsBalls: -10,
            payoutCoefficientPtPerBall: 4
        )
        #expect(p == -1000)
    }
}

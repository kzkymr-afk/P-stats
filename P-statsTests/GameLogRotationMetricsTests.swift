//
//  GameLogRotationMetricsTests.swift
//  P-statsTests
//
//  実質回転率（realRate）と異常入力時の落ちないことの検証。
//

import Testing
@testable import P_stats

@Suite("GameLog・実質回転率")
struct GameLogRotationMetricsTests {

    /// 投資 10,000pt（500pt×20）、貸玉 115玉/500pt（＝1,000pt あたり 230 玉）、通常回転 200 のときの実質回転率。
    ///
    /// 換算玉: (10,000÷500)×115 = 2,300 玉 → 単位 (250玉=1単位) = 9.2
    /// 実質回転率: 200 ÷ 9.2 ≈ 21.739…
    @Test func realRate_isApproximately21_74_for10kPt230BallsPer1kAnd200Spins() {
        let log = GameLog()
        log.selectedShop = Shop(name: "テスト店", ballsPerCashUnit: 115, payoutCoefficient: 4.0)
        log.selectedMachine = Machine(name: "テスト機", supportLimit: 100, defaultPrize: 1500)
        log.addCashInput(pt: 10_000)
        log.normalRotations = 200

        let cashBalls = Double(10_000 / 500) * 115.0
        let units = cashBalls / 250.0
        let expected = 200.0 / units

        #expect(abs(log.effectiveUnitsForBorder - units) < 0.000_1)
        #expect(abs(log.realRate - expected) < 0.001)
        #expect(abs(log.realRate - 21.739_130) < 0.001)
        #expect(abs(log.realRate - 21.74) < 0.01)
    }

    /// 貸玉・払出・回転・投資に異常値が混じっても計算プロパティが有限であり、assert で落ちないこと。
    @Test(arguments: [
        (balls: -115, payout: 4.0, cashPt: 10_000, spins: 200),
        (balls: 115, payout: -1.0, cashPt: 10_000, spins: 200),
        (balls: 115, payout: 0.0, cashPt: 10_000, spins: 200),
        (balls: 0, payout: 4.0, cashPt: 10_000, spins: 200),
        (balls: 115, payout: 4.0, cashPt: 0, spins: 200),
        (balls: 115, payout: 4.0, cashPt: 10_000, spins: -50),
        (balls: -50, payout: -2.0, cashPt: 500, spins: -1),
    ])
    func rotationMetrics_remainFinite_forAbnormalShopAndSpinInputs(
        balls: Int,
        payout: Double,
        cashPt: Int,
        spins: Int
    ) {
        let log = GameLog()
        log.selectedShop = Shop(name: "異常値店", ballsPerCashUnit: balls, payoutCoefficient: payout)
        log.selectedMachine = Machine(name: "異常値機", supportLimit: 100, defaultPrize: 1500)
        if cashPt > 0 {
            log.addCashInput(pt: cashPt)
        }
        log.normalRotations = spins

        let rr = log.realRate
        let eu = log.effectiveUnitsForBorder
        let db = log.dynamicBorder
        let er = log.expectationRatio
        let surface = log.rotationPer1000Yen
        let trc = log.totalRealCost

        #expect(rr.isFinite)
        #expect(eu.isFinite)
        #expect(db.isFinite)
        #expect(er.isFinite)
        #expect(surface.isFinite)
        #expect(trc.isFinite)

        let borderForGauge = db > 0 ? db : 20.0
        _ = log.rotationMetricsDisplayTrust(borderForGauge: borderForGauge)
    }
}

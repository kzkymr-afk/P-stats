import SwiftUI

/// 保存済み `GameSession` 向け：スランプ（収支）グラフ。
/// - 保存時に記録した当たり・投資ログがあれば実戦と同じロジックでプロット
/// - 無ければ `editSessionPhasesJSON` があれば区間累積
/// - それも無ければ (0,0)→(通常回転, 実成績) の2点
struct SessionSlumpChartForSessionView: View {
    let session: GameSession
    var height: CGFloat = 160
    var strokeTint: Color = AppGlassStyle.accent

    private var payoutCoefficient: Double {
        session.payoutCoefficient > 0 ? session.payoutCoefficient : PersistedDataSemantics.defaultPayoutCoefficientPtPerBall
    }

    private var dynamicBorderForSlump: Double {
        if session.effectiveBorderPer1kAtSave > 0 { return session.effectiveBorderPer1kAtSave }
        if session.formulaBorderPer1k > 0 { return session.formulaBorderPer1k }
        return 0.01
    }

    private var holdingsBallsPerTapResolved: Int {
        session.slumpChartHoldingsBallsPerTap > 0 ? session.slumpChartHoldingsBallsPerTap : 125
    }

    /// (x:通常累積回転, y:収支pt)
    private var points: [(Int, Double)] {
        let (wins, lendings) = session.decodedSlumpWinsAndLendings()
        if !wins.isEmpty || !lendings.isEmpty {
            let timeline = SlumpChartTimelineContext(
                sessionStart: session.startedAt,
                timelineEnd: session.endedAt ?? session.date
            )
            let endFifo = SessionSlumpLiveChartPoints.terminalProfitPtWithChodamaFIFO(
                wins: wins,
                lendings: lendings,
                initialHoldings: session.slumpChartInitialHoldings,
                initialDisplayRotation: session.slumpChartInitialDisplayRotation,
                normalRotationsEnd: session.normalRotations,
                dynamicBorder: dynamicBorderForSlump,
                payoutCoefficient: payoutCoefficient,
                holdingsBallsPerTap: holdingsBallsPerTapResolved,
                chodamaCarryInBalls: session.slumpChartChodamaCarryInBalls,
                timeline: timeline
            )
            return SessionSlumpLiveChartPoints.build(
                wins: wins,
                lendings: lendings,
                initialHoldings: session.slumpChartInitialHoldings,
                initialDisplayRotation: session.slumpChartInitialDisplayRotation,
                normalRotationsEnd: session.normalRotations,
                dynamicBorder: dynamicBorderForSlump,
                payoutCoefficient: payoutCoefficient,
                holdingsBallsPerTap: holdingsBallsPerTapResolved,
                finalProfitPt: endFifo,
                chodamaCarryInBalls: session.slumpChartChodamaCarryInBalls,
                timeline: timeline
            )
        }

        let phases = GameSessionEditPhasesStorage.decode(session.editSessionPhasesJSON)
        if !phases.isEmpty {
            var out: [(Int, Double)] = [(0, 0)]
            var cumRot = 0
            var cumPt: Double = 0
            for p in phases {
                let r = max(0, p.rotationsUntilFirstHit)
                let invCash = Double(max(0, p.investmentCashPt))
                let invHold = Double(max(0, p.investmentHoldingsBalls)) * payoutCoefficient
                let rec = Double(max(0, p.recoveryHoldingsBalls)) * payoutCoefficient
                cumRot += r
                cumPt += rec - (invCash + invHold)
                out.append((cumRot, cumPt))
            }
            if session.normalRotations > cumRot {
                out.append((session.normalRotations, Double(session.performance)))
            }
            return out
        }
        let x = max(0, session.normalRotations)
        let y = Double(session.performance)
        if x == 0 { return [(0, 0)] }
        return [(0, 0), (x, y)]
    }

    private var xAxisMax: CGFloat {
        let n = max(0, session.normalRotations)
        if n < 300 { return 300 }
        return CGFloat(max(n, 1))
    }

    private var yRange: (min: Double, max: Double) {
        let ys = points.map(\.1)
        let dataMin = ys.min() ?? 0
        let dataMax = ys.max() ?? 0
        let spanNeeded = max(abs(dataMin), abs(dataMax))
        let half = max(SessionSlumpChartStyle.defaultHalfRangePt, spanNeeded * 1.08)
        return (-half, half)
    }

    var body: some View {
        SessionSlumpChartCanvas(
            points: points,
            yRange: yRange,
            xAxisMax: xAxisMax,
            strokeTint: strokeTint,
            height: height
        )
    }
}

import SwiftUI

/// 保存済み `GameSession` 向け：スランプ（収支）グラフ。
/// - `editSessionPhasesJSON` があれば区間ごとの累積で描画
/// - 無ければ (0,0)→(通常回転, 実成績) の2点で近似
struct SessionSlumpChartForSessionView: View {
    let session: GameSession
    var height: CGFloat = 160
    var strokeTint: Color = AppGlassStyle.accent

    private static let defaultHalfRangePt: Double = 30_000

    private var payoutCoefficient: Double {
        session.payoutCoefficient > 0 ? session.payoutCoefficient : PersistedDataSemantics.defaultPayoutCoefficientPtPerBall
    }

    /// (x:通常累積回転, y:収支pt)
    private var points: [(Int, Double)] {
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
            // 最終点が無い/ズレるケースの軽い補正（通常回転が大きい場合は終点を追加）
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
        let half = max(Self.defaultHalfRangePt, spanNeeded * 1.08)
        return (-half, half)
    }

    var body: some View {
        let pts = points
        let yr = yRange
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let padL: CGFloat = 36
            let padR: CGFloat = 8
            let padT: CGFloat = 22
            let padB: CGFloat = 14
            let plotW = max(1, w - padL - padR)
            let plotH = max(1, h - padT - padB)
            let xMax = xAxisMax

            ZStack(alignment: .topLeading) {
                let y0 = yPtToY(0, minY: yr.min, maxY: yr.max, plotH: plotH)
                Path { p in
                    p.move(to: CGPoint(x: padL, y: padT + y0))
                    p.addLine(to: CGPoint(x: padL + plotW, y: padT + y0))
                }
                .stroke(Color.white.opacity(0.35), lineWidth: 1)

                if pts.count >= 2 {
                    Path { path in
                        for (i, pair) in pts.enumerated() {
                            let xRot = CGFloat(pair.0)
                            let px = padL + min(1, xRot / xMax) * plotW
                            let py = padT + yPtToY(pair.1, minY: yr.min, maxY: yr.max, plotH: plotH)
                            let pt = CGPoint(x: px, y: py)
                            if i == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
                        }
                    }
                    .stroke(strokeTint.opacity(0.95), style: StrokeStyle(lineWidth: 2, lineJoin: .round))
                } else if let last = pts.last {
                    let xRot = CGFloat(last.0)
                    let px = padL + min(1, xRot / xMax) * plotW
                    let py = padT + yPtToY(last.1, minY: yr.min, maxY: yr.max, plotH: plotH)
                    Circle()
                        .fill(strokeTint.opacity(0.95))
                        .frame(width: 6, height: 6)
                        .position(x: px, y: py)
                }

                Text("スランプ（収支）")
                    .font(AppTypography.sectionSubheading)
                    .foregroundColor(.white.opacity(0.92))
                    .padding(6)

                VStack(spacing: 0) {
                    Text(formatPt(yr.max))
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundColor(.white.opacity(0.6))
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    Spacer(minLength: 0)
                    Text("0")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundColor(.white.opacity(0.5))
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    Spacer(minLength: 0)
                    Text(formatPt(yr.min))
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundColor(.white.opacity(0.6))
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .frame(width: padL - 4)
                .frame(height: plotH)
                .padding(.leading, 4)
                .padding(.top, padT)
                .allowsHitTesting(false)

                Text("\(Int(xMax))回")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(0.5))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(.trailing, padR)
                    .padding(.bottom, 4)
            }
        }
        .frame(height: height)
        .frame(maxWidth: .infinity)
        .background(Color.black.opacity(0.88))
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.46),
                            strokeTint.opacity(0.35),
                            Color.white.opacity(0.09)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
    }

    private func yPtToY(_ profit: Double, minY: Double, maxY: Double, plotH: CGFloat) -> CGFloat {
        let t = (profit - minY) / (maxY - minY)
        return plotH * (1 - t)
    }

    private func formatPt(_ v: Double) -> String {
        let k = v / 1000.0
        if abs(k) >= 10 { return String(format: "%+.0fk", k) }
        return String(format: "%+.0f", v)
    }
}


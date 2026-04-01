import SwiftUI

/// 大当たりモード用：横軸＝通常累積回転、縦軸＝損益（pt）。`liveChartPoints` を利用。
struct SessionSlumpLineChartView: View {
    @Bindable var log: GameLog
    var height: CGFloat
    /// 枠・軸ラベル用（RUSH 色で統一可能）
    var strokeTint: Color

    /// 横軸最大：300回未満のときは300、それ以降は現在の通常回転に合わせる
    private var xAxisMax: CGFloat {
        let n = log.normalRotations
        if n < 300 { return 300 }
        return CGFloat(max(n, 1))
    }

    /// 縦軸レンジ：±3万ptをデフォルト。超えたらデータに合わせて拡張（原点は常に中央付近にスケール）
    private static let defaultHalfRangePt: Double = 30_000

    private var yRange: (min: Double, max: Double) {
        let pts = log.liveChartPoints.map(\.1)
        let dataMin = pts.min() ?? 0
        let dataMax = pts.max() ?? 0
        let spanNeeded = max(abs(dataMin), abs(dataMax))
        let half = max(Double(Self.defaultHalfRangePt), spanNeeded * 1.08)
        return (-half, half)
    }

    var body: some View {
        let pts = log.liveChartPoints
        let xr = yRange
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
                // 0 線（損益ゼロ）
                let y0 = yPtToY(0, minY: xr.min, maxY: xr.max, plotH: plotH)
                Path { p in
                    p.move(to: CGPoint(x: padL, y: padT + y0))
                    p.addLine(to: CGPoint(x: padL + plotW, y: padT + y0))
                }
                .stroke(Color.white.opacity(0.35), lineWidth: 1)

                // 折れ線（1点のみのときは点）
                if pts.count >= 2 {
                    Path { path in
                        for (i, pair) in pts.enumerated() {
                            let xRot = CGFloat(pair.0)
                            let px = padL + min(1, xRot / xMax) * plotW
                            let py = padT + yPtToY(pair.1, minY: xr.min, maxY: xr.max, plotH: plotH)
                            let pt = CGPoint(x: px, y: py)
                            if i == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
                        }
                    }
                    .stroke(strokeTint.opacity(0.95), style: StrokeStyle(lineWidth: 2, lineJoin: .round))
                } else if let last = pts.last {
                    let xRot = CGFloat(last.0)
                    let px = padL + min(1, xRot / xMax) * plotW
                    let py = padT + yPtToY(last.1, minY: xr.min, maxY: xr.max, plotH: plotH)
                    Circle()
                        .fill(strokeTint.opacity(0.95))
                        .frame(width: 6, height: 6)
                        .position(x: px, y: py)
                }

                Text("スランプ（収支）")
                    .font(AppTypography.sectionSubheading)
                    .foregroundColor(.white.opacity(0.92))
                    .padding(6)

                // 軸ラベル（左：最大／0／最小）
                VStack(spacing: 0) {
                    Text(formatPt(xr.max))
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundColor(.white.opacity(0.6))
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    Spacer(minLength: 0)
                    Text("0")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundColor(.white.opacity(0.5))
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    Spacer(minLength: 0)
                    Text(formatPt(xr.min))
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

    /// 損益 pt を上がプラスになるよう Y（上端0）
    private func yPtToY(_ profit: Double, minY: Double, maxY: Double, plotH: CGFloat) -> CGFloat {
        let span = maxY - minY
        guard span.isFinite, abs(span) > 1e-9 else { return plotH * 0.5 }
        let t = (profit - minY) / span
        guard t.isFinite, !t.isNaN else { return plotH * 0.5 }
        return plotH * CGFloat(1 - t)
    }

    private func formatPt(_ v: Double) -> String {
        guard v.isValidForNumericDisplay else { return "—" }
        let k = v / 1000.0
        guard k.isValidForNumericDisplay else { return "—" }
        if abs(k) >= 10 { return k.displayFormat("%+.0fk") }
        return v.displayFormat("%+.0f")
    }
}

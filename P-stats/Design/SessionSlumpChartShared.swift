import SwiftUI

// MARK: - スランプ（収支）折れ線チャート共通（実戦中・履歴詳細で同一見た目）

/// レイアウト定数。色は `ThemeManager` / `ApplicationTheme` 参照。
enum SessionSlumpChartStyle {
    static let cornerRadius: CGFloat = 20
    /// 縦軸の片側レンジの下限（±3万pt）。データが超えたら 1.08 倍で拡張。
    static let defaultHalfRangePt: Double = 30_000

    static let padL: CGFloat = 36
    static let padR: CGFloat = 8
    static let padT: CGFloat = 22
    static let padB: CGFloat = 14

    /// 損益 pt を上がプラスになるよう Y（上端0）。非有限・ゼロ幅は中央寄せ。
    static func yPtToY(_ profit: Double, minY: Double, maxY: Double, plotH: CGFloat) -> CGFloat {
        let span = maxY - minY
        guard span.isFinite, abs(span) > 1e-9 else { return plotH * 0.5 }
        let t = (profit - minY) / span
        guard t.isFinite, !t.isNaN else { return plotH * 0.5 }
        return plotH * CGFloat(1 - t)
    }

    static func formatPtAxisLabel(_ v: Double) -> String {
        guard v.isValidForNumericDisplay else { return "—" }
        let k = v / 1000.0
        guard k.isValidForNumericDisplay else { return "—" }
        if abs(k) >= 10 { return k.displayFormat("%+.0fk") }
        return v.displayFormat("%+.0f")
    }
}

/// スランプ折れ線の描画＋パネル装飾を1か所に集約。
struct SessionSlumpChartCanvas: View {
    @EnvironmentObject private var themeManager: ThemeManager

    let points: [(Int, Double)]
    let yRange: (min: Double, max: Double)
    let xAxisMax: CGFloat
    let strokeTint: Color
    var height: CGFloat

    var body: some View {
        let pts = points
        let xr = yRange
        let t = themeManager.currentTheme
        let S = SessionSlumpChartStyle.self
        let panelR = max(0, t.cornerRadius)
        GeometryReader { geo in
            let w = geo.size.width
            let padL = S.padL
            let padR = S.padR
            let padT = S.padT
            let padB = S.padB
            let plotW = max(1, w - padL - padR)
            let plotH = max(1, geo.size.height - padT - padB)
            let xMax = xAxisMax

            ZStack(alignment: .topLeading) {
                let y0 = S.yPtToY(0, minY: xr.min, maxY: xr.max, plotH: plotH)
                Path { p in
                    p.move(to: CGPoint(x: padL, y: padT + y0))
                    p.addLine(to: CGPoint(x: padL + plotW, y: padT + y0))
                }
                .stroke(t.slumpChartZeroLineColor, lineWidth: 1)

                if pts.count >= 2 {
                    Path { path in
                        for (i, pair) in pts.enumerated() {
                            let xRot = CGFloat(pair.0)
                            let px = padL + min(1, xRot / xMax) * plotW
                            let py = padT + S.yPtToY(pair.1, minY: xr.min, maxY: xr.max, plotH: plotH)
                            let pt = CGPoint(x: px, y: py)
                            if i == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
                        }
                    }
                    .stroke(strokeTint.opacity(0.95), style: StrokeStyle(lineWidth: 2, lineJoin: .round))
                } else if let last = pts.last {
                    let xRot = CGFloat(last.0)
                    let px = padL + min(1, xRot / xMax) * plotW
                    let py = padT + S.yPtToY(last.1, minY: xr.min, maxY: xr.max, plotH: plotH)
                    Circle()
                        .fill(strokeTint.opacity(0.95))
                        .frame(width: 6, height: 6)
                        .position(x: px, y: py)
                }

                Text("スランプ（収支）")
                    .font(t.themedFont(size: 14, weight: .semibold))
                    .foregroundColor(t.slumpChartTitleColor)
                    .padding(6)

                VStack(spacing: 0) {
                    Text(S.formatPtAxisLabel(xr.max))
                        .font(t.themedFont(size: 9, weight: .medium, monospaced: true))
                        .foregroundColor(t.slumpChartAxisLabelStrongColor)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    Spacer(minLength: 0)
                    Text("0")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundColor(t.slumpChartAxisLabelMidColor)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    Spacer(minLength: 0)
                    Text(S.formatPtAxisLabel(xr.min))
                        .font(t.themedFont(size: 9, weight: .medium, monospaced: true))
                        .foregroundColor(t.slumpChartAxisLabelStrongColor)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .frame(width: padL - 4)
                .frame(height: plotH)
                .padding(.leading, 4)
                .padding(.top, padT)
                .allowsHitTesting(false)

                Text("\(Int(xMax))回")
                    .font(t.themedFont(size: 9, weight: .medium, monospaced: true))
                    .foregroundColor(t.slumpChartXEndLabelColor)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(.trailing, padR)
                    .padding(.bottom, 4)
            }
        }
        .frame(height: height)
        .frame(maxWidth: .infinity)
        .background(t.slumpChartPanelFillColor, in: RoundedRectangle(cornerRadius: panelR, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: panelR, style: .continuous)
                .stroke(t.accentColor, lineWidth: max(t.borderWidth, 1))
        )
    }
}

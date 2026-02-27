import SwiftUI
import SwiftData

/// 通常大当たり後のチャンスモード：フォーカスモードに準じた構成。上3/8＝折れ線、1/8＝履歴、下1/2＝左2/3 RUSH・右1/3 時短終了
struct ChanceModeView: View {
    @Bindable var log: GameLog
    let onExit: () -> Void

    private let accent = AppGlassStyle.accent
    private let bg = AppGlassStyle.background
    private let maxChartHours: Double = 13
    private let timeShortAccent = Color.orange

    var body: some View {
        GeometryReader { geo in
            let top = geo.size.height * (3.0 / 8.0)
            let mid = geo.size.height * (1.0 / 8.0)
            let bottom = geo.size.height * 0.5
            ZStack {
                bg.ignoresSafeArea()
                VStack(spacing: 0) {
                    // 上3/8: 損益折れ線グラフ
                    profitLineChartView(height: top)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)

                    // 1/8: 大当たり履歴
                    WinHistoryBarChartView(records: Array(log.winRecords.suffix(30)), maxHeight: mid)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)

                    // 下1/2: 左2/3 RUSH / 右1/3 時短終了（角丸・通常画面と同様）
                    HStack(spacing: 6) {
                        Button(action: {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            log.addWin(type: .rush, atRotation: log.totalRotations)
                        }) {
                            ZStack {
                                AppGlassStyle.cardBackground
                                Text("RUSH")
                                    .font(.system(size: 22, weight: .bold, design: .monospaced))
                                    .foregroundColor(Color.red.opacity(0.9))
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.red.opacity(0.4), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .frame(maxWidth: .infinity)

                        Button(action: {
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            log.endTimeShortAndReturnToNormal()
                            onExit()
                        }) {
                            ZStack {
                                AppGlassStyle.cardBackground
                                VStack(spacing: 4) {
                                    Text("時短")
                                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                                    Text("終了")
                                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                                        .foregroundColor(timeShortAccent)
                                }
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppGlassStyle.strokeGradient, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .frame(width: geo.size.width * (1.0 / 3.0))
                    }
                    .frame(height: bottom)
                }
            }
        }
    }

    @ViewBuilder
    private func profitLineChartView(height: CGFloat) -> some View {
        let start = log.sessionStartDate ?? Date()
        let now = Date()
        let rangeSec = max(now.timeIntervalSince(start), 1)
        let rangeSecCap = min(rangeSec, maxChartHours * 3600)
        let points = log.chartTimeline
            .filter { $0.0.timeIntervalSince(start) >= 0 }
            .sorted { $0.0 < $1.0 }
        let allY = points.map(\.1) + [0]
        let minY = (allY.min() ?? 0) - 200
        let maxY = (allY.max() ?? 0) + 200
        let yRange = max(maxY - minY, 1)
        let chartH = height - 24

        VStack(alignment: .leading, spacing: 2) {
            Text("損益（現在の持ち玉−投資）円")
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundColor(accent.opacity(0.7))
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(AppGlassStyle.rowBackground)
                    .frame(height: chartH)
                GeometryReader { g in
                    let w = g.size.width
                    let h = g.size.height
                    let zeroY = h - CGFloat((0 - minY) / yRange) * h
                    Path { path in
                        path.move(to: CGPoint(x: 0, y: zeroY))
                        path.addLine(to: CGPoint(x: w, y: zeroY))
                    }
                    .stroke(accent.opacity(0.35), style: StrokeStyle(lineWidth: 1))
                    if !points.isEmpty {
                        Path { path in
                            for (i, p) in points.enumerated() {
                                let tx = p.0.timeIntervalSince(start)
                                let x = CGFloat(min(tx, rangeSecCap)) / CGFloat(rangeSecCap) * w
                                let y = h - CGFloat((p.1 - minY) / yRange) * h
                                if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
                                else { path.addLine(to: CGPoint(x: x, y: y)) }
                            }
                        }
                        .stroke(accent, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    }
                }
                .frame(height: chartH)
            }
            .frame(height: chartH)
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(AppGlassStyle.strokeGradient, lineWidth: 1))
            HStack {
                Text("0h").font(.system(size: 8, design: .monospaced)).foregroundColor(accent.opacity(0.5))
                Spacer()
                Text(String(format: "%.1fh", rangeSecCap / 3600)).font(.system(size: 8, design: .monospaced)).foregroundColor(accent.opacity(0.5))
            }
        }
        .frame(height: height)
    }
}

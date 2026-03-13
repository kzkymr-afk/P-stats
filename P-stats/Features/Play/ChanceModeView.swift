import SwiftUI
import SwiftData

/// 通常大当たり後のチャンスモード：フォーカスモードに準じた構成。上3/8＝折れ線、1/8＝履歴、下1/2＝左2/3 RUSH・右1/3 昇格/時短終了
struct ChanceModeView: View {
    @Bindable var log: GameLog
    var onRushExit: () -> Void
    /// LT仕様削除のため未使用。nil のときは LT 昇格ボタンを表示しない。
    var onLtExit: (() -> Void)? = nil
    var onTimeShortEnd: () -> Void

    private let accent = AppGlassStyle.accent
    private let bg = AppGlassStyle.background
    private let maxChartHours: Double = 13
    private let timeShortAccent = Color.orange
    private let panelBg = Color.black.opacity(0.85)
    private var glassStroke: LinearGradient {
        LinearGradient(
            colors: [
                Color.white.opacity(0.42),
                accent.opacity(0.35),
                Color.white.opacity(0.08)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    var body: some View {
        GeometryReader { geo in
            let top = geo.size.height * (3.0 / 8.0)
            let mid = geo.size.height * (1.0 / 8.0)
            let bottom = geo.size.height * 0.5
            let w = max(1, geo.size.width)
            let chartAreaH = max(1, top)
            let chartAreaW = max(1, w - 32)
            let chartSizeValid = chartAreaH.isFinite && chartAreaH > 0 && chartAreaW.isFinite && chartAreaW > 0
            ZStack {
                bg.ignoresSafeArea()
                VStack(spacing: 0) {

                    // 上3/8: 損益折れ線グラフ（幅は親に合わせる）。寸法が無効なときは表示しない
                    Group {
                        if chartSizeValid {
                            profitLineChartView(height: chartAreaH, availableWidth: chartAreaW)
                        } else {
                            Color.clear.frame(width: 44, height: 44)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)

                    // 1/8: 大当たり履歴（角丸パネル）
                    WinHistoryBarChartView(records: Array(log.winRecords.suffix(30)), maxHeight: mid)
                        .padding(6)
                        .frame(maxWidth: .infinity)
                        .background(panelBg)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(glassStroke, lineWidth: 1))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 4)

                    // 下1/2: 引き戻し(左半分) / 右半分上: RUSH昇格 / 右半分下: 時短終了
                    HStack(spacing: 6) {
                        // 左半分: 引き戻し (RUSH当たり)
                        Button(action: {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            log.addWin(type: .rush, atRotation: log.totalRotations)
                        }) {
                            ZStack {
                                AppGlassStyle.cardBackground
                                VStack(spacing: 8) {
                                    Text("引き戻し")
                                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                                        .foregroundColor(AppGlassStyle.rushColor.opacity(0.8))
                                    Text("RUSH")
                                        .font(.system(size: 24, weight: .bold, design: .monospaced))
                                        .foregroundColor(AppGlassStyle.rushColor.opacity(AppGlassStyle.rushTitleOpacity))
                                }
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppGlassStyle.rushColor.opacity(AppGlassStyle.rushStrokeOpacity), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .frame(maxWidth: .infinity)

                        // 右半分: RUSH昇格 / LT昇格（hasLT時） / 時短終了
                        VStack(spacing: 6) {
                            // 上: RUSH昇格
                            Button(action: {
                                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                log.promoteLastNormalToRush()
                                onRushExit()
                            }) {
                                ZStack {
                                    AppGlassStyle.cardBackground
                                    HStack(spacing: 6) {
                                        Text("RUSH")
                                            .font(.system(size: 16, weight: .bold, design: .monospaced))
                                        Text("昇格")
                                            .font(.system(size: 16, weight: .bold, design: .monospaced))
                                    }
                                    .foregroundColor(AppGlassStyle.rushColor)
                                }
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .clipShape(RoundedRectangle(cornerRadius: 16))
                                .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppGlassStyle.rushColor.opacity(0.5), lineWidth: 1))
                            }
                            .buttonStyle(.plain)

                            // 下: 時短終了
                            Button(action: {
                                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                log.endTimeShortAndReturnToNormal()
                                onTimeShortEnd()
                            }) {
                                ZStack {
                                    AppGlassStyle.cardBackground
                                    HStack(spacing: 6) {
                                        Text("時短")
                                            .font(.system(size: 16, weight: .bold, design: .monospaced))
                                        Text("終了")
                                            .font(.system(size: 16, weight: .bold, design: .monospaced))
                                            .foregroundColor(timeShortAccent)
                                    }
                                }
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .clipShape(RoundedRectangle(cornerRadius: 16))
                                .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppGlassStyle.strokeGradient, lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .frame(height: bottom)
                    .padding(.horizontal, 16)
                }
                .frame(minWidth: 0, maxWidth: .infinity)
            }
        }
    }

    /// 横軸: 総回転数 0–1000G、1001G以降は100G刻みで窓移動。縦軸: 1000円目盛・5000円中目盛・10000円で「◯万円」表示（左側）
    @ViewBuilder
    private func profitLineChartView(height: CGFloat, availableWidth: CGFloat = .infinity) -> some View {
        let safeHeight: CGFloat = (height.isFinite && height > 0) ? height : 44
        let chartH: CGFloat = (safeHeight - 44).isFinite && (safeHeight - 44) > 0 ? max(1, safeHeight - 44) : 44
        let totalRot = log.normalRotations
        let leftRot = totalRot > 1000 ? ((totalRot - 1) / 100) * 100 : 0
        let rightRot = leftRot + 1000
        let rotRange = max(rightRot - leftRot, 1)
        let points = log.liveChartPoints
            .filter { $0.0 >= leftRot && $0.0 <= rightRot }
            .sorted { $0.0 < $1.0 }
        let allY = points.map(\.1) + [0]
        let rawMinY = allY.min() ?? 0
        let rawMaxY = allY.max() ?? 0
        let minY = (rawMinY - 200).rounded(downTo: 1000)
        let maxY = (rawMaxY + 200).rounded(upTo: 1000)
        let yRange = max(maxY - minY, 1000.0)
        let safeAvailableWidth: CGFloat = max(1, (availableWidth.isFinite && availableWidth > 0) ? availableWidth : 300)
        let axisLabelWidth: CGFloat = max(1, min(54, safeAvailableWidth * 0.14))
        // ランタイムの Invalid frame dimension を防ぐため、必ず正の有限値のみ使用
        let safeFrameW: CGFloat = (axisLabelWidth.isFinite && axisLabelWidth > 0) ? min(500, max(1, axisLabelWidth)) : 20
        let safeFrameH: CGFloat = (chartH.isFinite && chartH > 0) ? min(2000, max(1, chartH)) : 44
        let safeTotalH: CGFloat = (safeHeight.isFinite && safeHeight > 0) ? min(2000, max(1, safeHeight)) : 44
        let dimensionsValid = safeFrameW.isFinite && safeFrameW >= 1 && safeFrameH.isFinite && safeFrameH >= 1 && safeTotalH.isFinite && safeTotalH >= 1

        if dimensionsValid {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.system(size: 14, weight: .bold))
                Text("成績グラフ")
                    .font(.system(size: 14, weight: .bold, design: .default))
            }
            .foregroundColor(accent.opacity(0.9))
            .padding(.leading, safeFrameW + 8)

            HStack(alignment: .center, spacing: 0) {
                Spacer(minLength: 0)
                // 縦軸ラベル
                ZStack(alignment: .trailing) {
                    ForEach(yAxisLabelValues(minY: minY, maxY: maxY), id: \.self) { yVal in
                        let y = safeFrameH - CGFloat((Double(yVal) - minY) / yRange) * safeFrameH
                        Text(yAxisLabelString(yVal))
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(accent.opacity(0.8))
                            .position(x: max(0, safeFrameW - 6), y: y)
                    }
                }
                .frame(width: safeFrameW, height: safeFrameH)
                
                Rectangle()
                    .fill(accent.opacity(0.3))
                    .frame(width: 1, height: safeFrameH)
                
                ZStack(alignment: .center) {
                    Rectangle()
                        .fill(AppGlassStyle.rowBackground)
                        .frame(height: safeFrameH)
                    
                    GeometryReader { g in
                        let w = max(1, g.size.width.isFinite ? g.size.width : 1)
                        let h = max(1, g.size.height.isFinite ? g.size.height : 1)
                        let zeroY = h - CGFloat((0 - minY) / yRange) * h
                        
                        ZStack(alignment: .leading) {
                            // 横グリッド線
                            ForEach(yTickValuesAll(minY: minY, maxY: maxY), id: \.self) { yVal in
                                let y = h - CGFloat((yVal - minY) / yRange) * h
                                let isMajor = Int(yVal) % 10000 == 0
                                let isMedium = Int(yVal) % 5000 == 0
                                if isMajor || isMedium {
                                    Path { path in
                                        path.move(to: CGPoint(x: 0, y: y))
                                        path.addLine(to: CGPoint(x: w, y: y))
                                    }
                                    .stroke(accent.opacity(isMajor ? 0.25 : 0.1), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                                } else {
                                    Path { path in
                                        path.move(to: CGPoint(x: 0, y: y))
                                        path.addLine(to: CGPoint(x: 4, y: y))
                                    }
                                    .stroke(accent.opacity(0.15), style: StrokeStyle(lineWidth: 1))
                                }
                            }
                            
                            // 縦グリッド（回転数）
                            ForEach(xTickValues(left: leftRot, right: rightRot), id: \.self) { rot in
                                let x = CGFloat(rot - leftRot) / CGFloat(rotRange) * w
                                Path { path in
                                    path.move(to: CGPoint(x: x, y: 0))
                                    path.addLine(to: CGPoint(x: x, y: h))
                                }
                                .stroke(accent.opacity(0.1), style: StrokeStyle(lineWidth: 1, dash: [2, 4]))
                            }

                            // 0ライン
                            Path { path in
                                path.move(to: CGPoint(x: 0, y: zeroY))
                                path.addLine(to: CGPoint(x: w, y: zeroY))
                            }
                            .stroke(accent.opacity(0.5), style: StrokeStyle(lineWidth: 1.5))
                            
                            if !points.isEmpty {
                                // グラフの塗りつぶし (Area)
                                Path { path in
                                    for (i, p) in points.enumerated() {
                                        let x = CGFloat(p.0 - leftRot) / CGFloat(rotRange) * w
                                        let y = h - CGFloat((p.1 - minY) / yRange) * h
                                        if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
                                        else { path.addLine(to: CGPoint(x: x, y: y)) }
                                    }
                                    if let last = points.last, let first = points.first {
                                        let lastX = CGFloat(last.0 - leftRot) / CGFloat(rotRange) * w
                                        let firstX = CGFloat(first.0 - leftRot) / CGFloat(rotRange) * w
                                        path.addLine(to: CGPoint(x: lastX, y: h))
                                        path.addLine(to: CGPoint(x: firstX, y: h))
                                        path.closeSubpath()
                                    }
                                }
                                .fill(LinearGradient(
                                    colors: [accent.opacity(0.35), accent.opacity(0.0)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                ))
                                
                                // 折れ線
                                Path { path in
                                    for (i, p) in points.enumerated() {
                                        let x = CGFloat(p.0 - leftRot) / CGFloat(rotRange) * w
                                        let y = h - CGFloat((p.1 - minY) / yRange) * h
                                        if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
                                        else { path.addLine(to: CGPoint(x: x, y: y)) }
                                    }
                                }
                                .stroke(accent, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                                
                                // マーカー
                                ForEach(winMarkerPoints(points: points), id: \.rotation) { item in
                                    let x = CGFloat(item.rotation - leftRot) / CGFloat(rotRange) * w
                                    let y = h - CGFloat((item.profit - minY) / yRange) * h
                                    Circle()
                                        .fill(item.type == .rush ? Color.red : Color.blue)
                                        .frame(width: 8, height: 8)
                                        .overlay(Circle().stroke(Color.white.opacity(0.9), lineWidth: 1.5))
                                        .position(x: x, y: y)
                                        .shadow(color: .black.opacity(0.5), radius: 2, x: 0, y: 1)
                                }
                            }
                        }
                    }
                    .frame(height: safeFrameH)
                }
                .frame(maxWidth: .infinity)
                .frame(height: safeFrameH)
                Spacer(minLength: 0)
            }
            .frame(height: safeFrameH)
            
            // 横軸ラベル（回転数）
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                HStack(spacing: 0) {
                    ForEach(xTickValues(left: leftRot, right: rightRot), id: \.self) { rot in
                        Text("\(rot)")
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                            .foregroundColor(accent.opacity(0.7))
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                        if rot < rightRot { Spacer(minLength: 0) }
                    }
                }
                .padding(.leading, safeFrameW + 1)
                .padding(.trailing, 8)
                Spacer(minLength: 0)
            }
        }
        .frame(minWidth: 1, minHeight: 1)
        .padding(12)
        .frame(minWidth: 0, maxWidth: .infinity)
        .frame(height: safeTotalH)
        .background(panelBg)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(glassStroke, lineWidth: 1))
        } else {
            Color.clear.frame(width: 44, height: 44)
        }
    }

    /// 縦軸: 1000円刻み（小目盛・中目盛・ラベル用の全目盛り）
    private func yTickValuesAll(minY: Double, maxY: Double) -> [Double] {
        var list: [Double] = []
        var v = (minY / 1000).rounded(.down) * 1000
        while v <= maxY {
            list.append(v)
            v += 1000
        }
        return list
    }

    /// 縦軸ラベル: 10000円単位で「◯万円」表示
    private func yAxisLabelValues(minY: Double, maxY: Double) -> [Int] {
        var list: [Int] = []
        var v = Int((minY / 10000).rounded(.down) * 10000)
        while v <= Int(maxY) {
            list.append(v)
            v += 10000
        }
        return list
    }

    private func yAxisLabelString(_ yVal: Int) -> String {
        if yVal >= 0 { return "+\(yVal / 10000)万" }
        return "\(yVal / 10000)万"
    }

    private func xTickValues(left: Int, right: Int) -> [Int] {
        stride(from: left, through: right, by: 100).map { $0 }
    }

    /// 収支グラフ上で大当たり位置に表示する丸マーカー用（RUSH=赤・通常=青）。横軸は総回転数
    private func winMarkerPoints(points: [(Int, Double)]) -> [(rotation: Int, profit: Double, type: WinType)] {
        points.compactMap { p in
            guard p.0 != 0 else { return nil }
            let xRot = p.0
            guard let record = log.winRecords.first(where: { (record) in (record.normalRotationsAtWin ?? record.rotationAtWin) == xRot }) else { return nil }
            return (rotation: xRot, profit: p.1, type: record.type)
        }
    }
}

private extension Double {
    func rounded(downTo step: Double) -> Double { (self / step).rounded(.down) * step }
    func rounded(upTo step: Double) -> Double { (self / step).rounded(.up) * step }
}

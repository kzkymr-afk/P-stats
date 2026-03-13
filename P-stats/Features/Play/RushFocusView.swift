import SwiftUI
import SwiftData

/// RUSHフォーカスモード：上3/8＝折れ線、1/8＝大当たり履歴、下1/2＝RUSHボタン、右下＝RUSH終了。フェーズ4: machineDetail があればそのモードの bonuses を動的表示。
struct RushFocusView: View {
    @Bindable var log: GameLog
    var machineDetail: MachineDetail? = nil
    let onExit: () -> Void

    @State private var showRushEndSheet = false

    private let accent = AppGlassStyle.accent
    private let modeIdRush = 1
    private let bg = AppGlassStyle.background
    private let maxChartHours: Double = 13

    var body: some View {
        GeometryReader { geo in
            let top = geo.size.height * (3.0 / 8.0)
            let mid = geo.size.height * (1.0 / 8.0)
            let bottom = geo.size.height * 0.5
            let w = max(1, geo.size.width)
            let exitSquareSize = min(w / 3.0, 120)
            ZStack {
                bg.ignoresSafeArea()
                VStack(spacing: 0) {
                    // 上3/8: 損益折れ線グラフ（幅は親に合わせる）
                    profitLineChartView(height: top, availableWidth: w - 32)
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

                    // 下1/2: RUSHボタン（フェーズ4: machineDetail なら bonuses を動的表示）＋右下にRUSH終了
                    ZStack(alignment: .bottomTrailing) {
                        rushBonusButtons

                        HStack(spacing: 8) {
                            Button(action: {
                                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                showRushEndSheet = true
                            }) {
                                ZStack {
                                    AppGlassStyle.rushColor.opacity(0.2)
                                    Text("RUSH\n終了")
                                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                                        .foregroundColor(AppGlassStyle.rushColor)
                                        .multilineTextAlignment(.center)
                                }
                                .frame(width: exitSquareSize, height: exitSquareSize)
                                .clipShape(RoundedRectangle(cornerRadius: 16))
                                .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppGlassStyle.rushColor.opacity(0.5), lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.trailing, 12)
                        .padding(.bottom, 12)
                    }
                    .frame(height: bottom)
                    .padding(.horizontal, 16)
                }
                .frame(minWidth: 0, maxWidth: .infinity)
            }
        }
        .sheet(isPresented: $showRushEndSheet) {
            RushEndInputSheet(log: log, onConfirm: {
                showRushEndSheet = false
                log.endRushAndReturnToNormal()
                onExit()
            }, onCancel: { showRushEndSheet = false })
        }
    }

    @ViewBuilder
    private var rushBonusButtons: some View {
        if let mode = machineDetail?.modes.first(where: { $0.modeId == modeIdRush }), !mode.bonuses.isEmpty {
            if mode.bonuses.count == 1, let bonus = mode.bonuses.first {
                Button(action: {
                    OrganicHaptics.playRushHeartbeat()
                    log.recordHit(bonus: bonus, atRotation: log.totalRotations)
                }) {
                    ZStack {
                        AppGlassStyle.rushColor.opacity(AppGlassStyle.rushBackgroundOpacity)
                        Text(bonus.name)
                            .font(.system(size: 22, weight: .bold, design: .monospaced))
                            .foregroundColor(AppGlassStyle.rushColor.opacity(AppGlassStyle.rushTitleOpacity))
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppGlassStyle.rushColor.opacity(AppGlassStyle.rushStrokeOpacity), lineWidth: 1))
                }
                .buttonStyle(.plain)
            } else {
                VStack(spacing: 8) {
                    ForEach(mode.bonuses) { bonus in
                        Button(action: {
                            OrganicHaptics.playRushHeartbeat()
                            log.recordHit(bonus: bonus, atRotation: log.totalRotations)
                        }) {
                            ZStack {
                                AppGlassStyle.rushColor.opacity(AppGlassStyle.rushBackgroundOpacity)
                                Text(bonus.name)
                                    .font(.system(size: 18, weight: .bold, design: .monospaced))
                                    .foregroundColor(AppGlassStyle.rushColor.opacity(AppGlassStyle.rushTitleOpacity))
                                    .lineLimit(1)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppGlassStyle.rushColor.opacity(AppGlassStyle.rushStrokeOpacity), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        } else {
            Button(action: {
                OrganicHaptics.playRushHeartbeat()
                log.addWin(type: .rush, atRotation: log.totalRotations)
            }) {
                ZStack {
                    AppGlassStyle.rushColor.opacity(AppGlassStyle.rushBackgroundOpacity)
                    Text("RUSH")
                        .font(.system(size: 22, weight: .bold, design: .monospaced))
                        .foregroundColor(AppGlassStyle.rushColor.opacity(AppGlassStyle.rushTitleOpacity))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppGlassStyle.rushColor.opacity(AppGlassStyle.rushStrokeOpacity), lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
    }

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

    /// 横軸: 総回転数 0–1000G、1001G以降は100G刻みで窓移動（100–1100、200–1200…）
    @ViewBuilder
    private func profitLineChartView(height: CGFloat, availableWidth: CGFloat = .infinity) -> some View {
        let safeHeight: CGFloat = (height.isFinite && height > 0) ? height : 44
        let chartH: CGFloat = max(1, safeHeight - 44)
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
        let minY = (rawMinY - 200).roundedRush(downTo: 1000)
        let maxY = (rawMaxY + 200).roundedRush(upTo: 1000)
        let yRange = max(maxY - minY, 1000.0)
        let axisLabelWidth: CGFloat = min(54, (availableWidth.isFinite ? availableWidth : 300) * 0.14)

        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.system(size: 14, weight: .bold))
                Text("収支グラフ")
                    .font(.system(size: 14, weight: .bold, design: .default))
            }
            .foregroundColor(accent.opacity(0.9))
            .padding(.leading, axisLabelWidth + 8)

            HStack(alignment: .center, spacing: 0) {
                Spacer(minLength: 0)
                // 縦軸ラベル
                ZStack(alignment: .trailing) {
                    ForEach(yAxisLabelValuesRush(minY: minY, maxY: maxY), id: \.self) { yVal in
                        let y = chartH - CGFloat((Double(yVal) - minY) / yRange) * chartH
                        Text(yAxisLabelStringRush(yVal))
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(accent.opacity(0.8))
                            .position(x: axisLabelWidth - 6, y: y)
                    }
                }
                .frame(width: axisLabelWidth, height: max(1, chartH))
                
                Rectangle()
                    .fill(accent.opacity(0.3))
                    .frame(width: 1, height: max(1, chartH))
                
                ZStack(alignment: .center) {
                    Rectangle()
                        .fill(AppGlassStyle.rowBackground)
                        .frame(height: max(1, chartH))
                    
                    GeometryReader { g in
                        let w = max(1, g.size.width)
                        let h = max(1, g.size.height)
                        let zeroY = h - CGFloat((0 - minY) / yRange) * h
                        
                        ZStack(alignment: .leading) {
                            // 横グリッド線
                            ForEach(yTickValuesAllRush(minY: minY, maxY: maxY), id: \.self) { yVal in
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
                            ForEach(xTickValuesRush(left: leftRot, right: rightRot), id: \.self) { rot in
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
                                        .fill(item.type == .rush ? Color.red : (item.type == .lt ? AppGlassStyle.ltColor : Color.blue))
                                        .frame(width: 8, height: 8)
                                        .overlay(Circle().stroke(Color.white.opacity(0.9), lineWidth: 1.5))
                                        .position(x: x, y: y)
                                        .shadow(color: .black.opacity(0.5), radius: 2, x: 0, y: 1)
                                }
                            }
                        }
                    }
                    .frame(height: max(1, chartH))
                }
                .frame(maxWidth: .infinity)
                .frame(height: max(1, chartH))
                Spacer(minLength: 0)
            }
            .frame(height: max(1, chartH))
            
            // 横軸ラベル（回転数）
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                HStack(spacing: 0) {
                    ForEach(xTickValuesRush(left: leftRot, right: rightRot), id: \.self) { rot in
                        Text("\(rot)")
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                            .foregroundColor(accent.opacity(0.7))
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                        if rot < rightRot { Spacer(minLength: 0) }
                    }
                }
                .padding(.leading, axisLabelWidth + 1)
                .padding(.trailing, 8)
                Spacer(minLength: 0)
            }
        }
        .padding(12)
        .frame(minWidth: 0, maxWidth: .infinity)
        .frame(height: max(1, safeHeight))
        .background(panelBg)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(glassStroke, lineWidth: 1))
    }

    private func yTickValuesAllRush(minY: Double, maxY: Double) -> [Double] {
        var list: [Double] = []
        var v = (minY / 1000).rounded(.down) * 1000
        while v <= maxY {
            list.append(v)
            v += 1000
        }
        return list
    }

    private func yAxisLabelValuesRush(minY: Double, maxY: Double) -> [Int] {
        var list: [Int] = []
        var v = Int((minY / 10000).rounded(.down) * 10000)
        while v <= Int(maxY) {
            list.append(v)
            v += 10000
        }
        return list
    }

    private func yAxisLabelStringRush(_ yVal: Int) -> String {
        if yVal >= 0 { return "+\(yVal / 10000)万" }
        return "\(yVal / 10000)万"
    }

    private func xTickValuesRush(left: Int, right: Int) -> [Int] {
        stride(from: left, through: right, by: 100).map { $0 }
    }

    /// 収支グラフ上で大当たり位置に表示する丸マーカー用（RUSH=赤・LT=金・通常=青）。横軸は総回転数
    private func winMarkerPoints(points: [(Int, Double)]) -> [(rotation: Int, profit: Double, type: WinType)] {
        points.compactMap { p in
            guard p.0 != 0 else { return nil }
            let xRot = p.0
            guard let record = log.winRecords.first(where: { (record) in (record.normalRotationsAtWin ?? record.rotationAtWin) == xRot }) else { return nil }
            return (rotation: xRot, profit: p.1, type: record.type)
        }
    }
}

// MARK: - RUSH終了入力（獲得出玉＋終了時回転数）
private struct RushEndInputSheet: View {
    @Bindable var log: GameLog
    let onConfirm: () -> Void
    let onCancel: () -> Void

    @State private var payoutText: String = ""
    @State private var selectedRotation: Int
    @FocusState private var payoutFocused: Bool

    private var rotationOptions: [Int] {
        let support = log.selectedMachine.supportLimit
        let common = [50, 100, 150, 200, 250, 300, 500]
        let set = Set(common + [support])
        return set.sorted()
    }

    init(log: GameLog, onConfirm: @escaping () -> Void, onCancel: @escaping () -> Void) {
        self.log = log
        self.onConfirm = onConfirm
        self.onCancel = onCancel
        _selectedRotation = State(initialValue: log.selectedMachine.supportLimit)
    }

    private var payoutValue: Int? { Int(payoutText.trimmingCharacters(in: .whitespaces)) }
    private var canConfirm: Bool { payoutValue != nil && (payoutValue ?? 0) >= 0 }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("獲得出玉（玉数）", text: $payoutText)
                        .keyboardType(.numberPad)
                        .focused($payoutFocused)
                } header: {
                    Text("獲得出玉")
                } footer: {
                    Text("このRUSHで獲得した出玉数を入力してください。")
                }

                Section {
                    Picker("終了時回転数", selection: $selectedRotation) {
                        ForEach(rotationOptions, id: \.self) { rot in
                            Text("\(rot) 回").tag(rot)
                        }
                    }
                    .pickerStyle(.menu)
                } header: {
                    Text("RUSH終了時の回転数")
                } footer: {
                    Text("マスターで複数ある場合はここで選択。元データはマスターに入力しておきます。")
                }
            }
            .navigationTitle("RUSH終了")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { onCancel() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("確定") {
                        let total = payoutValue ?? 0
                        log.fixTotalChainPrize(finalTotal: total, rotationAtEnd: selectedRotation)
                        onConfirm()
                    }
                    .disabled(!canConfirm)
                }
            }
            .keyboardDismissToolbar()
        }
    }
}

// MARK: - LT（上位RUSH）フォーカスモード（ゴールド系・LT当たり/LT終了）
struct LtFocusView: View {
    @Bindable var log: GameLog
    var machineDetail: MachineDetail? = nil
    let onExit: () -> Void

    private let accent = AppGlassStyle.ltColor
    private let modeIdLt = 2
    private let bg = AppGlassStyle.background
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
            let exitSquareSize = min(w / 3.0, 120)
            ZStack {
                bg.ignoresSafeArea()
                VStack(spacing: 0) {
                    profitLineChartView(height: top, availableWidth: w - 32)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)

                    WinHistoryBarChartView(records: Array(log.winRecords.suffix(30)), maxHeight: mid)
                        .padding(6)
                        .frame(maxWidth: .infinity)
                        .background(panelBg)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(glassStroke, lineWidth: 1))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 4)

                    ZStack(alignment: .bottomTrailing) {
                        ltBonusButtons

                        Button(action: {
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            log.endLtAndReturnToNormal()
                            onExit()
                        }) {
                            ZStack {
                                AppGlassStyle.ltColor.opacity(0.2)
                                Text("LT\n終了")
                                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                                    .foregroundColor(AppGlassStyle.ltColor)
                                    .multilineTextAlignment(.center)
                            }
                            .frame(width: exitSquareSize, height: exitSquareSize)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppGlassStyle.ltColor.opacity(0.5), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .padding(.trailing, 12)
                        .padding(.bottom, 12)
                    }
                    .frame(height: bottom)
                    .padding(.horizontal, 16)
                }
                .frame(minWidth: 0, maxWidth: .infinity)
            }
        }
    }

    @ViewBuilder
    private var ltBonusButtons: some View {
        if let mode = machineDetail?.modes.first(where: { $0.modeId == modeIdLt }), !mode.bonuses.isEmpty {
            if mode.bonuses.count == 1, let bonus = mode.bonuses.first {
                Button(action: {
                    log.recordHit(bonus: bonus, atRotation: log.totalRotations)
                }) {
                    ZStack {
                        AppGlassStyle.ltColor.opacity(AppGlassStyle.ltBackgroundOpacity)
                        Text(bonus.name)
                            .font(.system(size: 22, weight: .bold, design: .monospaced))
                            .foregroundColor(AppGlassStyle.ltColor.opacity(AppGlassStyle.ltTitleOpacity))
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppGlassStyle.ltColor.opacity(AppGlassStyle.ltStrokeOpacity), lineWidth: 1))
                }
                .buttonStyle(.plain)
            } else {
                VStack(spacing: 8) {
                    ForEach(mode.bonuses) { bonus in
                        Button(action: {
                            log.recordHit(bonus: bonus, atRotation: log.totalRotations)
                        }) {
                            ZStack {
                                AppGlassStyle.ltColor.opacity(AppGlassStyle.ltBackgroundOpacity)
                                Text(bonus.name)
                                    .font(.system(size: 18, weight: .bold, design: .monospaced))
                                    .foregroundColor(AppGlassStyle.ltColor.opacity(AppGlassStyle.ltTitleOpacity))
                                    .lineLimit(1)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppGlassStyle.ltColor.opacity(AppGlassStyle.ltStrokeOpacity), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        } else {
            Button(action: {
                log.addWin(type: .lt, atRotation: log.totalRotations)
            }) {
                ZStack {
                    AppGlassStyle.ltColor.opacity(AppGlassStyle.ltBackgroundOpacity)
                    Text("LT")
                        .font(.system(size: 22, weight: .bold, design: .monospaced))
                        .foregroundColor(AppGlassStyle.ltColor.opacity(AppGlassStyle.ltTitleOpacity))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppGlassStyle.ltColor.opacity(AppGlassStyle.ltStrokeOpacity), lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private func profitLineChartView(height: CGFloat, availableWidth: CGFloat = .infinity) -> some View {
        let safeHeight: CGFloat = (height.isFinite && height > 0) ? height : 44
        let chartH: CGFloat = max(1, safeHeight - 44)
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
        let minY = (rawMinY - 200).roundedRush(downTo: 1000)
        let maxY = (rawMaxY + 200).roundedRush(upTo: 1000)
        let yRange = max(maxY - minY, 1000.0)
        let axisLabelWidth: CGFloat = min(54, (availableWidth.isFinite ? availableWidth : 300) * 0.14)

        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.system(size: 14, weight: .bold))
                Text("収支グラフ")
                    .font(.system(size: 14, weight: .bold, design: .default))
            }
            .foregroundColor(accent.opacity(0.9))
            .padding(.leading, axisLabelWidth + 8)

            HStack(alignment: .center, spacing: 0) {
                Spacer(minLength: 0)
                ZStack(alignment: .trailing) {
                    ForEach(yAxisLabelValuesLt(minY: minY, maxY: maxY), id: \.self) { yVal in
                        let y = chartH - CGFloat((Double(yVal) - minY) / yRange) * chartH
                        Text(yAxisLabelStringLt(yVal))
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(accent.opacity(0.8))
                            .position(x: axisLabelWidth - 6, y: y)
                    }
                }
                .frame(width: axisLabelWidth, height: max(1, chartH))
                Rectangle()
                    .fill(accent.opacity(0.3))
                    .frame(width: 1, height: max(1, chartH))
                ZStack(alignment: .center) {
                    Rectangle()
                        .fill(AppGlassStyle.rowBackground)
                        .frame(height: max(1, chartH))
                    GeometryReader { g in
                        let w = max(1, g.size.width)
                        let h = max(1, g.size.height)
                        let zeroY = h - CGFloat((0 - minY) / yRange) * h
                        ZStack(alignment: .leading) {
                            ForEach(yTickValuesAllLt(minY: minY, maxY: maxY), id: \.self) { yVal in
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
                            ForEach(xTickValuesLt(left: leftRot, right: rightRot), id: \.self) { rot in
                                let x = CGFloat(rot - leftRot) / CGFloat(rotRange) * w
                                Path { path in
                                    path.move(to: CGPoint(x: x, y: 0))
                                    path.addLine(to: CGPoint(x: x, y: h))
                                }
                                .stroke(accent.opacity(0.1), style: StrokeStyle(lineWidth: 1, dash: [2, 4]))
                            }
                            Path { path in
                                path.move(to: CGPoint(x: 0, y: zeroY))
                                path.addLine(to: CGPoint(x: w, y: zeroY))
                            }
                            .stroke(accent.opacity(0.5), style: StrokeStyle(lineWidth: 1.5))
                            if !points.isEmpty {
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
                                Path { path in
                                    for (i, p) in points.enumerated() {
                                        let x = CGFloat(p.0 - leftRot) / CGFloat(rotRange) * w
                                        let y = h - CGFloat((p.1 - minY) / yRange) * h
                                        if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
                                        else { path.addLine(to: CGPoint(x: x, y: y)) }
                                    }
                                }
                                .stroke(accent, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                                ForEach(winMarkerPointsLt(points: points), id: \.rotation) { item in
                                    let x = CGFloat(item.rotation - leftRot) / CGFloat(rotRange) * w
                                    let y = h - CGFloat((item.profit - minY) / yRange) * h
                                    let fillColor: Color = item.type == .lt ? AppGlassStyle.ltColor : (item.type == .rush ? Color.red : Color.blue)
                                    Circle()
                                        .fill(fillColor)
                                        .frame(width: 8, height: 8)
                                        .overlay(Circle().stroke(Color.white.opacity(0.9), lineWidth: 1.5))
                                        .position(x: x, y: y)
                                        .shadow(color: .black.opacity(0.5), radius: 2, x: 0, y: 1)
                                }
                            }
                        }
                    }
                    .frame(height: max(1, chartH))
                }
                .frame(maxWidth: .infinity)
                .frame(height: max(1, chartH))
                Spacer(minLength: 0)
            }
            .frame(height: max(1, chartH))
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                HStack(spacing: 0) {
                    ForEach(xTickValuesLt(left: leftRot, right: rightRot), id: \.self) { rot in
                        Text("\(rot)")
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                            .foregroundColor(accent.opacity(0.7))
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                        if rot < rightRot { Spacer(minLength: 0) }
                    }
                }
                .padding(.leading, axisLabelWidth + 1)
                .padding(.trailing, 8)
                Spacer(minLength: 0)
            }
        }
        .padding(12)
        .frame(minWidth: 0, maxWidth: .infinity)
        .frame(height: max(1, safeHeight))
        .background(panelBg)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(glassStroke, lineWidth: 1))
    }

    private func yTickValuesAllLt(minY: Double, maxY: Double) -> [Double] {
        var list: [Double] = []
        var v = (minY / 1000).rounded(.down) * 1000
        while v <= maxY { list.append(v); v += 1000 }
        return list
    }
    private func yAxisLabelValuesLt(minY: Double, maxY: Double) -> [Int] {
        var list: [Int] = []
        var v = Int((minY / 10000).rounded(.down) * 10000)
        while v <= Int(maxY) { list.append(v); v += 10000 }
        return list
    }
    private func yAxisLabelStringLt(_ yVal: Int) -> String {
        if yVal >= 0 { return "+\(yVal / 10000)万" }
        return "\(yVal / 10000)万"
    }
    private func xTickValuesLt(left: Int, right: Int) -> [Int] {
        stride(from: left, through: right, by: 100).map { $0 }
    }
    private func winMarkerPointsLt(points: [(Int, Double)]) -> [(rotation: Int, profit: Double, type: WinType)] {
        points.compactMap { p in
            guard p.0 != 0 else { return nil }
            let xRot = p.0
            guard let record = log.winRecords.first(where: { (record) in (record.normalRotationsAtWin ?? record.rotationAtWin) == xRot }) else { return nil }
            return (rotation: xRot, profit: p.1, type: record.type)
        }
    }
}

private extension Double {
    func roundedRush(downTo step: Double) -> Double { (self / step).rounded(.down) * step }
    func roundedRush(upTo step: Double) -> Double { (self / step).rounded(.up) * step }
}

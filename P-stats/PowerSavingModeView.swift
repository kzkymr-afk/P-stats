import SwiftUI
import SwiftData

// MARK: - 省エネモード（ジェスチャー＋タップ・周辺発光・ミニマルUI）
/// 上半分＝現金投資、下半分＝持ち玉投資。スワイプは左→右に統一。下15％にRUSH/通常ボタン。ゲームカウントはタップで+1。
struct PowerSavingModeView: View {
    @Bindable var log: GameLog
    /// true＝右手操作、false＝左手操作（スワイプは左手モードでも左→右に統一）
    var rightHandMode: Bool = false
    let onExit: () -> Void
    let onOpenRush: () -> Void
    let onOpenNormal: () -> Void

    @State private var ripplePoint: CGPoint?
    @State private var rippleScale: CGFloat = 0.3
    @State private var rippleOpacity: Double = 0.8
    @State private var rippleId = 0

    private let cyan = AppGlassStyle.accent
    private let swipeThreshold: CGFloat = 50
    /// 持ち玉は125玉単位（1スワイプ＝125玉）
    private let holdingsBallsPerSwipe: Int = 125
    /// 現金は500円単位（1スワイプ＝1000円＝2単位）
    private let cashYenPerSwipe: Int = 1000

    /// 画面下部の高さ比率（RUSH・通常ボタン領域）。はみ出し防止のため多めに確保
    private let bottomButtonAreaRatio: CGFloat = 0.22

    private var edgeGlowColor: Color {
        guard log.dynamicBorder > 0, log.effectiveUnitsForBorder > 0 else { return cyan }
        return AppGlassStyle.edgeGlowColor(border: log.dynamicBorder, realRate: log.realRate)
    }

    private let headerFixedHeight: CGFloat = 100
    private let bottomBarFixedHeight: CGFloat = 72

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let safeBottom = geo.safeAreaInsets.bottom
            let bottomH = bottomBarFixedHeight + safeBottom
            let mainH = max(44, h - headerFixedHeight - bottomH)

            ZStack {
                AppGlassStyle.background.ignoresSafeArea()

                Rectangle()
                    .stroke(edgeGlowColor.opacity(0.7), lineWidth: 8)
                    .allowsHitTesting(false)

                if let pt = ripplePoint {
                    Circle()
                        .stroke(cyan.opacity(0.6), lineWidth: 2)
                        .scaleEffect(rippleScale)
                        .opacity(rippleOpacity)
                        .frame(width: 80, height: 80)
                        .position(pt)
                        .allowsHitTesting(false)
                }

                VStack(spacing: 0) {
                    // ヘッダー: グラスモーフィズムで他と統一
                    headerView(geo: geo, headerHeight: headerFixedHeight)
                        .frame(height: headerFixedHeight)

                    // メイン: 左2/5＝現金・持ち玉ボタン、右3/5＝カウントボタン（高さは左列と合わせて縮めて調整）
                    mainActionRow(geo: geo, totalWidth: w, totalHeight: mainH)
                    .frame(maxHeight: .infinity)

                    // 下部: RUSH / 通常（画面内に必ず収める）
                    HStack(spacing: 0) {
                        Button(action: {
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            onOpenRush()
                        }) {
                            Text("RUSH")
                                .font(.system(size: 20, weight: .bold, design: .monospaced))
                                .foregroundColor(AppGlassStyle.rushColor)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                        .buttonStyle(.plain)
                        .background(AppGlassStyle.rushColor.opacity(0.2))
                        .overlay(RoundedRectangle(cornerRadius: 0).stroke(AppGlassStyle.rushColor.opacity(0.6), lineWidth: 1))

                        Button(action: {
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            onOpenNormal()
                        }) {
                            Text("通常")
                                .font(.system(size: 20, weight: .bold, design: .monospaced))
                                .foregroundColor(AppGlassStyle.normalColor)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                        .buttonStyle(.plain)
                        .background(AppGlassStyle.normalColor.opacity(0.2))
                        .overlay(RoundedRectangle(cornerRadius: 0).stroke(AppGlassStyle.normalColor.opacity(0.6), lineWidth: 1))
                    }
                    .frame(height: bottomBarFixedHeight)
                    .padding(.bottom, safeBottom)
                }
            }
        }
        .background(AppGlassStyle.background)
        .transaction { t in t.animation = nil }
    }

    private func headerView(geo: GeometryProxy, headerHeight: CGFloat) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Button(action: {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                onExit()
            }) {
                Image(systemName: "chevron.down.circle.fill")
                    .font(.title2)
                Text("終了")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
            }
            .foregroundColor(cyan.opacity(0.9))
            .buttonStyle(.plain)

            Spacer(minLength: 6)

            VStack(alignment: .leading, spacing: 0) {
                row(label: "現在の回転数", value: "\(log.gamesSinceLastWin)回")
                Divider().background(cyan.opacity(0.3)).padding(.horizontal, 8)
                row(label: "総現金投資", value: "\(log.investment.formattedYen)円")
                Divider().background(cyan.opacity(0.3)).padding(.horizontal, 8)
                row(label: "総持ち玉投資", value: "\(log.holdingsInvestedBalls)玉")
                Divider().background(cyan.opacity(0.3)).padding(.horizontal, 8)
                row(label: "現在の持ち玉数", value: "\(log.totalHoldings)玉")
                Divider().background(cyan.opacity(0.3)).padding(.horizontal, 8)
                HStack(spacing: 12) {
                    row(label: "RUSH", value: "\(log.rushWinCount)回")
                    row(label: "通常", value: "\(log.normalWinCount)回")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.black.opacity(0.85))
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 8)
    }

    private func row(label: String, value: String) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundColor(cyan.opacity(0.85))
            Spacer(minLength: 4)
            Text(value)
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundColor(cyan)
        }
        .padding(.vertical, 6)
    }

    /// 左2/5＝現金・持ち玉ボタン（縦2分割）、右3/5＝カウントボタン（タップ+1）。高さは縮めて調整。
    @ViewBuilder
    private func mainActionRow(geo: GeometryProxy, totalWidth: CGFloat, totalHeight: CGFloat) -> some View {
        let leftW = totalWidth * 2 / 5
        let rightW = totalWidth * 3 / 5
        let rowH = max(80, totalHeight * 0.85)
        let halfH = max(36, rowH / 2)
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                investmentZone(width: leftW, height: halfH, isCash: true, label: "現金 500円", sub: "タップ or スワイプ")
                investmentZone(width: leftW, height: halfH, isCash: false, label: "持ち玉 125玉", sub: "タップ or スワイプ")
            }
            .frame(width: leftW, height: rowH)
            Button(action: {
                log.incrementRotation()
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                triggerRipple(at: CGPoint(x: leftW + rightW / 2, y: rowH / 2))
            }) {
                VStack(spacing: 4) {
                    Text("\(log.gamesSinceLastWin)")
                        .font(.system(size: min(48, rowH * 0.4), weight: .bold, design: .monospaced))
                        .foregroundColor(cyan)
                    Text("タップ+1")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundColor(cyan.opacity(0.8))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .buttonStyle(.plain)
            .frame(width: rightW, height: rowH)
            .background(Color.black.opacity(0.2))
            .overlay(RoundedRectangle(cornerRadius: 0).stroke(cyan.opacity(0.35), lineWidth: 1))
        }
        .frame(height: rowH)
    }

    private func investmentZone(width: CGFloat, height: CGFloat, isCash: Bool, label: String, sub: String) -> some View {
        ZStack {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture {
                    if isCash {
                        log.addLending(type: .cash)
                    } else {
                        guard log.totalHoldings > 0 else { return }
                        log.addLending(type: .holdings)
                    }
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    triggerRipple(at: CGPoint(x: width / 2, y: height / 2))
                }
                .gesture(
                    DragGesture(minimumDistance: 30)
                        .onEnded { value in
                            guard value.translation.width > swipeThreshold else { return }
                            if isCash {
                                log.addCashInvestment(yen: cashYenPerSwipe)
                            } else {
                                log.addHoldingsInvestment(balls: holdingsBallsPerSwipe)
                            }
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        }
                )
            VStack(spacing: 6) {
                Text(label)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(cyan.opacity(0.9))
                Text(sub)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(cyan.opacity(0.5))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .allowsHitTesting(false)
        }
        .frame(height: max(1, height))
        .background(Color.black.opacity(0.2))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(cyan.opacity(0.35), lineWidth: 1.5)
        )
    }

    private func statPill(label: String, value: String, unit: String) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundColor(cyan.opacity(0.8))
            Text(value)
                .font(.system(size: 16, weight: .bold, design: .monospaced))
                .foregroundColor(cyan)
            if !unit.isEmpty {
                Text(unit)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundColor(cyan.opacity(0.8))
            }
        }
        .lineLimit(1)
    }

    private func triggerRipple(at point: CGPoint) {
        rippleId += 1
        ripplePoint = point
        rippleScale = 0.3
        rippleOpacity = 0.6
        withAnimation(.easeOut(duration: 0.25)) {
            rippleScale = 1.8
            rippleOpacity = 0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) {
            ripplePoint = nil
        }
    }
}

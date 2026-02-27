import SwiftUI
import SwiftData

// MARK: - 省エネモード（ジェスチャー＋タップ・周辺発光・ミニマルUI）
/// 上半分＝現金投資、下半分＝持ち玉投資。スワイプは左→右に統一。下15％にRUSH/通常ボタン。ゲームカウントはタップで+1。
struct GesturePlayView: View {
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
    private let holdingsBallsPerSwipe: Int = 250

    /// 画面下部の高さ比率（RUSH・通常ボタン領域）
    private let bottomButtonAreaRatio: CGFloat = 0.15

    private var edgeGlowColor: Color {
        guard log.dynamicBorder > 0, log.effectiveUnitsForBorder > 0 else { return cyan }
        let border = log.dynamicBorder
        let rate = log.realRate
        let diff = rate - border
        if diff > 1.5 { return Color(red: 0.2, green: 0.45, blue: 1.0) }
        if diff > 0.5 { return Color(red: 0, green: 0.83, blue: 1.0) }
        if diff >= -0.5 { return Color.white }
        if diff >= -1.5 { return Color(red: 1.0, green: 0.65, blue: 0.2) }
        return Color(red: 1.0, green: 0.25, blue: 0.25)
    }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let bottomH = h * bottomButtonAreaRatio
            let mainH = h - bottomH
            let topHalfH = mainH / 2

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
                    // ヘッダー: 終了 ＋ 統計（ゲームカウントはタップで+1）
                    headerView(geo: geo, headerHeight: 100)
                        .frame(height: 100)

                    // メイン: 上半分＝現金、下半分＝持ち玉（スワイプは左→右のみ）
                    VStack(spacing: 0) {
                        // 上半分: 現金投資
                        investmentZone(
                            width: w,
                            height: topHalfH,
                            isCash: true,
                            label: "現金 1k",
                            sub: "タップ or 左→右スワイプ"
                        )
                        // 下半分: 持ち玉投資
                        investmentZone(
                            width: w,
                            height: topHalfH,
                            isCash: false,
                            label: "持ち玉 250玉",
                            sub: "タップ or 左→右スワイプ"
                        )
                    }
                    .frame(height: mainH)

                    // 下15%: 左＝RUSH、右＝通常
                    HStack(spacing: 0) {
                        Button(action: {
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            onOpenRush()
                        }) {
                            Text("RUSH")
                                .font(.system(size: 18, weight: .bold, design: .monospaced))
                                .foregroundColor(Color.red.opacity(0.95))
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                        .buttonStyle(.plain)
                        .background(Color.red.opacity(0.12))
                        .overlay(RoundedRectangle(cornerRadius: 0).stroke(Color.red.opacity(0.4), lineWidth: 1))

                        Button(action: {
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            onOpenNormal()
                        }) {
                            Text("通常")
                                .font(.system(size: 18, weight: .bold, design: .monospaced))
                                .foregroundColor(Color.blue.opacity(0.95))
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                        .buttonStyle(.plain)
                        .background(Color.blue.opacity(0.12))
                        .overlay(RoundedRectangle(cornerRadius: 0).stroke(Color.blue.opacity(0.4), lineWidth: 1))
                    }
                    .frame(height: bottomH)
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

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 16) {
                    statPill(label: "RUSH", value: "\(log.rushWinCount)", unit: "")
                    statPill(label: "通常", value: "\(log.normalWinCount)", unit: "回")
                    // ゲームカウント: タップで+1
                    Button(action: {
                        log.incrementRotation()
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        triggerRipple(at: CGPoint(x: geo.size.width / 2, y: headerHeight / 2))
                    }) {
                        HStack(spacing: 3) {
                            Text("通算")
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                .foregroundColor(cyan.opacity(0.65))
                            Text("\(log.totalRotations)")
                                .font(.system(size: 16, weight: .bold, design: .monospaced))
                                .foregroundColor(cyan)
                            Text("回")
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                .foregroundColor(cyan.opacity(0.65))
                        }
                    }
                    .buttonStyle(.plain)
                }
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                HStack(spacing: 6) {
                    Text("総現金投資")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(cyan.opacity(0.7))
                    Text("\(log.investment)円")
                        .font(.system(size: 16, weight: .bold, design: .monospaced))
                        .foregroundColor(cyan.opacity(0.95))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color.black.opacity(0.35))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 12)
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
                            // 左→右スワイプに統一（片手操作しやすい）
                            guard value.translation.width > swipeThreshold else { return }
                            if isCash {
                                log.addCashInvestment(yen: 1000)
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
        .frame(height: height)
        .background(Color.black.opacity(0.2))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(cyan.opacity(0.35), lineWidth: 1.5)
        )
    }

    private func statPill(label: String, value: String, unit: String) -> some View {
        HStack(spacing: 3) {
            Text(label)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundColor(cyan.opacity(0.65))
            Text(value)
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundColor(cyan.opacity(0.95))
            if !unit.isEmpty {
                Text(unit)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(cyan.opacity(0.65))
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

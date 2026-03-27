import SwiftUI
import UIKit

/// 右端配置想定：つまみを左へスライドし、`thresholdFraction`（可動距離の約3/5）以上で `onConfirmed`
struct SlideToConfirmBigHitRail: View {
    var height: CGFloat
    var cornerRadius: CGFloat
    var accent: Color
    var style: BigHitSlideRailStyle = .minimalGlass
    var onConfirmed: () -> Void
    var onAccessibilityConfirmRequested: () -> Void

    /// スライド可能距離に対する確定しきい値（3/5＝可動距離の6割）
    private static let thresholdFraction: CGFloat = 0.6
    /// 角型ハンドルの幅（高さはレールの `height` に合わせる）
    private static let thumbWidth: CGFloat = 40
    private static let horizontalInset: CGFloat = 7
    private static let lockoutSeconds: TimeInterval = 0.55
    private static let completionFlashSeconds: TimeInterval = 0.52

    /// ハンドル位置（左方向が負）。`UIPanGestureRecognizer` で直接更新し SwiftUI のジェスチャー二重状態を避ける
    @State private var panOffset: CGFloat = 0
    @State private var confirmLocked = false
    @State private var showCompletionFlash = false
    @State private var completionBlink = false

    var body: some View {
        GeometryReader { geo in
            let W = geo.size.width.isFinite ? max(0, geo.size.width) : 0
            let H = geo.size.height.isFinite ? max(0, geo.size.height) : 0
            let thumbW = Self.thumbWidth
            let thumbH = H
            let travel = max(1, W - thumbW - Self.horizontalInset * 2)
            let drag = max(-travel, min(0, panOffset))
            let progress = min(1, abs(drag) / travel)
            let thumbCenterX = W - Self.horizontalInset - thumbW / 2 + drag
            let confirmLineX = W - Self.horizontalInset - thumbW / 2 - travel * Self.thresholdFraction

            ZStack {
                ZStack(alignment: .leading) {
                    themedTrackBase(width: W, height: H, progress: progress)
                    confirmZoneLeadingHighlight(width: W, height: H, endX: confirmLineX, cornerRadius: cornerRadius)
                    themedProgressFill(width: W, height: H, cornerRadius: cornerRadius, progress: progress)
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .stroke(themedStroke(progress: progress), lineWidth: themedStrokeWidth)
                    confirmThresholdMarker(height: H, x: confirmLineX)
                    themedLabelRow(thumbReserve: thumbW, progress: progress)
                        .padding(.leading, 10)
                        .padding(.trailing, 4)
                        .allowsHitTesting(false)
                    Rectangle()
                        .fill(Color.clear)
                        .frame(width: max(1, W - thumbW - Self.horizontalInset * 2))
                        .frame(maxHeight: .infinity)
                        .contentShape(Rectangle())
                        .simultaneousGesture(
                            LongPressGesture(minimumDuration: 0.88)
                                .onEnded { _ in
                                    guard !confirmLocked else { return }
                                    onAccessibilityConfirmRequested()
                                }
                        )

                    themedTrailParticles(
                        progress: progress,
                        thumbCenter: CGPoint(x: thumbCenterX, y: H / 2),
                        size: CGSize(width: W, height: H)
                    )
                    .allowsHitTesting(false)

                    HStack(spacing: 0) {
                        Spacer(minLength: 0)
                        thumbVisual(width: thumbW, height: thumbH)
                            .frame(width: thumbW, height: thumbH)
                            .offset(x: panOffset)
                            .overlay {
                                SlideThumbPanBridge(
                                    panOffset: $panOffset,
                                    travel: travel,
                                    thresholdFraction: Self.thresholdFraction,
                                    isInteractionLocked: confirmLocked,
                                    onEnded: { d in
                                        handleEnd(travel: travel, drag: d)
                                    }
                                )
                            }
                    }
                    .padding(.trailing, Self.horizontalInset)
                    .frame(width: W, height: H)
                    .accessibilitySortPriority(1)
                }
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius))

                if showCompletionFlash {
                    completionFlashLayer(width: W, height: H, cornerRadius: cornerRadius)
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }
            }
            .animation(.easeOut(duration: 0.16), value: showCompletionFlash)
            .onChange(of: showCompletionFlash) { _, on in
                if on, style == .neonCyberpunk {
                    Task { @MainActor in
                        for _ in 0..<6 {
                            try? await Task.sleep(nanoseconds: 80_000_000)
                            completionBlink.toggle()
                        }
                    }
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("大当たりを記録するスライド")
            .accessibilityHint("このバーは大当たり（連チャン記録）を始めるためのボタンです。右端のハンドルを左へスワイプし、白い目印のところまで動かすと大当たり記録が始まります。長押しまたはアクションメニューで確認だけ先に開けます。")
            .accessibilityAddTraits(.allowsDirectInteraction)
            .accessibilityActions {
                Button("確認して開始") {
                    onAccessibilityConfirmRequested()
                }
            }
        }
        .frame(height: height.isFinite ? max(0, height) : 0)
    }

    /// 左側「確定ゾーン」をうっすら強調（目印より左側）
    private func confirmZoneLeadingHighlight(width W: CGFloat, height H: CGFloat, endX: CGFloat, cornerRadius: CGFloat) -> some View {
        let safeW = W.isFinite ? max(0, W) : 0
        let safeH = H.isFinite ? max(0, H) : 0
        let safeEnd = endX.isFinite ? endX : 0
        let w = min(max(0, safeEnd), safeW)
        return HStack(spacing: 0) {
            LinearGradient(
                colors: [
                    Color.white.opacity(0.085),
                    Color.white.opacity(0.02)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: w.isFinite ? max(0, w) : 0)
            Spacer(minLength: 0)
        }
        .frame(width: safeW, height: safeH)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .allowsHitTesting(false)
    }

    private func confirmThresholdMarker(height H: CGFloat, x: CGFloat) -> some View {
        let safeH = H.isFinite ? max(0, H) : 0
        // 高さが小さいとき `H - 8` が負になり得るため下限を付ける
        let capH = max(2, min(safeH * 0.68, max(0, safeH - 8)))
        let markerH = capH.isFinite ? capH : 2
        let cx = x.isFinite ? x : 0
        let cy = safeH > 0 ? safeH / 2 : 0
        return Capsule()
            .fill(Color.white.opacity(0.5))
            .frame(width: 2, height: markerH)
            .position(x: cx, y: cy)
            .allowsHitTesting(false)
    }

    private var themedStrokeWidth: CGFloat {
        switch style {
        case .minimalGlass: return 1
        case .waSengoku: return 1.8
        case .premiumGold: return 2
        default: return 1.5
        }
    }

    @ViewBuilder
    private func themedTrackBase(width W: CGFloat, height H: CGFloat, progress: CGFloat) -> some View {
        switch style {
        case .neonCyberpunk:
            ZStack {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.04, green: 0.04, blue: 0.08),
                                Color(red: 0.02, green: 0.02, blue: 0.05)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                HoneycombPattern(cornerRadius: cornerRadius, opacity: 0.14)
                ScanlineSweep(height: H, cornerRadius: cornerRadius)
            }
        case .minimalGlass:
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(.ultraThinMaterial)
                .background(
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.12),
                                    accent.opacity(0.06),
                                    Color.white.opacity(0.08)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                )
        case .mechanicalIndustrial:
            ZStack {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(
                        LinearGradient(
                            stops: [
                                .init(color: Color(red: 0.28, green: 0.22, blue: 0.16), location: 0),
                                .init(color: Color(red: 0.1, green: 0.08, blue: 0.065), location: 0.45),
                                .init(color: Color(red: 0.16, green: 0.12, blue: 0.085), location: 1)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                // 奥行き・反射（写実寄りの下地）
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(
                        RadialGradient(
                            colors: [
                                Color.white.opacity(0.09),
                                Color.black.opacity(0.35),
                                Color.black.opacity(0.58)
                            ],
                            center: .center,
                            startRadius: 4,
                            endRadius: max(W, H) * 0.95
                        )
                    )
                    .blendMode(.overlay)
                MechanicalIndustrialWatchworks(progress: Double(progress), cornerRadius: cornerRadius)
            }
        case .dynamicLiquid:
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(
                    AngularGradient(
                        colors: [
                            Color(red: 0.2, green: 0.5, blue: 0.85),
                            Color(red: 0.6, green: 0.25, blue: 0.9),
                            Color(red: 0.15, green: 0.85, blue: 0.7),
                            Color(red: 0.9, green: 0.35, blue: 0.5),
                            Color(red: 0.2, green: 0.5, blue: 0.85)
                        ],
                        center: .center,
                        angle: .degrees(Double(progress) * 40 - 20)
                    )
                )
                .opacity(0.45)
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(Color.black.opacity(0.35))
                )
        case .waSengoku:
            ZStack {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.05, green: 0, blue: 0),
                                Color(red: 0.45, green: 0.08, blue: 0.08),
                                Color(red: 0.05, green: 0, blue: 0)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                WashiNoiseOverlay(cornerRadius: cornerRadius)
                    .opacity(0.22)
            }
        case .premiumGold:
            ZStack {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.14, green: 0.02, blue: 0.04),
                                Color(red: 0.22, green: 0.04, blue: 0.08),
                                Color(red: 0.1, green: 0.01, blue: 0.03)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                FiligreePattern(cornerRadius: cornerRadius)
                    .opacity(0.35)
                SpinningSigil(progress: Double(progress), cornerRadius: cornerRadius)
            }
        }
    }

    @ViewBuilder
    private func themedProgressFill(width W: CGFloat, height H: CGFloat, cornerRadius: CGFloat, progress: CGFloat) -> some View {
        let p = max(0, min(1, progress))
        let mask = HStack(spacing: 0) {
            Rectangle()
                .frame(width: max(1, W * p))
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)

        switch style {
        case .neonCyberpunk:
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.35, green: 0.75, blue: 1.0).opacity(0.15 + Double(p) * 0.55),
                            Color(red: 0.65, green: 0.2, blue: 1.0).opacity(0.2 + Double(p) * 0.5)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .mask(mask)
        case .minimalGlass:
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.08 + Double(p) * 0.38),
                            Color.white.opacity(0.04 + Double(p) * 0.28)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .mask(mask)
        case .mechanicalIndustrial:
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.75, green: 0.55, blue: 0.18).opacity(0.25 + Double(p) * 0.45),
                            Color(red: 0.35, green: 0.32, blue: 0.3).opacity(0.2 + Double(p) * 0.35)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .mask(mask)
        case .dynamicLiquid:
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(
                    RadialGradient(
                        colors: [
                            Color(red: 0.3, green: 0.95, blue: 0.85).opacity(0.5 + Double(p) * 0.35),
                            Color(red: 0.2, green: 0.4, blue: 0.95).opacity(0.35),
                            Color.purple.opacity(0.25)
                        ],
                        center: .leading,
                        startRadius: 2,
                        endRadius: W * 0.9
                    )
                )
                .mask(mask)
                .blur(radius: 0.6)
        case .waSengoku:
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.08 + Double(p) * 0.72),
                            Color(red: 0.83, green: 0.69, blue: 0.22).opacity(0.15 + Double(p) * 0.55)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .mask(mask)
        case .premiumGold:
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(
                    AngularGradient(
                        colors: [
                            Color(red: 0.85, green: 0.65, blue: 0.2).opacity(0.2 + Double(p) * 0.65),
                            Color(red: 0.7, green: 0.9, blue: 1.0).opacity(0.35 + Double(p) * 0.4),
                            Color(red: 0.95, green: 0.8, blue: 0.25).opacity(0.25 + Double(p) * 0.55)
                        ],
                        center: .center,
                        angle: .degrees(Double(p) * 200 - 100)
                    )
                )
                .mask(mask)
        }
    }

    private func themedStroke(progress: CGFloat) -> AnyShapeStyle {
        let p = Double(progress)
        switch style {
        case .neonCyberpunk:
            return AnyShapeStyle(
                LinearGradient(
                    colors: [
                        Color.cyan.opacity(0.5 + p * 0.35),
                        Color.purple.opacity(0.45 + p * 0.35)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
        case .minimalGlass:
            return AnyShapeStyle(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.45 + p * 0.25),
                        accent.opacity(0.25 + p * 0.2)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        case .mechanicalIndustrial:
            return AnyShapeStyle(
                LinearGradient(
                    colors: [
                        Color(red: 0.55, green: 0.45, blue: 0.3).opacity(0.85),
                        Color(red: 0.35, green: 0.3, blue: 0.25).opacity(0.9)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        case .dynamicLiquid:
            return AnyShapeStyle(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.55),
                        Color.cyan.opacity(0.35 + p * 0.25)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
        case .waSengoku:
            return AnyShapeStyle(
                LinearGradient(
                    colors: [
                        Color(red: 0.83, green: 0.69, blue: 0.22).opacity(0.75 + p * 0.2),
                        Color(red: 0.6, green: 0.1, blue: 0.1).opacity(0.65)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
        case .premiumGold:
            return AnyShapeStyle(
                LinearGradient(
                    colors: [
                        Color(red: 0.9, green: 0.75, blue: 0.35).opacity(0.85),
                        Color(red: 0.55, green: 0.2, blue: 0.35).opacity(0.75)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        }
    }

    @ViewBuilder
    private func themedLabelRow(thumbReserve: CGFloat, progress: CGFloat) -> some View {
        let p = max(0.55, min(1, 0.78 + Double(progress) * 0.2))
        HStack(alignment: .center, spacing: 5) {
            VStack(alignment: .leading, spacing: 3) {
                Text("大当たり")
                    .font(bigHitTitleFont)
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)
                    .foregroundStyle(bigHitTitleStyle)
                    .shadow(color: bigHitTitleShadow.opacity(0.65), radius: 0, x: 0.8, y: 0.8)
                    .shadow(color: bigHitTitleShadow.opacity(0.35), radius: 2, x: 0, y: 0.5)
                Text("左スワイプで確定")
                    .font(subtitleHintFont)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                    .foregroundStyle(subtitleHintStyle(opacity: p))
            }
            Spacer(minLength: thumbReserve + Self.horizontalInset + 6)
        }
    }

    private var bigHitTitleFont: Font {
        switch style {
        case .neonCyberpunk:
            return .system(size: 20, weight: .black, design: .monospaced)
        case .minimalGlass:
            return .system(size: 19, weight: .heavy, design: .rounded)
        case .mechanicalIndustrial:
            return .system(size: 18, weight: .black, design: .default).width(.condensed)
        case .dynamicLiquid:
            return .system(size: 19, weight: .heavy, design: .rounded)
        case .waSengoku:
            return .system(size: 18, weight: .heavy, design: .serif)
        case .premiumGold:
            return .system(size: 19, weight: .heavy, design: .default)
        }
    }

    private var subtitleHintFont: Font {
        switch style {
        case .neonCyberpunk:
            return .system(size: 11, weight: .semibold, design: .monospaced)
        case .minimalGlass, .dynamicLiquid:
            return .system(size: 11, weight: .semibold, design: .rounded)
        case .mechanicalIndustrial:
            return .system(size: 10, weight: .medium, design: .default).width(.condensed)
        case .waSengoku:
            return .system(size: 10, weight: .medium, design: .serif)
        case .premiumGold:
            return .system(size: 11, weight: .medium, design: .default)
        }
    }

    private var bigHitTitleStyle: AnyShapeStyle {
        switch style {
        case .minimalGlass:
            return AnyShapeStyle(Color.white)
        case .mechanicalIndustrial:
            return AnyShapeStyle(
                LinearGradient(
                    colors: [
                        Color(red: 1, green: 0.96, blue: 0.88),
                        Color(red: 0.92, green: 0.72, blue: 0.38)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        case .waSengoku:
            return AnyShapeStyle(
                LinearGradient(
                    colors: [
                        Color.white,
                        Color(red: 0.95, green: 0.82, blue: 0.35)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
        case .premiumGold:
            return AnyShapeStyle(
                LinearGradient(
                    colors: [
                        Color(red: 1, green: 0.92, blue: 0.55),
                        Color(red: 0.95, green: 0.75, blue: 0.35)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        case .neonCyberpunk:
            return AnyShapeStyle(
                LinearGradient(
                    colors: [
                        Color(red: 0.45, green: 0.98, blue: 1),
                        Color(red: 0.85, green: 0.45, blue: 1)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
        case .dynamicLiquid:
            return AnyShapeStyle(Color.white)
        }
    }

    private var bigHitTitleShadow: Color {
        switch style {
        case .neonCyberpunk:
            return .black.opacity(0.95)
        case .minimalGlass, .dynamicLiquid:
            return .black.opacity(0.55)
        case .mechanicalIndustrial:
            return .black.opacity(0.92)
        case .waSengoku:
            return .black.opacity(0.85)
        case .premiumGold:
            return .black.opacity(0.88)
        }
    }

    private func subtitleHintStyle(opacity: Double) -> AnyShapeStyle {
        switch style {
        case .minimalGlass, .dynamicLiquid:
            return AnyShapeStyle(Color.white.opacity(0.88 * opacity))
        case .mechanicalIndustrial:
            return AnyShapeStyle(Color(red: 0.96, green: 0.93, blue: 0.82).opacity(0.95 * opacity))
        case .waSengoku:
            return AnyShapeStyle(Color(red: 0.98, green: 0.9, blue: 0.6).opacity(0.92 * opacity))
        case .premiumGold:
            return AnyShapeStyle(Color(red: 0.98, green: 0.88, blue: 0.45).opacity(0.9 * opacity))
        case .neonCyberpunk:
            return AnyShapeStyle(Color.cyan.opacity(0.75 * opacity))
        }
    }

    @ViewBuilder
    private func thumbVisual(width w: CGFloat, height h: CGFloat) -> some View {
        switch style {
        case .neonCyberpunk:
            thumbNeon(width: w, height: h)
        case .minimalGlass:
            thumbGlass(width: w, height: h)
        case .mechanicalIndustrial:
            thumbIndustrial(width: w, height: h)
        case .dynamicLiquid:
            thumbLiquid(width: w, height: h)
        case .waSengoku:
            thumbWa(width: w, height: h)
        case .premiumGold:
            thumbGold(width: w, height: h)
        }
    }

    private func handleEnd(travel: CGFloat, drag: CGFloat) {
        let reached = abs(drag) >= travel * Self.thresholdFraction
        if reached && !confirmLocked {
            confirmLocked = true
            panOffset = 0
            showCompletionFlash = true
            onConfirmed()
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.completionFlashSeconds) {
                showCompletionFlash = false
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.lockoutSeconds) {
                confirmLocked = false
            }
        } else {
            // 振動（左右ブレ）を抑えたクリティカル寄りスプリング。パン側ですでに最終位置が panOffset に入っている
            withAnimation(.spring(response: 0.24, dampingFraction: 0.98)) {
                panOffset = 0
            }
        }
    }

    // MARK: - Thumbs

    @ViewBuilder
    private func thumbNeon(width w: CGFloat, height h: CGFloat) -> some View {
        let r = max(2, min(w, h) * 0.14)
        let icon = max(12, min(w, h) * 0.36)
        ZStack {
            RoundedRectangle(cornerRadius: r)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(white: 0.42),
                            Color(white: 0.22),
                            Color(white: 0.35)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            RoundedRectangle(cornerRadius: r)
                .stroke(
                    LinearGradient(colors: [.cyan.opacity(0.85), .purple.opacity(0.65)], startPoint: .top, endPoint: .bottom),
                    lineWidth: 1.2
                )
            Image(systemName: "chevron.left.2")
                .font(.system(size: icon, weight: .heavy, design: .monospaced))
                .foregroundStyle(
                    LinearGradient(colors: [.cyan, .purple], startPoint: .leading, endPoint: .trailing)
                )
                .symbolRenderingMode(.hierarchical)
        }
        .frame(width: w, height: h)
        .shadow(color: .cyan.opacity(0.4), radius: 5, x: 0, y: 0)
    }

    @ViewBuilder
    private func thumbGlass(width w: CGFloat, height h: CGFloat) -> some View {
        let r = max(2, min(w, h) * 0.16)
        let icon = max(12, min(w, h) * 0.34)
        ZStack {
            RoundedRectangle(cornerRadius: r)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.94),
                            Color.white.opacity(0.7)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            RoundedRectangle(cornerRadius: r)
                .stroke(Color.white.opacity(0.75), lineWidth: 1.1)
            Image(systemName: "arrow.left")
                .font(.system(size: icon, weight: .bold, design: .rounded))
                .foregroundStyle(
                    LinearGradient(colors: [accent.opacity(0.75), accent.opacity(0.4)], startPoint: .top, endPoint: .bottom)
                )
        }
        .frame(width: w, height: h)
        .shadow(color: .black.opacity(0.2), radius: 6, x: 0, y: 4)
    }

    @ViewBuilder
    private func thumbIndustrial(width w: CGFloat, height h: CGFloat) -> some View {
        let r = max(1.5, min(w, h) * 0.08)
        let icon = max(11, min(w, h) * 0.32)
        ZStack {
            RoundedRectangle(cornerRadius: r)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.5, green: 0.46, blue: 0.4),
                            Color(red: 0.26, green: 0.24, blue: 0.22),
                            Color(red: 0.38, green: 0.34, blue: 0.3)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            RoundedRectangle(cornerRadius: r)
                .stroke(
                    LinearGradient(
                        colors: [
                            Color(red: 0.88, green: 0.76, blue: 0.48),
                            Color(red: 0.5, green: 0.42, blue: 0.3)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1.4
                )
            Image(systemName: "arrowshape.left.fill")
                .font(.system(size: icon, weight: .bold))
                .foregroundStyle(
                    LinearGradient(
                        colors: [
                            Color(red: 0.92, green: 0.88, blue: 0.78),
                            Color(red: 0.62, green: 0.58, blue: 0.52)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .shadow(color: .black.opacity(0.35), radius: 0, x: 0, y: 0.5)
        }
        .frame(width: w, height: h)
        .shadow(color: Color(red: 0.08, green: 0.06, blue: 0.05).opacity(0.9), radius: 3, x: 0, y: 2)
    }

    @ViewBuilder
    private func thumbLiquid(width w: CGFloat, height h: CGFloat) -> some View {
        let r = max(3, min(w, h) * 0.2)
        let icon = max(12, min(w, h) * 0.34)
        ZStack {
            RoundedRectangle(cornerRadius: r)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.65),
                            Color(red: 0.4, green: 0.85, blue: 0.92),
                            Color(red: 0.28, green: 0.38, blue: 0.82)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            RoundedRectangle(cornerRadius: r)
                .stroke(
                    LinearGradient(colors: [.white.opacity(0.6), .cyan.opacity(0.45)], startPoint: .top, endPoint: .bottom),
                    lineWidth: 1.1
                )
            Image(systemName: "arrowtriangle.left.fill")
                .font(.system(size: icon * 0.92, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
        }
        .frame(width: w, height: h)
        .shadow(color: .cyan.opacity(0.35), radius: 5, x: 0, y: 2)
    }

    @ViewBuilder
    private func thumbWa(width w: CGFloat, height h: CGFloat) -> some View {
        let r = max(2, min(w, h) * 0.12)
        let icon = max(12, min(w, h) * 0.32)
        ZStack {
            RoundedRectangle(cornerRadius: r)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.92, green: 0.78, blue: 0.32),
                            Color(red: 0.68, green: 0.46, blue: 0.12)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            RoundedRectangle(cornerRadius: r)
                .stroke(
                    LinearGradient(
                        colors: [
                            Color(red: 0.55, green: 0.12, blue: 0.12),
                            Color(red: 0.82, green: 0.66, blue: 0.22)
                        ],
                        startPoint: .bottomLeading,
                        endPoint: .topTrailing
                    ),
                    lineWidth: 1.8
                )
            Image(systemName: "arrow.left")
                .font(.system(size: icon * 0.88, weight: .heavy, design: .serif))
                .foregroundStyle(Color(red: 0.32, green: 0.06, blue: 0.08).opacity(0.92))
        }
        .frame(width: w, height: h)
        .shadow(color: Color(red: 0.45, green: 0.1, blue: 0.1).opacity(0.45), radius: 4, x: 0, y: 2)
    }

    @ViewBuilder
    private func thumbGold(width w: CGFloat, height h: CGFloat) -> some View {
        let r = max(2, min(w, h) * 0.12)
        let icon = max(12, min(w, h) * 0.32)
        ZStack {
            RoundedRectangle(cornerRadius: r)
                .fill(
                    AngularGradient(
                        colors: [
                            Color(red: 0.96, green: 0.82, blue: 0.38),
                            Color(red: 0.72, green: 0.52, blue: 0.16),
                            Color(red: 0.9, green: 0.74, blue: 0.36),
                            Color(red: 0.62, green: 0.44, blue: 0.14)
                        ],
                        center: .center
                    )
                )
            RoundedRectangle(cornerRadius: r)
                .stroke(Color(red: 0.48, green: 0.24, blue: 0.32), lineWidth: 1.2)
            Image(systemName: "arrow.left.circle.fill")
                .font(.system(size: icon, weight: .bold))
                .foregroundStyle(Color(red: 0.22, green: 0.05, blue: 0.12))
                .shadow(color: Color(red: 0.98, green: 0.9, blue: 0.55).opacity(0.5), radius: 0, x: 0, y: 0.5)
        }
        .frame(width: w, height: h)
        .shadow(color: Color(red: 1, green: 0.82, blue: 0.35).opacity(0.45), radius: 6, x: 0, y: 0)
    }

    // MARK: - Trail & completion

    @ViewBuilder
    private func themedTrailParticles(progress: CGFloat, thumbCenter: CGPoint, size: CGSize) -> some View {
        let p = Double(progress)
        ZStack {
            ForEach(0..<10, id: \.self) { i in
                trailPiece(index: i, progress: p, thumb: thumbCenter, size: size)
            }
        }
    }

    @ViewBuilder
    private func trailPiece(index i: Int, progress p: Double, thumb: CGPoint, size: CGSize) -> some View {
        let phase = Double(i) / 10
        let ox = CGFloat(i * 7 - 35) * CGFloat(p)
        let oy = sin(phase * .pi * 2 + p * 4) * 6 * CGFloat(p)
        switch style {
        case .neonCyberpunk:
            Circle()
                .fill(Color.cyan.opacity(0.35 + p * 0.45))
                .frame(width: 3, height: 3)
                .offset(x: thumb.x + ox - size.width / 2 + CGFloat(20 + i * 4) * CGFloat(p), y: thumb.y + oy - size.height / 2)
                .opacity(p)
        case .minimalGlass:
            Circle()
                .stroke(Color.white.opacity(0.25 + p * 0.35), lineWidth: 1)
                .frame(width: CGFloat(8 + i * 2) * CGFloat(p * 0.5 + 0.1), height: CGFloat(8 + i * 2) * CGFloat(p * 0.5 + 0.1))
                .offset(x: thumb.x - size.width / 2 + ox * 0.3, y: thumb.y - size.height / 2 + oy * 0.3)
                .opacity(p * 0.6)
        case .mechanicalIndustrial:
            Circle()
                .fill(Color.white.opacity(0.25 + p * 0.45))
                .frame(width: 4, height: 4)
                .blur(radius: 1)
                .offset(x: thumb.x - size.width / 2 + ox + CGFloat(12 + i * 5) * CGFloat(p), y: thumb.y - size.height / 2 + oy)
                .opacity(p)
        case .dynamicLiquid:
            Circle()
                .fill(
                    [Color.cyan, Color.purple, Color.pink, Color.blue][i % 4].opacity(0.4 + p * 0.5)
                )
                .frame(width: CGFloat(4 + (i % 3) * 2), height: CGFloat(4 + (i % 3) * 2))
                .offset(x: thumb.x - size.width / 2 + ox * 1.2 + CGFloat(i * 6) * CGFloat(p), y: thumb.y - size.height / 2 + oy * 1.4)
                .opacity(p)
        case .waSengoku:
            Capsule()
                .fill(
                    i % 2 == 0
                        ? Color.pink.opacity(0.45 + p * 0.45)
                        : Color(red: 0.95, green: 0.82, blue: 0.35).opacity(0.35 + p * 0.5)
                )
                .frame(width: 5, height: 3)
                .rotationEffect(.degrees(Double(i * 37)))
                .offset(x: thumb.x - size.width / 2 + ox + CGFloat(8 + i * 6) * CGFloat(p), y: thumb.y - size.height / 2 + oy - CGFloat(i * 2))
                .opacity(p)
        case .premiumGold:
            Image(systemName: "sparkles")
                .font(.system(size: CGFloat(7 + i % 4)))
                .foregroundStyle(Color(red: 0.95, green: 0.85, blue: 0.45).opacity(0.5 + p * 0.5))
                .offset(x: thumb.x - size.width / 2 + ox * 0.5 + CGFloat(i * 9) * CGFloat(p), y: thumb.y - size.height / 2 + oy - CGFloat(i * 3))
                .opacity(p)
        }
    }

    private func completionFlashLayer(width W: CGFloat, height H: CGFloat, cornerRadius: CGFloat) -> some View {
        ZStack {
            switch style {
            case .neonCyberpunk:
                Color.white.opacity(0.82)
                Text("WARNING: BONUS")
                    .font(.system(size: 11, weight: .black, design: .monospaced))
                    .foregroundStyle(Color.red)
                    .opacity(completionBlink ? 1 : 0.15)
            case .minimalGlass:
                LinearGradient(
                    colors: [
                        Color.pink.opacity(0.15),
                        Color.blue.opacity(0.12),
                        Color.mint.opacity(0.12)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                Text("Success")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.95))
            case .mechanicalIndustrial:
                Color(red: 0.15, green: 0.12, blue: 0.1).opacity(0.88)
                Text("連結完了")
                    .font(.system(size: 15, weight: .heavy))
                    .foregroundStyle(Color(red: 0.95, green: 0.85, blue: 0.55))
            case .dynamicLiquid:
                RadialGradient(
                    colors: [.cyan.opacity(0.55), .purple.opacity(0.45), .clear],
                    center: .center,
                    startRadius: 2,
                    endRadius: max(W, H) * 0.55
                )
                Text("WIN")
                    .font(.system(size: 20, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .shadow(color: .cyan, radius: 6)
            case .waSengoku:
                Color.black.opacity(0.55)
                Text("天晴")
                    .font(.system(size: 22, weight: .heavy, design: .serif))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [
                                Color(red: 0.95, green: 0.85, blue: 0.45),
                                Color.white
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
            case .premiumGold:
                ZStack {
                    HStack(spacing: 0) {
                        Rectangle()
                            .fill(
                                LinearGradient(colors: [Color(red: 0.95, green: 0.8, blue: 0.35), .yellow.opacity(0.5)], startPoint: .leading, endPoint: .trailing)
                            )
                            .frame(width: W * 0.42)
                        Spacer()
                        Rectangle()
                            .fill(
                                LinearGradient(colors: [.yellow.opacity(0.5), Color(red: 0.95, green: 0.8, blue: 0.35)], startPoint: .leading, endPoint: .trailing)
                            )
                            .frame(width: W * 0.42)
                    }
                    .opacity(0.9)
                    Text("勝利")
                        .font(.system(size: 20, weight: .heavy))
                        .foregroundStyle(Color(red: 0.2, green: 0.05, blue: 0.08))
                }
            }
        }
        .frame(width: W, height: H)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }
}

// MARK: - UIKit pan bridge

/// `DragGesture` + `@GestureState` だと終了フレームで位置が二重に効きブレやすいため、`UIPanGestureRecognizer` で一本化する。
private struct SlideThumbPanBridge: UIViewRepresentable {
    @Binding var panOffset: CGFloat
    var travel: CGFloat
    var thresholdFraction: CGFloat
    var isInteractionLocked: Bool
    var onEnded: (CGFloat) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UIView {
        let v = UIView()
        v.backgroundColor = UIColor.clear
        v.isUserInteractionEnabled = true
        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePan(_:)))
        pan.cancelsTouchesInView = false
        pan.delaysTouchesBegan = false
        v.addGestureRecognizer(pan)
        return v
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        let c = context.coordinator
        c.binding = $panOffset
        c.travel = max(1, travel)
        c.threshold = thresholdFraction
        c.locked = isInteractionLocked
        c.onEndedClosure = onEnded
    }

    final class Coordinator: NSObject {
        var binding: Binding<CGFloat>?
        var travel: CGFloat = 1
        var threshold: CGFloat = 0.6
        var locked = false
        var onEndedClosure: (CGFloat) -> Void = { _ in }

        private var baseAtStart: CGFloat = 0
        private var hapticStarted = false
        private var hapticCrossed = false

        @objc func handlePan(_ g: UIPanGestureRecognizer) {
            guard let bind = binding, let view = g.view else { return }
            if locked {
                return
            }
            let tx = g.translation(in: view).x
            switch g.state {
            case .began:
                baseAtStart = bind.wrappedValue
                hapticStarted = false
                hapticCrossed = false
            case .changed:
                let clamped = max(-travel, min(0, baseAtStart + tx))
                var tran = Transaction()
                tran.disablesAnimations = true
                tran.animation = nil
                withTransaction(tran) {
                    bind.wrappedValue = clamped
                }
                let prog = travel > 0 ? abs(clamped) / travel : 0
                if !hapticStarted, abs(tx) > 1.5 {
                    hapticStarted = true
                    HapticUtil.impact(.light)
                }
                let thr = max(0, min(1, threshold))
                if prog >= thr - 0.02 {
                    if !hapticCrossed {
                        hapticCrossed = true
                        HapticUtil.impact(.rigid)
                    }
                } else if prog < thr * 0.82 {
                    hapticCrossed = false
                }
            case .ended, .cancelled, .failed:
                let clamped = max(-travel, min(0, baseAtStart + tx))
                var tran = Transaction()
                tran.disablesAnimations = true
                tran.animation = nil
                withTransaction(tran) {
                    bind.wrappedValue = clamped
                }
                hapticStarted = false
                hapticCrossed = false
                onEndedClosure(clamped)
            default:
                break
            }
        }
    }
}

// MARK: - Decorative subviews

private struct HoneycombPattern: View {
    var cornerRadius: CGFloat
    var opacity: Double

    var body: some View {
        GeometryReader { geo in
            Canvas { ctx, s in
                let r: CGFloat = 9
                let cols = Int(ceil(s.width / (r * 1.5))) + 2
                let rows = Int(ceil(s.height / (r * sqrt(3)))) + 2
                for row in 0..<rows {
                    for col in 0..<cols {
                        let ox = CGFloat(col) * r * 1.5 + (row % 2 == 0 ? 0 : r * 0.75)
                        let oy = CGFloat(row) * r * CGFloat(sqrt(3)) * 0.5
                        var p = Path()
                        for k in 0..<6 {
                            let a = CGFloat(k) * .pi / 3 - .pi / 6
                            let x = ox + cos(a) * r
                            let y = oy + sin(a) * r
                            if k == 0 { p.move(to: CGPoint(x: x, y: y)) }
                            else { p.addLine(to: CGPoint(x: x, y: y)) }
                        }
                        p.closeSubpath()
                        ctx.stroke(p, with: .color(Color.cyan.opacity(0.35 * opacity)), lineWidth: 0.6)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        }
    }
}

private struct ScanlineSweep: View {
    var height: CGFloat
    var cornerRadius: CGFloat

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.04, paused: false)) { t in
            let phase = t.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 2.4) / 2.4
            let y = CGFloat(phase) * height
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(
                    LinearGradient(
                        colors: [.clear, Color.cyan.opacity(0.08), .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .mask(
                    Rectangle()
                        .frame(height: 14)
                        .offset(y: y - height / 2)
                )
        }
        .allowsHitTesting(false)
    }
}

// MARK: - メカニカル・インダストリアル（写実寄りスパー近似・噛み合わせ＋前面可動機構）

private struct MechanicalIndustrialWatchworks: View {
    var progress: Double
    var cornerRadius: CGFloat

    private enum Metal {
        static let gold = Color(red: 0.82, green: 0.68, blue: 0.38)
        static let goldDark = Color(red: 0.58, green: 0.44, blue: 0.26)
        static let silver = Color(red: 0.76, green: 0.77, blue: 0.8)
        static let silverDim = Color(red: 0.52, green: 0.53, blue: 0.56)
        static let steel = Color(red: 0.5, green: 0.52, blue: 0.55)
        static let steelDark = Color(red: 0.34, green: 0.36, blue: 0.39)
        static let copper = Color(red: 0.72, green: 0.44, blue: 0.32)
        static let copperDark = Color(red: 0.48, green: 0.3, blue: 0.22)
        static let brass = Color(red: 0.78, green: 0.6, blue: 0.34)
        static let brassDark = Color(red: 0.52, green: 0.38, blue: 0.22)
        static let iron = Color(red: 0.3, green: 0.27, blue: 0.25)
        static let ironDeep = Color(red: 0.18, green: 0.15, blue: 0.13)
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: false)) { timeline in
            let micro = sin(timeline.date.timeIntervalSinceReferenceDate * 2.4) * 0.04
            GeometryReader { _ in
                Canvas { context, size in
                    let w = size.width
                    let h = size.height
                    let p = max(0, min(1, progress))
                    let drive = CGFloat(p * 2 * .pi * 5.5 + micro * Double(p))

                    Self.drawAmbientOcclusion(context: &context, w: w, h: h, cornerRadius: cornerRadius)
                    Self.drawBrushedGrain(context: &context, size: size)
                    Self.drawRivetBackdrop(context: &context, w: w, h: h)
                    Self.drawOilSmudge(context: &context, w: w, h: h, p: p)

                    let m: CGFloat = max(0.78, min(h, w) * 0.058)
                    let yRow = h * 0.56
                    let zs = [14, 11, 10, 11, 9]
                    let faceCols: [Color] = [Metal.brass, Metal.silver, Metal.copper, Metal.steel, Metal.gold]
                    let rimCols: [Color] = [Metal.brassDark, Metal.silverDim, Metal.copperDark, Metal.steelDark, Metal.goldDark]

                    var cx = w * 0.045 + m * CGFloat(zs[0]) / 2
                    var theta = drive
                    var centers: [CGPoint] = []
                    var radii: [CGFloat] = []
                    for i in 0 ..< zs.count {
                        let z = zs[i]
                        let rr = m * CGFloat(z) / 2
                        let c = CGPoint(x: cx, y: yRow)
                        centers.append(c)
                        radii.append(rr)
                        Self.drawSpurGearRealistic(
                            context: &context,
                            center: c,
                            module: m,
                            teeth: z,
                            rotation: theta,
                            face: faceCols[i % faceCols.count],
                            rim: rimCols[i % rimCols.count]
                        )
                        if i + 1 < zs.count {
                            let zN = zs[i + 1]
                            let rN = m * CGFloat(zN) / 2
                            cx += rr + rN
                            theta = -theta * CGFloat(z) / CGFloat(zN) + .pi / CGFloat(zN)
                        }
                    }

                    if centers.count >= 3 {
                        let c1 = centers[1]
                        let r1 = radii[1]
                        let z1 = zs[1]
                        let zP = 8
                        let rP = m * CGFloat(zP) / 2
                        let midX = (centers[1].x + centers[2].x) / 2
                        let cyP = c1.y - r1 - rP - m * 0.12
                        let theta1 = -drive * CGFloat(zs[0]) / CGFloat(z1) + .pi / CGFloat(z1)
                        Self.drawSpurGearRealistic(
                            context: &context,
                            center: CGPoint(x: midX, y: cyP),
                            module: m,
                            teeth: zP,
                            rotation: -theta1 * CGFloat(z1) / CGFloat(zP) + .pi / CGFloat(zP),
                            face: Metal.steel,
                            rim: Metal.ironDeep
                        )
                    }

                    if centers.count >= 4 {
                        let cPen = centers[centers.count - 2]
                        let rPen = radii[radii.count - 2]
                        let zPen = zs[zs.count - 2]
                        let zQ = 7
                        let rQ = m * CGFloat(zQ) / 2
                        let cTop = CGPoint(x: cPen.x, y: cPen.y - rPen - rQ - m * 0.1)
                        var thetaPen = drive
                        for i in 0 ..< (zs.count - 2) {
                            let z = zs[i]
                            let zN = zs[i + 1]
                            thetaPen = -thetaPen * CGFloat(z) / CGFloat(zN) + .pi / CGFloat(zN)
                        }
                        Self.drawSpurGearRealistic(
                            context: &context,
                            center: cTop,
                            module: m,
                            teeth: zQ,
                            rotation: -thetaPen * CGFloat(zPen) / CGFloat(zQ) + .pi / CGFloat(zQ),
                            face: Metal.brass,
                            rim: Metal.brassDark
                        )
                    }

                    Self.drawPistonRod(context: &context, cx: w * 0.04, cyTop: h * 0.1, len: h * 0.55, stroke: CGFloat(p) * h * 0.12, wide: 4.5, fill: Metal.copper, accent: Metal.copperDark)
                    Self.drawPistonRod(context: &context, cx: w * 0.96, cyTop: h * 0.12, len: h * 0.5, stroke: CGFloat(p) * h * 0.1, wide: 4, fill: Metal.silver, accent: Metal.silverDim)

                    let camAngle = p * 2 * Double.pi * 2.1
                    Self.drawCrankLink(context: &context, axle: CGPoint(x: w * 0.42, y: h * 0.2), r: 9, angle: camAngle, strokeLen: w * 0.14, bar: Metal.gold, joint: Metal.goldDark)
                    Self.drawCrankLink(context: &context, axle: CGPoint(x: w * 0.72, y: h * 0.24), r: 7, angle: -camAngle * 1.3 + 0.4, strokeLen: w * 0.11, bar: Metal.brass, joint: Metal.brassDark)

                    Self.drawSlottedShutter(context: &context, w: w, h: h, p: p)
                    Self.drawOscillatingRack(context: &context, w: w, h: h, p: p)
                    Self.drawLinkageWeb(context: &context, w: w, h: h, p: p)
                    Self.drawGaugeFace(context: &context, c: CGPoint(x: w * 0.22, y: h * 0.28), r: min(w, h) * 0.1, p: p)
                    Self.drawPerforatedOverlay(context: &context, w: w, h: h, p: p)

                    Self.drawAnchorEscapement(context: &context, pivot: CGPoint(x: w * 0.55, y: h * 0.82), scale: min(h, w) * 0.07, rock: sin(p * .pi * 20) * 0.45 + sin(p * .pi * 11) * 0.2, rim: Metal.silver, fork: Metal.brass)

                    Self.drawHexBoltsForeground(context: &context, w: w, h: h)
                    Self.drawBridgeBezel(context: &context, w: w, h: h, p: p)
                }
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            }
        }
        .allowsHitTesting(false)
    }

    private static func spurGearOutline(center c: CGPoint, module m: CGFloat, teeth z: Int, rotation rot: CGFloat) -> Path {
        let pitch = 2 * CGFloat.pi / CGFloat(max(z, 4))
        let add = max(0.65, m * 0.95)
        let rp = m * CGFloat(z) / 2
        let Ro = rp + add * 0.82
        let Rr = max(m * 0.75, rp - add * 0.95)
        var path = Path()
        for i in 0 ..< z {
            let base = CGFloat(i) * pitch + rot
            let a0 = base + pitch * 0.02
            let a1 = base + pitch * 0.2
            let a2 = base + pitch * 0.48
            let a3 = base + pitch * 0.985
            func P(_ ang: CGFloat, _ rad: CGFloat) -> CGPoint {
                CGPoint(x: c.x + cos(ang - .pi / 2) * rad, y: c.y + sin(ang - .pi / 2) * rad)
            }
            if i == 0 { path.move(to: P(a0, Rr)) }
            path.addLine(to: P(a1, Rr + (Ro - Rr) * 0.18))
            path.addQuadCurve(to: P(a2, Rr + (Ro - Rr) * 0.18), control: P((a1 + a2) / 2, Ro + m * 0.06))
            path.addLine(to: P(a3, Rr))
        }
        path.closeSubpath()
        return path
    }

    private static func drawSpurGearRealistic(context: inout GraphicsContext, center c: CGPoint, module m: CGFloat, teeth z: Int, rotation rot: CGFloat, face: Color, rim: Color) {
        let outline = spurGearOutline(center: c, module: m, teeth: z, rotation: rot)
        context.fill(
            outline,
            with: .linearGradient(
                Gradient(stops: [
                    .init(color: face.opacity(0.98), location: 0),
                    .init(color: rim.opacity(0.72), location: 0.48),
                    .init(color: face.opacity(0.52), location: 1)
                ]),
                startPoint: CGPoint(x: c.x - m * 4, y: c.y - m * 5),
                endPoint: CGPoint(x: c.x + m * 5, y: c.y + m * 4)
            )
        )
        context.stroke(outline, with: .color(Color.black.opacity(0.42)), lineWidth: 0.5)
        context.stroke(outline, with: .color(Color.white.opacity(0.18)), lineWidth: 0.28)
        let hr = m * CGFloat(z) * 0.13
        let hub = CGRect(x: c.x - hr, y: c.y - hr, width: hr * 2, height: hr * 2)
        context.fill(Path(ellipseIn: hub), with: .linearGradient(
            Gradient(colors: [Metal.ironDeep, Metal.iron]),
            startPoint: CGPoint(x: hub.minX, y: hub.minY),
            endPoint: CGPoint(x: hub.maxX, y: hub.maxY)
        ))
        context.stroke(Path(ellipseIn: hub), with: .color(face.opacity(0.45)), lineWidth: 0.32)
        let slot = CGRect(x: c.x - hr * 0.38, y: c.y - hr * 0.1, width: hr * 0.76, height: hr * 0.2)
        context.fill(Path(roundedRect: slot, cornerRadius: 0.06), with: .color(Color.black.opacity(0.35)))
    }

    private static func drawAmbientOcclusion(context: inout GraphicsContext, w: CGFloat, h: CGFloat, cornerRadius: CGFloat) {
        let rrect = Path(roundedRect: CGRect(x: 1, y: 1, width: w - 2, height: h - 2), cornerRadius: max(0, cornerRadius - 1))
        context.stroke(rrect, with: .color(Color.black.opacity(0.55)), lineWidth: 2)
        context.stroke(rrect, with: .color(Color.white.opacity(0.06)), lineWidth: 0.5)
    }

    private static func drawBrushedGrain(context: inout GraphicsContext, size: CGSize) {
        let w = size.width
        let h = size.height
        var grain = Path()
        var x: CGFloat = 0
        let step: CGFloat = 2.2
        while x < w {
            grain.move(to: CGPoint(x: x, y: 0))
            grain.addLine(to: CGPoint(x: x + h * 0.035, y: h))
            x += step
        }
        context.stroke(grain, with: .color(Color.white.opacity(0.034)), lineWidth: 0.32)
    }

    private static func drawRivetBackdrop(context: inout GraphicsContext, w: CGFloat, h: CGFloat) {
        let cols = 14
        let rows = 4
        for r in 0 ..< rows {
            for col in 0 ..< cols {
                let ox = CGFloat(col) / CGFloat(cols - 1) * w
                let oy = CGFloat(r) / CGFloat(rows - 1) * h * 0.88 + h * 0.06
                let jitter = CGFloat((col * 17 + r * 31) % 5) * 0.4
                let rcx = min(w - 4, max(4, ox + jitter))
                let rcy = min(h - 4, max(4, oy + jitter * 0.3))
                let rr: CGFloat = 1.2
                context.fill(Path(ellipseIn: CGRect(x: rcx - rr, y: rcy - rr, width: rr * 2, height: rr * 2)), with: .color(Metal.brassDark.opacity(0.35)))
                context.stroke(Path(ellipseIn: CGRect(x: rcx - rr, y: rcy - rr, width: rr * 2, height: rr * 2)), with: .color(Metal.ironDeep.opacity(0.35)), lineWidth: 0.22)
            }
        }
    }

    private static func drawOilSmudge(context: inout GraphicsContext, w: CGFloat, h: CGFloat, p: Double) {
        let o = 0.06 + p * 0.05
        context.fill(
            Path(ellipseIn: CGRect(x: w * 0.18, y: h * 0.02, width: w * 0.35, height: h * 0.28)),
            with: .color(Color.black.opacity(o))
        )
        context.fill(
            Path(ellipseIn: CGRect(x: w * 0.62, y: h * 0.58, width: w * 0.22, height: h * 0.22)),
            with: .color(Color(red: 0.12, green: 0.1, blue: 0.08).opacity(0.22 + p * 0.08))
        )
    }

    private static func drawSlottedShutter(context: inout GraphicsContext, w: CGFloat, h: CGFloat, p: Double) {
        let slide = CGFloat(p) * w * 0.07
        for i in 0 ..< 6 {
            let x = w * 0.12 + CGFloat(i) * w * 0.14 + slide
            let slot = CGRect(x: x, y: h * 0.08, width: w * 0.035, height: h * 0.84)
            context.fill(Path(roundedRect: slot, cornerRadius: 0.6), with: .color(Color.black.opacity(0.22)))
            context.stroke(Path(roundedRect: slot, cornerRadius: 0.6), with: .color(Metal.silver.opacity(0.25)), lineWidth: 0.35)
        }
    }

    private static func drawOscillatingRack(context: inout GraphicsContext, w: CGFloat, h: CGFloat, p: Double) {
        let ox = sin(p * .pi * 14) * w * 0.018
        let rackX = w * 0.38 + CGFloat(ox)
        let rackW: CGFloat = w * 0.05
        let teethH: CGFloat = 2.8
        var y: CGFloat = h * 0.35
        while y < h * 0.72 {
            let tooth = CGRect(x: rackX, y: y, width: rackW, height: teethH)
            context.fill(Path(roundedRect: tooth, cornerRadius: 0.35), with: .color(Metal.steelDark.opacity(0.78)))
            context.stroke(Path(roundedRect: tooth, cornerRadius: 0.35), with: .color(Color.black.opacity(0.35)), lineWidth: 0.25)
            y += teethH + 1.1
        }
        context.fill(Path(roundedRect: CGRect(x: rackX - 1.2, y: h * 0.32, width: rackW + 2.4, height: 4), cornerRadius: 0.4), with: .color(Metal.iron.opacity(0.65)))
    }

    private static func drawLinkageWeb(context: inout GraphicsContext, w: CGFloat, h: CGFloat, p: Double) {
        let a = CGPoint(x: w * 0.28, y: h * 0.42 + CGFloat(p) * h * 0.06)
        let b = CGPoint(x: w * 0.62, y: h * 0.38 - CGFloat(p) * h * 0.04)
        let c = CGPoint(x: w * 0.82, y: h * 0.52 + sin(p * .pi * 8) * h * 0.03)
        context.stroke(Path { path in
            path.move(to: a)
            path.addLine(to: b)
            path.addLine(to: c)
        }, with: .color(Metal.brass.opacity(0.38)), lineWidth: 1.1)
        for pt in [a, b, c] {
            context.fill(Path(ellipseIn: CGRect(x: pt.x - 2, y: pt.y - 2, width: 4, height: 4)), with: .color(Metal.ironDeep))
        }
    }

    private static func drawGaugeFace(context: inout GraphicsContext, c: CGPoint, r: CGFloat, p: Double) {
        context.stroke(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)), with: .color(Metal.silverDim.opacity(0.55)), lineWidth: 1.2)
        context.fill(Path(ellipseIn: CGRect(x: c.x - r + 2, y: c.y - r + 2, width: (r - 2) * 2, height: (r - 2) * 2)), with: .color(Color.black.opacity(0.35)))
        let ang = -CGFloat.pi * 0.75 + CGFloat(p) * CGFloat.pi * 1.1
        let tip = CGPoint(x: c.x + cos(ang) * (r * 0.72), y: c.y + sin(ang) * (r * 0.72))
        context.stroke(Path { path in
            path.move(to: c)
            path.addLine(to: tip)
        }, with: .color(Metal.gold.opacity(0.85)), lineWidth: 1.35)
        context.fill(Path(ellipseIn: CGRect(x: c.x - 2, y: c.y - 2, width: 4, height: 4)), with: .color(Metal.iron))
    }

    private static func drawPerforatedOverlay(context: inout GraphicsContext, w: CGFloat, h: CGFloat, p: Double) {
        let cols = 12
        let rows = 3
        let shift = CGFloat(p) * 3
        for row in 0 ..< rows {
            for col in 0 ..< cols {
                let cx = CGFloat(col) / CGFloat(cols) * (w * 0.72) + w * 0.05 + shift
                let cy = CGFloat(row) / CGFloat(max(1, rows - 1)) * (h * 0.22) + h * 0.06 + (row % 2 == 0 ? 0 : 2.5)
                let hole = Path(ellipseIn: CGRect(x: cx, y: cy, width: 2.6, height: 2.6))
                context.fill(hole, with: .color(Color.black.opacity(0.28)))
                context.stroke(hole, with: .color(Metal.silver.opacity(0.15)), lineWidth: 0.25)
            }
        }
    }

    private static func drawHexBoltsForeground(context: inout GraphicsContext, w: CGFloat, h: CGFloat) {
        let pts: [CGPoint] = [
            CGPoint(x: w * 0.06, y: h * 0.06),
            CGPoint(x: w * 0.94, y: h * 0.08),
            CGPoint(x: w * 0.07, y: h * 0.92),
            CGPoint(x: w * 0.93, y: h * 0.9)
        ]
        for pt in pts {
            drawHexBolt(context: &context, c: pt, r: 3.2)
        }
    }

    private static func drawHexBolt(context: inout GraphicsContext, c: CGPoint, r: CGFloat) {
        var hex = Path()
        for k in 0 ..< 6 {
            let t = CGFloat(k) / 6 * 2 * .pi - .pi / 2
            let p = CGPoint(x: c.x + cos(t) * r, y: c.y + sin(t) * r)
            if k == 0 { hex.move(to: p) } else { hex.addLine(to: p) }
        }
        hex.closeSubpath()
        context.fill(hex, with: .linearGradient(
            Gradient(colors: [Metal.silver, Metal.iron]),
            startPoint: CGPoint(x: c.x - r, y: c.y - r),
            endPoint: CGPoint(x: c.x + r, y: c.y + r)
        ))
        context.stroke(hex, with: .color(Color.black.opacity(0.45)), lineWidth: 0.35)
        context.fill(Path(ellipseIn: CGRect(x: c.x - r * 0.35, y: c.y - r * 0.35, width: r * 0.7, height: r * 0.7)), with: .color(Metal.ironDeep.opacity(0.8)))
    }

    private static func drawBridgeBezel(context: inout GraphicsContext, w: CGFloat, h: CGFloat, p: Double) {
        let y1 = h * 0.08 + CGFloat(p) * 1.5
        let y2 = h * 0.92 - CGFloat(p) * 1.5
        context.stroke(Path { path in
            path.move(to: CGPoint(x: w * 0.06, y: y1))
            path.addQuadCurve(to: CGPoint(x: w * 0.94, y: y1), control: CGPoint(x: w * 0.5, y: y1 - 3.5))
        }, with: .color(Metal.gold.opacity(0.22 + p * 0.08)), lineWidth: 0.85)
        context.stroke(Path { path in
            path.move(to: CGPoint(x: w * 0.08, y: y2))
            path.addQuadCurve(to: CGPoint(x: w * 0.92, y: y2), control: CGPoint(x: w * 0.5, y: y2 + 3.2))
        }, with: .color(Metal.brass.opacity(0.18 + p * 0.06)), lineWidth: 0.65)
    }

    private static func drawPistonRod(context: inout GraphicsContext, cx: CGFloat, cyTop: CGFloat, len: CGFloat, stroke: CGFloat, wide: CGFloat, fill: Color, accent: Color) {
        let headH: CGFloat = 7
        let travel = stroke
        let y1 = cyTop + travel
        let body = CGRect(x: cx - wide / 2, y: y1, width: wide, height: max(6, len - travel))
        context.fill(Path(roundedRect: body, cornerRadius: 1.2), with: .color(fill.opacity(0.75)))
        context.stroke(Path(roundedRect: body, cornerRadius: 1.2), with: .color(accent.opacity(0.85)), lineWidth: 0.55)
        let head = CGRect(x: cx - (wide + 3) / 2, y: y1 - headH, width: wide + 3, height: headH + 1)
        context.fill(Path(roundedRect: head, cornerRadius: 2), with: .color(fill.opacity(0.9)))
        context.stroke(Path(roundedRect: head, cornerRadius: 2), with: .color(accent), lineWidth: 0.5)
        let rail = CGRect(x: cx - 1.1, y: cyTop - 2, width: 2.2, height: len + headH + 6)
        context.stroke(Path(roundedRect: rail, cornerRadius: 0.4), with: .color(Metal.ironDeep.opacity(0.55)), lineWidth: 0.8)
    }

    private static func drawCrankLink(context: inout GraphicsContext, axle: CGPoint, r: CGFloat, angle: Double, strokeLen: CGFloat, bar: Color, joint: Color) {
        let a = CGFloat(angle)
        let pin = CGPoint(x: axle.x + cos(a) * r, y: axle.y + sin(a) * r)
        context.stroke(Path { p in
            p.move(to: axle)
            p.addLine(to: pin)
        }, with: .color(bar.opacity(0.55)), lineWidth: 2.2)
        let end = CGPoint(x: pin.x + cos(a + 0.65) * strokeLen * 0.35, y: pin.y + sin(a + 0.65) * strokeLen * 0.35)
        context.stroke(Path { p in
            p.move(to: pin)
            p.addLine(to: end)
        }, with: .color(joint.opacity(0.65)), lineWidth: 1.4)
        context.fill(Path(ellipseIn: CGRect(x: axle.x - 2.5, y: axle.y - 2.5, width: 5, height: 5)), with: .color(Metal.iron))
        context.fill(Path(ellipseIn: CGRect(x: pin.x - 2, y: pin.y - 2, width: 4, height: 4)), with: .color(bar.opacity(0.85)))
    }

    private static func drawAnchorEscapement(context: inout GraphicsContext, pivot: CGPoint, scale: CGFloat, rock: Double, rim: Color, fork: Color) {
        let r = CGFloat(rock)
        let c = cos(r)
        let s = sin(r)
        func rot(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: pivot.x + x * c - y * s, y: pivot.y + x * s + y * c)
        }
        let a1 = rot(-scale * 0.55, scale * 0.1)
        let a2 = rot(scale * 0.55, scale * 0.1)
        let tip = rot(0, -scale * 0.75)
        var forkPath = Path()
        forkPath.move(to: a1)
        forkPath.addQuadCurve(to: a2, control: tip)
        forkPath.addLine(to: pivot)
        forkPath.closeSubpath()
        context.fill(forkPath, with: .color(fork.opacity(0.55)))
        context.stroke(forkPath, with: .color(rim.opacity(0.45)), lineWidth: 0.55)
        context.stroke(Path(ellipseIn: CGRect(x: pivot.x - 3, y: pivot.y - 3, width: 6, height: 6)), with: .color(rim.opacity(0.35)), lineWidth: 0.45)
        // 逃がし車風の歯のシルエット（固定・装飾）
        let escapeCx = pivot.x + scale * 0.95
        let escapeCy = pivot.y - scale * 0.15
        for k in 0..<8 {
            let t = CGFloat(k) / 8 * 2 * .pi
            let ir: CGFloat = 4
            let orr: CGFloat = k % 2 == 0 ? 7 : 5.5
            let x0 = escapeCx + cos(t - 0.08) * ir
            let y0 = escapeCy + sin(t - 0.08) * ir
            let x1 = escapeCx + cos(t + 0.08) * orr
            let y1 = escapeCy + sin(t + 0.08) * orr
            context.stroke(Path { path in
                path.move(to: CGPoint(x: x0, y: y0))
                path.addLine(to: CGPoint(x: x1, y: y1))
            }, with: .color(Metal.silverDim.opacity(0.4)), lineWidth: 0.85)
        }
        context.fill(Path(ellipseIn: CGRect(x: escapeCx - 2, y: escapeCy - 2, width: 4, height: 4)), with: .color(Metal.iron.opacity(0.65)))
    }
}

private struct WashiNoiseOverlay: View {
    var cornerRadius: CGFloat

    var body: some View {
        Canvas { ctx, size in
            let count = 180
            for i in 0..<count {
                let x = CGFloat((i * 97) % Int(size.width))
                let y = CGFloat((i * 53) % Int(size.height))
                let o = Double((i * 13) % 7) / 20
                ctx.fill(
                    Path(ellipseIn: CGRect(x: x, y: y, width: 1.2, height: 1.2)),
                    with: .color(Color.white.opacity(0.06 + o * 0.06))
                )
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .allowsHitTesting(false)
    }
}

private struct FiligreePattern: View {
    var cornerRadius: CGFloat

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            Canvas { ctx, _ in
                let step: CGFloat = 22
                var x: CGFloat = 6
                while x < w {
                    var y: CGFloat = 8
                    while y < h {
                        var p = Path()
                        p.addArc(center: CGPoint(x: x, y: y), radius: 10, startAngle: .degrees(0), endAngle: .degrees(180), clockwise: true)
                        ctx.stroke(p, with: .color(Color(red: 0.85, green: 0.72, blue: 0.35).opacity(0.14)), lineWidth: 0.8)
                        y += step
                    }
                    x += step
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        }
        .allowsHitTesting(false)
    }
}

private struct SpinningSigil: View {
    var progress: Double
    var cornerRadius: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .strokeBorder(
                AngularGradient(
                    colors: [
                        Color(red: 0.95, green: 0.82, blue: 0.4).opacity(0.15),
                        Color(red: 0.7, green: 0.95, blue: 1).opacity(0.2),
                        Color(red: 0.95, green: 0.82, blue: 0.4).opacity(0.15)
                    ],
                    center: .center,
                    angle: .degrees(progress * 360)
                ),
                lineWidth: 2
            )
            .opacity(0.55)
            .allowsHitTesting(false)
    }
}

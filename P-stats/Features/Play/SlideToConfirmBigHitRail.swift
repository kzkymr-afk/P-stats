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
    /// メカニカル・インダストリアル用：つまみの横速度（ポイント/秒）。レールの駆動表現にのみ使用。
    @State private var industrialPanVelocityX: CGFloat = 0
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
                    themedTrackBase(
                        width: W,
                        height: H,
                        progress: progress,
                        industrialVelocityX: style == .mechanicalIndustrial ? industrialPanVelocityX : 0
                    )
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
                        thumbVisual(width: thumbW, height: thumbH, progress: progress, industrialVelocityX: industrialPanVelocityX)
                            .frame(width: thumbW, height: thumbH)
                            .offset(x: panOffset)
                            .overlay {
                                SlideThumbPanBridge(
                                    panOffset: $panOffset,
                                    travel: travel,
                                    thresholdFraction: Self.thresholdFraction,
                                    isInteractionLocked: confirmLocked,
                                    onPanVelocity: style == .mechanicalIndustrial
                                        ? { industrialPanVelocityX = $0 }
                                        : nil,
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
    private func themedTrackBase(width W: CGFloat, height H: CGFloat, progress: CGFloat, industrialVelocityX: CGFloat = 0) -> some View {
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
            MechanicalIndustrialAssetTrack(
                progress: progress,
                cornerRadius: cornerRadius,
                panVelocityX: industrialVelocityX
            )
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
                            Color(red: 0.62, green: 0.52, blue: 0.36).opacity(0.12 + Double(p) * 0.38),
                            Color(red: 0.42, green: 0.38, blue: 0.34).opacity(0.1 + Double(p) * 0.32)
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
                        Color(red: 0.78, green: 0.68, blue: 0.48).opacity(0.55 + p * 0.2),
                        Color(red: 0.22, green: 0.18, blue: 0.14).opacity(0.88)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
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
    private func thumbVisual(width w: CGFloat, height h: CGFloat, progress: CGFloat, industrialVelocityX: CGFloat = 0) -> some View {
        switch style {
        case .neonCyberpunk:
            thumbNeon(width: w, height: h)
        case .minimalGlass:
            thumbGlass(width: w, height: h)
        case .mechanicalIndustrial:
            thumbIndustrial(width: w, height: h, progress: progress, velocityX: industrialVelocityX)
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
    private func thumbIndustrial(width w: CGFloat, height h: CGFloat, progress: CGFloat, velocityX: CGFloat) -> some View {
        let r = max(1.5, min(w, h) * 0.11)
        let p = Double(max(0, min(1, progress)))
        let vx = Double(velocityX)
        let velSpin = max(-18, min(18, vx / 95))
        let spin = -p * 72 + velSpin
        let icon = max(10, min(w, h) * 0.3)
        ZStack {
            Image(BigHitSlideRailMechanicalIndustrialAsset.name)
                .resizable()
                .scaledToFill()
                .scaleEffect(2.28)
                .rotationEffect(.degrees(spin))
                .offset(x: CGFloat(p * 1.2), y: CGFloat(-p * 0.8))
                .frame(width: w, height: h)
                .clipShape(RoundedRectangle(cornerRadius: r))

            RoundedRectangle(cornerRadius: r)
                .stroke(
                    LinearGradient(
                        colors: [
                            Color(red: 0.9, green: 0.82, blue: 0.62).opacity(0.95),
                            Color(red: 0.42, green: 0.36, blue: 0.3).opacity(0.88)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.45
                )
            RoundedRectangle(cornerRadius: r)
                .stroke(Color.white.opacity(0.14), lineWidth: 0.45)
                .padding(0.6)

            Image(systemName: "chevron.left.2")
                .font(.system(size: icon, weight: .heavy, design: .default))
                .foregroundStyle(
                    LinearGradient(
                        colors: [
                            Color(red: 0.96, green: 0.9, blue: 0.76),
                            Color(red: 0.55, green: 0.5, blue: 0.44)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .shadow(color: .black.opacity(0.55), radius: 0, x: 0.6, y: 0.8)
        }
        .frame(width: w, height: h)
        .shadow(color: Color(red: 0.02, green: 0.018, blue: 0.015).opacity(0.92), radius: 4, x: 0, y: 2.5)
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
            Image(BigHitSlideRailMechanicalIndustrialAsset.name)
                .resizable()
                .scaledToFill()
                .frame(width: CGFloat(5 + (i % 4)), height: CGFloat(5 + (i % 3)))
                .blur(radius: 0.35)
                .rotationEffect(.degrees(Double(i * 41) + p * 52 + sin(Double(i) + p * 6) * 8))
                .offset(
                    x: thumb.x - size.width / 2 + ox + CGFloat(14 + i * 6) * CGFloat(p),
                    y: thumb.y - size.height / 2 + oy + sin(Double(i) * 0.7 + p * 9) * 3
                )
                .opacity(p * 0.62)
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
    /// メカニカル系スタイル向け：`.changed` で横速度、終了時は 0
    var onPanVelocity: ((CGFloat) -> Void)?
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
        c.onPanVelocityClosure = onPanVelocity
        c.onEndedClosure = onEnded
    }

    final class Coordinator: NSObject {
        var binding: Binding<CGFloat>?
        var travel: CGFloat = 1
        var threshold: CGFloat = 0.6
        var locked = false
        var onPanVelocityClosure: ((CGFloat) -> Void)?
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
                onPanVelocityClosure?(CGFloat(g.velocity(in: view).x))
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
                onPanVelocityClosure?(0)
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

// MARK: - メカニカル・インダストリアル（`BigHitRailMechanicalIndustrial` アセット・スワイプ連動パララックス）

private enum MechanicalIndustrialRailPalette {
    static let grooveBaseTop = Color(red: 0.19, green: 0.15, blue: 0.12)
    static let grooveBaseMid = Color(red: 0.08, green: 0.065, blue: 0.055)
    static let grooveBaseBottom = Color(red: 0.045, green: 0.037, blue: 0.032)
    static let rimLight = Color(red: 0.72, green: 0.62, blue: 0.46)
}

private enum BigHitSlideRailMechanicalIndustrialAsset {
    static let name = "BigHitRailMechanicalIndustrial"
}

private struct MechanicalIndustrialTexturePlate: View {
    var alignment: Alignment = .center
    var scale: CGFloat
    var offsetX: CGFloat
    var offsetY: CGFloat
    var rotation: Double
    var opacity: Double
    var blur: CGFloat

    var body: some View {
        GeometryReader { geo in
            let cw = geo.size.width * scale
            let ch = geo.size.height * scale
            Image(BigHitSlideRailMechanicalIndustrialAsset.name)
                .resizable()
                .scaledToFill()
                .frame(width: cw, height: ch)
                .rotationEffect(.degrees(rotation))
                .offset(x: offsetX, y: offsetY)
                .frame(width: geo.size.width, height: geo.size.height, alignment: alignment)
                .clipped()
        }
        .opacity(opacity)
        .blur(radius: blur)
    }
}

private struct MechanicalIndustrialAssetTrack: View {
    var progress: CGFloat
    var cornerRadius: CGFloat
    /// 左スワイプ時は負の値になりやすい（ポイント/秒）
    var panVelocityX: CGFloat

    var body: some View {
        GeometryReader { geo in
            let maxR = hypot(geo.size.width, geo.size.height) * 0.98
            let p = CGFloat(max(0, min(1, progress)))
            let pD = Double(p)
            let vx = Double(panVelocityX)
            let velBoost = max(-48, min(48, vx / 26))

            let pistonA = sin(pD * .pi) * 5.5
            let pistonB = sin(pD * .pi * 1.45) * 4.2
            let gearMain = -pD * 410 + velBoost
            let gearCounter = pD * 268 - velBoost * 0.72
            let gearAccent = pD * 195 + velBoost * 0.35

            ZStack {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(
                        LinearGradient(
                            colors: [
                                MechanicalIndustrialRailPalette.grooveBaseTop,
                                MechanicalIndustrialRailPalette.grooveBaseMid,
                                MechanicalIndustrialRailPalette.grooveBaseBottom
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                MechanicalIndustrialTexturePlate(
                    alignment: .center,
                    scale: 1.44,
                    offsetX: p * -24,
                    offsetY: CGFloat(pistonA * 0.72),
                    rotation: gearMain * 0.2,
                    opacity: 0.8,
                    blur: 0.45
                )

                MechanicalIndustrialTexturePlate(
                    alignment: .center,
                    scale: 1.11,
                    offsetX: p * -34 + CGFloat(pistonB * 0.28),
                    offsetY: p * -5.5 + CGFloat(pistonA * 0.22),
                    rotation: gearCounter * 0.16,
                    opacity: 0.93,
                    blur: 0
                )

                MechanicalIndustrialTexturePlate(
                    alignment: .topTrailing,
                    scale: 1.72,
                    offsetX: p * 19 + CGFloat(pistonB * 0.62),
                    offsetY: -p * 8.5 + CGFloat(pistonA * -0.38),
                    rotation: -pD * 182 + velBoost * 0.52,
                    opacity: 0.36,
                    blur: 1.15
                )
                .blendMode(.hardLight)

                MechanicalIndustrialTexturePlate(
                    alignment: .bottomLeading,
                    scale: 1.95,
                    offsetX: -p * 13 + CGFloat(pistonA * 0.45),
                    offsetY: p * 7.5 + CGFloat(pistonB * -0.55),
                    rotation: gearAccent * 0.12,
                    opacity: 0.3,
                    blur: 1.4
                )
                .blendMode(.plusLighter)

                MechanicalIndustrialTexturePlate(
                    alignment: .leading,
                    scale: 2.28,
                    offsetX: p * -9 + CGFloat(pistonA * 0.18),
                    offsetY: CGFloat(pistonB * 0.35),
                    rotation: pD * 118 - velBoost * 0.22,
                    opacity: 0.21,
                    blur: 1.55
                )
                .blendMode(.softLight)

                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.black.opacity(0.64),
                                Color.black.opacity(0.14),
                                Color.black.opacity(0.09),
                                Color.black.opacity(0.6)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .blendMode(.multiply)

                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(
                        RadialGradient(
                            colors: [
                                Color.white.opacity(0.055),
                                Color.black.opacity(0.52),
                                Color.black.opacity(0.79)
                            ],
                            center: .center,
                            startRadius: 2,
                            endRadius: maxR
                        )
                    )
                    .blendMode(.overlay)
                    .opacity(0.9)

                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(
                        LinearGradient(
                            colors: [
                                MechanicalIndustrialRailPalette.rimLight.opacity(0.48),
                                Color.black.opacity(0.58),
                                MechanicalIndustrialRailPalette.rimLight.opacity(0.3)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.05
                    )
                    .blur(radius: 0.12)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        }
        .allowsHitTesting(false)
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

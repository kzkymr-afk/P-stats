import SwiftUI
import UIKit

extension AppTheme {
    var bigHitRailChrome: BigHitRailChrome {
        .dark
    }
}

/// 大当たりスライドバーの配色（アプリのダーク／ライトに合わせる）
enum BigHitRailChrome: Equatable {
    /// 従来の黒・ガラス基調
    case dark
}

/// 右端配置想定：つまみを左へスライドし、`thresholdFraction`（可動距離の約3/5）以上で `onConfirmed`
struct SlideToConfirmBigHitRail: View {
    var height: CGFloat
    var cornerRadius: CGFloat
    var accent: Color
    var chrome: BigHitRailChrome = .dark
    var onConfirmed: () -> Void
    var onAccessibilityConfirmRequested: () -> Void

    /// スライド可能距離に対する確定しきい値（3/5＝可動距離の6割）
    private static let thresholdFraction: CGFloat = 0.6
    private static let thumbWidth: CGFloat = 40
    private static let horizontalInset: CGFloat = 7
    private static let lockoutSeconds: TimeInterval = 0.55
    private static let completionFlashSeconds: TimeInterval = 0.52

    @State private var panOffset: CGFloat = 0
    @State private var confirmLocked = false
    @State private var showCompletionFlash = false

    var body: some View {
        GeometryReader { geo in
            let W = geo.size.width.isFinite ? max(0, geo.size.width) : 0
            let H = geo.size.height.isFinite ? max(0, geo.size.height) : 0
            let thumbW = Self.thumbWidth
            let thumbH = H
            let travel = max(1, W - thumbW - Self.horizontalInset * 2)
            let drag = max(-travel, min(0, panOffset))
            let progress = min(1, abs(drag) / travel)
            let confirmLineX = W - Self.horizontalInset - thumbW / 2 - travel * Self.thresholdFraction
            let th = Self.thresholdFraction
            /// つまみと同じ「しきい値比率」で伸び、しきい値到達時の右端＝確定ライン（過剰に伸びない）
            let fillWidth: CGFloat = {
                if progress <= th {
                    return (progress / th) * confirmLineX
                }
                let tail = (progress - th) / max(1e-6, 1 - th)
                return confirmLineX + tail * max(0, W - confirmLineX)
            }()

            ZStack {
                ZStack(alignment: .leading) {
                    trackBase(width: W, height: H)
                    confirmZoneHighlight(width: W, height: H, endX: confirmLineX)
                    progressFill(width: fillWidth, height: H, progress: progress)
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .stroke(strokeStyle(progress: progress), lineWidth: strokeLineWidth)
                    confirmMarker(height: H, x: confirmLineX)
                    labelRow(thumbReserve: thumbW, progress: progress)
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

                    HStack(spacing: 0) {
                        Spacer(minLength: 0)
                        thumbView(width: thumbW, height: thumbH)
                            .frame(width: thumbW, height: thumbH)
                            .offset(x: panOffset)
                            .overlay {
                                SlideThumbPanBridge(
                                    panOffset: $panOffset,
                                    travel: travel,
                                    thresholdFraction: Self.thresholdFraction,
                                    isInteractionLocked: confirmLocked,
                                    onPanVelocity: nil,
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
                    completionFlash(width: W, height: H)
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }
            }
            .animation(.easeOut(duration: 0.16), value: showCompletionFlash)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("大当たりを記録するスライド")
            .accessibilityHint("このバーは大当たり（連チャン記録）を始めるためのボタンです。右端のハンドルを左へスワイプし、目印のところまで動かすと大当たり記録が始まります。長押しまたはアクションメニューで確認だけ先に開けます。")
            .accessibilityAddTraits(.allowsDirectInteraction)
            .accessibilityActions {
                Button("確認して開始") {
                    onAccessibilityConfirmRequested()
                }
            }
        }
        .frame(height: height.isFinite ? max(0, height) : 0)
    }

    private var strokeLineWidth: CGFloat { 1 }

    private func confirmZoneHighlight(width W: CGFloat, height H: CGFloat, endX: CGFloat) -> some View {
        let safeW = W.isFinite ? max(0, W) : 0
        let safeH = H.isFinite ? max(0, H) : 0
        let w = min(max(0, endX), safeW)
        let hi: Double = chrome == .dark ? 0.085 : 0.12
        let lo: Double = chrome == .dark ? 0.02 : 0.04
        return HStack(spacing: 0) {
            LinearGradient(
                colors: [
                    Color.primary.opacity(hi),
                    Color.primary.opacity(lo)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: max(0, w))
            Spacer(minLength: 0)
        }
        .frame(width: safeW, height: safeH)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .allowsHitTesting(false)
    }

    private func confirmMarker(height H: CGFloat, x: CGFloat) -> some View {
        let safeH = H.isFinite ? max(0, H) : 0
        let capH = max(2, min(safeH * 0.68, max(0, safeH - 8)))
        let cx = x.isFinite ? x : 0
        let cy = safeH > 0 ? safeH / 2 : 0
        return Capsule()
            .fill(Color.primary.opacity(chrome == .dark ? 0.55 : 0.45))
            .frame(width: 2, height: capH)
            .position(x: cx, y: cy)
            .allowsHitTesting(false)
    }

    @ViewBuilder
    private func trackBase(width W: CGFloat, height H: CGFloat) -> some View {
        switch chrome {
        case .dark:
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
        }
    }

    @ViewBuilder
    private func progressFill(width fillW: CGFloat, height H: CGFloat, progress: CGFloat) -> some View {
        let p = max(0, min(1, progress))
        let fw = max(1, fillW)
        let mask = HStack(spacing: 0) {
            Rectangle().frame(width: fw)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)

        switch chrome {
        case .dark:
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
        }
    }

    private func strokeStyle(progress: CGFloat) -> AnyShapeStyle {
        let p = Double(max(0, min(1, progress)))
        switch chrome {
        case .dark:
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
        }
    }

    private func labelRow(thumbReserve: CGFloat, progress: CGFloat) -> some View {
        let p = max(0.55, min(1, 0.78 + Double(progress) * 0.2))
        let title = Color.primary
        let sub = Color.primary.opacity(chrome == .dark ? 0.75 * p : 0.62 * p)
        return HStack(alignment: .center, spacing: 5) {
            VStack(alignment: .leading, spacing: 3) {
                Text("大当たり")
                    .font(.system(size: 19, weight: .heavy, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)
                    .foregroundStyle(title)
                Text("左スワイプで確定")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                    .foregroundStyle(sub)
            }
            Spacer(minLength: thumbReserve + Self.horizontalInset + 6)
        }
    }

    @ViewBuilder
    private func thumbView(width w: CGFloat, height h: CGFloat) -> some View {
        let r = max(2, min(w, h) * 0.16)
        let icon = max(12, min(w, h) * 0.34)
        switch chrome {
        case .dark:
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
    }

    private func completionFlash(width W: CGFloat, height H: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(accent.opacity(0.35))
            .frame(width: W, height: H)
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
            withAnimation(.spring(response: 0.24, dampingFraction: 0.98)) {
                panOffset = 0
            }
        }
    }
}

// MARK: - UIKit pan bridge

/// `DragGesture` + `@GestureState` だと終了フレームで位置が二重に効きブレやすいため、`UIPanGestureRecognizer` で一本化する。
private struct SlideThumbPanBridge: UIViewRepresentable {
    @Binding var panOffset: CGFloat
    var travel: CGFloat
    var thresholdFraction: CGFloat
    var isInteractionLocked: Bool
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

import SwiftUI

// MARK: - メタル質感（CSS .metal 相当）
/// ベース背景・外側シャドウ・内側シャドウ（overlay + mask）を適用する ViewModifier
struct MetalViewModifier: ViewModifier {
    var cornerRadius: CGFloat = 12
    var borderWidth: CGFloat = 4

    private static let baseLight = Color(hue: 0, saturation: 0, brightness: 0.90)
    private static let baseMid = Color(hue: 0, saturation: 0, brightness: 0.85)
    private static let baseDark = Color(hue: 0, saturation: 0, brightness: 0.70)
    private static let innerBorder = Color(hue: 0, saturation: 0, brightness: 0.15)
    private static let innerShadow = Color(hue: 0, saturation: 0, brightness: 0, opacity: 0.25)
    private static let innerHighlight = Color(hue: 0, saturation: 0, brightness: 1, opacity: 0.7)
    private static let outerShadow = Color(hue: 0, saturation: 0, brightness: 0, opacity: 0.15)
    private static let outerHighlight = Color(hue: 0, saturation: 0, brightness: 1, opacity: 0.5)

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(
                        LinearGradient(
                            colors: [Self.baseLight, Self.baseMid, Self.baseDark],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            )
            .overlay(insetShadowOverlay)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(Self.innerBorder.opacity(0.8), lineWidth: borderWidth)
            )
            .shadow(color: Self.outerShadow, radius: 6, x: 0, y: -5)
            .shadow(color: Self.outerHighlight, radius: 6, x: 0, y: 5)
    }

    /// 内側シャドウ・ハイライトを overlay + mask で表現（inset box-shadow 相当）
    private var insetShadowOverlay: some View {
        ZStack {
            // 上縁の内側ハイライト（inset 0 2px 1px）
            VStack {
                LinearGradient(
                    colors: [Self.innerHighlight, Self.innerHighlight.opacity(0)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 7)
                Spacer(minLength: 0)
            }
            // 下縁の内側シャドウ（inset 0 -1px 0）
            VStack {
                Spacer(minLength: 0)
                LinearGradient(
                    colors: [Self.innerShadow.opacity(0), Self.innerShadow],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 7)
            }
        }
        .mask(
            RoundedRectangle(cornerRadius: cornerRadius)
                .padding(borderWidth)
        )
    }
}

// MARK: - メタル ButtonStyle
struct MetalButtonStyle: ButtonStyle {
    var cornerRadius: CGFloat = 12
    var borderWidth: CGFloat = 4

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .modifier(MetalViewModifier(cornerRadius: cornerRadius, borderWidth: borderWidth))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeInOut(duration: 0.2), value: configuration.isPressed)
    }
}

// MARK: - 円形メタル（.metal.radial）
/// AngularGradient と複数の RadialGradient を重ねて円形削り出しの質感を再現
struct MetalRadialView<Content: View>: View {
    let size: CGFloat
    @ViewBuilder let content: () -> Content

    private var radius: CGFloat { size / 2 }

    var body: some View {
        content()
            .frame(width: size, height: size)
            .background(
                ZStack {
                    // ベース: 中心から外側へのグラデーション（90% → 85% → 60%）
                    RadialGradient(
                        colors: [
                            Color(hue: 0, saturation: 0, brightness: 0.90),
                            Color(hue: 0, saturation: 0, brightness: 0.85),
                            Color(hue: 0, saturation: 0, brightness: 0.60)
                        ],
                        center: .center,
                        startRadius: size * 0.05,
                        endRadius: radius
                    )
                    // 上端ハイライト
                    RadialGradient(
                        colors: [Color.white.opacity(0.5), Color.white.opacity(0)],
                        center: UnitPoint(x: 0.5, y: 0),
                        startRadius: 0,
                        endRadius: radius * 0.5
                    )
                    // 下端ハイライト
                    RadialGradient(
                        colors: [Color.white.opacity(0.6), Color.white.opacity(0)],
                        center: UnitPoint(x: 0.5, y: 1),
                        startRadius: 0,
                        endRadius: radius * 0.6
                    )
                    // 左端ハイライト
                    RadialGradient(
                        colors: [Color.white.opacity(0.5), Color.white.opacity(0)],
                        center: UnitPoint(x: 0, y: 0.5),
                        startRadius: 0,
                        endRadius: radius * 0.35
                    )
                    // 右端ハイライト
                    RadialGradient(
                        colors: [Color.white.opacity(0.5), Color.white.opacity(0)],
                        center: UnitPoint(x: 1, y: 0.5),
                        startRadius: 0,
                        endRadius: radius * 0.25
                    )
                    // 擬似円錐（暗いエッジ）: AngularGradient で周囲にわずかな暗さ
                    AngularGradient(
                        colors: [
                            Color.black.opacity(0.1),
                            Color.clear,
                            Color.black.opacity(0.1),
                            Color.clear,
                            Color.black.opacity(0.1)
                        ],
                        center: .center
                    )
                }
                .clipShape(Circle())
            )
            .overlay(metalRadialInsetOverlay)
            .overlay(
                Circle()
                    .strokeBorder(Color(hue: 0, saturation: 0, brightness: 0.15).opacity(0.8), lineWidth: 4)
            )
            .shadow(color: Color.black.opacity(0.15), radius: 6, x: 0, y: -5)
            .shadow(color: Color.white.opacity(0.5), radius: 6, x: 0, y: 5)
    }

    private var metalRadialInsetOverlay: some View {
        ZStack {
            VStack {
                LinearGradient(
                    colors: [Color.white.opacity(0.7), Color.white.opacity(0)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 7)
                Spacer(minLength: 0)
            }
            VStack {
                Spacer(minLength: 0)
                LinearGradient(
                    colors: [Color.clear, Color.black.opacity(0.25)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 7)
            }
        }
        .mask(Circle().padding(4))
    }
}

// MARK: - 線形メタル（.metal.linear / .oval）
/// 複数の LinearGradient を重ねて縦方向の削り出し質感を再現
struct MetalLinearView<Content: View>: View {
    var cornerRadius: CGFloat
    var isOval: Bool
    @ViewBuilder let content: () -> Content

    init(cornerRadius: CGFloat = 8, isOval: Bool = false, @ViewBuilder content: @escaping () -> Content) {
        self.cornerRadius = cornerRadius
        self.isOval = isOval
        self.content = content
    }

    private static var linearMetalBaseGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(hue: 0, saturation: 0, brightness: 0.78),
                Color(hue: 0, saturation: 0, brightness: 0.90),
                Color(hue: 0, saturation: 0, brightness: 0.78),
                Color(hue: 0, saturation: 0, brightness: 0.70)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private static var linearMetalStripeGradient: LinearGradient {
        LinearGradient(
            stops: [
                .init(color: Color.white.opacity(0), location: 0),
                .init(color: Color.white.opacity(0.06), location: 0.02),
                .init(color: Color.white.opacity(0), location: 0.05),
                .init(color: Color.white.opacity(0.06), location: 0.08),
                .init(color: Color.white.opacity(0), location: 0.12),
                .init(color: Color.white.opacity(0.06), location: 0.15),
                .init(color: Color.white.opacity(0), location: 0.2),
                .init(color: Color.white.opacity(0.05), location: 0.25),
                .init(color: Color.white.opacity(0), location: 0.3)
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    private var linearMetalGradientStack: some View {
        ZStack {
            Self.linearMetalBaseGradient
            Self.linearMetalStripeGradient
        }
    }

    @ViewBuilder
    private var linearMetalBackground: some View {
        if isOval {
            linearMetalGradientStack.clipShape(Capsule())
        } else {
            linearMetalGradientStack.clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        }
    }

    private var linearMetalStroke: some View {
        Group {
            if isOval {
                Capsule().strokeBorder(Color(hue: 0, saturation: 0, brightness: 0.15).opacity(0.8), lineWidth: 4)
            } else {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(Color(hue: 0, saturation: 0, brightness: 0.15).opacity(0.8), lineWidth: 4)
            }
        }
    }

    var body: some View {
        content()
            .background(linearMetalBackground)
            .overlay(metalLinearInsetOverlay)
            .overlay(linearMetalStroke)
            .shadow(color: Color.black.opacity(0.15), radius: 6, x: 0, y: -5)
            .shadow(color: Color.white.opacity(0.5), radius: 6, x: 0, y: 5)
    }

    @ViewBuilder
    private var metalLinearInsetMask: some View {
        if isOval {
            Capsule().padding(4)
        } else {
            RoundedRectangle(cornerRadius: cornerRadius).padding(4)
        }
    }

    private var metalLinearInsetOverlay: some View {
        ZStack {
            VStack {
                LinearGradient(
                    colors: [Color.white.opacity(0.7), Color.white.opacity(0)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 7)
                Spacer(minLength: 0)
            }
            VStack {
                Spacer(minLength: 0)
                LinearGradient(
                    colors: [Color.clear, Color.black.opacity(0.25)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 7)
            }
        }
        .mask(metalLinearInsetMask)
    }
}

// MARK: - メタルスライダー用スタイル・カスタムスライダー
struct MetalSliderStyle {
    var trackHeight: CGFloat = 20
    var thumbSize: CGFloat = 44
    var trackCornerRadius: CGFloat = 10
}

/// メタル質感のカスタムスライダー（線形トラック + 円形サム）
struct MetalSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    var style: MetalSliderStyle = MetalSliderStyle()

    @State private var isDragging = false

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let thumbHalf = style.thumbSize / 2
            let trackWidth = w - style.thumbSize
            let fraction = (value - range.lowerBound) / (range.upperBound - range.lowerBound)
            let clamped = min(max(fraction, 0), 1)
            let thumbX = thumbHalf + clamped * trackWidth

            ZStack(alignment: .leading) {
                // トラック（線形メタル）
                MetalLinearView(cornerRadius: style.trackCornerRadius, isOval: false) {
                    Color.clear
                }
                .frame(width: w, height: style.trackHeight)

                // サム（円形メタル）
                MetalRadialView(size: style.thumbSize) {
                    Color.clear
                }
                .scaleEffect(isDragging ? 1.05 : 1)
                .position(x: thumbX, y: geo.size.height / 2)
            }
            .frame(height: max(style.trackHeight, style.thumbSize))
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { g in
                        isDragging = true
                        let x = g.location.x - thumbHalf
                        let t = min(max(x / trackWidth, 0), 1)
                        value = range.lowerBound + t * (range.upperBound - range.lowerBound)
                    }
                    .onEnded { _ in
                        isDragging = false
                    }
            )
        }
        .frame(height: max(style.trackHeight, style.thumbSize) + 20)
    }
}

// MARK: - プレビュー
#Preview("Metal Modifier") {
    VStack(spacing: 24) {
        Text("METAL")
            .font(.system(size: 48, weight: .bold))
            .modifier(MetalViewModifier(cornerRadius: 12, borderWidth: 4))
            .frame(width: 200, height: 80)

        Button("Metal Button") { }
            .buttonStyle(MetalButtonStyle(cornerRadius: 12))
            .padding(.horizontal, 24)
    }
    .padding()
    .background(Color.gray.opacity(0.3))
}

#Preview("Metal Radial") {
    MetalRadialView(size: 160) {
        Text("R")
            .font(.system(size: 72, weight: .bold))
            .foregroundStyle(Color(hue: 0, saturation: 0, brightness: 0.2))
    }
    .padding()
    .background(Color.gray.opacity(0.3))
}

#Preview("Metal Linear / Slider") {
    VStack(spacing: 32) {
        MetalLinearView(cornerRadius: 8) {
            Text("LINEAR")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(Color(hue: 0, saturation: 0, brightness: 0.2))
                .frame(height: 80)
        }
        .frame(width: 200)

        MetalSlider(value: .constant(0.6), range: 0...1)
            .padding(.horizontal, 24)
    }
    .padding()
    .background(Color.gray.opacity(0.3))
}

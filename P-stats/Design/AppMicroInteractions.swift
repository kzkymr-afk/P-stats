import SwiftUI

enum AppMicroInteractions {
    // MARK: - Numeric text transition
    struct NumericTextTransition: ViewModifier {
        func body(content: Content) -> some View {
            if #available(iOS 17.0, *) {
                content.contentTransition(.numericText())
            } else {
                content
            }
        }
    }

    // MARK: - Pressable button style (consistent “sink”)
    struct PressableButtonStyle: ButtonStyle {
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var pressedScale: CGFloat = 0.97
        var pressedOpacity: Double = 0.94
        var shadowColor: Color = AppDesignSystem.Metrics.elevatedShadowColor
        var shadowRadius: CGFloat = AppDesignSystem.Metrics.elevatedShadowRadius
        var shadowY: CGFloat = AppDesignSystem.Metrics.elevatedShadowY

        func makeBody(configuration: Configuration) -> some View {
            let pressed = configuration.isPressed
            let scale = reduceMotion ? 1.0 : (pressed ? pressedScale : 1.0)
            let opacity = pressed ? pressedOpacity : 1.0
            let radius = pressed ? max(0, shadowRadius * 0.55) : shadowRadius
            let y = pressed ? max(0, shadowY * 0.55) : shadowY
            return configuration.label
                .scaleEffect(scale)
                .opacity(opacity)
                .shadow(color: shadowColor, radius: radius, x: 0, y: y)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: pressed)
        }
    }

    // MARK: - Toast
    struct ToastView: View {
        var text: String
        var systemImage: String = "checkmark.circle.fill"

        var body: some View {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .foregroundStyle(Color.white.opacity(0.9))
                Text(text)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.white.opacity(0.95))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color.black.opacity(0.78), in: Capsule())
            .overlay(Capsule().stroke(Color.white.opacity(0.12), lineWidth: 1))
        }
    }

    struct ToastPresenter: ViewModifier {
        @Binding var isPresented: Bool
        var text: String
        var systemImage: String

        func body(content: Content) -> some View {
            content
                .overlay(alignment: .top) {
                    if isPresented {
                        ToastView(text: text, systemImage: systemImage)
                            .padding(.top, 10)
                            .transition(.move(edge: .top).combined(with: .opacity))
                            .zIndex(999)
                    }
                }
        }
    }
}

extension View {
    func appNumericText() -> some View {
        modifier(AppMicroInteractions.NumericTextTransition())
    }

    func appToast(isPresented: Binding<Bool>, text: String, systemImage: String = "checkmark.circle.fill") -> some View {
        modifier(AppMicroInteractions.ToastPresenter(isPresented: isPresented, text: text, systemImage: systemImage))
    }
}


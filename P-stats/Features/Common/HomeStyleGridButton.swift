import SwiftUI

// MARK: - ホームグリッドと実戦の共通：押下挙動（沈む・影）
/// 壁紙上でも読みやすいカード面＋均一な影。ホーム `mainActionsGrid` と実戦の主要ボタンで共有。
struct HomeStyleGridButtonPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        let scale: CGFloat = reduceMotion ? 1.0 : (pressed ? 0.97 : 1.0)
        return configuration.label
            .scaleEffect(scale)
            .opacity(pressed ? 0.94 : 1.0)
            .shadow(
                color: .black.opacity(pressed ? 0.2 : 0.36),
                radius: pressed ? 2.5 : 5,
                x: 0,
                y: pressed ? 1.5 : 3
            )
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: pressed)
    }
}

/// ホーム `HomeGridButtonLabelSplit` と同系のカード面（実戦の現金・持ち玉・カウント・下部バー用）
struct HomeStylePlayCardBackground: View {
    var cornerRadius: CGFloat
    /// 実戦のライト配色時は明るいカード面に切り替え
    var appTheme: AppTheme = .dark

    var body: some View {
        Group {
            switch appTheme {
            case .dark:
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(AppGlassStyle.cardBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .stroke(Color.white.opacity(0.14), lineWidth: 1)
                    )
                    .compositingGroup()
            case .light:
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(Color.white.opacity(0.94))
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .stroke(Color.black.opacity(0.1), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.06), radius: 4, x: 0, y: 2)
                    .compositingGroup()
            }
        }
    }
}

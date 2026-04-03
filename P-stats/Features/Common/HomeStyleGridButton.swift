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

/// ホーム `HomeGridButtonLabelSplit` と同系のカード面（実戦の現金・持ち玉・カウント・下部バー用）。
/// 背景・枠は `ThemeManager` のスキン（`ApplicationTheme`）に追従する。
struct HomeStylePlayCardBackground: View {
    var cornerRadius: CGFloat
    @EnvironmentObject private var themeManager: ThemeManager

    var body: some View {
        let skin = themeManager.currentTheme
        let strokeW: CGFloat = skin.borderWidth >= 2 ? min(2, skin.borderWidth) : 1
        return RoundedRectangle(cornerRadius: cornerRadius)
            .fill(skin.panelBackground)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(skin.playCardOutline, lineWidth: strokeW)
            )
            .compositingGroup()
    }
}

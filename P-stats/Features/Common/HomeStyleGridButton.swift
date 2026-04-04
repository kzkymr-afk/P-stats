import SwiftUI

// MARK: - ホームグリッドと実戦の共通：押下挙動（沈む・影）
/// 壁紙上でも読みやすいカード面＋均一な影。ホーム `mainActionsGrid` と実戦の主要ボタンで共有。
struct HomeStyleGridButtonPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var themeManager: ThemeManager

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        let scale: CGFloat = reduceMotion ? 1.0 : (pressed ? 0.97 : 1.0)
        let shadowSpec = pressed
            ? themeManager.currentTheme.interactiveSurfaceShadowPressed
            : themeManager.currentTheme.interactiveSurfaceShadowRest
        return configuration.label
            .scaleEffect(scale)
            .opacity(pressed ? 0.94 : 1.0)
            .themeShadow(shadowSpec)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: pressed)
    }
}

/// ホーム `pstatsPanelStyle()` と同じ主面＋アクセント枠（実戦の現金・持ち玉・カウント・下部バー用）。
/// 大当たりモードで `bigHitThemedStroke` など別枠を重ねる場合は `includeBorder: false` にして塗りのみにする。
struct HomeStylePlayCardBackground: View {
    var cornerRadius: CGFloat
    var includeBorder: Bool = true
    @EnvironmentObject private var themeManager: ThemeManager

    var body: some View {
        let skin = themeManager.currentTheme
        let r = max(0, cornerRadius)
        let shape = RoundedRectangle(cornerRadius: r, style: .continuous)
        return shape
            .fill(skin.panelBackground)
            .overlay(
                Group {
                    if includeBorder {
                        shape.stroke(skin.accentColor, lineWidth: skin.borderWidth)
                    }
                }
            )
            .compositingGroup()
    }
}

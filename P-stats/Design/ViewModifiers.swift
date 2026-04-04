import SwiftUI

// MARK: - テーマ駆動パネル（全画面共通）

/// `ThemeManager` 経由で背景・角丸・アクセント枠を一括適用する。
/// 枠線の見た目変更（発光・影など）はこの修飾子だけを直せば全画面に反映される。
struct PStatsThemedPanelStyleModifier: ViewModifier {
    @EnvironmentObject private var themeManager: ThemeManager

    func body(content: Content) -> some View {
        let t = themeManager.currentTheme
        let r = max(0, t.cornerRadius)
        content
            .background(t.panelBackground, in: RoundedRectangle(cornerRadius: r, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: r, style: .continuous)
                    .stroke(t.accentColor, lineWidth: t.borderWidth)
            )
    }
}

extension View {
    /// パネル背景・角丸・アクセント色の枠を `ThemeManager.currentTheme` で一括適用する。
    func pstatsPanelStyle() -> some View {
        modifier(PStatsThemedPanelStyleModifier())
    }

    /// フォーム内の二次ボタン面・入力周りの薄い面（例: 分析詳細の「期間」ボタン）。
    func pstatsInputChrome(cornerRadius: CGFloat = 12) -> some View {
        modifier(PStatsInputChromeModifier(cornerRadius: cornerRadius))
    }

    /// DMM / 店舗リサーチなど、下部クロームバーの背後＋細い枠。
    func pstatsChromeSheetBarStyle() -> some View {
        modifier(PStatsChromeSheetBarModifier())
    }

    /// `ApplicationTheme` のシャドウ仕様を適用する。
    func themeShadow(_ spec: ThemeShadowSpec) -> some View {
        shadow(color: spec.color, radius: spec.radius, x: spec.x, y: spec.y)
    }
}

// MARK: - 入力・クロームバー

private struct PStatsInputChromeModifier: ViewModifier {
    @EnvironmentObject private var themeManager: ThemeManager
    var cornerRadius: CGFloat

    func body(content: Content) -> some View {
        let t = themeManager.currentTheme
        let r = max(0, cornerRadius)
        content.background(t.panelElevatedSecondaryBackground, in: RoundedRectangle(cornerRadius: r, style: .continuous))
    }
}

private struct PStatsChromeSheetBarModifier: ViewModifier {
    @EnvironmentObject private var themeManager: ThemeManager

    func body(content: Content) -> some View {
        let t = themeManager.currentTheme
        content
            .background(t.chromeSheetBackdropColor)
            .overlay(
                RoundedRectangle(cornerRadius: 0)
                    .stroke(t.chromeSheetBorderColor, lineWidth: 1)
                    .padding(1)
            )
    }
}

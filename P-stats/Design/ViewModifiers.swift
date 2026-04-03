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
}

import SwiftUI

/// 画面全体で共通化する「面（カード/パネル）」。
/// View 側からは具体的な角丸・不透明度・枠線を直接書かない。
enum AppPanelVariant {
    case card
    case row
}

struct AppGlassPanel<Content: View>: View {
    @EnvironmentObject private var themeManager: ThemeManager

    var variant: AppPanelVariant = .card
    var padding: CGFloat? = nil
    var cornerRadius: CGFloat? = nil
    var content: () -> Content

    init(
        variant: AppPanelVariant = .card,
        padding: CGFloat? = nil,
        cornerRadius: CGFloat? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.variant = variant
        self.padding = padding
        self.cornerRadius = cornerRadius
        self.content = content
    }

    private var resolvedPadding: CGFloat {
        padding ?? (variant == .row ? DesignTokens.Spacing.sm : 14)
    }

    private var resolvedCornerRadius: CGFloat {
        cornerRadius ?? (variant == .row ? DesignTokens.CornerRadius.card : DesignTokens.CornerRadius.panel)
    }

    private var rowBackground: Color { themeManager.currentTheme.listRowBackground }

    var body: some View {
        let padded = content().padding(resolvedPadding)
        switch variant {
        case .card:
            padded.pstatsPanelStyle()
        case .row:
            padded.background(rowBackground, in: RoundedRectangle(cornerRadius: resolvedCornerRadius, style: .continuous))
        }
    }
}

private struct PStatsPanelModifier: ViewModifier {
    var variant: AppPanelVariant

    func body(content: Content) -> some View {
        AppGlassPanel(variant: variant) { content }
    }
}

extension View {
    func pstatsPanel(_ variant: AppPanelVariant = .card) -> some View {
        modifier(PStatsPanelModifier(variant: variant))
    }
}

import SwiftUI

// MARK: - グラスモーフィズム共通（やや不透明で統一）
/// SwiftUI 用の Color / Gradient。DesignTokens の値を参照して組み立てる。
enum AppGlassStyle {
    static let background = Color(hex: DesignTokens.Color.backgroundHex)
    static let rowBackground = Color.black.opacity(DesignTokens.Opacity.rowBackground)
    static let cardBackground = Color.black.opacity(DesignTokens.Opacity.cardBackground)
    static let accent = Color(
        red: DesignTokens.Color.accentR,
        green: DesignTokens.Color.accentG,
        blue: DesignTokens.Color.accentB
    )

    /// RUSH／通常／LTボタン用（背景・枠・文字の統一）
    static let rushColor = Color(hex: DesignTokens.Color.rushHex)
    static let normalColor = Color(hex: DesignTokens.Color.normalHex)
    static let ltColor = Color(
        red: DesignTokens.Color.ltR,
        green: DesignTokens.Color.ltG,
        blue: DesignTokens.Color.ltB
    )
    static let rushBackgroundOpacity: Double = DesignTokens.Opacity.rushBackground
    static let rushStrokeOpacity: Double = DesignTokens.Opacity.rushStroke
    static let normalBackgroundOpacity: Double = DesignTokens.Opacity.normalBackground
    static let normalStrokeOpacity: Double = DesignTokens.Opacity.normalStroke
    static let ltBackgroundOpacity: Double = DesignTokens.Opacity.ltBackground
    static let ltStrokeOpacity: Double = DesignTokens.Opacity.ltStroke
    static let rushTitleOpacity: Double = DesignTokens.Opacity.rushTitle
    static let normalTitleOpacity: Double = DesignTokens.Opacity.normalTitle
    static let ltTitleOpacity: Double = DesignTokens.Opacity.ltTitle

    /// フェーズ4: mode_id のみからの従来色（マスタ未取得時のフォールバック）。
    static func modeColor(modeId: Int) -> Color {
        switch modeId {
        case 1: return rushColor
        case 2: return ltColor
        default: return normalColor
        }
    }

    /// 滞在モードの見出し色。マスタの `ui_role` と `is_time_short` を反映する。
    ///
    /// §6 論点（電サポ＝親のときの優先）: `is_time_short == true` なら **ui_role より先に** 青系（`normalColor`）を採用する。
    /// 突入先未確定と時短はどちらも青系になりうるため、文言は `PlayModeVocabulary` / 当たりシートのラベルで区別する。
    ///
    /// - `is_time_short == true` のときは `ui_role` が RUSH でも青系（通常色）を優先する。
    /// - マスタが無いときは `modeColor(modeId:)` にフォールバックする。
    static func modeAccentColor(master: MachineFullMaster?, modeId: Int) -> Color {
        guard let mm = master?.modes.first(where: { $0.modeId == modeId }) else {
            return modeColor(modeId: modeId)
        }
        if mm.isTimeShort { return normalColor }
        switch mm.uiRole {
        case 0: return normalColor
        case 2: return ltColor
        default: return rushColor
        }
    }

    /// 実質回転率とボーダーの差に応じたエッジ発光色（±0.5=白、+0.5〜+1.5=水色、+1.5超=青、-0.5〜-1.5=黄オレンジ、-1.5未満=赤）
    static func edgeGlowColor(border: Double, realRate: Double) -> Color {
        guard border > 0 else { return accent }
        let diff = realRate - border
        if diff > 1.5 {
            return Color(
                red: DesignTokens.Color.edgeGlowBlueR,
                green: DesignTokens.Color.edgeGlowBlueG,
                blue: DesignTokens.Color.edgeGlowBlueB
            )
        }
        if diff > 0.5 { return accent }
        if diff >= -0.5 { return .white }
        if diff >= -1.5 {
            return Color(
                red: DesignTokens.Color.edgeGlowOrangeR,
                green: DesignTokens.Color.edgeGlowOrangeG,
                blue: DesignTokens.Color.edgeGlowOrangeB
            )
        }
        return Color(
            red: DesignTokens.Color.edgeGlowRedR,
            green: DesignTokens.Color.edgeGlowRedG,
            blue: DesignTokens.Color.edgeGlowRedB
        )
    }

    static var strokeGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color.white.opacity(DesignTokens.Opacity.strokeGradientTop),
                Color.white.opacity(DesignTokens.Opacity.strokeGradientMid),
                Color.white.opacity(DesignTokens.Opacity.strokeGradientBottom)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    /// ホーム下部タブバーとデータ分析ドックで共通の寸法・タイポ（見た目を揃える）
    enum MainTabDock {
        /// タブ行＋上下パディングの合計が低いほどドックが「上に伸びた」ように見えにくい
        static let tabRowHeight: CGFloat = 40
        static let paddingTop: CGFloat = 4
        static let paddingBottom: CGFloat = 4
        static let iconPointSize: CGFloat = 20
        static let labelPointSize: CGFloat = 9
        /// バー高さに対して大きすぎると角の円弧がコンテンツ側へ食い込んで見える
        static let topCornerRadius: CGFloat = 18
        static let horizontalInset: CGFloat = 20
        static let innerHorizontalPadding: CGFloat = 8
    }
}

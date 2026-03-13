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

    /// フェーズ4: mode_id に応じたモード色（0=通常=青, 1=RUSH=赤, 2=LT=ゴールド）
    static func modeColor(modeId: Int) -> Color {
        switch modeId {
        case 1: return rushColor
        case 2: return ltColor
        default: return normalColor
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
}

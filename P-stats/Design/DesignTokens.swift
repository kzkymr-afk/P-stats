import Foundation
#if canImport(SwiftUI)
import SwiftUI
#endif

/// デザインの「値だけ」を定義。Android で同じトークンを使いやすいように数値・文字列のみ。
/// SwiftUI の Color / View は持たない。AppGlassStyle 等がここを参照して Color を組み立てる。
enum DesignTokens {
    enum Color {
        static let backgroundHex = "0A0E1A"
        static let accentR: Double = 0
        static let accentG: Double = 0.83
        static let accentB: Double = 1.0
        static let rushHex = "FF0000"
        static let normalHex = "0000FF"
        static let ltR: Double = 0.95
        static let ltG: Double = 0.75
        static let ltB: Double = 0.2
        /// エッジ発光（青系・+1.5超）
        static let edgeGlowBlueR: Double = 0.2
        static let edgeGlowBlueG: Double = 0.45
        static let edgeGlowBlueB: Double = 1.0
        /// エッジ発光（黄オレンジ・-0.5〜-1.5）
        static let edgeGlowOrangeR: Double = 1.0
        static let edgeGlowOrangeG: Double = 0.65
        static let edgeGlowOrangeB: Double = 0.2
        /// エッジ発光（赤・-1.5未満）
        static let edgeGlowRedR: Double = 1.0
        static let edgeGlowRedG: Double = 0.25
        static let edgeGlowRedB: Double = 0.25
    }

    enum Opacity {
        static let rowBackground: Double = 0.65
        static let cardBackground: Double = 0.70
        static let rushBackground: Double = 0.12
        static let normalBackground: Double = 0.12
        static let ltBackground: Double = 0.12
        static let rushStroke: Double = 0.4
        static let normalStroke: Double = 0.4
        static let ltStroke: Double = 0.4
        static let rushTitle: Double = 0.95
        static let normalTitle: Double = 0.95
        static let ltTitle: Double = 0.95
        /// ストロークグラデーション（上〜下）
        static let strokeGradientTop: Double = 0.45
        static let strokeGradientMid: Double = 0.18
        static let strokeGradientBottom: Double = 0.1
    }

    enum Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 16
        static let lg: CGFloat = 24
        static let xl: CGFloat = 32
    }

    enum CornerRadius {
        static let card: CGFloat = 12
        static let panel: CGFloat = 14
        static let button: CGFloat = 16
    }
}

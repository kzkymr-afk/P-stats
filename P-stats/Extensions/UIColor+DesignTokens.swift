import UIKit

extension UIColor {
    /// `DesignTokens` の sRGB 成分（0...1）から `UIColor` を生成（SwiftUI 側と同じ数値源用）
    static func pstatsSRGB(red r: Double, green g: Double, blue b: Double, alpha: CGFloat = 1) -> UIColor {
        UIColor(red: CGFloat(r), green: CGFloat(g), blue: CGFloat(b), alpha: alpha)
    }
}

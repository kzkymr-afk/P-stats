import SwiftUI
import UIKit

// MARK: - iPhone風 半透明ドック用ブラー
struct TranslucentBlurView: UIViewRepresentable {
    var style: UIBlurEffect.Style = .systemUltraThinMaterialDark
    var alpha: CGFloat = 0.92

    func makeUIView(context: Context) -> UIVisualEffectView {
        let v = UIVisualEffectView(effect: UIBlurEffect(style: style))
        v.alpha = alpha
        return v
    }

    func updateUIView(_ uiView: UIVisualEffectView, context: Context) {
        uiView.alpha = alpha
    }
}

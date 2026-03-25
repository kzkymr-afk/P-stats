import SwiftUI
import UIKit

/// `numberPad` 用。`ToolbarItem(placement: .keyboard)` が効かない画面でも、キーボード上に「完了」を出す。
struct NumberPadTextField: UIViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var maxDigits: Int
    var font: UIFont
    var textColor: UIColor
    var accentColor: UIColor
    var doneTitle: String
    /// 値を変えるたびにキーボードを開く（親から `+= 1` してフォーカス要求）
    var focusTrigger: Int = 0

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, maxDigits: maxDigits)
    }

    func makeUIView(context: Context) -> UITextField {
        let tf = UITextField()
        tf.keyboardType = .numberPad
        tf.textAlignment = .right
        tf.font = font
        tf.textColor = textColor
        tf.placeholder = placeholder.isEmpty ? nil : placeholder
        tf.addTarget(context.coordinator, action: #selector(Coordinator.textChanged(_:)), for: .editingChanged)
        tf.autocorrectionType = .no
        tf.spellCheckingType = .no
        tf.text = text
        tf.inputAccessoryView = makeToolbar(coordinator: context.coordinator)
        return tf
    }

    func updateUIView(_ uiView: UITextField, context: Context) {
        context.coordinator.text = $text
        context.coordinator.maxDigits = maxDigits
        if uiView.text != text {
            uiView.text = text
        }
        if let bar = uiView.inputAccessoryView as? UIToolbar {
            bar.tintColor = accentColor
        }
        if focusTrigger != context.coordinator.lastFocusTrigger {
            context.coordinator.lastFocusTrigger = focusTrigger
            DispatchQueue.main.async {
                uiView.becomeFirstResponder()
            }
        }
    }

    private func makeToolbar(coordinator: Coordinator) -> UIToolbar {
        let bar = UIToolbar()
        bar.sizeToFit()
        bar.tintColor = accentColor
        let flex = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
        let done = UIBarButtonItem(title: doneTitle, style: .prominent, target: coordinator, action: #selector(Coordinator.doneTapped))
        bar.items = [flex, done]
        return bar
    }

    final class Coordinator: NSObject {
        var text: Binding<String>
        var maxDigits: Int
        var lastFocusTrigger: Int = 0

        init(text: Binding<String>, maxDigits: Int) {
            self.text = text
            self.maxDigits = maxDigits
        }

        @objc func textChanged(_ tf: UITextField) {
            let raw = tf.text ?? ""
            let digits = raw.filter { $0.isNumber }
            let limited = String(digits.prefix(maxDigits))
            if limited != raw {
                tf.text = limited
            }
            if text.wrappedValue != limited {
                text.wrappedValue = limited
            }
        }

        @objc func doneTapped() {
            UIApplication.dismissKeyboard()
        }
    }
}

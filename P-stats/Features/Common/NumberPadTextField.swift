import SwiftUI
import UIKit

/// `numberPad` / `decimalPad` 用のキーボード付属ツールバー（左：前へ・次へ、右：入力完了）。
enum NumericPadInputAccessory {
    /// 左矢印＝前の入力欄、右矢印＝次の入力欄、チェック＝キーボードを閉じる
    static func makeToolbar(
        accentColor: UIColor,
        target: AnyObject,
        previousSelector: Selector?,
        nextSelector: Selector?,
        doneSelector: Selector
    ) -> UIToolbar {
        let bar = UIToolbar()
        bar.sizeToFit()
        bar.tintColor = accentColor
        var items: [UIBarButtonItem] = []
        if let sel = previousSelector {
            let b = UIBarButtonItem(image: UIImage(systemName: "chevron.left"), style: .plain, target: target, action: sel)
            b.accessibilityLabel = "前の入力欄へ"
            items.append(b)
        }
        if let sel = nextSelector {
            let b = UIBarButtonItem(image: UIImage(systemName: "chevron.right"), style: .plain, target: target, action: sel)
            b.accessibilityLabel = "次の入力欄へ"
            items.append(b)
        }
        items.append(UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil))
        let done = UIBarButtonItem(image: UIImage(systemName: "checkmark"), style: .plain, target: target, action: doneSelector)
        done.accessibilityLabel = "入力完了"
        items.append(done)
        bar.items = items
        return bar
    }
}

/// 整数のみ（`numberPad`）。ツールバーで前後フィールド移動と確定ができる。
struct IntegerPadTextField: UIViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var maxDigits: Int
    var font: UIFont
    var textColor: UIColor
    var accentColor: UIColor
    /// 値を変えるたびにキーボードを開く（親から `+= 1` してフォーカス要求）
    var focusTrigger: Int = 0
    /// 幅が狭いとき数字が切れないよう小さくする（横はみ出し対策）
    var adjustsFontSizeToFitWidth: Bool = false
    /// `adjustsFontSizeToFitWidth` 利用時の最小フォント（pt）
    var minimumFontSize: CGFloat = 11
    /// テンキー付属ツールバー左上：前の入力欄へ（nil ならボタンなし）
    var onPreviousField: (() -> Void)? = nil
    /// 次の入力欄へ（nil ならボタンなし）
    var onNextField: (() -> Void)? = nil
    /// 互換用（ツールバーはチェックマークのまま）
    var doneTitle: String = "完了"
    var previousFieldTitle: String = "前へ"
    var nextFieldTitle: String = "次へ"
    /// フォームで無効化したいとき（灰色・入力不可）
    var isEnabled: Bool = true

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
        tf.isEnabled = isEnabled
        tf.text = text
        tf.adjustsFontSizeToFitWidth = adjustsFontSizeToFitWidth
        if adjustsFontSizeToFitWidth { tf.minimumFontSize = minimumFontSize }
        tf.inputAccessoryView = accessoryToolbar(coordinator: context.coordinator)
        return tf
    }

    func updateUIView(_ uiView: UITextField, context: Context) {
        context.coordinator.text = $text
        context.coordinator.maxDigits = maxDigits
        context.coordinator.onPrevious = onPreviousField
        context.coordinator.onNext = onNextField
        uiView.inputAccessoryView = accessoryToolbar(coordinator: context.coordinator)
        if uiView.text != text {
            uiView.text = text
        }
        if let bar = uiView.inputAccessoryView as? UIToolbar {
            bar.tintColor = accentColor
        }
        if focusTrigger != context.coordinator.lastFocusTrigger {
            context.coordinator.lastFocusTrigger = focusTrigger
            DispatchQueue.main.async {
                if isEnabled { uiView.becomeFirstResponder() }
            }
        }
        uiView.adjustsFontSizeToFitWidth = adjustsFontSizeToFitWidth
        if adjustsFontSizeToFitWidth { uiView.minimumFontSize = minimumFontSize }
        uiView.isEnabled = isEnabled
        uiView.alpha = isEnabled ? 1.0 : 0.48
    }

    private func accessoryToolbar(coordinator: Coordinator) -> UIToolbar {
        let prevSel: Selector? = onPreviousField != nil ? #selector(Coordinator.previousTapped) : nil
        let nextSel: Selector? = onNextField != nil ? #selector(Coordinator.nextTapped) : nil
        return NumericPadInputAccessory.makeToolbar(
            accentColor: accentColor,
            target: coordinator,
            previousSelector: prevSel,
            nextSelector: nextSel,
            doneSelector: #selector(Coordinator.doneTapped)
        )
    }

    final class Coordinator: NSObject {
        var text: Binding<String>
        var maxDigits: Int
        var lastFocusTrigger: Int = 0
        var onPrevious: (() -> Void)?
        var onNext: (() -> Void)?

        init(text: Binding<String>, maxDigits: Int) {
            self.text = text
            self.maxDigits = maxDigits
        }

        @objc func textChanged(_ tf: UITextField) {
            let raw = tf.text ?? ""
            let digits = raw.filter(\.isNumber)
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

        @objc func previousTapped() {
            onPrevious?()
        }

        @objc func nextTapped() {
            onNext?()
        }
    }
}

/// 小数を含む数値（`decimalPad`）。整数部・小数部の桁上限を個別に指定できる。
struct DecimalPadTextField: UIViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var maxIntegerDigits: Int
    var maxFractionDigits: Int
    var font: UIFont
    var textColor: UIColor
    var accentColor: UIColor
    var focusTrigger: Int = 0
    var adjustsFontSizeToFitWidth: Bool = false
    var minimumFontSize: CGFloat = 11
    var onPreviousField: (() -> Void)? = nil
    var onNextField: (() -> Void)? = nil
    var doneTitle: String = "完了"
    var previousFieldTitle: String = "前へ"
    var nextFieldTitle: String = "次へ"

    func makeCoordinator() -> Coordinator {
        Coordinator(
            text: $text,
            maxIntegerDigits: maxIntegerDigits,
            maxFractionDigits: maxFractionDigits
        )
    }

    func makeUIView(context: Context) -> UITextField {
        let tf = UITextField()
        tf.keyboardType = .decimalPad
        tf.textAlignment = .right
        tf.font = font
        tf.textColor = textColor
        tf.placeholder = placeholder.isEmpty ? nil : placeholder
        tf.addTarget(context.coordinator, action: #selector(Coordinator.textChanged(_:)), for: .editingChanged)
        tf.autocorrectionType = .no
        tf.spellCheckingType = .no
        tf.text = text
        tf.adjustsFontSizeToFitWidth = adjustsFontSizeToFitWidth
        if adjustsFontSizeToFitWidth { tf.minimumFontSize = minimumFontSize }
        tf.inputAccessoryView = accessoryToolbar(coordinator: context.coordinator)
        return tf
    }

    func updateUIView(_ uiView: UITextField, context: Context) {
        context.coordinator.text = $text
        context.coordinator.maxIntegerDigits = maxIntegerDigits
        context.coordinator.maxFractionDigits = maxFractionDigits
        context.coordinator.onPrevious = onPreviousField
        context.coordinator.onNext = onNextField
        uiView.inputAccessoryView = accessoryToolbar(coordinator: context.coordinator)
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
        uiView.adjustsFontSizeToFitWidth = adjustsFontSizeToFitWidth
        if adjustsFontSizeToFitWidth { uiView.minimumFontSize = minimumFontSize }
    }

    private func accessoryToolbar(coordinator: Coordinator) -> UIToolbar {
        let prevSel: Selector? = onPreviousField != nil ? #selector(Coordinator.previousTapped) : nil
        let nextSel: Selector? = onNextField != nil ? #selector(Coordinator.nextTapped) : nil
        return NumericPadInputAccessory.makeToolbar(
            accentColor: accentColor,
            target: coordinator,
            previousSelector: prevSel,
            nextSelector: nextSel,
            doneSelector: #selector(Coordinator.doneTapped)
        )
    }

    final class Coordinator: NSObject {
        var text: Binding<String>
        var maxIntegerDigits: Int
        var maxFractionDigits: Int
        var lastFocusTrigger: Int = 0
        var onPrevious: (() -> Void)?
        var onNext: (() -> Void)?

        init(text: Binding<String>, maxIntegerDigits: Int, maxFractionDigits: Int) {
            self.text = text
            self.maxIntegerDigits = maxIntegerDigits
            self.maxFractionDigits = maxFractionDigits
        }

        @objc func textChanged(_ tf: UITextField) {
            let normalized = Coordinator.normalizeDecimalInput(
                tf.text ?? "",
                maxIntegerDigits: maxIntegerDigits,
                maxFractionDigits: maxFractionDigits
            )
            if normalized != tf.text {
                tf.text = normalized
            }
            if text.wrappedValue != normalized {
                text.wrappedValue = normalized
            }
        }

        static func normalizeDecimalInput(_ raw: String, maxIntegerDigits: Int, maxFractionDigits: Int) -> String {
            var sawDot = false
            var intCount = 0
            var fracCount = 0
            var out = ""
            for ch in raw {
                if ch == "." || ch == "．" || ch == "。" {
                    if sawDot { continue }
                    sawDot = true
                    out.append(".")
                    continue
                }
                guard ch.isNumber else { continue }
                if !sawDot {
                    if intCount >= maxIntegerDigits { continue }
                    intCount += 1
                    out.append(ch)
                } else {
                    if fracCount >= maxFractionDigits { continue }
                    fracCount += 1
                    out.append(ch)
                }
            }
            return out
        }

        @objc func doneTapped() {
            UIApplication.dismissKeyboard()
        }

        @objc func previousTapped() {
            onPrevious?()
        }

        @objc func nextTapped() {
            onNext?()
        }
    }
}

/// 互換名（整数テンキー）
typealias NumberPadTextField = IntegerPadTextField

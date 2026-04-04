import SwiftUI
import UIKit

// MARK: - テンキー・キーボードを閉じる（キーウィンドウ優先）
extension UIApplication {
    /// `numberPad` / `decimalPad` 等で `resignFirstResponder` が効かない端末向けに `endEditing` を優先
    static func dismissKeyboard() {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene else {
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            return
        }
        for window in scene.windows where window.isKeyWindow {
            window.endEditing(true)
            return
        }
        scene.windows.first?.endEditing(true)
    }
}

// MARK: - キーボード・テンキー用：右側に「完了」（閉じる）を表示（全画面で統一）
extension View {
    func keyboardDismissToolbar() -> some View {
        self.toolbar {
            ToolbarItem(placement: .keyboard) {
                HStack {
                    Spacer(minLength: 0)
                    Button {
                        UIApplication.dismissKeyboard()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.title3)
                            Text("完了")
                                .font(.body.weight(.semibold))
                        }
                        .foregroundStyle(AppGlassStyle.accent)
                    }
                    .accessibilityLabel("キーボードを閉じる")
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
}

// MARK: - リスト選択のマイクロインタラクション（押下で沈む・選択時触感・選択中は発光）
struct ListSelectionStyleModifier: ViewModifier {
    var isSelected: Bool

    @EnvironmentObject private var themeManager: ThemeManager
    @State private var isPressed = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(isPressed ? 0.95 : 1.0)
            .themeShadow(themeManager.currentTheme.listSelectionShadowSpec(isSelected: isSelected))
            .animation(.spring(response: 0.35, dampingFraction: 0.7), value: isPressed)
            .animation(.easeOut(duration: 0.2), value: isSelected)
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        if !isPressed {
                            UISelectionFeedbackGenerator().selectionChanged()
                            withAnimation(.easeInOut(duration: 0.12)) { isPressed = true }
                        }
                    }
                    .onEnded { _ in
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) { isPressed = false }
                        HapticUtil.impact(.medium)
                    }
            )
    }
}

extension View {
    func listSelectionStyle(isSelected: Bool = false) -> some View {
        modifier(ListSelectionStyleModifier(isSelected: isSelected))
    }
}

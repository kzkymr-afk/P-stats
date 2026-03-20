import SwiftUI
import UIKit

// MARK: - キーボード・テンキー用：テンキー枠内右上にチェックマークで閉じる（全画面で統一）
extension View {
    func keyboardDismissToolbar() -> some View {
        self.toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                // 上：戻る / 下：次へ（キーボード・テンキー共通アクセサリ）
                Button {
                    // `UIResponder.selectPreviousKeyView` は Swift の型定義に無い場合があるため、
                    // セレクタは文字列指定で呼ぶ（存在しない場合は単に何もしない）
                    UIApplication.shared.sendAction(NSSelectorFromString("selectPreviousKeyView:"), to: nil, from: nil, for: nil)
                    UIApplication.shared.sendAction(NSSelectorFromString("selectPreviousKeyView"), to: nil, from: nil, for: nil)
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                        .foregroundStyle(AppGlassStyle.accent)
                }
                Button {
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                } label: {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(AppGlassStyle.accent)
                }
                Button {
                    UIApplication.shared.sendAction(NSSelectorFromString("selectNextKeyView:"), to: nil, from: nil, for: nil)
                    UIApplication.shared.sendAction(NSSelectorFromString("selectNextKeyView"), to: nil, from: nil, for: nil)
                } label: {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.title2)
                        .foregroundStyle(AppGlassStyle.accent)
                }
            }
        }
    }
}

// MARK: - リスト選択のマイクロインタラクション（押下で沈む・選択時触感・選択中は発光）
struct ListSelectionStyleModifier: ViewModifier {
    var isSelected: Bool

    @State private var isPressed = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(isPressed ? 0.95 : 1.0)
            .shadow(color: isSelected ? AppGlassStyle.accent.opacity(0.3) : .clear, radius: 10)
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

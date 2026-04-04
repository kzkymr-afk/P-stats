import SwiftUI

/// `#Preview` 用：`ThemeManager` を注入して `EnvironmentObject` 欠落によるクラッシュを防ぐ。
struct ThemePreview<Content: View>: View {
    let content: Content

    init(@ViewBuilder _ content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content.environmentObject(ThemeManager.shared)
    }
}

import SwiftUI

/// 起動スプラッシュ。アイコンは表示せず、P-STATSテキストを起動直後から表示。背景はフォント色（シアン）→黒へ徐々に変化させ、文字が徐々に見えるようにする。
struct LaunchView: View {
    var onFinish: () -> Void

    @EnvironmentObject private var themeManager: ThemeManager
    @State private var gradientProgress: Double = 0

    var body: some View {
        let t = themeManager.currentTheme
        let cyan = t.accentColor
        ZStack {
            LaunchAppearance.launchEndColor
                .ignoresSafeArea()

            Rectangle()
                .fill(LaunchAppearance.launchStartColor)
                .opacity(1 - gradientProgress)
                .ignoresSafeArea()

            VStack(spacing: 2) {
                Text("P-STATS")
                    .font(.system(size: 32, weight: .ultraLight, design: .default))
                    .tracking(2)
                    .foregroundStyle(cyan)
                    .themeShadow(t.splashTitleDepthShadow)
                    .themeShadow(t.splashTitleGlowShadow)
                Text("実戦データを記録・分析")
                    .font(.system(size: 9, weight: .light, design: .default))
                    .tracking(0.5)
                    .foregroundColor(.white.opacity(0.9))
                    .themeShadow(t.splashSubtitleDepthShadow)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.5)) {
                gradientProgress = 1
            }
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 550_000_000)
                await Task.yield()
                onFinish()
            }
        }
    }
}

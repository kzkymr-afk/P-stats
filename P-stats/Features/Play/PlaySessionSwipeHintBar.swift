import SwiftUI

/// 実戦画面の「スワイプで情報」バー。`PlayView` 本体から切り出し、レイアウトとジェスチャを局所化する。
struct PlaySessionSwipeHintBar: View {
    @EnvironmentObject private var themeManager: ThemeManager
    let focusAccent: Color
    let rightHandMode: Bool
    let insightPanelWidth: CGFloat
    @Binding var drawerOffset: CGFloat
    @Binding var swipeZoneGlow: Bool
    @Binding var didFireUnlockHaptic: Bool
    let geo: GeometryProxy
    var onUnlockThresholdHaptic: () -> Void

    var body: some View {
        let skin = themeManager.currentTheme
        let openThreshold = geo.size.width * 0.25
        let unlockHapticThreshold: CGFloat = 10
        let swipeBarHeight: CGFloat = 60
        let swipeBarCornerRadius: CGFloat = 4
        let swipeBarHorizontalMargin: CGFloat = 16
        let stainlessBase = Color(
            red: DesignTokens.PlaySessionChrome.swipeHintBarStainlessR,
            green: DesignTokens.PlaySessionChrome.swipeHintBarStainlessG,
            blue: DesignTokens.PlaySessionChrome.swipeHintBarStainlessB
        )
        let cyanNeon = skin.playNormalAccent
        let magentaNeon = skin.playRushAccent
        let bgGradient = LinearGradient(
            colors: [stainlessBase, stainlessBase.opacity(0.98), stainlessBase],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        let hairlineGradient = LinearGradient(
            stops: [
                .init(color: Color.white.opacity(DesignTokens.Surface.Interaction.SwipeHintHairline.clear), location: 0),
                .init(color: Color.white.opacity(DesignTokens.Surface.Interaction.SwipeHintHairline.stop02), location: 0.2),
                .init(color: Color.white.opacity(DesignTokens.Surface.Interaction.SwipeHintHairline.stop035), location: 0.35),
                .init(color: Color.white.opacity(DesignTokens.Surface.Interaction.SwipeHintHairline.stop05), location: 0.5),
                .init(color: Color.white.opacity(DesignTokens.Surface.Interaction.SwipeHintHairline.stop065), location: 0.65),
                .init(color: Color.white.opacity(DesignTokens.Surface.Interaction.SwipeHintHairline.stop08), location: 0.8),
                .init(color: Color.white.opacity(DesignTokens.Surface.Interaction.SwipeHintHairline.clear), location: 1)
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
        ZStack {
            RoundedRectangle(cornerRadius: swipeBarCornerRadius)
                .fill(bgGradient)
            RoundedRectangle(cornerRadius: swipeBarCornerRadius)
                .fill(hairlineGradient)
            if swipeZoneGlow {
                RoundedRectangle(cornerRadius: swipeBarCornerRadius)
                    .fill(focusAccent.opacity(0.15))
                    .blur(radius: 8)
                    .animation(.easeOut(duration: 0.15), value: swipeZoneGlow)
            }
            HStack(spacing: 8) {
                Image(systemName: "chevron.left.2")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(skin.mainTextColor.opacity(0.5))
                Spacer()
                Text("スワイプで情報")
                    .font(AppTypography.annotationSmall)
                    .fontWeight(.bold)
                    .foregroundColor(skin.mainTextColor.opacity(0.7))
                Spacer()
                Color.clear.frame(width: 24, height: 1)
            }
            .padding(.horizontal, 12)
        }
        .overlay(alignment: .top) {
            Rectangle().fill(cyanNeon.opacity(1)).frame(height: 0.5)
                .themeShadow(skin.playSwipeHintLeadingShadow)
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(magentaNeon.opacity(1)).frame(height: 0.5)
                .themeShadow(skin.playSwipeHintTrailingShadow)
        }
        .clipShape(RoundedRectangle(cornerRadius: swipeBarCornerRadius))
        .frame(height: swipeBarHeight)
        .padding(.horizontal, swipeBarHorizontalMargin)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 8)
                .onChanged { value in
                    if !swipeZoneGlow { swipeZoneGlow = true }
                    let delta = rightHandMode ? value.translation.width : -value.translation.width
                    let newOffset = min(insightPanelWidth, max(0, delta))
                    drawerOffset = newOffset
                    if newOffset >= unlockHapticThreshold && !didFireUnlockHaptic {
                        onUnlockThresholdHaptic()
                        didFireUnlockHaptic = true
                    }
                }
                .onEnded { value in
                    swipeZoneGlow = false
                    let delta = rightHandMode ? value.translation.width : -value.translation.width
                    let current = min(insightPanelWidth, max(0, delta))
                    if current > openThreshold {
                        withAnimation(.easeOut(duration: 0.22)) { drawerOffset = insightPanelWidth }
                    } else {
                        withAnimation(.easeOut(duration: 0.2)) {
                            drawerOffset = 0
                            didFireUnlockHaptic = false
                        }
                    }
                }
        )
    }
}

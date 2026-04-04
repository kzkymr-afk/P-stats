import SwiftUI

/// 実戦画面用：ヘッダー直下にハンドル＋バナーをオーバーレイ表示。**上方向**にスワイプで退避。背面の遊技 UI は操作可能。
struct SwipeDismissiblePlayAdBanner: View {
    let adUnitID: String
    /// 実戦終了ダイアログ中は false（常にバナーを出し、閉じられない）
    var allowDismiss: Bool
    @Binding var userDismissed: Bool

    @State private var dragY: CGFloat = 0

    private var showExpanded: Bool {
        !userDismissed || !allowDismiss
    }

    private var dismissDrag: some Gesture {
        DragGesture(minimumDistance: 14, coordinateSpace: .local)
            .onChanged { g in
                dragY = min(0, g.translation.height)
            }
            .onEnded { g in
                let threshold: CGFloat = 40
                if g.translation.height < -threshold {
                    userDismissed = true
                    HapticUtil.impact(.light)
                }
                dragY = 0
            }
    }

    var body: some View {
        Group {
            if showExpanded {
                if allowDismiss {
                    VStack(spacing: 0) {
                        HStack(spacing: 8) {
                            Capsule()
                                .fill(Color.white.opacity(DesignTokens.Surface.AdBanner.dismissAffordance))
                                .frame(width: 42, height: 5)
                            Text("上スワイプで隠す")
                                .font(.system(size: 10, weight: .medium, design: .rounded))
                                .foregroundColor(.white.opacity(0.58))
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(Color.black.opacity(DesignTokens.Surface.AdBanner.chromeBackdropStrong))
                        .gesture(dismissDrag)

                        AdaptiveBannerSlot(adUnitID: adUnitID)
                            .frame(maxWidth: .infinity)
                            .background(Color.black)
                    }
                    .offset(y: dragY)
                } else {
                    VStack(spacing: 0) {
                        AdaptiveBannerSlot(adUnitID: adUnitID)
                            .frame(maxWidth: .infinity)
                            .background(Color.black)
                    }
                }
            } else {
                Button {
                    userDismissed = false
                    HapticUtil.impact(.light)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.up")
                            .font(.system(size: 11, weight: .semibold))
                        Text("広告エリアを表示")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                    }
                    .foregroundColor(.white.opacity(0.88))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .background(Color.black.opacity(DesignTokens.Surface.AdBanner.chromeBackdrop))
                }
                .buttonStyle(.plain)
            }
        }
        .animation(.easeOut(duration: 0.2), value: userDismissed)
        .animation(.easeOut(duration: 0.2), value: allowDismiss)
    }
}

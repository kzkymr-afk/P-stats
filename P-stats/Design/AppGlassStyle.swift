import SwiftUI

// MARK: - グラスモーフィズム共通（やや不透明で統一）
/// SwiftUI 用の Color / Gradient。DesignTokens の値を参照して組み立てる。
enum AppGlassStyle {
    static let background = Color(hex: DesignTokens.Color.backgroundHex)
    static let rowBackground = Color.black.opacity(DesignTokens.Opacity.rowBackground)
    static let cardBackground = Color.black.opacity(DesignTokens.Opacity.cardBackground)
    static let accent = Color(
        red: DesignTokens.Color.accentR,
        green: DesignTokens.Color.accentG,
        blue: DesignTokens.Color.accentB
    )

    /// RUSH／通常／LTボタン用（背景・枠・文字の統一）
    static let rushColor = Color(hex: DesignTokens.Color.rushHex)
    static let normalColor = Color(hex: DesignTokens.Color.normalHex)
    static let ltColor = Color(
        red: DesignTokens.Color.ltR,
        green: DesignTokens.Color.ltG,
        blue: DesignTokens.Color.ltB
    )
    static let rushBackgroundOpacity: Double = DesignTokens.Opacity.rushBackground
    static let rushStrokeOpacity: Double = DesignTokens.Opacity.rushStroke
    static let normalBackgroundOpacity: Double = DesignTokens.Opacity.normalBackground
    static let normalStrokeOpacity: Double = DesignTokens.Opacity.normalStroke
    static let ltBackgroundOpacity: Double = DesignTokens.Opacity.ltBackground
    static let ltStrokeOpacity: Double = DesignTokens.Opacity.ltStroke
    static let rushTitleOpacity: Double = DesignTokens.Opacity.rushTitle
    static let normalTitleOpacity: Double = DesignTokens.Opacity.normalTitle
    static let ltTitleOpacity: Double = DesignTokens.Opacity.ltTitle

    /// フェーズ4: mode_id のみからの従来色（マスタ未取得時のフォールバック）。
    static func modeColor(modeId: Int) -> Color {
        switch modeId {
        case 1: return rushColor
        case 2: return ltColor
        default: return normalColor
        }
    }

    /// 滞在モードの見出し色。マスタの `ui_role` と `is_time_short` を反映する。
    ///
    /// §6 論点（電サポ＝親のときの優先）: `is_time_short == true` なら **ui_role より先に** 青系（`normalColor`）を採用する。
    /// 突入先未確定と時短はどちらも青系になりうるため、文言は `PlayModeVocabulary` / 当たりシートのラベルで区別する。
    ///
    /// - `is_time_short == true` のときは `ui_role` が RUSH でも青系（通常色）を優先する。
    /// - マスタが無いときは `modeColor(modeId:)` にフォールバックする。
    static func modeAccentColor(master: MachineFullMaster?, modeId: Int) -> Color {
        guard let mm = master?.modes.first(where: { $0.modeId == modeId }) else {
            return modeColor(modeId: modeId)
        }
        if mm.isTimeShort { return normalColor }
        switch mm.uiRole {
        case 0: return normalColor
        case 2: return ltColor
        default: return rushColor
        }
    }

    /// 実質回転率とボーダーの差に応じたエッジ発光色（±0.5=白、+0.5〜+1.5=水色、+1.5超=青、-0.5〜-1.5=黄オレンジ、-1.5未満=赤）
    static func edgeGlowColor(border: Double, realRate: Double) -> Color {
        guard border > 0 else { return accent }
        let diff = realRate - border
        if diff > 1.5 {
            return Color(
                red: DesignTokens.Color.edgeGlowBlueR,
                green: DesignTokens.Color.edgeGlowBlueG,
                blue: DesignTokens.Color.edgeGlowBlueB
            )
        }
        if diff > 0.5 { return accent }
        if diff >= -0.5 { return .white }
        if diff >= -1.5 {
            return Color(
                red: DesignTokens.Color.edgeGlowOrangeR,
                green: DesignTokens.Color.edgeGlowOrangeG,
                blue: DesignTokens.Color.edgeGlowOrangeB
            )
        }
        return Color(
            red: DesignTokens.Color.edgeGlowRedR,
            green: DesignTokens.Color.edgeGlowRedG,
            blue: DesignTokens.Color.edgeGlowRedB
        )
    }

    static var strokeGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color.white.opacity(DesignTokens.Opacity.strokeGradientTop),
                Color.white.opacity(DesignTokens.Opacity.strokeGradientMid),
                Color.white.opacity(DesignTokens.Opacity.strokeGradientBottom)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    /// ホーム下部タブバーとデータ分析ドックで共通の寸法・タイポ（参考: Prime Video 系下部ナビ）
    enum MainTabDock {
        /// 1 タブ列の最小高（アイコン＋ラベルを縦方向センタリング）
        static let tabRowHeight: CGFloat = 44
        /// グレア帯〜タブ行の間（ドック全体を低く見せるため抑えめ）
        static let paddingTopBelowGlare: CGFloat = 2
        /// ホームインジケータ上の最小すきま（`safeAreaInsets.bottom` に加算）。Prime 相当で余分な持ち上げを避ける
        static let paddingBottomInterior: CGFloat = 3
        static let iconPointSize: CGFloat = 23
        static let labelPointSize: CGFloat = 10
        static let tabIconLabelSpacing: CGFloat = 2
        static let horizontalInset: CGFloat = 0
        static let innerHorizontalPadding: CGFloat = 10
        static let inactiveTint = Color(red: 0.6, green: 0.6, blue: 0.6)
        /// 選択列スポットライト（ドック高さを抑えつつアイコン背後に収める）
        static let selectedGlowSlotHeight: CGFloat = 56
        /// Prime 風：純黒ではなくわずかに青みのあるチャコール
        static let dockBackgroundTop = Color(red: 0.11, green: 0.12, blue: 0.14)
        static let dockBackgroundBottom = Color(red: 0.035, green: 0.036, blue: 0.042)
    }

    /// 選択列背面：アイコン直下を最亮にし、下方向と画面奥へフェード（下端への垂れ下がりを抑える）
    private struct MainTabDockPrimeSelectedGlow: View {
        var body: some View {
            ZStack(alignment: .top) {
                LinearGradient(
                    stops: [
                        .init(color: Color.white.opacity(0.36), location: 0),
                        .init(color: Color.white.opacity(0.14), location: 0.22),
                        .init(color: Color.white.opacity(0.05), location: 0.42),
                        .init(color: Color.clear, location: 0.78)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .mask {
                    EllipticalGradient(
                        stops: [
                            .init(color: .white, location: 0),
                            .init(color: .white.opacity(0.62), location: 0.48),
                            .init(color: .clear, location: 1)
                        ],
                        center: UnitPoint(x: 0.5, y: 0.02),
                        startRadiusFraction: 0,
                        endRadiusFraction: 0.98
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .blur(radius: 7)
            .opacity(0.82)
            .allowsHitTesting(false)
        }
    }

    /// `GeometryReader` 由来の下端セーフエリア（`@Environment(\.safeAreaInsets)` が使えないターゲット向け）
    private struct MainTabDockSafeBottomKey: PreferenceKey {
        static var defaultValue: CGFloat = 0
        static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
            value = nextValue()
        }
    }

    private struct MainTabDockBackground: View {
        var body: some View {
            ZStack {
                LinearGradient(
                    colors: [
                        MainTabDock.dockBackgroundTop,
                        MainTabDock.dockBackgroundBottom
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                LinearGradient(
                    stops: [
                        .init(color: Color.white.opacity(0.055), location: 0),
                        .init(color: Color.clear, location: 0.38)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                LinearGradient(
                    stops: [
                        .init(color: Color.clear, location: 0),
                        .init(color: Color.black.opacity(0.22), location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        }
    }

    /// ドック上縁：非選択時は極細の分離線、選択グレアあり時は上向き光でエッジが照らされたように見せる
    private struct DockTopEdgeHighlight: View {
        var isLit: Bool

        var body: some View {
            ZStack(alignment: .top) {
                if isLit {
                    LinearGradient(
                        stops: [
                            .init(color: Color.white.opacity(0.2), location: 0),
                            .init(color: Color.white.opacity(0.05), location: 0.45),
                            .init(color: Color.clear, location: 1)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 6)
                    .blur(radius: 1.5)
                    .allowsHitTesting(false)
                }
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(isLit ? 0.42 : 0.09),
                                Color.white.opacity(isLit ? 0.18 : 0.04),
                                Color.white.opacity(isLit ? 0.05 : 0)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(height: isLit ? 1.5 : 0.85)
                    .allowsHitTesting(false)
            }
            .frame(maxWidth: .infinity)
        }
    }

    /// チャコールグラデーション＋上端シアン。選択列はアイコン寄りを照らすスポットライト。
    struct MainTabDockChrome<Content: View>: View {
        var selectedTabIndex: Int?
        var tabCount: Int
        @ViewBuilder var content: () -> Content

        @State private var safeBottomInset: CGFloat = 0

        var body: some View {
            let glowH = MainTabDock.selectedGlowSlotHeight
            let bottomPad = safeBottomInset + MainTabDock.paddingBottomInterior
            let hasSelectionGlare = selectedTabIndex != nil
            VStack(spacing: 0) {
                ZStack(alignment: .bottom) {
                    MainTabDockBackground()

                    HStack(spacing: 0) {
                        ForEach(0..<max(tabCount, 1), id: \.self) { i in
                            Group {
                                if let s = selectedTabIndex, s == i {
                                    MainTabDockPrimeSelectedGlow()
                                } else {
                                    Color.clear
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: glowH)
                        }
                    }
                    .frame(height: glowH)
                    .allowsHitTesting(false)

                    VStack(spacing: 0) {
                        content()
                            .padding(.horizontal, MainTabDock.innerHorizontalPadding)
                            .padding(.top, MainTabDock.paddingTopBelowGlare)
                            .padding(.bottom, bottomPad)
                    }
                }
                .overlay(alignment: .top) {
                    DockTopEdgeHighlight(isLit: hasSelectionGlare)
                }
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)
                .background {
                    MainTabDockBackground()
                        .ignoresSafeArea(edges: .bottom)
                }
            }
            .padding(.horizontal, MainTabDock.horizontalInset)
            .background {
                GeometryReader { geo in
                    Color.clear
                        .preference(key: MainTabDockSafeBottomKey.self, value: geo.safeAreaInsets.bottom)
                        .allowsHitTesting(false)
                }
            }
            .onPreferenceChange(MainTabDockSafeBottomKey.self) { safeBottomInset = $0 }
            .ignoresSafeArea(edges: .bottom)
        }
    }
}

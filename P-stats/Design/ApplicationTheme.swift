import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// MARK: - シャドウ仕様（テーマ駆動）

/// インライン `.shadow(color:radius:x:y:)` を置き換えるための値束ね。
struct ThemeShadowSpec: Equatable {
    var color: Color
    var radius: CGFloat
    var x: CGFloat
    var y: CGFloat

    static let none = ThemeShadowSpec(color: .clear, radius: 0, x: 0, y: 0)
}

/// 実戦「スワイプで情報」バー上下の縁発光の見た目。スキンごとに切り替える。
enum PlaySwipeHintEdgeGlowStyle: Equatable, Sendable {
    /// グラス既定：アクセントに沿った適度な縁光
    case standard
    /// ネオン強調：半径・不透明度を上げる
    case neon
    /// 和風・筆跡向け：墨色の広いにじみ（将来スキン用）
    case inkWash
    /// 縁の発光なし
    case minimal
}

// MARK: - スキン（見た目）の契約

/// どのスキンでも共通して定義しておく色・形状・フォント識別子。
protocol ApplicationTheme {
    /// メインのアクセント色
    var accentColor: Color { get }
    /// パネルやカードの背景色（主面）
    var panelBackground: Color { get }
    /// 標準的な文字色
    var mainTextColor: Color { get }
    /// 補足情報の文字色
    var subTextColor: Color { get }
    /// パネルの角丸の大きさ
    var cornerRadius: CGFloat { get }
    /// 枠線の太さ
    var borderWidth: CGFloat { get }
    /// メインで使用するフォント名（システムフォントの場合は識別用の論理名）
    var fontName: String { get }

    // MARK: - サーフェス（白/黒インラインの置き換え）

    /// 主パネル上の二次面（旧 `Color.white.opacity(0.1)` 相当）
    var panelSecondaryBackground: Color { get }
    /// 数値入力・フォーム行の下地
    var inputFieldBackground: Color { get }
    /// `panelSecondaryBackground` より一段明るい帯（フォーム内区画など）
    var panelElevatedSecondaryBackground: Color { get }
    /// リスト行・インサイト行など（旧 `AppGlassStyle.rowBackground`）
    var listRowBackground: Color { get }

    /// 暗背景上の主オーバーレイ（`Color.white.opacity` の役割代替）
    var surfacePrimary: Color { get }
    /// 暗背景上の副オーバーレイ
    var surfaceSecondary: Color { get }
    /// 下帯・モーダル周りのスクリム
    var overlayDark: Color { get }
    /// 欠損・注意の前景（旧システムオレンジ相当）
    var cautionForegroundColor: Color { get }
    /// 強調シアン系（旧 `Color.cyan` 相当・薄塗りボタン等）
    var highlightAccentColor: Color { get }

    // MARK: - 線・区切り（グラス UI 共通）

    var hairlineDividerColor: Color { get }
    var gaugeLineColor: Color { get }
    var chartGridLineColor: Color { get }

    // MARK: - セマンティック（実戦・アクション）

    /// 投資・支出側の強調（現金・持ち玉ゾーン等）
    var investmentColor: Color { get }
    /// 回収・プラス方向（金〜アンバー）
    var recoveryColor: Color { get }
    /// 当たり・大当たりのネオン的強調
    var jackpotColor: Color { get }

    // MARK: - 実戦・インサイト（既存セマンティック）

    /// 実戦の「通常」系カウント・状態表示
    var playNormalAccent: Color { get }
    /// RUSH 系の強調
    var playRushAccent: Color { get }
    /// 投資ゾーン見出し（`investmentColor` と揃える想定）
    var playInvestmentHeadline: Color { get }
    /// 実戦カード類の枠線（単色）
    var playCardOutline: Color { get }
    /// インサイトドロワー全体の背景
    var insightDrawerBackdrop: Color { get }
    /// インサイト内の区画・行の面
    var insightSectionSurface: Color { get }

    // MARK: - シャドウ（インライン `.shadow` の置き換え）

    /// カード／立体的ボタン（実戦 `playButtonChrome` 等）
    var cardShadow: ThemeShadowSpec { get }
    /// グリッドボタン・インタラクティブ面（非押下）
    var interactiveSurfaceShadowRest: ThemeShadowSpec { get }
    /// グリッドボタン・インタラクティブ面（押下中）
    var interactiveSurfaceShadowPressed: ThemeShadowSpec { get }
    /// リスト行が選択中の外光
    var listSelectionShadow: ThemeShadowSpec { get }
    /// 履歴グラフのバー上ラベルなど
    var compactLabelShadow: ThemeShadowSpec { get }
    /// スライドレールなど軽い浮き
    var railShadow: ThemeShadowSpec { get }
    /// スワイプヒントバー縁の演出種別（`playSwipeHintLeadingShadow` / `Trailing` の解決に使う）
    var playSwipeHintEdgeGlowStyle: PlaySwipeHintEdgeGlowStyle { get }

    // MARK: - スプラッシュ（起動画面）

    var splashTitleDepthShadow: ThemeShadowSpec { get }
    var splashTitleGlowShadow: ThemeShadowSpec { get }
    var splashSubtitleDepthShadow: ThemeShadowSpec { get }

    // MARK: - 分析ダッシュボード・Swift Charts

    var navigationBarBackdropColor: Color { get }
    var bottomToolbarScrimColor: Color { get }
    var analyticsAuxiliaryListRowColor: Color { get }
    var chartRuleMarkMutedColor: Color { get }
    var chartMajorGridColor: Color { get }
    var chartMediumGridColor: Color { get }
    var chartMinorGridColor: Color { get }
    var chartFaintGridColor: Color { get }
    var chartAxisTickColor: Color { get }
    var chartZeroBaselineColor: Color { get }
    var chartYAxisLabelColor: Color { get }
    var chartYAxisLabelSoftColor: Color { get }
    var chartXAxisLabelColor: Color { get }
    var chartXAxisCaptionColor: Color { get }
    var analyticsDatePillBackground: Color { get }
    var analyticsSeparatorLineColor: Color { get }
    var chartLossBarColor: Color { get }

    // MARK: - フォーム・内蔵ブラウザ系の深い面

    var formCanvasDeepBackground: Color { get }
    var formCanvasMutedBackground: Color { get }
    var chromeSheetBackdropColor: Color { get }
    var chromeSheetBorderColor: Color { get }

    /// フォーム深層面の中間（例: 0.05 相当）
    var formCanvasMidBackground: Color { get }
    /// 収支トレンドの「期待値」折れ線・棒の基調色
    var chartTheoreticalAccentColor: Color { get }
    /// 累計チャートの欠損側バンド
    var analyticsTrendDeficitBandColor: Color { get }
}

// MARK: - デフォルト（DesignTokens / AppDesignSystem がソース・AppGlassStyle はここ経由）

struct DefaultTheme: ApplicationTheme {
    var accentColor: Color { AppDesignSystem.Palette.accent }
    var panelBackground: Color { Color.black.opacity(DesignTokens.Opacity.cardBackground) }
    var mainTextColor: Color { AppDesignSystem.Palette.textPrimary }
    var subTextColor: Color { AppDesignSystem.Palette.textSecondary }
    var cornerRadius: CGFloat { DesignTokens.CornerRadius.panel }
    var borderWidth: CGFloat { DesignTokens.Thickness.hairline }

    var fontName: String { "SF Pro Rounded" }

    var surfacePrimary: Color { Color.white.opacity(DesignTokens.Surface.WhiteOnDark.medium) }
    var surfaceSecondary: Color { Color.white.opacity(DesignTokens.Surface.WhiteOnDark.extraLow) }
    var overlayDark: Color { Color.black.opacity(DesignTokens.Surface.BlackOverlay.bottomToolbar) }
    var cautionForegroundColor: Color {
        Color(
            red: DesignTokens.Home.statusWarningR,
            green: DesignTokens.Home.statusWarningG,
            blue: DesignTokens.Home.statusWarningB
        )
    }
    var highlightAccentColor: Color {
        Color(
            red: DesignTokens.Semantic.Standard.highlightAccentR,
            green: DesignTokens.Semantic.Standard.highlightAccentG,
            blue: DesignTokens.Semantic.Standard.highlightAccentB
        )
    }

    var panelSecondaryBackground: Color { Color.white.opacity(DesignTokens.Opacity.panelSecondaryOverlay) }
    var inputFieldBackground: Color { Color.white.opacity(DesignTokens.Opacity.inputFieldOverlay) }
    var panelElevatedSecondaryBackground: Color { Color.white.opacity(DesignTokens.Opacity.panelElevatedOverlay) }
    var listRowBackground: Color { Color.black.opacity(DesignTokens.Opacity.rowBackground) }

    var hairlineDividerColor: Color { AppDesignSystem.Palette.divider }
    var gaugeLineColor: Color { AppDesignSystem.Palette.gaugeLine }
    var chartGridLineColor: Color { AppDesignSystem.Palette.chartGrid }

    var investmentColor: Color {
        Color(
            red: DesignTokens.Semantic.Standard.investmentR,
            green: DesignTokens.Semantic.Standard.investmentG,
            blue: DesignTokens.Semantic.Standard.investmentB
        )
    }
    var recoveryColor: Color {
        Color(
            red: DesignTokens.Semantic.Standard.recoveryR,
            green: DesignTokens.Semantic.Standard.recoveryG,
            blue: DesignTokens.Semantic.Standard.recoveryB
        )
    }
    var jackpotColor: Color { AppDesignSystem.Palette.accent }

    var playNormalAccent: Color { Color(hex: DesignTokens.Color.normalHex) }
    var playRushAccent: Color { Color(hex: DesignTokens.Color.rushHex) }
    var playInvestmentHeadline: Color { investmentColor }
    var playCardOutline: Color { Color.white.opacity(DesignTokens.Surface.WhiteOnDark.outlineSubtle) }
    var insightDrawerBackdrop: Color { AppDesignSystem.Palette.background }
    var insightSectionSurface: Color { listRowBackground }

    var cardShadow: ThemeShadowSpec {
        ThemeShadowSpec(
            color: Color.black.opacity(DesignTokens.Surface.BlackOverlay.shadowCard),
            radius: DesignTokens.Elevation.shadowRadiusCard,
            x: 0,
            y: DesignTokens.Elevation.shadowYCard
        )
    }

    var interactiveSurfaceShadowRest: ThemeShadowSpec {
        ThemeShadowSpec(
            color: Color.black.opacity(DesignTokens.Surface.BlackOverlay.shadowMedium),
            radius: DesignTokens.Elevation.shadowRadiusInteractive,
            x: 0,
            y: DesignTokens.Elevation.shadowYCard
        )
    }

    var interactiveSurfaceShadowPressed: ThemeShadowSpec {
        ThemeShadowSpec(
            color: Color.black.opacity(DesignTokens.Surface.BlackOverlay.shadowLight),
            radius: DesignTokens.Elevation.shadowRadiusPressed,
            x: 0,
            y: DesignTokens.Elevation.shadowYPressed
        )
    }

    var listSelectionShadow: ThemeShadowSpec {
        ThemeShadowSpec(
            color: accentColor.opacity(DesignTokens.Surface.AccentTint.listSelectionGlow),
            radius: DesignTokens.Elevation.shadowRadiusListSelection,
            x: 0,
            y: 0
        )
    }

    var compactLabelShadow: ThemeShadowSpec {
        ThemeShadowSpec(
            color: Color.black.opacity(DesignTokens.Surface.BlackOverlay.shadowCompact),
            radius: DesignTokens.Elevation.shadowRadiusCompactLabel,
            x: 0,
            y: DesignTokens.Elevation.shadowYCompactLabel
        )
    }

    var railShadow: ThemeShadowSpec {
        ThemeShadowSpec(
            color: Color.black.opacity(DesignTokens.Surface.BlackOverlay.shadowLight),
            radius: DesignTokens.Elevation.shadowRadiusRail,
            x: 0,
            y: DesignTokens.Elevation.shadowYRail
        )
    }

    var splashTitleDepthShadow: ThemeShadowSpec {
        ThemeShadowSpec(
            color: Color.black.opacity(DesignTokens.Surface.BlackOverlay.splashDepthStrong),
            radius: DesignTokens.Elevation.shadowRadiusCompactLabel,
            x: 0,
            y: DesignTokens.Elevation.shadowYSplashDepth
        )
    }

    var splashTitleGlowShadow: ThemeShadowSpec {
        ThemeShadowSpec(
            color: accentColor.opacity(DesignTokens.Surface.AccentTint.splashTitleGlow),
            radius: DesignTokens.Elevation.shadowRadiusSplashTitle,
            x: 0,
            y: 0
        )
    }

    var splashSubtitleDepthShadow: ThemeShadowSpec {
        ThemeShadowSpec(
            color: Color.black.opacity(DesignTokens.Surface.BlackOverlay.splashDepthWeak),
            radius: DesignTokens.Elevation.shadowRadiusSplashSubtitle,
            x: 0,
            y: 0
        )
    }

    var navigationBarBackdropColor: Color { Color.black.opacity(DesignTokens.Surface.BlackOverlay.navigationBar) }
    var bottomToolbarScrimColor: Color { Color.black.opacity(DesignTokens.Surface.BlackOverlay.bottomToolbar) }
    var analyticsAuxiliaryListRowColor: Color { Color.black.opacity(DesignTokens.Surface.BlackOverlay.auxiliaryRow) }
    var chartRuleMarkMutedColor: Color { Color.white.opacity(DesignTokens.Surface.WhiteOnDark.chartRule) }
    var chartMajorGridColor: Color { Color.white.opacity(DesignTokens.Surface.WhiteOnDark.chartMajor) }
    var chartMediumGridColor: Color { Color.white.opacity(DesignTokens.Surface.WhiteOnDark.chartMedium) }
    var chartMinorGridColor: Color { Color.white.opacity(DesignTokens.Surface.WhiteOnDark.chartMinor) }
    var chartFaintGridColor: Color { Color.white.opacity(DesignTokens.Surface.WhiteOnDark.chartFaint) }
    var chartAxisTickColor: Color { Color.white.opacity(DesignTokens.Surface.WhiteOnDark.chartAxis) }
    var chartZeroBaselineColor: Color { Color.white.opacity(DesignTokens.Surface.WhiteOnDark.chartAxis) }
    var chartYAxisLabelColor: Color { Color.white.opacity(DesignTokens.Surface.WhiteOnDark.chartLabelY) }
    var chartYAxisLabelSoftColor: Color { Color.white.opacity(DesignTokens.Surface.WhiteOnDark.chartLabelYSoft) }
    var chartXAxisLabelColor: Color { Color.white.opacity(DesignTokens.Surface.WhiteOnDark.chartLabelX) }
    var chartXAxisCaptionColor: Color { Color.white.opacity(DesignTokens.Surface.WhiteOnDark.chartCaptionX) }
    var analyticsDatePillBackground: Color { Color.black.opacity(DesignTokens.Surface.BlackOverlay.datePill) }
    var analyticsSeparatorLineColor: Color { Color.white.opacity(DesignTokens.Surface.WhiteOnDark.separatorFaint) }
    var chartLossBarColor: Color { AppDesignSystem.Palette.loss }

    var formCanvasDeepBackground: Color { Color.white.opacity(DesignTokens.Surface.WhiteOnDark.formDeep) }
    var formCanvasMutedBackground: Color { Color.white.opacity(DesignTokens.Surface.WhiteOnDark.formMuted) }
    var chromeSheetBackdropColor: Color { Color.black.opacity(DesignTokens.Surface.BlackOverlay.chromeBackdrop) }
    var chromeSheetBorderColor: Color { Color.white.opacity(DesignTokens.Surface.WhiteOnDark.chromeBorder) }

    var formCanvasMidBackground: Color { Color.white.opacity(DesignTokens.Surface.WhiteOnDark.formMid) }
    var chartTheoreticalAccentColor: Color {
        Color(
            red: DesignTokens.Semantic.Standard.theoreticalAccentR,
            green: DesignTokens.Semantic.Standard.theoreticalAccentG,
            blue: DesignTokens.Semantic.Standard.theoreticalAccentB
        )
    }
    var analyticsTrendDeficitBandColor: Color {
        Color(
            red: DesignTokens.Color.edgeGlowRedR,
            green: DesignTokens.Color.edgeGlowRedG,
            blue: DesignTokens.Color.edgeGlowRedB
        ).opacity(0.22)
    }
}

extension DefaultTheme {
    /// 環境や DI なしで参照するシングルトン的デフォルト。
    static let shared = DefaultTheme()
}

// MARK: - テーマに基づくフォント

extension ApplicationTheme {
    /// `fontName` が SF Pro Rounded（既定）のときはシステムの Rounded／Monospaced を使う。
    /// `system.default` は標準のサンセリフ（モダンなゴシック体に近いシステム UI フォント）。
    func themedFont(size: CGFloat, weight: Font.Weight = .regular, monospaced: Bool = false) -> Font {
        let n = fontName.trimmingCharacters(in: .whitespacesAndNewlines)
        let useSystemDefault = n == "system.default" || n == "system.sans"
        if useSystemDefault {
            return .system(size: size, weight: weight, design: monospaced ? .monospaced : .default)
        }
        let useSystemRounded = n.isEmpty
            || n.localizedCaseInsensitiveContains("SF Pro Rounded")
            || n == "system.rounded"
        if useSystemRounded {
            return .system(size: size, weight: weight, design: monospaced ? .monospaced : .rounded)
        }
        return Font.custom(n, size: size)
    }

    /// PostScript 名など **実フォント名** を `fontName` にしたスキン用。バンドルに無い名前のときはシステム系へフォールバックし、黙って潰れるのを防ぐ。
    func themedFontResolvingCustomName(size: CGFloat, weight: Font.Weight = .regular, monospaced: Bool = false) -> Font {
        let n = fontName.trimmingCharacters(in: .whitespacesAndNewlines)
        let isLogicalToken = n.isEmpty
            || n == "system.default"
            || n == "system.sans"
            || n == "system.rounded"
            || n.localizedCaseInsensitiveContains("SF Pro Rounded")
        if isLogicalToken {
            return themedFont(size: size, weight: weight, monospaced: monospaced)
        }
        #if canImport(UIKit)
        if UIFont(name: n, size: size) != nil {
            return Font.custom(n, size: size)
        }
        #endif
        return themedFont(size: size, weight: weight, monospaced: monospaced)
    }

    /// 選択中でないときは影なし、選択中は `listSelectionShadow`。
    func listSelectionShadowSpec(isSelected: Bool) -> ThemeShadowSpec {
        isSelected ? listSelectionShadow : .none
    }

    var playSwipeHintEdgeGlowStyle: PlaySwipeHintEdgeGlowStyle { .standard }

    /// 実戦スワイプヒント左（通常系アクセント）の縁発光
    var playSwipeHintLeadingShadow: ThemeShadowSpec {
        switch playSwipeHintEdgeGlowStyle {
        case .standard:
            return ThemeShadowSpec(
                color: playNormalAccent.opacity(0.7),
                radius: DesignTokens.Elevation.swipeHintRadiusStandard,
                x: 0,
                y: 0
            )
        case .neon:
            return ThemeShadowSpec(
                color: playNormalAccent.opacity(0.9),
                radius: DesignTokens.Elevation.swipeHintRadiusNeon,
                x: 0,
                y: 1
            )
        case .inkWash:
            let ink = Color(
                red: DesignTokens.PlaySessionChrome.swipeHintInkWashR,
                green: DesignTokens.PlaySessionChrome.swipeHintInkWashG,
                blue: DesignTokens.PlaySessionChrome.swipeHintInkWashB
            )
            return ThemeShadowSpec(color: ink.opacity(0.52), radius: DesignTokens.Elevation.swipeHintInkWashRadius, x: 0, y: 2)
        case .minimal:
            return .none
        }
    }

    /// 実戦スワイプヒント右（RUSH 系アクセント）の縁発光
    var playSwipeHintTrailingShadow: ThemeShadowSpec {
        switch playSwipeHintEdgeGlowStyle {
        case .standard:
            return ThemeShadowSpec(
                color: playRushAccent.opacity(0.7),
                radius: DesignTokens.Elevation.swipeHintRadiusStandard,
                x: 0,
                y: 0
            )
        case .neon:
            return ThemeShadowSpec(
                color: playRushAccent.opacity(0.88),
                radius: DesignTokens.Elevation.swipeHintRadiusNeon,
                x: 0,
                y: -1
            )
        case .inkWash:
            let warmInk = Color(
                red: DesignTokens.PlaySessionChrome.swipeHintInkWashTrailingR,
                green: DesignTokens.PlaySessionChrome.swipeHintInkWashTrailingG,
                blue: DesignTokens.PlaySessionChrome.swipeHintInkWashTrailingB
            )
            return ThemeShadowSpec(color: warmInk.opacity(0.48), radius: 13, x: 0, y: -2)
        case .minimal:
            return .none
        }
    }

    /// スランプチャート枠のグラデーション（`strokeTint` は連チャン系アクセント）
    func slumpChartBorderGradient(strokeTint: Color) -> LinearGradient {
        LinearGradient(
            colors: [
                Color.white.opacity(0.46),
                strokeTint.opacity(0.35),
                Color.white.opacity(0.09)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    /// スランプチャートのゼロ線（`chartZeroBaselineColor` よりやや弱い見た目に寄せる場合は調整）
    var slumpChartZeroLineColor: Color { chartZeroBaselineColor }
    var slumpChartTitleColor: Color { mainTextColor }
    var slumpChartAxisLabelStrongColor: Color { subTextColor.opacity(0.88) }
    var slumpChartAxisLabelMidColor: Color { subTextColor.opacity(0.74) }
    var slumpChartXEndLabelColor: Color { subTextColor.opacity(0.74) }
    /// 一覧行用の薄い面ではなく、カードパネルと同じ主面に揃える。
    var slumpChartPanelFillColor: Color { panelBackground }
}

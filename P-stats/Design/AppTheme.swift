import SwiftUI

/// アプリ全体のデザインシステム（核）。
/// 既存に `AppTheme`（起動時モード等の設定用enum）があるため、設計トークン側は別名にする。
/// 色・タイポ・角丸/影などの「判断」をここに集約し、画面側はこれを参照する。
enum AppDesignSystem {
    // MARK: - Color palette (Identity)
    //
    // 「実機の興奮 × 分析の冷静さ」
    // - Base: 深いネイビー（暗所でも眩しくない、データ表示が映える）
    // - Accent: シアン（計測/分析の冷静さ、操作の主導色）
    // - Semantic: Win/Loss/Expectation を「一目で誤読しにくい」色相で固定
    enum Palette {
        /// アプリの土台（背景）
        static let background = Color(hex: DesignTokens.Color.backgroundHex)

        /// 主要アクセント（ボタン/強調/リンク）
        static let accent = Color(
            red: DesignTokens.Color.accentR,
            green: DesignTokens.Color.accentG,
            blue: DesignTokens.Color.accentB
        )

        /// サブアクセント（通常系のラベル・弱い強調）
        static let subAccent = Color(hex: DesignTokens.Color.normalHex)

        /// 勝ち（プラス）
        static let win = Color(
            red: DesignTokens.Semantic.Standard.winR,
            green: DesignTokens.Semantic.Standard.winG,
            blue: DesignTokens.Semantic.Standard.winB
        )
        /// 大勝ち（強調したいプラス）
        static let winStrong = Color(
            red: DesignTokens.Semantic.Standard.winStrongR,
            green: DesignTokens.Semantic.Standard.winStrongG,
            blue: DesignTokens.Semantic.Standard.winStrongB
        )
        /// 負け（マイナス）
        static let loss = Color(
            red: DesignTokens.Semantic.Standard.lossR,
            green: DesignTokens.Semantic.Standard.lossG,
            blue: DesignTokens.Semantic.Standard.lossB
        )
        /// 期待値（分析の“正”）
        static let expectation = Color(
            red: DesignTokens.Semantic.Standard.expectationR,
            green: DesignTokens.Semantic.Standard.expectationG,
            blue: DesignTokens.Semantic.Standard.expectationB
        )

        /// 主テキスト
        static let textPrimary = Color.white.opacity(DesignTokens.Surface.WhiteOnDark.textPrimary)
        /// 補助テキスト
        static let textSecondary = Color.white.opacity(DesignTokens.Surface.WhiteOnDark.textSecondary)
        /// 薄い補助/注釈
        static let textTertiary = Color.white.opacity(DesignTokens.Surface.WhiteOnDark.textTertiary)

        /// 区切り線（薄い）
        static let divider = Color.white.opacity(DesignTokens.Surface.WhiteOnDark.divider)
        /// チャート/ゲージの線
        static let gaugeLine = Color.white.opacity(DesignTokens.Surface.WhiteOnDark.gaugeLine)
        /// チャートのグリッド
        static let chartGrid = Color.white.opacity(DesignTokens.Surface.WhiteOnDark.chartGrid)
    }

    // MARK: - Typography (Numbers first)
    enum Typography {
        /// パネル見出し（Main）
        static let panelHeading = Font.system(size: 17, weight: .semibold, design: .rounded)
        /// サブ見出し
        static let sectionSubheading = Font.system(size: 15, weight: .semibold, design: .rounded)
        /// 本文
        static let bodyRounded = Font.system(size: 14, weight: .medium, design: .rounded)
        /// 狭い場所のパネルタイトル
        static let insightPanelTitle = Font.system(size: 13, weight: .semibold, design: .rounded)
        /// 数値（読みやすさ最優先）
        static let bodyMonoSemibold = Font.system(size: 14, weight: .semibold, design: .monospaced)
        // MARK: 注釈（TextStyle の caption / caption2 相当を +1pt）
        static let annotation = Font.system(size: 13, weight: .regular, design: .rounded)
        static let annotationMedium = Font.system(size: 13, weight: .medium, design: .rounded)
        static let annotationSemibold = Font.system(size: 13, weight: .semibold, design: .rounded)
        static let annotationLight = Font.system(size: 13, weight: .light, design: .rounded)
        static let annotationMonospacedDigitSemibold = Font.system(size: 13, weight: .semibold, design: .rounded).monospacedDigit()
        static let annotationSmall = Font.system(size: 12, weight: .regular, design: .rounded)
        static let annotationSmallMedium = Font.system(size: 12, weight: .medium, design: .rounded)
        static let annotationSmallSemibold = Font.system(size: 12, weight: .semibold, design: .rounded)
        static let annotationSmallMonospacedDigitSemibold = Font.system(size: 12, weight: .semibold, design: .rounded).monospacedDigit()
    }

    // MARK: - Shape / Shadow (Consistent geometry)
    enum Metrics {
        enum CornerRadius {
            static let card: CGFloat = DesignTokens.CornerRadius.card
            static let panel: CGFloat = DesignTokens.CornerRadius.panel
            static let button: CGFloat = DesignTokens.CornerRadius.button
        }

        /// “浮かせたい”要素向けの共通シャドウ
        static let elevatedShadowColor = Color.black.opacity(DesignTokens.Surface.BlackOverlay.shadowMedium)
        static let elevatedShadowRadius: CGFloat = DesignTokens.Elevation.shadowRadiusInteractive
        static let elevatedShadowY: CGFloat = DesignTokens.Elevation.shadowYCard
    }

    // MARK: - Components (Reusable look & feel)
    enum Spacing {
        static let xs: CGFloat = DesignTokens.Spacing.xs
        static let sm: CGFloat = DesignTokens.Spacing.sm
        static let md: CGFloat = DesignTokens.Spacing.md
        static let lg: CGFloat = DesignTokens.Spacing.lg
        static let xl: CGFloat = DesignTokens.Spacing.xl
    }

    /// 画面全体の“空気”を作るための背景（薄いグラデーション＋光源）
    enum Background {
        static var base: some View {
            ZStack {
                Palette.background
                LinearGradient(
                    colors: [
                        Palette.accent.opacity(0.10),
                        Color.clear,
                        Palette.subAccent.opacity(0.06)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                RadialGradient(
                    colors: [Color.white.opacity(DesignTokens.Surface.WhiteOnDark.low), .clear],
                    center: .topTrailing,
                    startRadius: 10,
                    endRadius: 520
                )
            }
        }
    }

    /// カード/パネルの標準（立体感＋境界）
    enum CardStyle {
        static let fill = AppGlassStyle.cardBackground
        static let stroke = AppGlassStyle.strokeGradient
        static let strokeLineWidth: CGFloat = DesignTokens.Thickness.hairline
        static let cornerRadius: CGFloat = Metrics.CornerRadius.panel

        static func shadow(isEnabled: Bool = true) -> (color: Color, radius: CGFloat, x: CGFloat, y: CGFloat) {
            guard isEnabled else { return (.clear, 0, 0, 0) }
            return (Metrics.elevatedShadowColor, Metrics.elevatedShadowRadius, 0, Metrics.elevatedShadowY)
        }
    }

    /// 数値のハイライト（最重要を“飛び込ませる”）
    enum EmphasisNumber {
        static func font(size: CGFloat, weight: Font.Weight = .heavy, monospaced: Bool = true) -> Font {
            let base = Font.system(size: size, weight: weight, design: monospaced ? .monospaced : .rounded)
            return base
        }

        static func color(forSignedValue value: Double) -> Color {
            if value > 0 { return Palette.win }
            if value < 0 { return Palette.loss }
            return Palette.textPrimary
        }
    }
}


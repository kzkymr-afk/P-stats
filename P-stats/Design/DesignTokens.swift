import Foundation
#if canImport(SwiftUI)
import SwiftUI
#endif

/// デザインの「値だけ」を定義。Android で同じトークンを使いやすいように数値・文字列のみ。
/// SwiftUI の Color / View は持たない。AppGlassStyle 等がここを参照して Color を組み立てる。
enum DesignTokens {
    enum Color {
        static let backgroundHex = "0A0E1A"
        /// 黒背景上の視認性（WCAG 観点で純青 #00F より高明度のシアン寄り）
        static let accentR: Double = 0.35
        static let accentG: Double = 0.88
        static let accentB: Double = 1.0
        static let rushHex = "FF0000"
        /// 通常系ボタン・ラベル用。純青は暗背景でコントラスト不足のため高明度スカイブルー
        static let normalHex = "78B0FF"
        /// エッジ発光（青系・+1.5超）— 暗背景で区別しやすい明るめの青
        static let edgeGlowBlueR: Double = 0.45
        static let edgeGlowBlueG: Double = 0.65
        static let edgeGlowBlueB: Double = 1.0
        /// エッジ発光（黄オレンジ・-0.5〜-1.5）
        static let edgeGlowOrangeR: Double = 1.0
        static let edgeGlowOrangeG: Double = 0.65
        static let edgeGlowOrangeB: Double = 0.2
        /// エッジ発光（赤・-1.5未満）
        static let edgeGlowRedR: Double = 1.0
        static let edgeGlowRedG: Double = 0.25
        static let edgeGlowRedB: Double = 0.25
    }

    // MARK: - 面・オーバーレイ不透明度（暗背景上の白 / スクリム）

    enum Surface {
        /// 暗背景に載せる白のオーバーレイ階層
        enum WhiteOnDark {
            static let ultraLow: Double = 0.03
            static let extraLow: Double = 0.05
            static let low: Double = 0.06
            static let mediumLow: Double = 0.08
            static let medium: Double = 0.10
            static let elevated: Double = 0.12
            static let outlineSubtle: Double = 0.14
            static let strong: Double = 0.15
            static let high: Double = 0.20
            static let chartRule: Double = 0.40
            static let hairlineStrong: Double = 0.35
            static let textPrimary: Double = 0.92
            /// シート内の強調ラベル（ほぼ不透明の白）
            static let nearOpaqueLabel: Double = 0.95
            static let textSecondary: Double = 0.68
            static let textTertiary: Double = 0.52
            static let captionOnPanel: Double = 0.55
            static let divider: Double = 0.15
            static let gaugeLine: Double = 0.22
            static let chartGrid: Double = 0.18
            static let chartMajor: Double = 0.20
            static let chartMedium: Double = 0.15
            static let chartMinor: Double = 0.12
            static let chartFaint: Double = 0.07
            static let chartAxis: Double = 0.35
            static let chartLabelY: Double = 0.70
            static let chartLabelYSoft: Double = 0.65
            static let chartLabelX: Double = 0.80
            static let chartCaptionX: Double = 0.78
            static let separatorFaint: Double = 0.12
            static let chromeBorder: Double = 0.35
            static let formDeep: Double = 0.03
            static let formMuted: Double = 0.06
            static let formMid: Double = 0.05
            static let formDeepNeon: Double = 0.04
            static let analyticsAuxiliaryRowNeon: Double = 0.06
            /// 操作無効・グレーアウト時の白文字
            static let disabled: Double = 0.6
            /// シート冒頭説明など
            static let sheetIntro: Double = 0.88
            static let footnoteOnSheet: Double = 0.72
            static let supportingLabel: Double = 0.62
            static let metaHint: Double = 0.58
            /// 数値パッド周りの枠
            static let strokeInputWell: Double = 0.18
            /// 大当たり履歴チャートの虹時アクセント線
            static let winHistoryAccentStroke: Double = 0.92
            /// 連チャンカードの副題（虹背景時）
            static let rainbowSubtitle: Double = 0.82
            /// ボーダーメーター
            static let borderMeterTrack: Double = 0.08
            static let borderMeterTrackBorder: Double = 0.22
            static let borderMeterCenterLine: Double = 0.5
            static let borderMeterTickStrong: Double = 0.45
            static let borderMeterTickWeak: Double = 0.25
            static let borderMeterMarkerHalo: Double = 0.4
            static let borderMeterMuted: Double = 0.55
            static let chartBarBaseline: Double = 0.18
            /// 実戦ヘッダー等の副次ラベル（`AppDesignSystem`）
            static let playSecondaryText: Double = 0.75
            /// 実戦ヘッダーの静音アイコン
            static let playMutedGlyph: Double = 0.35
        }

        enum BlackOverlay {
            static let shadowLight: Double = 0.20
            static let shadowMedium: Double = 0.36
            static let shadowCard: Double = 0.55
            static let shadowCompact: Double = 0.70
            static let splashDepthStrong: Double = 0.50
            static let splashDepthWeak: Double = 0.40
            static let navigationBar: Double = 0.94
            static let navigationBarNeon: Double = 0.97
            static let bottomToolbar: Double = 0.55
            static let bottomToolbarNeon: Double = 0.72
            static let auxiliaryRow: Double = 0.85
            static let datePill: Double = 0.58
            static let chromeBackdrop: Double = 0.92
            static let chromeBackdropNeon: Double = 0.94
            static let sheetNearOpaque: Double = 0.97
            static let playSheetBackdrop: Double = 0.97
            static let playToolbarBackground: Double = 0.95
            static let playIntegerPadWell: Double = 0.35
            /// 実戦ログパネル面（`AppDesignSystem`）
            static let playLogPanelFill: Double = 0.93
        }

        /// 設定タブのセグメント・行・区切り
        enum Settings {
            static let segmentInactiveCapsule: Double = 0.28
            static let listRowWash: Double = 0.12
            static let listRowWashElevated: Double = 0.18
            static let listRowWashSoft: Double = 0.14
            static let divider: Double = 0.15
        }

        /// 履歴・管理のフィルタ_capsule・パネル
        enum History {
            static let filterCapsuleFill: Double = 0.58
            static let filterCapsuleStroke: Double = 0.15
            static let panelScrim: Double = 0.55
        }

        /// 省電力オーバーレイ
        enum PowerSaving {
            static let dialogScrim: Double = 0.85
            static let surroundingDim: Double = 0.2
        }

        /// セッション編集フォーム行
        enum SessionEditor {
            static let fieldChrome: Double = 0.12
            static let rowWash: Double = 0.06
        }

        /// 精算シート
        enum Settlement {
            static let auxiliaryWash: Double = 0.06
            static let divider: Double = 0.2
        }

        /// アップグレード訴求ハーフシート
        enum Monetization {
            static let teaserRowWash: Double = 0.14
        }

        /// スライドレール・スワイプヒントの白膜（進捗連動は係数トークンで表現）
        enum Interaction {
            enum BigHitRail {
                static let trackBandHigh: Double = 0.12
                static let trackBandLow: Double = 0.08
                static let accentInTrack: Double = 0.06
                static let progressWhiteStartBase: Double = 0.08
                static let progressWhiteStartScale: Double = 0.38
                static let progressWhiteEndBase: Double = 0.04
                static let progressWhiteEndScale: Double = 0.28
                static let strokeWhiteBase: Double = 0.45
                static let strokeWhiteScale: Double = 0.25
                static let strokeAccentBase: Double = 0.25
                static let strokeAccentScale: Double = 0.2
                static let thumbHighlight: Double = 0.94
                static let thumbMid: Double = 0.7
                static let thumbRim: Double = 0.75
            }
            enum SwipeHintHairline {
                static let clear: Double = 0
                static let stop02: Double = 0.04
                static let stop035: Double = 0.11
                static let stop05: Double = 0.06
                static let stop065: Double = 0.12
                static let stop08: Double = 0.03
            }
        }

        /// アクセント色を薄く塗る（実戦ボタン等）
        enum AccentTint {
            static let subtleFill: Double = 0.28
            static let rushWash: Double = 0.20
            static let rushStroke: Double = 0.45
            static let listSelectionGlow: Double = 0.30
            static let splashTitleGlow: Double = 0.50
            static let warningPanelBackground: Double = 0.18
            static let chromeTintMid: Double = 0.42
            static let primarySheetButtonStroke: Double = 0.55
        }

        /// 実戦 `PlayView` のクロム・メーター演出
        enum Play {
            enum GlassChrome {
                static let rimOpacityBase: Double = 0.93
                static let whiteHighlightMix: Double = 0.5
                /// `tint.opacity(o * rimTintMix)` 用（枠グラデの中間）
                static let rimTintMix: Double = 0.35
                static let whiteRimLowMix: Double = 0.1
                static let rimLit: Double = 0.38
                static let rimDim: Double = 0.1
            }
            enum ButtonMetal {
                static let radialGrayMid: Double = 0.74
                static let radialGrayEdge: Double = 0.88
            }
            enum BorderGauge {
                static let axisLabelOpacity: Double = 0.9
                static let untrustedHintOpacity: Double = 0.85
            }
        }
    }

    enum Thickness {
        static let hairline: CGFloat = 1
        static let borderNeonSkin: CGFloat = 2
        static let borderMeterTrackStroke: CGFloat = 1
        static let borderMeterTickMajor: CGFloat = 1.2
        static let borderMeterTickMinor: CGFloat = 0.8
        static let borderMeterMarkerOutline: CGFloat = 0.8
        static let primarySheetButtonStroke: CGFloat = 1.2
        static let bigHitRailThumbRim: CGFloat = 1.1
    }

    enum Elevation {
        static let shadowRadiusCard: CGFloat = 5
        static let shadowYCard: CGFloat = 3
        static let shadowRadiusInteractive: CGFloat = 5
        static let shadowRadiusPressed: CGFloat = 2.5
        static let shadowYPressed: CGFloat = 1.5
        static let shadowRadiusListSelection: CGFloat = 10
        static let shadowRadiusCompactLabel: CGFloat = 2
        static let shadowYCompactLabel: CGFloat = 1
        static let shadowRadiusRail: CGFloat = 6
        static let shadowYRail: CGFloat = 4
        static let shadowRadiusSplashTitle: CGFloat = 6
        static let shadowRadiusSplashSubtitle: CGFloat = 1
        static let shadowYSplashDepth: CGFloat = 1
        static let swipeHintRadiusStandard: CGFloat = 4
        static let swipeHintRadiusNeon: CGFloat = 8
        static let swipeHintInkWashRadius: CGFloat = 14
        static let swipeHintInkWashTrailingRadius: CGFloat = 13
        static let shadowRadiusNeonCard: CGFloat = 8
        static let shadowYNeonCard: CGFloat = 3
        static let shadowRadiusNeonInteractive: CGFloat = 6
        static let shadowYNeonInteractive: CGFloat = 2
        static let shadowRadiusNeonPressed: CGFloat = 3
        static let shadowYNeonPressed: CGFloat = 1
        static let shadowRadiusNeonRail: CGFloat = 8
        static let shadowYNeonRail: CGFloat = 4
        static let shadowRadiusNeonSplash: CGFloat = 8
    }

    /// レイアウト寸法（角丸・余白の直書き削減）
    enum Layout {
        static let cornerRadiusStandard: CGFloat = 12
        static let cornerRadiusCard: CGFloat = 14
        static let cornerRadiusControl: CGFloat = 10
        static let cornerRadiusSmall: CGFloat = 8
        static let paddingXS: CGFloat = 4
        static let paddingS: CGFloat = 8
        static let paddingM: CGFloat = 16
        static let paddingL: CGFloat = 20
    }

    /// 広告枠（バナー・ネイティブ）の下地・ラベル階調
    enum AdChrome {
        static let bannerBackdropR: Double = Glass.dockBackgroundTopR
        static let bannerBackdropG: Double = Glass.dockBackgroundTopG
        static let bannerBackdropB: Double = Glass.dockBackgroundTopB
        static let bannerBackdropOpacity: Double = 0.96
        static let borderOpacity: Double = Surface.WhiteOnDark.chromeBorder
        static let disclosureLabelOpacity: Double = Surface.WhiteOnDark.captionOnPanel
        static let nativeCardBackgroundOpacity: Double = 0.95
    }

    enum Opacity {
        /// リスト行・インサイト等（壁紙上でも読みやすく）
        static let rowBackground: Double = 0.88
        /// カード・パネル全般
        static let cardBackground: Double = 0.90
        static let rushBackground: Double = 0.12
        static let normalBackground: Double = 0.12
        static let rushStroke: Double = 0.4
        static let normalStroke: Double = 0.4
        static let rushTitle: Double = 0.95
        static let normalTitle: Double = 0.95
        /// ストロークグラデーション（上〜下）
        static let strokeGradientTop: Double = 0.45
        static let strokeGradientMid: Double = 0.18
        static let strokeGradientBottom: Double = 0.1
        /// 主パネル上の二次面（白の薄いオーバーレイ）
        static let panelSecondaryOverlay: Double = Surface.WhiteOnDark.medium
        /// 入力欄・フォーム行の下地
        static let inputFieldOverlay: Double = Surface.WhiteOnDark.mediumLow
        /// 二次面より一段明るい帯（フォーム内の区画など）
        static let panelElevatedOverlay: Double = Surface.WhiteOnDark.elevated
    }

    enum Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 16
        static let lg: CGFloat = 24
        static let xl: CGFloat = 32
    }

    /// アダプティブバナー帯とタブドックのあいだ（ドック側の装飾・滲みで広告が欠けて見えないようにする）
    enum AdaptiveBannerChrome {
        static let gapAboveTabDock: CGFloat = 2
    }

    enum CornerRadius {
        static let card: CGFloat = 12
        static let panel: CGFloat = 14
        static let button: CGFloat = 16
    }

    // MARK: - 共有カード画像（`SessionShareTemplates` / `SharePalette`）

    /// エクスポート用テンプレート専用。アプリ内 `ApplicationTheme` とは独立した数値トークン。
    enum ShareCard {
        // simple 背景グラデ終端
        static let simpleGradientEndR: Double = 0.96
        static let simpleGradientEndG: Double = 0.97
        static let simpleGradientEndB: Double = 0.99

        // 収支ハイライト（カード用）
        static let profitGoldStrongR: Double = 0.98
        static let profitGoldStrongG: Double = 0.84
        static let profitGoldStrongB: Double = 0.28
        static let profitSkyR: Double = 0.30
        static let profitSkyG: Double = 0.74
        static let profitSkyB: Double = 1.00
        static let profitLossR: Double = 1.00
        static let profitLossG: Double = 0.30
        static let profitLossB: Double = 0.30

        // simple: ボーダー差プラス／マイナス
        static let borderDiffPositiveSimpleR: Double = 0.10
        static let borderDiffPositiveSimpleG: Double = 0.50
        static let borderDiffPositiveSimpleB: Double = 0.90
        static let borderDiffPositiveDarkR: Double = 0.38
        static let borderDiffPositiveDarkG: Double = 0.95
        static let borderDiffPositiveDarkB: Double = 0.70
        static let borderDiffNegativeCoralR: Double = 1.00
        static let borderDiffNegativeCoralG: Double = 0.42
        static let borderDiffNegativeCoralB: Double = 0.42

        // simple 大きい収支ボックス
        static let simpleBigProfitR: Double = 0.05
        static let simpleBigProfitG: Double = 0.35
        static let simpleBigProfitB: Double = 0.90
        static let simpleBigLossR: Double = 0.90
        static let simpleBigLossG: Double = 0.10
        static let simpleBigLossB: Double = 0.10

        // keiji 背景 3-stop
        static let keijiBgDeepR: Double = 0.32
        static let keijiBgDeepG: Double = 0.02
        static let keijiBgDeepB: Double = 0.06
        static let keijiBgPaperR: Double = 0.92
        static let keijiBgPaperG: Double = 0.92
        static let keijiBgPaperB: Double = 0.90
        static let keijiBgShadowR: Double = 0.20
        static let keijiBgShadowG: Double = 0.02
        static let keijiBgShadowB: Double = 0.05

        // keiji 枠・金
        static let keijiBorderGoldR: Double = 0.98
        static let keijiBorderGoldG: Double = 0.86
        static let keijiBorderGoldB: Double = 0.35
        static let keijiProfitGoldR: Double = 0.88
        static let keijiProfitGoldG: Double = 0.72
        static let keijiProfitGoldB: Double = 0.22
        static let keijiProfitLossR: Double = 0.75
        static let keijiProfitLossG: Double = 0.10
        static let keijiProfitLossB: Double = 0.10

        // keiji 桜・金箔
        static let keijiSakuraR: Double = 1.0
        static let keijiSakuraG: Double = 0.75
        static let keijiSakuraB: Double = 0.88
        static let keijiFoil1R: Double = 1.0
        static let keijiFoil1G: Double = 0.88
        static let keijiFoil1B: Double = 0.35
        static let keijiFoil2R: Double = 0.95
        static let keijiFoil2G: Double = 0.70
        static let keijiFoil2B: Double = 0.18
        static let keijiFoil3R: Double = 1.0
        static let keijiFoil3G: Double = 0.92
        static let keijiFoil3B: Double = 0.55

        // eva 背景中間
        static let evaBgMidR: Double = 0.02
        static let evaBgMidG: Double = 0.06
        static let evaBgMidB: Double = 0.16

        // eva 枠
        static let evaBorderMagentaR: Double = 0.75
        static let evaBorderMagentaG: Double = 0.25
        static let evaBorderMagentaB: Double = 1.0
        static let evaBorderGreenR: Double = 0.35
        static let evaBorderGreenG: Double = 1.0
        static let evaBorderGreenB: Double = 0.55

        // eva 回路・ネオン
        static let evaTraceCyanR: Double = 0.45
        static let evaTraceCyanG: Double = 0.90
        static let evaTraceCyanB: Double = 1.00
        static let evaTraceBlueR: Double = 0.20
        static let evaTraceBlueG: Double = 0.65
        static let evaTraceBlueB: Double = 1.00
        static let evaTraceYellowR: Double = 1.00
        static let evaTraceYellowG: Double = 0.90
        static let evaTraceYellowB: Double = 0.25

        static let evaNeonPurpleR: Double = 0.75
        static let evaNeonPurpleG: Double = 0.25
        static let evaNeonPurpleB: Double = 1.0
        static let evaNeonGreenR: Double = 0.35
        static let evaNeonGreenG: Double = 1.0
        static let evaNeonGreenB: Double = 0.55

        // eva 収支グロー
        static let evaGlowPositiveR: Double = 0.35
        static let evaGlowPositiveG: Double = 0.95
        static let evaGlowPositiveB: Double = 1.0
        static let evaGlowNegativeR: Double = 1.0
        static let evaGlowNegativeG: Double = 0.42
        static let evaGlowNegativeB: Double = 0.42

        // MARK: テンプレ前景・クロム（白／黒のスクリム。`SessionShareTemplates` / Composer）

        enum TemplateForeground {
            static let simplePrimary: Double = 0.92
            static let decoratedPrimary: Double = 0.95
            static let simpleSecondary: Double = 0.62
            static let decoratedSecondary: Double = 0.72
            static let simplePanelBody: Double = 0.72
            static let decoratedPanelBody: Double = 0.55
            static let simpleInnerStroke: Double = 0.10
            static let decoratedInnerStroke: Double = 0.12
            static let simpleLogoCircle: Double = 0.06
            static let decoratedLogoCircle: Double = 0.12
            static let profitNeutralOnLight: Double = 0.9
        }

        enum TemplateChrome {
            static let simpleRadialVignette: Double = 0.06
            static let rocketWatermarkSimple: Double = 0.08
            static let rocketWatermarkDecorated: Double = 0.08
            static let sparklesGlyph: Double = 0.08
            static let outerBorderDarkStrong: Double = 0.16
            static let outerBorderDarkSoft: Double = 0.06
            static let statPanelBackdrop: Double = 0.55
            static let statPanelStroke: Double = 0.12
            static let keijiBorderSecondaryWhite: Double = 0.12
            static let evaTraceWhiteMix: Double = 0.22
        }

        enum ComposerChrome {
            static let toolbarScrim: Double = 0.6
            static let previewBackdrop: Double = 0.55
            static let previewStroke: Double = 0.12
        }
    }

    /// 実戦ヘッダーとトップバナーの位置・余白（`PlayView`）
    enum PlayLayout {
        /// `headerRow` の `.padding(.vertical)` 片側。実高には上下で 2 倍して加算する。
        static let headerRowVerticalPadding: CGFloat = 6
        /// ヘッダーブロック下端〜バナー上端の余白
        static let marginBelowHeaderBeforeBanner: CGFloat = 10
        /// バナー非表示時、ヘッダー直下〜メインカラムまでの間隔
        static let spacerBelowHeaderNoAds: CGFloat = 8
        /// インサイトドロワーがこのオフセットを超えたらバナーを畳む（誤タッチ・ちらつき防止の閾値）
        static let insightDrawerOpenThresholdForAdSuppression: CGFloat = 16
        /// 入力・インサイト表示時のバナー opacity 切り替え（秒）
        static let bannerFocusCrossfadeSeconds: Double = 0.25
    }

    /// 実戦スワイプヒントバーなど、端末 UI 用の固定トークン
    enum PlaySessionChrome {
        static let swipeHintBarStainlessR: Double = 0.22
        static let swipeHintBarStainlessG: Double = 0.23
        static let swipeHintBarStainlessB: Double = 0.25
        /// `PlaySwipeHintEdgeGlowStyle.inkWash` 用の墨色（縁のにじみ）
        static let swipeHintInkWashR: Double = 0.18
        static let swipeHintInkWashG: Double = 0.16
        static let swipeHintInkWashB: Double = 0.15
        /// 右縁用：わずかに朱寄りの墨（`PlaySwipeHintEdgeGlowStyle.inkWash`）
        static let swipeHintInkWashTrailingR: Double = 0.24
        static let swipeHintInkWashTrailingG: Double = 0.13
        static let swipeHintInkWashTrailingB: Double = 0.11
    }

    // MARK: - セマンティック（勝敗・投資回収・期待値）

    /// 既定スキン用。`NeonCyber` 専用の投資／回収は `Semantic.NeonCyber`。
    enum Semantic {
        enum Standard {
            static let winR: Double = 0.30
            static let winG: Double = 0.74
            static let winB: Double = 1.00
            static let winStrongR: Double = 0.98
            static let winStrongG: Double = 0.84
            static let winStrongB: Double = 0.28
            static let lossR: Double = 1.00
            static let lossG: Double = 0.30
            static let lossB: Double = 0.30
            static let expectationR: Double = 0.38
            static let expectationG: Double = 0.95
            static let expectationB: Double = 0.70
            static let investmentR: Double = 1.0
            static let investmentG: Double = 0.35
            static let investmentB: Double = 0.32
            /// `winStrong` と同一（回収・プラス方向の強調）
            static let recoveryR: Double = winStrongR
            static let recoveryG: Double = winStrongG
            static let recoveryB: Double = winStrongB
            /// チャート「期待値」等（旧 `Color.orange` に相当する sRGB）
            static let theoreticalAccentR: Double = 1.0
            static let theoreticalAccentG: Double = 0.5843137254901961
            static let theoreticalAccentB: Double = 0.0
            /// 強調シアン（旧 `Color.cyan`）
            static let highlightAccentR: Double = 0.0
            static let highlightAccentG: Double = 1.0
            static let highlightAccentB: Double = 1.0
        }

        /// ネオンサイバースキン用の投資／回収（色相をやや変える）
        enum NeonCyber {
            static let investmentR: Double = 1.0
            static let investmentG: Double = 0.42
            static let investmentB: Double = 0.38
            static let recoveryR: Double = 1.0
            static let recoveryG: Double = 0.82
            static let recoveryB: Double = 0.35
            /// 分析チャートの理論値線（ネオンではアンバー寄り）
            static let theoreticalChartR: Double = 1.0
            static let theoreticalChartG: Double = 0.82
            static let theoreticalChartB: Double = 0.35
        }
    }

    // MARK: - ホーム UI（インフォパネル等）

    enum Home {
        /// 広告バナー表示時のホーム統合パネル縦スロット。バナー・ボタン列の縦バランス用（ボタン最小高は `HomeMainColumnLayout` 側）。
        enum IntegratedPanelSlotWithBanner {
            static let maxHeight: CGFloat = 248
            static let minHeight: CGFloat = 152
            /// `contentBodyH` に対する比率（その後 min/max でクランプ）
            static let heightFractionOfContentBody: CGFloat = 0.22
        }

        /// 余剰・上昇コピーなどのポジティブ（ミント緑）
        static let statusPositiveR: Double = 0.35
        static let statusPositiveG: Double = 0.92
        static let statusPositiveB: Double = 0.55
        /// 星取りの負けマーカーなど（ロスをピンクで区別）
        static let statusLossAccentR: Double = 0.95
        static let statusLossAccentG: Double = 0.30
        static let statusLossAccentB: Double = 0.50
        /// 欠損・注意コピー（オレンジ系、`Color.orange` に近い固定 sRGB）
        static let statusWarningR: Double = 1.0
        static let statusWarningG: Double = 0.58
        static let statusWarningB: Double = 0.0
    }

    // MARK: - システム・起動・ウィンドウ根

    enum System {
        /// ブートストラップ／起動終端の iOS 風ダークグレー（28/255）
        static let rootBackgroundR: Double = 28 / 255
        static let rootBackgroundG: Double = 28 / 255
        static let rootBackgroundB: Double = 30 / 255
        /// 設定テーマ `AppTheme` のベース（極暗ネイビー）
        static let appChromeBackgroundR: Double = 0.02
        static let appChromeBackgroundG: Double = 0.02
        static let appChromeBackgroundB: Double = 0.05
    }

    // MARK: - ネイティブ広告 UIKit ブリッジ

    enum NativeAd {
        static let ctaForegroundR: Double = 0.25
        static let ctaForegroundG: Double = 0.85
        static let ctaForegroundB: Double = 0.95
        /// リスト用ネイティブ内 `GADMediaView` の高さ。120pt だと動画クリエイティブで「mediaView is too small for video」になりやすい。
        static let listCardMediaHeight: CGFloat = 180
        /// `OptionalNativeAdCardSlot` の SwiftUI 側最小高さ（メディア枠拡大に合わせる）
        static let listCardSlotMinHeight: CGFloat = 260
    }

    // MARK: - ホーム背景オーブ（`HomeView` / `StaticHomeBackgroundView` 共通）

    enum HomeBackground {
        static let orbPrimaryR: Double = 0.5
        static let orbPrimaryG: Double = 0.2
        static let orbPrimaryB: Double = 0.9
        static let orbSecondaryR: Double = 0.9
        static let orbSecondaryG: Double = 0.2
        static let orbSecondaryB: Double = 0.5
    }

    // MARK: - グラス UI（`AppGlassStyle`）

    enum Glass {
        static let dockInactiveTintR: Double = 0.6
        static let dockInactiveTintG: Double = 0.6
        static let dockInactiveTintB: Double = 0.6
        static let dockBackgroundTopR: Double = 0.11
        static let dockBackgroundTopG: Double = 0.12
        static let dockBackgroundTopB: Double = 0.14
        static let dockBackgroundBottomR: Double = 0.035
        static let dockBackgroundBottomG: Double = 0.036
        static let dockBackgroundBottomB: Double = 0.042
    }

    // MARK: - ネオンサイバースキン（`NeonCyberTheme`）

    enum NeonCyber {
        static let accentMagentaR: Double = 191 / 255
        static let accentMagentaG: Double = 0
        static let accentMagentaB: Double = 1
        static let cyanNeonR: Double = 0
        static let cyanNeonG: Double = 1
        static let cyanNeonB: Double = 1
        static let mainTextR: Double = 0.94
        static let mainTextG: Double = 0.96
        static let mainTextB: Double = 1
        static let subTextR: Double = 0.55
        static let subTextG: Double = 0.48
        static let subTextB: Double = 0.82
    }
}

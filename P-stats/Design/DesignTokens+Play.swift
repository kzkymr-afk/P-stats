import SwiftUI

// MARK: - 実戦・大当たり演出（数値は `DesignTokens.Play`、見た目は `DesignTokens.PlayCelebration`）

extension DesignTokens {
    /// 大当たり連チャン演出などの生数値（`PlayCelebration` が `Color` を組み立てる）
    enum Play {
        /// 虹バンド（コーラル〜バイオレット）
        enum RainbowBand {
            static let coralR: Double = 0.98
            static let coralG: Double = 0.32
            static let coralB: Double = 0.38
            static let amberR: Double = 1.0
            static let amberG: Double = 0.72
            static let amberB: Double = 0.18
            static let mintR: Double = 0.42
            static let mintG: Double = 0.95
            static let mintB: Double = 0.48
            static let skyR: Double = 0.32
            static let skyG: Double = 0.72
            static let skyB: Double = 1.0
            static let violetR: Double = 0.82
            static let violetG: Double = 0.42
            static let violetB: Double = 1.0
        }

        /// 虹オーバーレイ各ストップの不透明度（`RainbowBand` と同じ並び＋先頭コーラルの繰り返し）
        enum RainbowAtmosphereOpacity {
            static let coral1: Double = 0.28
            static let amber: Double = 0.24
            static let mint: Double = 0.22
            static let sky: Double = 0.26
            static let violet: Double = 0.24
            static let coral2: Double = 0.26
        }

        /// 連チャン 5〜9：金系オーバーレイ
        enum JackpotAtmosphere {
            static let brightR: Double = 1.0
            static let brightG: Double = 0.78
            static let brightB: Double = 0.22
            static let brightO: Double = 0.34
            static let midR: Double = 0.92
            static let midG: Double = 0.62
            static let midB: Double = 0.08
            static let midO: Double = 0.22
            static let deepR: Double = 0.55
            static let deepG: Double = 0.38
            static let deepB: Double = 0.06
            static let deepO: Double = 0.12
        }

        /// 初当たり〜1：青系オーバーレイ
        enum FirstHitAtmosphere {
            static let topR: Double = 0.35
            static let topG: Double = 0.58
            static let topB: Double = 0.96
            static let topO: Double = 0.4
            static let midR: Double = 0.22
            static let midG: Double = 0.45
            static let midB: Double = 0.88
            static let midO: Double = 0.24
            static let deepR: Double = 0.15
            static let deepG: Double = 0.35
            static let deepB: Double = 0.72
            static let deepO: Double = 0.14
        }

        /// 連チャン段階別の単色（テーマの RUSH 色と組み合わせる）
        enum ChainPrimary {
            static let blueR: Double = 0.45
            static let blueG: Double = 0.72
            static let blueB: Double = 0.98
            static let goldR: Double = 1.0
            static let goldG: Double = 0.78
            static let goldB: Double = 0.22
            static let rainbowVioletR: Double = 0.85
            static let rainbowVioletG: Double = 0.45
            static let rainbowVioletB: Double = 0.98
            static let lineTintRainbowR: Double = 0.75
            static let lineTintRainbowG: Double = 0.4
            static let lineTintRainbowB: Double = 0.95
        }

        /// 大当たり終了シートの強調色
        enum BigHitExit {
            static let abandonBackgroundR: Double = 0.52
            static let abandonBackgroundG: Double = 0.14
            static let abandonBackgroundB: Double = 0.16
            static let requiredLabelR: Double = 1.0
            static let requiredLabelG: Double = 0.38
            static let requiredLabelB: Double = 0.38
        }

        /// ボーダーメーター三角マーカー（diff を [-5,5] にクランプして補間）
        enum BorderMeterMarker {
            static let diffMin: Double = -5
            static let diffMax: Double = 5
            static let negativeRed: Double = 1
            static let negativeGreen: Double = 0.25
            static let negativeBlue: Double = 0.25
            static let neutralRed: Double = 1
            static let neutralGreen: Double = 1
            static let neutralBlue: Double = 1
            static let positiveRed: Double = 0.2
            static let positiveGreen: Double = 0.5
            static let positiveBlue: Double = 1
        }
    }

    /// 実戦 `PlayView` 大当たり演出用の組み立て済み `Color` / グラデーション
    struct PlayCelebration {
        private static func rgb(_ r: Double, _ g: Double, _ b: Double) -> SwiftUI.Color {
            SwiftUI.Color(red: r, green: g, blue: b)
        }

        private static let R = Play.RainbowBand.self
        private static let RA = Play.RainbowAtmosphereOpacity.self

        /// 枠線・全面グラデなど：コーラルで閉じる 6 ストップ
        static var rainbowColors: [SwiftUI.Color] {
            [
                rgb(R.coralR, R.coralG, R.coralB),
                rgb(R.amberR, R.amberG, R.amberB),
                rgb(R.mintR, R.mintG, R.mintB),
                rgb(R.skyR, R.skyG, R.skyB),
                rgb(R.violetR, R.violetG, R.violetB),
                rgb(R.coralR, R.coralG, R.coralB)
            ]
        }

        /// 文字のレインボー帯（5 ストップ）
        static var rainbowTextForegroundColors: [SwiftUI.Color] {
            [
                rgb(R.coralR, R.coralG, R.coralB),
                rgb(R.amberR, R.amberG, R.amberB),
                rgb(R.mintR, R.mintG, R.mintB),
                rgb(R.skyR, R.skyG, R.skyB),
                rgb(R.violetR, R.violetG, R.violetB)
            ]
        }

        static var rainbowForegroundGradient: SwiftUI.LinearGradient {
            SwiftUI.LinearGradient(colors: rainbowColors, startPoint: .leading, endPoint: .trailing)
        }

        static var rainbowTextForegroundGradient: SwiftUI.LinearGradient {
            SwiftUI.LinearGradient(colors: rainbowTextForegroundColors, startPoint: .leading, endPoint: .trailing)
        }

        /// 壁紙オーバーレイ（連チャン 10+）
        static var rainbowAtmosphereColors: [SwiftUI.Color] {
            [
                rgb(R.coralR, R.coralG, R.coralB).opacity(RA.coral1),
                rgb(R.amberR, R.amberG, R.amberB).opacity(RA.amber),
                rgb(R.mintR, R.mintG, R.mintB).opacity(RA.mint),
                rgb(R.skyR, R.skyG, R.skyB).opacity(RA.sky),
                rgb(R.violetR, R.violetG, R.violetB).opacity(RA.violet),
                rgb(R.coralR, R.coralG, R.coralB).opacity(RA.coral2)
            ]
        }

        private static let J = Play.JackpotAtmosphere.self

        /// 壁紙オーバーレイ（連チャン 5〜9）
        static var jackpotAtmosphereColors: [SwiftUI.Color] {
            [
                rgb(J.brightR, J.brightG, J.brightB).opacity(J.brightO),
                rgb(J.midR, J.midG, J.midB).opacity(J.midO),
                rgb(J.deepR, J.deepG, J.deepB).opacity(J.deepO)
            ]
        }

        private static let F = Play.FirstHitAtmosphere.self

        /// 壁紙オーバーレイ（初当たり〜1）
        static var firstHitAtmosphereColors: [SwiftUI.Color] {
            [
                rgb(F.topR, F.topG, F.topB).opacity(F.topO),
                rgb(F.midR, F.midG, F.midB).opacity(F.midO),
                rgb(F.deepR, F.deepG, F.deepB).opacity(F.deepO)
            ]
        }

        private static let C = Play.ChainPrimary.self

        static var chainPrimaryBlue: SwiftUI.Color { rgb(C.blueR, C.blueG, C.blueB) }
        static var chainPrimaryGold: SwiftUI.Color { rgb(C.goldR, C.goldG, C.goldB) }
        static var chainPrimaryRainbowViolet: SwiftUI.Color { rgb(C.rainbowVioletR, C.rainbowVioletG, C.rainbowVioletB) }
        static var lineTintRainbowRepresentative: SwiftUI.Color { rgb(C.lineTintRainbowR, C.lineTintRainbowG, C.lineTintRainbowB) }

        private static let X = Play.BigHitExit.self

        static var bigHitAbandonBackground: SwiftUI.Color {
            rgb(X.abandonBackgroundR, X.abandonBackgroundG, X.abandonBackgroundB)
        }

        static var bigHitRequiredLabel: SwiftUI.Color {
            rgb(X.requiredLabelR, X.requiredLabelG, X.requiredLabelB)
        }

        /// `BorderMeterView` マーカー（`snappedDiff` は事前に [-5,5] へクランプ済み想定）
        static func borderMeterMarkerColor(snappedDiff: Double) -> SwiftUI.Color {
            let M = Play.BorderMeterMarker.self
            let d = min(max(snappedDiff, M.diffMin), M.diffMax)
            if d <= 0 {
                let t = (d + 5) / 5
                let g = M.negativeGreen * (1 - t) + M.neutralGreen * t
                let b = M.negativeBlue * (1 - t) + M.neutralBlue * t
                return SwiftUI.Color(red: M.neutralRed, green: g, blue: b)
            } else {
                let t = d / 5
                let r = M.neutralRed * (1 - t) + M.positiveRed * t
                let g = M.neutralGreen * (1 - t) + M.positiveGreen * t
                let b = M.neutralBlue * (1 - t) + M.positiveBlue * t
                return SwiftUI.Color(red: r, green: g, blue: b)
            }
        }
    }
}

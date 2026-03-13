import SwiftUI
import SwiftData

// MARK: - あたりモード（Bonus Real-time Monitor）
/// ダークネイビー・水色ネオン・約定モニター風。1R純増をリアルタイム調整し、実効ボーダーを再計算。
struct BonusMonitorView: View {
    @Bindable var machine: Machine
    let ballsPer1000: Double   // 貸玉料金（1000ptあたりの玉数）
    let payoutCoefficient: Double   // 払出係数（pt/玉）
    let onFinish: (Double) -> Void
    @Environment(\.dismiss) private var dismiss

    private let step: Double = 1.0
    private let minNet: Double = 50
    private let maxNet: Double = 250

    /// メーカー公表ベースの1R純増（ゲージ100%の基準）
    private var makerDefaultNetPerRound: Double {
        machine.averageNetPerRound > 0 ? machine.averageNetPerRound : 140
    }

    @State private var currentNetPerRound: Double = 0

    /// 実効ボーダー（現在の1R純増ベース）。貸玉料金・交換率を考慮: prob × 貸玉料金/純増 × (4/交換率)
    private var effectiveBorder: Double {
        guard payoutCoefficient > 0, currentNetPerRound > 0, ballsPer1000 > 0 else { return 0 }
        let prob = machine.probabilityDenominator
        guard prob > 0 else { return 0 }
        return prob * ballsPer1000 / currentNetPerRound * (4.0 / payoutCoefficient)
    }

    /// 公表値に対する獲得期待度（0.5〜1.5 → ゲージ表示用）
    private var expectationRatio: Double {
        guard makerDefaultNetPerRound > 0 else { return 1.0 }
        return min(max(currentNetPerRound / makerDefaultNetPerRound, 0.5), 1.5)
    }

    private var accentColor: Color { AppGlassStyle.accent }
    private var backgroundColor: Color { AppGlassStyle.background }

    var body: some View {
        ZStack {
            backgroundColor.ignoresSafeArea()

            VStack(spacing: 0) {
                // ヘッダー: タイトル（集中モード）+ 終了
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("FOCUS")
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .tracking(2)
                            .foregroundColor(accentColor.opacity(0.9))
                        Text("集中モード（右打ち中）")
                            .font(.system(size: 10, weight: .medium, design: .default))
                            .foregroundColor(accentColor.opacity(0.6))
                    }
                    Spacer()
                    Button("終了") {
                        commitAndDismiss()
                    }
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundColor(accentColor)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(accentColor, lineWidth: 1))
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 8)

                // 実効ボーダー（隅に小さく）
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("EFF.BORDER")
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundColor(accentColor.opacity(0.6))
                        Text(effectiveBorder > 0 ? String(format: "%.1f", effectiveBorder) : "—")
                            .font(.system(size: 16, weight: .bold, design: .monospaced))
                            .foregroundColor(accentColor)
                    }
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 8)

                // 中央: 円形プログレス（公表値に対する獲得期待度）
                ZStack {
                    // ベース円
                    Circle()
                        .stroke(accentColor.opacity(0.15), lineWidth: 6)
                        .frame(width: 200, height: 200)
                    // プログレス（0.5=0%, 1.0=100%, 1.5=100%）
                    Circle()
                        .trim(from: 0, to: CGFloat(min(1, max(0, expectationRatio - 0.5))))
                        .stroke(accentColor, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                        .frame(width: 200, height: 200)
                        .rotationEffect(.degrees(-90))
                    VStack(spacing: 4) {
                        Text(String(format: "%.0f", currentNetPerRound))
                            .font(.system(size: 36, weight: .black, design: .monospaced))
                            .foregroundColor(accentColor)
                        Text("1R NET")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundColor(accentColor.opacity(0.7))
                        Text(String(format: "%.2f%%", expectationRatio * 100))
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundColor(accentColor.opacity(0.8))
                    }
                }
                .padding(.vertical, 24)

                // 1R純増スライダー（メタルデザイン）
                VStack(alignment: .leading, spacing: 6) {
                    Text("1R純増（玉）")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(accentColor.opacity(0.7))
                    MetalSlider(value: $currentNetPerRound, range: minNet...maxNet, style: MetalSliderStyle(trackHeight: 16, thumbSize: 40, trackCornerRadius: 8))
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 8)

                Spacer(minLength: 12)

                // 下半分: デュアルカウンター Loss (-1) | Gain (+1)
                HStack(spacing: 0) {
                    Button(action: applyLoss) {
                        ZStack {
                            AppGlassStyle.rushColor.opacity(0.15)
                            VStack(spacing: 6) {
                                Text("−1")
                                    .font(.system(size: 28, weight: .black, design: .monospaced))
                                    .foregroundColor(AppGlassStyle.rushColor.opacity(AppGlassStyle.rushTitleOpacity))
                                Text("LOSS")
                                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                                    .tracking(1)
                                    .foregroundColor(AppGlassStyle.rushColor.opacity(0.8))
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .overlay(RoundedRectangle(cornerRadius: 0).stroke(AppGlassStyle.rushColor.opacity(AppGlassStyle.rushStrokeOpacity), lineWidth: 1))
                    }
                    .buttonStyle(.plain)

                    Button(action: applyGain) {
                        ZStack {
                            Color(red: 0, green: 0.5, blue: 0.5).opacity(0.2)
                            VStack(spacing: 6) {
                                Text("+1")
                                    .font(.system(size: 28, weight: .black, design: .monospaced))
                                    .foregroundColor(accentColor)
                                Text("GAIN")
                                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                                    .tracking(1)
                                    .foregroundColor(accentColor.opacity(0.9))
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .overlay(RoundedRectangle(cornerRadius: 0).stroke(accentColor.opacity(0.5), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
                .frame(height: 220)
            }
        }
        .font(.system(size: 14, design: .monospaced))
        .onAppear {
            currentNetPerRound = machine.averageNetPerRound > 0 ? machine.averageNetPerRound : makerDefaultNetPerRound
            currentNetPerRound = min(max(currentNetPerRound, minNet), maxNet)
            UIApplication.shared.isIdleTimerDisabled = true
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
        }
    }

    private func applyLoss() {
        currentNetPerRound = max(minNet, currentNetPerRound - step)
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
    }

    private func applyGain() {
        currentNetPerRound = min(maxNet, currentNetPerRound + step)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func commitAndDismiss() {
        onFinish(currentNetPerRound)
        dismiss()
    }
}

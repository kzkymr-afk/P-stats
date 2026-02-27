import SwiftUI

// MARK: - Bonus Standby（待機モード）
/// 極限まで暗く、中央の円が呼吸するように明滅。入力をロック。ダブルタップで結果入力へ。
struct BonusStandbyOverlay: View {
    let onDoubleTap: () -> Void

    @State private var breathOpacity: Double = 0.25
    private let cyan = AppGlassStyle.accent

    var body: some View {
        ZStack {
            AppGlassStyle.background.opacity(0.96)
                .ignoresSafeArea()
                .onTapGesture(count: 2, perform: onDoubleTap)

            // 呼吸する円（ゆっくり明滅）。低電力モードではアニメーションなしでバッテリー節約
            Circle()
                .stroke(cyan.opacity(breathOpacity), lineWidth: 2)
                .frame(width: 72, height: 72)
                .onAppear {
                    if !ProcessInfo.processInfo.isLowPowerModeEnabled {
                        withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true)) {
                            breathOpacity = 0.08
                        }
                    } else {
                        breathOpacity = 0.2
                    }
                }
        }
        .allowsHitTesting(true)
    }
}

// MARK: - 結果入力（RESULT / 今回の回収）
/// Set Count と Total Gain のみ。銀行振込のような清潔なUI。完了後は期待値フィードバックでメンタルサポート。
struct ChainResultInputView: View {
    @Bindable var machine: Machine
    let ballsPer1000: Double   // 貸玉料金（1000円あたりの玉数）
    let exchangeRate: Double   // 交換率（円/玉）
    let totalRealCost: Double
    let normalRotations: Int
    let onDismiss: () -> Void

    @State private var setCountStr: String = ""
    @State private var totalGainStr: String = ""
    @State private var phase: Phase = .input
    @State private var theoreticalProfit: Int = 0
    @FocusState private var focusedField: Field?
    enum Field { case setCount, totalGain }
    enum Phase { case input, feedback }

    private let cyan = AppGlassStyle.accent

    var body: some View {
        ZStack {
            AppGlassStyle.background
                .ignoresSafeArea()

            if phase == .input {
                inputContent
            } else {
                feedbackContent
            }
        }
        .font(.system(size: 15, weight: .medium, design: .monospaced))
    }

    private var inputContent: some View {
        VStack(spacing: 28) {
            Text("RESULT")
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .tracking(2)
                .foregroundColor(cyan.opacity(0.9))
                .padding(.top, 24)

            VStack(alignment: .leading, spacing: 8) {
                Text("Set Count")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(cyan.opacity(0.7))
                TextField("", text: $setCountStr)
                    .keyboardType(.numberPad)
                    .textFieldStyle(.plain)
                    .padding(.vertical, 14)
                    .padding(.horizontal, 16)
                    .background(AppGlassStyle.rowBackground)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(cyan.opacity(0.4), lineWidth: 1))
                    .foregroundColor(.white)
                    .focused($focusedField, equals: .setCount)
            }
            .padding(.horizontal, 24)

            VStack(alignment: .leading, spacing: 8) {
                Text("Total Gain")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(cyan.opacity(0.7))
                TextField("", text: $totalGainStr)
                    .keyboardType(.numberPad)
                    .textFieldStyle(.plain)
                    .padding(.vertical, 14)
                    .padding(.horizontal, 16)
                    .background(AppGlassStyle.rowBackground)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(cyan.opacity(0.4), lineWidth: 1))
                    .foregroundColor(.white)
                    .focused($focusedField, equals: .totalGain)
            }
            .padding(.horizontal, 24)

            Button(action: submit) {
                Text("確定")
                    .font(.system(size: 15, weight: .semibold, design: .monospaced))
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(cyan)
            }
            .cornerRadius(10)
            .padding(.horizontal, 24)
            .padding(.top, 8)
            .disabled(setCountStr.isEmpty || totalGainStr.isEmpty)

            Spacer(minLength: 0)
        }
    }

    private var feedbackContent: some View {
        VStack(spacing: 24) {
            Spacer(minLength: 40)
            Text("今回の期待値（仕事量）")
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundColor(cyan.opacity(0.8))
            Text(theoreticalProfit >= 0 ? "+\(theoreticalProfit) 円" : "\(theoreticalProfit) 円")
                .font(.system(size: 42, weight: .bold, design: .monospaced))
                .foregroundColor(cyan)
            Text("収支は運、期待値は実力")
                .font(.system(size: 14, weight: .medium, design: .monospaced))
                .foregroundColor(cyan.opacity(0.6))
                .padding(.top, 8)
            Spacer(minLength: 0)
            Text("タップして SENSING に戻る")
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundColor(cyan.opacity(0.5))
                .padding(.bottom, 32)
        }
        .frame(maxWidth: .infinity)
        .onTapGesture {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            onDismiss()
        }
    }

    private func submit() {
        guard let sets = Int(setCountStr), sets > 0,
              let gain = Int(totalGainStr), gain >= 0 else { return }
        let rounds = machine.defaultRoundsPerHit
        let countPerRound = machine.countPerRound
        let totalRounds = sets * rounds
        guard totalRounds > 0 else { return }
        // 1Rあたりの実効純増 = (総獲得玉 / 総R数) - 打ち出し per R = (gain / totalRounds) - countPerRound
        let avgBallsPerRound = Double(gain) / Double(totalRounds)
        let effectiveNetPerRound = avgBallsPerRound - Double(countPerRound)
        let clamped = min(max(effectiveNetPerRound, 50), 250)
        machine.netPerRoundBase = clamped

        // 今回の期待値（仕事量）: 実質コスト × (現在回転率/新ボーダー - 1)。貸玉料金・交換率を考慮
        let rate = exchangeRate > 0 ? exchangeRate : 4.0
        let balls = ballsPer1000 > 0 ? ballsPer1000 : 250.0
        let prob = machine.probabilityDenominator
        guard prob > 0 else {
            theoreticalProfit = 0
            phase = .feedback
            return
        }
        let newBorder = prob * balls / clamped * (4.0 / rate)
        guard totalRealCost > 0, newBorder > 0, normalRotations >= 0 else {
            theoreticalProfit = 0
            phase = .feedback
            return
        }
        let currentRate = (Double(normalRotations) / totalRealCost) * 1000.0
        let ratio = currentRate / newBorder
        theoreticalProfit = Int(round(totalRealCost * (ratio - 1)))

        UINotificationFeedbackGenerator().notificationOccurred(.success)
        phase = .feedback
    }
}

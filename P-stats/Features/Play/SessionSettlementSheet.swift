import SwiftUI
import UIKit

/// 実戦保存直前：今回の獲得出玉と貯玉残の精算
struct SessionSettlementSheet: View {
    let recoveryBalls: Int
    /// 精算シート表示時点の店舗貯玉（`GameLog.selectedShop`）
    let chodamaBalanceBefore: Int
    let payoutCoefficient: Double
    let supportsChodama: Bool
    let onCancel: () -> Void
    let onConfirm: (SessionSettlementOutcome) -> Void

    @EnvironmentObject private var themeManager: ThemeManager
    @State private var step: Step = .main
    @State private var partialInputKind: PartialInputKind = .balls
    @State private var partialBallsText: String = ""
    @State private var partialPtText: String = ""
    @State private var partialPadTrigger = 0

    private var accent: Color { themeManager.currentTheme.accentColor }
    private var workingTotal: Int { max(0, chodamaBalanceBefore) + max(0, recoveryBalls) }

    private enum Step: Equatable {
        case main
        case partialExchange
        case fullExchangeConfirm
        case sessionWinningRemainder(ChodamaExchangeBreakdown)
        case poolFullRemainder(ChodamaExchangeBreakdown)
    }

    private enum PartialInputKind: String, CaseIterable {
        case balls = "玉数"
        case pt = "pt換算"
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppGlassStyle.background.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    Group {
                        switch step {
                        case .main:
                            mainMenu
                        case .partialExchange:
                            partialExchangeContent
                        case .fullExchangeConfirm:
                            fullExchangeConfirmContent
                        case .sessionWinningRemainder(let bd):
                            sessionRemainderContent(bd)
                        case .poolFullRemainder(let bd):
                            poolFullRemainderContent(bd)
                        }
                    }
                    .padding(16)
                    .padding(.bottom, 32)
                }
            }
            .navigationTitle("精算")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarBackground(Color.black, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .preferredColorScheme(.dark)
            .tint(accent)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(isAtRoot ? "閉じる" : "戻る") {
                        if isAtRoot {
                            onCancel()
                        } else {
                            goBack()
                        }
                    }
                    .foregroundStyle(accent)
                }
            }
            .onAppear {
                if partialBallsText.isEmpty { partialBallsText = "" }
            }
        }
    }

    private var isAtRoot: Bool {
        if case .main = step { return true }
        return false
    }

    private func goBack() {
        switch step {
        case .main:
            break
        case .partialExchange, .fullExchangeConfirm:
            step = .main
        case .sessionWinningRemainder, .poolFullRemainder:
            step = .main
        }
    }

    // MARK: - メイン

    private var mainMenu: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("この実戦の出玉は、今日の精算でどうしましたか？")
                    .font(.headline)
                    .foregroundStyle(.white)
                Text(summaryLine)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(DesignTokens.Surface.WhiteOnDark.sheetIntro))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .pstatsPanelStyle()

            if supportsChodama {
                settlementOptionRow(
                    title: "今回の獲得出玉を換金する",
                    subtitle: sessionExchangeSubtitle,
                    systemImage: "banknote.fill"
                ) {
                    let bd = ChodamaSettlement.exchangeBreakdown(balls: recoveryBalls, yenPerBall: payoutCoefficient)
                    if bd.remainderPt > 0 {
                        step = .sessionWinningRemainder(bd)
                    } else {
                        confirmSessionWinningExchange(remainderToChodama: true, breakdown: bd)
                    }
                }

                settlementOptionRow(
                    title: "貯玉の一部を換金する",
                    subtitle: "今回の出玉を含めた合計 \(workingTotal) 玉のうち、換金する量を入力します。",
                    systemImage: "circle.grid.2x2.fill"
                ) {
                    partialInputKind = .balls
                    partialBallsText = ""
                    partialPtText = ""
                    step = .partialExchange
                    partialPadTrigger += 1
                }

                settlementOptionRow(
                    title: "貯玉をすべて換金する",
                    subtitle: "店の貯玉 \(chodamaBalanceBefore) 玉 ＋ 今回 \(recoveryBalls) 玉 ＝ 合計 \(workingTotal) 玉を対象にします。",
                    systemImage: "tray.full.fill"
                ) {
                    step = .fullExchangeConfirm
                }

                settlementOptionRow(
                    title: "今回の獲得出玉を貯玉に預ける",
                    subtitle: "回収 \(recoveryBalls) 玉を店の貯玉残高に加算します。",
                    systemImage: "archivebox.fill"
                ) {
                    onConfirm(
                        SessionSettlementOutcome(
                            mode: .winningDepositChodama,
                            exchangeCashProceedsPt: 0,
                            chodamaBalanceDeltaBalls: recoveryBalls
                        )
                    )
                }
            } else {
                Text("この店舗は「貯玉サービス利用」がオフです。今回の獲得出玉の換金のみ記録できます（端数はアプリ上の貯玉に入れません）。")
                    .font(AppTypography.annotation)
                    .foregroundStyle(.white.opacity(DesignTokens.Surface.WhiteOnDark.footnoteOnSheet))
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.white.opacity(DesignTokens.Surface.Settlement.auxiliaryWash))
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                settlementOptionRow(
                    title: "今回の獲得出玉を換金する",
                    subtitle: sessionExchangeSubtitle,
                    systemImage: "banknote.fill"
                ) {
                    let bd = ChodamaSettlement.exchangeBreakdown(balls: recoveryBalls, yenPerBall: payoutCoefficient)
                    onConfirm(
                        SessionSettlementOutcome(
                            mode: .winningExchangeRemainderAbandon,
                            exchangeCashProceedsPt: bd.cashProceedsPt,
                            chodamaBalanceDeltaBalls: 0
                        )
                    )
                }
            }
        }
    }

    private var summaryLine: String {
        "今回の獲得出玉 \(recoveryBalls) 玉 · 精算前の貯玉 \(chodamaBalanceBefore) 玉 · 交換率 \(formatRate(payoutCoefficient)) pt/玉"
    }

    private var sessionBreakdown: ChodamaExchangeBreakdown {
        ChodamaSettlement.exchangeBreakdown(balls: recoveryBalls, yenPerBall: payoutCoefficient)
    }

    private var sessionExchangeSubtitle: String {
        let bd = sessionBreakdown
        if bd.cashProceedsPt > 0 {
            return "受け取り 約 \(bd.cashProceedsPt) pt（500pt 単位）。端数がある場合は次の画面で扱いを選びます。"
        }
        return "換金額が 500pt 未満のときは 0pt になります。端数の扱いは次の画面で選べます。"
    }

    // MARK: - 今回分換金・端数

    private func sessionRemainderContent(_ bd: ChodamaExchangeBreakdown) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("換金の端数の扱い")
                .font(.title3.weight(.bold))
                .foregroundStyle(.white)
            Text("500pt 刻みの換金で、端数 \(bd.remainderPt) pt（約 \(bd.remainderBalls) 玉分）が残ります。")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(DesignTokens.Surface.WhiteOnDark.sheetIntro))
                .fixedSize(horizontal: false, vertical: true)

            settlementOptionRow(
                title: "端数は貯玉に戻す",
                subtitle: "貯玉残高に \(bd.remainderBalls) 玉分を加算して記録します。",
                systemImage: "archivebox.fill"
            ) {
                confirmSessionWinningExchange(remainderToChodama: true, breakdown: bd)
            }

            settlementOptionRow(
                title: "端数は放棄する",
                subtitle: "換金 pt のみ記録し、端数は貯玉に入れません。",
                systemImage: "xmark.circle.fill"
            ) {
                confirmSessionWinningExchange(remainderToChodama: false, breakdown: bd)
            }
        }
    }

    private func confirmSessionWinningExchange(remainderToChodama: Bool, breakdown bd: ChodamaExchangeBreakdown) {
        let mode: SessionSettlementMode = remainderToChodama ? .winningExchangeRemainderChodama : .winningExchangeRemainderAbandon
        let delta = remainderToChodama ? bd.remainderBalls : 0
        onConfirm(
            SessionSettlementOutcome(
                mode: mode,
                exchangeCashProceedsPt: bd.cashProceedsPt,
                chodamaBalanceDeltaBalls: delta
            )
        )
    }

    // MARK: - 貯玉の一部換金

    private var partialExchangeContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("貯玉の一部を換金")
                .font(.title3.weight(.bold))
                .foregroundStyle(.white)
            Text("精算前貯玉 \(chodamaBalanceBefore) 玉 ＋ 今回 \(recoveryBalls) 玉 ＝ 合計 \(workingTotal) 玉まで指定できます。換金後、端数は自動的に貯玉に戻る前提で計算します。")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(DesignTokens.Surface.WhiteOnDark.sheetIntro))
                .fixedSize(horizontal: false, vertical: true)

            Picker("入力の種類", selection: $partialInputKind) {
                ForEach(PartialInputKind.allCases, id: \.self) { k in
                    Text(k.rawValue).tag(k)
                }
            }
            .pickerStyle(.segmented)

            if partialInputKind == .balls {
                Text("換金する玉数")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white.opacity(DesignTokens.Surface.WhiteOnDark.nearOpaqueLabel))
                IntegerPadTextField(
                    text: $partialBallsText,
                    placeholder: "1〜\(workingTotal)",
                    maxDigits: 9,
                    font: .systemFont(ofSize: 22, weight: .semibold),
                    textColor: .white,
                    accentColor: UIColor(accent),
                    focusTrigger: partialPadTrigger
                )
                .frame(maxWidth: .infinity, minHeight: 48)
                .padding(.horizontal, 12)
                .background(Color.white.opacity(DesignTokens.Surface.WhiteOnDark.formMuted))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            } else {
                Text("換金する玉の pt 換算（目安）")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white.opacity(DesignTokens.Surface.WhiteOnDark.nearOpaqueLabel))
                IntegerPadTextField(
                    text: $partialPtText,
                    placeholder: "pt",
                    maxDigits: 12,
                    font: .systemFont(ofSize: 22, weight: .semibold),
                    textColor: .white,
                    accentColor: UIColor(accent),
                    focusTrigger: partialPadTrigger
                )
                .frame(maxWidth: .infinity, minHeight: 48)
                .padding(.horizontal, 12)
                .background(Color.white.opacity(DesignTokens.Surface.WhiteOnDark.formMuted))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                Text("入力した pt から換金する玉数を概算します（四捨五入）。必要なら「玉数」に切り替えてください。")
                    .font(AppTypography.annotation)
                    .foregroundStyle(.white.opacity(DesignTokens.Surface.WhiteOnDark.footnoteOnSheet))
            }

            Button {
                applyPartialExchange()
            } label: {
                Text("換金を記録する")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .tint(accent)
            .disabled(!partialFormValid)
        }
    }

    private var partialFormValid: Bool {
        guard workingTotal > 0 else { return false }
        let u = resolvedPartialBallsToExchange
        return u != nil && u! >= 1 && u! <= workingTotal
    }

    private var resolvedPartialBallsToExchange: Int? {
        switch partialInputKind {
        case .balls:
            let t = partialBallsText.trimmingCharacters(in: .whitespaces)
            guard let v = Int(t), v > 0 else { return nil }
            return v
        case .pt:
            let t = partialPtText.trimmingCharacters(in: .whitespaces)
            guard let pt = Int(t), pt > 0, payoutCoefficient > 0 else { return nil }
            let balls = Int((Double(pt) / payoutCoefficient).rounded())
            return balls > 0 ? balls : nil
        }
    }

    private func applyPartialExchange() {
        guard let u = resolvedPartialBallsToExchange, u >= 1, u <= workingTotal else { return }
        let bd = ChodamaSettlement.exchangeBreakdown(balls: u, yenPerBall: payoutCoefficient)
        let delta = recoveryBalls - u + bd.remainderBalls
        onConfirm(
            SessionSettlementOutcome(
                mode: .chodamaPartialExchange,
                exchangeCashProceedsPt: bd.cashProceedsPt,
                chodamaBalanceDeltaBalls: delta
            )
        )
    }

    // MARK: - 貯玉すべて換金

    private var fullExchangeConfirmContent: some View {
        let bd = ChodamaSettlement.exchangeBreakdown(balls: workingTotal, yenPerBall: payoutCoefficient)
        return VStack(alignment: .leading, spacing: 16) {
            Text("貯玉をすべて換金")
                .font(.title3.weight(.bold))
                .foregroundStyle(.white)
            VStack(alignment: .leading, spacing: 6) {
                Text("対象: 合計 \(workingTotal) 玉")
                Text("pt 換算（目安）: 約 \(bd.totalRecoveryPt) pt")
                Text("換金（500pt 刻み）: 約 \(bd.cashProceedsPt) pt")
                if bd.remainderPt > 0 {
                    Text("端数: \(bd.remainderPt) pt（約 \(bd.remainderBalls) 玉分）")
                        .foregroundStyle(.orange.opacity(0.95))
                }
            }
            .font(.subheadline)
            .foregroundStyle(.white.opacity(DesignTokens.Surface.WhiteOnDark.sheetIntro))

            Button {
                if bd.remainderPt > 0 {
                    step = .poolFullRemainder(bd)
                } else {
                    confirmFullPoolExchange(remainderToChodama: true, breakdown: bd)
                }
            } label: {
                Text(bd.remainderPt > 0 ? "端数の扱いを選ぶ" : "換金を記録する")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .tint(accent)
        }
    }

    private func poolFullRemainderContent(_ bd: ChodamaExchangeBreakdown) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("すべて換金したあとの端数")
                .font(.title3.weight(.bold))
                .foregroundStyle(.white)
            Text("500pt 刻みの換金で、端数 \(bd.remainderPt) pt（約 \(bd.remainderBalls) 玉分）が残ります。")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(DesignTokens.Surface.WhiteOnDark.sheetIntro))
                .fixedSize(horizontal: false, vertical: true)

            settlementOptionRow(
                title: "端数は貯玉に戻す",
                subtitle: "最終的な貯玉残高は約 \(bd.remainderBalls) 玉として記録します。",
                systemImage: "archivebox.fill"
            ) {
                confirmFullPoolExchange(remainderToChodama: true, breakdown: bd)
            }

            settlementOptionRow(
                title: "端数は放棄する",
                subtitle: "換金 pt のみ記録し、貯玉残高は 0 に近い形で記録します。",
                systemImage: "xmark.circle.fill"
            ) {
                confirmFullPoolExchange(remainderToChodama: false, breakdown: bd)
            }
        }
    }

    private func confirmFullPoolExchange(remainderToChodama: Bool, breakdown bd: ChodamaExchangeBreakdown) {
        let u = workingTotal
        let rem = remainderToChodama ? bd.remainderBalls : 0
        let delta = recoveryBalls - u + rem
        onConfirm(
            SessionSettlementOutcome(
                mode: .chodamaFullExchange,
                exchangeCashProceedsPt: bd.cashProceedsPt,
                chodamaBalanceDeltaBalls: delta
            )
        )
    }

    // MARK: - 共通 UI

    private func settlementOptionRow(
        title: String,
        subtitle: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: systemImage)
                    .font(.title2)
                    .foregroundStyle(accent)
                    .frame(width: 36)
                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.white)
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(DesignTokens.Surface.WhiteOnDark.sheetIntro))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white.opacity(DesignTokens.Surface.WhiteOnDark.metaHint))
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .pstatsPanelStyle()
        }
        .buttonStyle(.plain)
    }

    private func formatRate(_ y: Double) -> String {
        if y == floor(y) { return String(format: "%.0f", y) }
        return String(format: "%.2f", y)
    }
}

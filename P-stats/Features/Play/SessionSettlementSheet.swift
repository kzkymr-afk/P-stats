import SwiftUI

/// 実戦保存直前：換金か貯玉かを選ばせるシート
struct SessionSettlementSheet: View {
    let recoveryBalls: Int
    let payoutCoefficient: Double
    let supportsChodama: Bool
    let onCancel: () -> Void
    let onConfirm: (SessionSettlementMode) -> Void

    @EnvironmentObject private var themeManager: ThemeManager
    private var accent: Color { themeManager.currentTheme.accentColor }
    private var breakdown: ChodamaExchangeBreakdown {
        ChodamaSettlement.exchangeBreakdown(balls: recoveryBalls, yenPerBall: payoutCoefficient)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppGlassStyle.background.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 16) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("回収 \(recoveryBalls) 玉")
                                .font(.title3.weight(.bold))
                                .foregroundStyle(.white)
                            Text("pt 換算　約 \(breakdown.totalRecoveryPt) pt（店の払出係数に基づく換金レート）")
                                .font(.subheadline)
                                .foregroundStyle(.white.opacity(0.85))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                        .pstatsPanelStyle()

                        if supportsChodama {
                            settlementButton(
                                title: "貯玉",
                                subtitle: "回収した玉をすべて店の貯玉残高に加算します。",
                                systemImage: "archivebox.fill"
                            ) {
                                onConfirm(.chodama)
                            }
                        } else {
                            Text("この店舗は「貯玉サービス利用」がオフです。店舗編集でオンにすると貯玉精算と端数の自動反映が使えます。")
                                .font(AppTypography.annotation)
                                .foregroundStyle(.white.opacity(0.7))
                                .padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.white.opacity(DesignTokens.Surface.Settlement.auxiliaryWash))
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }

                        Divider().background(themeManager.currentTheme.hairlineDividerColor)

                        settlementButton(
                            title: "換金",
                            subtitle: exchangeSubtitle,
                            systemImage: "banknote.fill"
                        ) {
                            onConfirm(.exchange)
                        }

                        if supportsChodama, breakdown.remainderPt > 0 {
                            Text("換金額は 500pt 刻みです。端数 \(breakdown.remainderPt) pt（約 \(breakdown.remainderBalls) 玉分）は貯玉残高へ加算します。")
                                .font(AppTypography.annotation)
                                .foregroundStyle(.white.opacity(0.72))
                                .fixedSize(horizontal: false, vertical: true)
                        } else if !supportsChodama, breakdown.remainderPt > 0 {
                            Text("換金額は 500pt 刻みです。端数は貯玉サービス未設定のため、アプリ上では残高に入れません。")
                                .font(AppTypography.annotation)
                                .foregroundStyle(.orange.opacity(0.9))
                                .fixedSize(horizontal: false, vertical: true)
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
                    Button("戻る") {
                        onCancel()
                    }
                    .foregroundStyle(accent)
                }
            }
        }
    }

    private var exchangeSubtitle: String {
        if breakdown.cashProceedsPt > 0 {
            return "受け取り 約 \(breakdown.cashProceedsPt) pt（500pt 単位）"
        }
        return "換金額が 500pt 未満のときは 0pt。端数は貯玉の扱いに従います。"
    }

    private func settlementButton(
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
                        .foregroundStyle(.white.opacity(0.85))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.45))
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .pstatsPanelStyle()
        }
        .buttonStyle(.plain)
    }
}

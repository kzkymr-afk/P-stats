import StoreKit
import SwiftUI

/// プレミアム（広告オフ＋分析フル）案内（ハーフシート）
struct AnalyticsUpgradeHalfSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var entitlements = EntitlementsStore.shared
    @ObservedObject private var analyticsTrial = RewardedAnalyticsTrialController.shared

    @State private var rewardedBusy = false
    @State private var rewardedMessage: String?

    private var cyan: Color { AppGlassStyle.accent }

    var body: some View {
        ZStack {
            AppGlassStyle.background.ignoresSafeArea()
            VStack(spacing: 20) {
                Image(systemName: "sparkles.rectangle.stack.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(cyan)
                Text("プレミアムでフル解放")
                    .font(.title3.weight(.bold))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                Text("広告を非表示にし、店舗・機種・メーカー別の分析・クロス分析・ヒートマップ・期間フィルタまですべて利用できます。")
                    .font(AppTypography.bodyRounded)
                    .foregroundColor(.white.opacity(0.82))
                    .multilineTextAlignment(.center)

                if entitlements.hasPurchasedPremium {
                    Label("プレミアムはご利用中です", systemImage: "checkmark.seal.fill")
                        .foregroundColor(cyan)
                } else {
                    if analyticsTrial.isTrialActive, let end = analyticsTrial.trialEndDate {
                        VStack(spacing: 6) {
                            Label("リワード試用中（プレミアム相当）", systemImage: "gift.fill")
                                .foregroundColor(cyan)
                            Text("有効期限: \(formatted(date: end)) まで")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.75))
                        }
                    }
                    if let product = entitlements.product(for: .premiumMonthly) {
                        Button {
                            Task { await entitlements.purchasePremium() }
                        } label: {
                            Text("今すぐ登録（\(product.displayPrice)）")
                                .fontWeight(.semibold)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .foregroundColor(.black)
                                .background(cyan)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }

                        if analyticsTrial.canOfferRewardToday() {
                            Button {
                                guard !rewardedBusy else { return }
                                rewardedBusy = true
                                rewardedMessage = nil
                                RewardedAdPresenter.presentForAnalyticsTrialReward { earned in
                                    rewardedBusy = false
                                    if earned {
                                        rewardedMessage = "24時間、広告オフと分析フルが使えます。"
                                    } else {
                                        rewardedMessage = "視聴が完了しなかったか、読み込みに失敗しました。"
                                    }
                                }
                            } label: {
                                HStack {
                                    if rewardedBusy {
                                        ProgressView().tint(cyan)
                                    }
                                    Text("動画広告を見て24時間試す（1日最大\(RewardedAnalyticsTrialController.maxRewardsPerCalendarDay)回）")
                                        .fontWeight(.semibold)
                                        .multilineTextAlignment(.center)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .foregroundColor(.white)
                                .background(Color.white.opacity(0.14))
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                            .disabled(rewardedBusy)
                        } else {
                            Text("本日のリワード試用は上限に達しています。また明日お試しください。")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.65))
                                .multilineTextAlignment(.center)
                        }
                    } else {
                        ProgressView()
                            .tint(cyan)
                        Text("価格情報を読み込み中…")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.6))
                    }
                }

                if let rewardedMessage {
                    Text(rewardedMessage)
                        .font(.caption)
                        .foregroundColor(.orange.opacity(0.95))
                        .multilineTextAlignment(.center)
                }

                if let err = entitlements.purchasesErrorMessage {
                    Text(err)
                        .font(.caption)
                        .foregroundColor(.orange)
                        .multilineTextAlignment(.center)
                }
                Spacer(minLength: 0)
            }
            .padding(24)
        }
        .presentationDragIndicator(.visible)
        .onChange(of: entitlements.hasPurchasedPremium) { _, purchased in
            if purchased { dismiss() }
        }
    }

    private func formatted(date: Date) -> String {
        JapaneseDateFormatters.yearMonthDay.string(from: date)
            + " "
            + DateFormatter.localizedString(from: date, dateStyle: .none, timeStyle: .short)
    }
}

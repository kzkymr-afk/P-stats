import StoreKit
import SwiftUI

/// プレミアム案内・購入（設定シート）
struct AnalyticsUpgradeSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var themeManager: ThemeManager
    @ObservedObject private var entitlements = EntitlementsStore.shared

    private var cyan: Color { themeManager.currentTheme.accentColor }

    var body: some View {
        NavigationStack {
            ZStack {
                AppGlassStyle.background.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 20) {
                        Text("無料版では、データ分析機能に制限があります。\nプレミアムに登録すると、広告が非表示になり、全ての分析機能が解放されます。")
                            .font(AppTypography.bodyRounded)
                            .foregroundColor(.white.opacity(0.85))

                        if entitlements.hasPurchasedPremium {
                            Label("プレミアムはご利用中です", systemImage: "checkmark.seal.fill")
                                .foregroundColor(cyan)
                        } else {
                            if entitlements.hasAnalyticsFull {
                                Label("リワード試用中はプレミアムと同じ内容です。継続は月額登録で確定できます。", systemImage: "gift.fill")
                                    .font(AppTypography.annotation)
                                    .foregroundColor(cyan.opacity(0.95))
                            }
                            purchaseBlock(
                                title: "プレミアム（広告オフ・分析フル）",
                                product: entitlements.product(for: .premiumMonthly),
                                action: { await entitlements.purchasePremium() }
                            )
                        }

                        if let err = entitlements.purchasesErrorMessage {
                            Text(err)
                                .font(AppTypography.annotation)
                                .foregroundColor(.orange)
                        }
                    }
                    .padding(20)
                }
            }
            .navigationTitle("プレミアム")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                        .foregroundColor(cyan)
                }
            }
            .alert("購入完了", isPresented: Binding(
                get: { entitlements.purchaseSuccessNotice != nil },
                set: { if !$0 { entitlements.acknowledgePurchaseSuccessNotice() } }
            )) {
                Button("OK") { entitlements.acknowledgePurchaseSuccessNotice() }
            } message: {
                Text(entitlements.purchaseSuccessNotice ?? "")
            }
        }
    }

    private func purchaseBlock(title: String, product: Product?, action: @escaping () async -> Void) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(AppTypography.panelHeading)
                .foregroundColor(.white)
            if let product {
                Button {
                    Task { await action() }
                } label: {
                    Text("月額で登録する（\(product.displayPriceJapanese)）")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .foregroundColor(.black)
                        .background(cyan)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            } else {
                ProgressView()
                    .tint(cyan)
                Text("価格情報を読み込み中…")
                    .font(AppTypography.annotation)
                    .foregroundColor(.white.opacity(0.6))
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .pstatsPanelStyle()
    }
}

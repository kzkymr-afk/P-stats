import Combine
import Foundation
import StoreKit
import UIKit

// MARK: - プロダクト ID（App Store Connect と完全一致）

/// プレミアム（**広告非表示 + 分析フル**）の月額自動更新サブスク。
enum IAPProductID: String, CaseIterable {
    case premiumMonthly = "jp.kzkymr.p-stats.sub.premium.monthly"
}

/// 旧2プラン時代のサブスク ID。移行直後のユーザー向けに `currentEntitlements` に残る間はプレミアムとみなす。
private enum IAPLegacyPremiumProductID: String {
    case removeAdsMonthly = "jp.kzkymr.p-stats.sub.remove_ads.monthly"
    case analyticsFullMonthly = "jp.kzkymr.p-stats.sub.analytics_full.monthly"
}

/// App Store Connect で登録した製品 ID と、上記の文字列を一致させる。
@MainActor
final class EntitlementsStore: ObservableObject {
    static let shared = EntitlementsStore()

    /// ストア上でプレミアム（広告オフ＋分析フル）が有効か。
    @Published private(set) var storedHasPremium = false

    /// 購入完了後に一度だけ見せる日本語メッセージ（システムの英語ダイアログに代わる案内）。
    @Published var purchaseSuccessNotice: String?

    /// リワード試用が「権限」として有効か（DEBUG では開発者向け上書きあり）。
    private var rewardTrialContributesToAccess: Bool {
        #if DEBUG
        switch DeveloperEntitlementDebugSettings.shared.rewardTrialMode {
        case .forceActive: return true
        case .forceInactive: return false
        case .actual: return RewardedAnalyticsTrialController.shared.isTrialActive
        }
        #else
        return RewardedAnalyticsTrialController.shared.isTrialActive
        #endif
    }

    /// 広告を表示しない（プレミアムまたはリワード試用中）。
    var hasRemoveAds: Bool {
        if hasPurchasedPremium { return true }
        if rewardTrialContributesToAccess { return true }
        return false
    }

    /// ストアの課金のみ（試用・リワード除く）。UI の「ご利用中」等。
    var hasPurchasedPremium: Bool {
        #if DEBUG
        switch DeveloperEntitlementDebugSettings.shared.premiumMode {
        case .forceSubscribed: return true
        case .forceNotSubscribed: return false
        case .useStoreKit: return storedHasPremium
        }
        #else
        return storedHasPremium
        #endif
    }

    /// 分析フル相当（プレミアムまたはリワード試用）。
    var hasAnalyticsFull: Bool {
        if hasPurchasedPremium { return true }
        if rewardTrialContributesToAccess { return true }
        return false
    }

    /// 設定などで「リワード試用中」と表示するか（DEBUG 上書きを反映）。
    var isRewardTrialActiveForDisplay: Bool {
        rewardTrialContributesToAccess
    }

    /// 試用期限の表示用。DEBUG で「試用中として扱う」かつ実際の試用がないときはダミー時刻。
    var rewardTrialEndDateForDisplay: Date? {
        guard rewardTrialContributesToAccess else { return nil }
        let real = RewardedAnalyticsTrialController.shared.trialEndDate
        #if DEBUG
        if DeveloperEntitlementDebugSettings.shared.rewardTrialMode == .forceActive,
           !RewardedAnalyticsTrialController.shared.isTrialActive {
            return Date().addingTimeInterval(TimeInterval(RewardedAnalyticsTrialController.trialHoursPerReward) * 3600)
        }
        #endif
        return real
    }

    /// `hasPurchasedAnalyticsFull` を置き換え（購読者コード互換）
    var hasPurchasedAnalyticsFull: Bool { hasPurchasedPremium }

    @Published var showAnalyticsUpsellHalfSheet = false
    @Published private(set) var products: [Product] = []
    @Published var purchasesErrorMessage: String?

    var analyticsUnlocked: Bool { hasAnalyticsFull }
    var shouldShowAds: Bool { !hasRemoveAds }

    private var transactionListenTask: Task<Void, Never>?

    private init() {
        transactionListenTask = Task {
            for await result in Transaction.updates {
                if case .verified(let transaction) = result {
                    await transaction.finish()
                }
                await refreshEntitlements()
            }
        }
        Task {
            await loadProducts()
            await refreshEntitlements()
        }
    }

    func loadProducts() async {
        let ids = IAPProductID.allCases.map(\.rawValue)
        do {
            let loaded = try await Product.products(for: ids)
            let order = IAPProductID.allCases.map(\.rawValue)
            let sorted = loaded.sorted {
                let i0 = order.firstIndex(of: $0.id) ?? Int.max
                let i1 = order.firstIndex(of: $1.id) ?? Int.max
                return i0 < i1
            }
            await MainActor.run {
                self.products = sorted
            }
        } catch {
            await MainActor.run {
                self.purchasesErrorMessage = Self.japanesePurchaseErrorMessage(error)
            }
        }
    }

    func refreshEntitlements() async {
        var premium = false
        for await entitlement in Transaction.currentEntitlements {
            guard case .verified(let transaction) = entitlement else { continue }
            if transaction.revocationDate != nil { continue }
            switch transaction.productID {
            case IAPProductID.premiumMonthly.rawValue,
                 IAPLegacyPremiumProductID.removeAdsMonthly.rawValue,
                 IAPLegacyPremiumProductID.analyticsFullMonthly.rawValue:
                premium = true
            default:
                break
            }
        }
        await MainActor.run {
            self.storedHasPremium = premium
            AdVisibilityManager.shared.syncFromEntitlements()
        }
    }

    func purchase(_ id: IAPProductID) async {
        await MainActor.run {
            purchasesErrorMessage = nil
            purchaseSuccessNotice = nil
        }
        var product: Product? = await MainActor.run { products.first { $0.id == id.rawValue } }
        if product == nil {
            await loadProducts()
            product = await MainActor.run { products.first { $0.id == id.rawValue } }
        }
        guard let product else {
            await MainActor.run {
                self.purchasesErrorMessage = "ストア情報を読み込めていません。通信状況を確認して再度お試しください。"
            }
            return
        }
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                if case .verified(let transaction) = verification {
                    await transaction.finish()
                    await refreshEntitlements()
                    await MainActor.run {
                        self.purchaseSuccessNotice = "購入が完了しました。ありがとうございます。"
                    }
                } else {
                    await MainActor.run {
                        self.purchasesErrorMessage = "購入の確認に失敗しました。"
                    }
                }
            case .userCancelled: break
            case .pending:
                await MainActor.run {
                    self.purchasesErrorMessage = "購入処理が保留中です。しばらくしてから戻ります。"
                }
            @unknown default: break
            }
        } catch {
            await MainActor.run {
                self.purchasesErrorMessage = Self.japanesePurchaseErrorMessage(error)
            }
        }
    }

    /// プレミアムが1件だけなので省略用。
    func purchasePremium() async {
        await purchase(.premiumMonthly)
    }

    func restorePurchases() async {
        await MainActor.run { purchasesErrorMessage = nil }
        do {
            try await AppStore.sync()
            await refreshEntitlements()
        } catch {
            await MainActor.run {
                self.purchasesErrorMessage = Self.japanesePurchaseErrorMessage(error)
            }
        }
    }

    func product(for id: IAPProductID) -> Product? {
        products.first { $0.id == id.rawValue }
    }

    func notifyAnalyticsAccessChanged() {
        objectWillChange.send()
        AdVisibilityManager.shared.syncFromEntitlements()
    }

    func acknowledgePurchaseSuccessNotice() {
        purchaseSuccessNotice = nil
    }

    /// 課金・リストアのエラーを日本語で表示（`localizedDescription` の英語を避ける）
    private nonisolated static func japanesePurchaseErrorMessage(_ error: Error) -> String {
        let ns = error as NSError
        if ns.domain == SKError.errorDomain, let code = SKError.Code(rawValue: ns.code) {
            switch code {
            case .paymentCancelled:
                return "購入はキャンセルされました。"
            case .paymentNotAllowed:
                return "このデバイスまたはアカウントでは購入できません。"
            case .clientInvalid, .paymentInvalid:
                return "購入を完了できませんでした。しばらくしてからお試しください。"
            case .storeProductNotAvailable:
                return "この商品は現在利用できません。"
            case .cloudServiceNetworkConnectionFailed, .cloudServicePermissionDenied:
                return "通信に失敗しました。ネットワークを確認してください。"
            default:
                break
            }
        }
        if ns.domain == NSURLErrorDomain {
            return "通信に失敗しました。ネットワークを確認してください。"
        }
        return "処理に失敗しました。しばらくしてからお試しください。"
    }

    func openManageSubscriptions() {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        guard let scene = scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first else { return }
        Task {
            try? await AppStore.showManageSubscriptions(in: scene)
            await refreshEntitlements()
        }
    }
}

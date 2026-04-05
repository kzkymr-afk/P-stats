#if DEBUG
import Combine
import Foundation

/// 開発者向け：ストアの購入状態・リワード試用を UI 上だけ上書き（本番ビルドには含めない）。
@MainActor
enum DebugPremiumEntitlementMode: String, CaseIterable, Identifiable {
    case useStoreKit
    case forceSubscribed
    case forceNotSubscribed

    var id: String { rawValue }

    var label: String {
        switch self {
        case .useStoreKit: return "実際の購入状態を使う"
        case .forceSubscribed: return "登録済みとして扱う"
        case .forceNotSubscribed: return "未登録として扱う（解約シミュレート）"
        }
    }
}

@MainActor
enum DebugRewardTrialMode: String, CaseIterable, Identifiable {
    case actual
    case forceActive
    case forceInactive

    var id: String { rawValue }

    var label: String {
        switch self {
        case .actual: return "実際のリワード試用"
        case .forceActive: return "試用中として扱う"
        case .forceInactive: return "試用なしとして扱う"
        }
    }
}

@MainActor
final class DeveloperEntitlementDebugSettings: ObservableObject {
    static let shared = DeveloperEntitlementDebugSettings()

    private let premiumKey = "devDebugPremiumEntitlementMode"
    private let rewardKey = "devDebugRewardTrialMode"

    @Published var premiumMode: DebugPremiumEntitlementMode {
        didSet {
            guard premiumMode != oldValue else { return }
            UserDefaults.standard.set(premiumMode.rawValue, forKey: premiumKey)
            EntitlementsStore.shared.notifyAnalyticsAccessChanged()
        }
    }

    @Published var rewardTrialMode: DebugRewardTrialMode {
        didSet {
            guard rewardTrialMode != oldValue else { return }
            UserDefaults.standard.set(rewardTrialMode.rawValue, forKey: rewardKey)
            EntitlementsStore.shared.notifyAnalyticsAccessChanged()
        }
    }

    private init() {
        let p = UserDefaults.standard.string(forKey: premiumKey).flatMap(DebugPremiumEntitlementMode.init(rawValue:)) ?? .useStoreKit
        let r = UserDefaults.standard.string(forKey: rewardKey).flatMap(DebugRewardTrialMode.init(rawValue:)) ?? .actual
        premiumMode = p
        rewardTrialMode = r
    }
}
#else
// Release ではこのモジュールにデバッグ用型を置かない（空の翻訳単位を避けるためのプレースホルダ）。
private enum _DeveloperEntitlementDebugSettingsNotInRelease {}
#endif

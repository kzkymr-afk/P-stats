import Foundation

/// 遊技開始ゲート「開始時の持ち玉」の初期表示方針（`startWithZeroHoldings` を置き換え）
enum InitialHoldingsGatePolicy: String, CaseIterable, Identifiable {
    /// 空欄。毎回自分で入力（貯玉を使わない・同日に台移動する等）
    case manual
    /// 常に 0 を入れた状態から始める
    case prefillZero
    /// 選択店舗の貯玉残高が 1 以上ならその数、0 なら 0
    case prefillChodamaFromShop

    var id: String { rawValue }

    /// `UserDefaults` キー（`AppStorage` と一致）
    static let storageKey = "initialHoldingsGatePolicy"

    /// 旧 `startWithZeroHoldings` からの一回限り移行（未設定時のみ）
    static func migrateFromLegacyIfNeeded() {
        let u = UserDefaults.standard
        guard u.object(forKey: storageKey) == nil else { return }
        let legacy = u.object(forKey: "startWithZeroHoldings") as? Bool
        let v: InitialHoldingsGatePolicy = (legacy == true) ? .prefillZero : .manual
        u.set(v.rawValue, forKey: storageKey)
    }

    var settingsTitle: String {
        switch self {
        case .manual: return "手入力（空欄から）"
        case .prefillZero: return "常に 0 を入れる"
        case .prefillChodamaFromShop: return "店の貯玉残高があれば合わせる"
        }
    }

    /// ゲートの `initialHoldingsText` に入れる文字列
    func initialText(for shop: Shop) -> String {
        switch self {
        case .manual: return ""
        case .prefillZero: return "0"
        case .prefillChodamaFromShop:
            let b = max(0, shop.chodamaBalanceBalls)
            return b > 0 ? "\(b)" : "0"
        }
    }
}

import SwiftUI

/// 実戦画面の「スライドで大当たり」レールの見た目（設定の「大当たり開始スライド」から選択）
enum BigHitSlideRailStyle: String, CaseIterable, Identifiable {
    case neonCyberpunk
    case minimalGlass
    case mechanicalIndustrial
    case dynamicLiquid
    case waSengoku
    case premiumGold

    var id: String { rawValue }

    /// `AppStorage` 用の既定値
    static var defaultStorageValue: String { minimalGlass.rawValue }

    var displayName: String {
        switch self {
        case .neonCyberpunk: return "ネオン・サイバーパンク"
        case .minimalGlass: return "ミニマル・ガラスモーフィズム"
        case .mechanicalIndustrial: return "メカニカル・インダストリアル"
        case .dynamicLiquid: return "ダイナミック・リキッド"
        case .waSengoku: return "和風・戦国極（きわみ）"
        case .premiumGold: return "プレミアム・ゴールド"
        }
    }
}

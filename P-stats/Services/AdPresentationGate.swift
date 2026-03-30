import Combine
import Foundation

/// 遊技セッション中は App Open 等を抑止するためのゲート（HomeView が状態を同期）。
@MainActor
final class AdPresentationGate: ObservableObject {
    static let shared = AdPresentationGate()

    /// `PlayView` の fullScreen が表示中、または実戦から設定へ一時退避中
    @Published private(set) var isPlaySessionBlockingAppOpen = false

    func setPlaySessionBlockingAppOpen(_ blocking: Bool) {
        if isPlaySessionBlockingAppOpen != blocking {
            isPlaySessionBlockingAppOpen = blocking
        }
    }

    private init() {}
}

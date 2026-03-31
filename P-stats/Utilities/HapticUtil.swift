import UIKit

// MARK: - バイブ（触覚フィードバック）ユーティリティ
enum HapticUtil {
    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: "hapticEnabled") as? Bool ?? true
    }

    static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .light) {
        guard isEnabled else { return }
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }

    static func notification(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        guard isEnabled else { return }
        UINotificationFeedbackGenerator().notificationOccurred(type)
    }

    /// 大当たり中の連チャン +1 用。rigid でキレのある一回、続けてごく短い soft で余韻を付ける。
    static func bigHitChainIncrement() {
        guard isEnabled else { return }
        let head = UIImpactFeedbackGenerator(style: .rigid)
        head.prepare()
        head.impactOccurred(intensity: 1.0)
        let tail = UIImpactFeedbackGenerator(style: .soft)
        tail.prepare()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.045) {
            guard isEnabled else { return }
            tail.impactOccurred(intensity: 0.55)
        }
    }
}

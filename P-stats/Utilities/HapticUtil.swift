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

    /// 大当たり中の連チャン +1 用。heavy→medium→soft の短い連打で「胸が跳ねる」感じ（通知音ほど大袈裟にはしない）。
    static func bigHitChainIncrement() {
        guard isEnabled else { return }
        let head = UIImpactFeedbackGenerator(style: .heavy)
        head.prepare()
        head.impactOccurred(intensity: 0.92)
        let mid = UIImpactFeedbackGenerator(style: .medium)
        mid.prepare()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.052) {
            guard isEnabled else { return }
            mid.impactOccurred(intensity: 0.62)
        }
        let tail = UIImpactFeedbackGenerator(style: .soft)
        tail.prepare()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.11) {
            guard isEnabled else { return }
            tail.impactOccurred(intensity: 0.42)
        }
    }
}

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
}

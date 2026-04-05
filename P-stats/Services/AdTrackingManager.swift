import AdSupport
import AppTrackingTransparency
import Foundation
import os

/// App Tracking Transparency（ATT）の許可ダイアログ。広告 SDK が IDFA を参照する前にユーザー同意を得る。
struct AdTrackingManager {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.p-stats", category: "AdTracking")

    /// 同一プロセス内で遅延リクエストが二重に積まれないようにする。
    private static var permissionRequestScheduled = false

    static func requestPermission() {
        guard #available(iOS 14, *) else { return }
        guard ATTrackingManager.trackingAuthorizationStatus == .notDetermined else {
            return
        }
        guard !permissionRequestScheduled else { return }
        permissionRequestScheduled = true

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            ATTrackingManager.requestTrackingAuthorization { status in
                switch status {
                case .authorized:
                    _ = ASIdentifierManager.shared().advertisingIdentifier
                    Self.logger.debug("ATT Status: 許可されました (IDFAアクセス可能)")
                case .denied:
                    Self.logger.debug("ATT Status: 拒否されました")
                case .restricted:
                    Self.logger.debug("ATT Status: 制限されています")
                case .notDetermined:
                    Self.logger.debug("ATT Status: 未決定")
                @unknown default:
                    break
                }
            }
        }
    }
}

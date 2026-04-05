import SwiftUI
import LocalAuthentication
import Security
import Combine

// MARK: - 旧アプリパスコード用Keychain（本体認証移行済み。removePasscode 時のみ削除に使用）
private enum KeychainPasscode {
    static let service = "P-stats.app.lock"

    static func delete() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service
        ]
        SecItemDelete(query as CFDictionary)
    }
}

// MARK: - アプリロック状態
final class AppLockState: ObservableObject {
    static let shared = AppLockState()

    @Published var isUnlocked = false
    @AppStorage(UserDefaultsKey.appLockEnabled.rawValue) var lockEnabled = false
    @AppStorage(UserDefaultsKey.appLockUseBiometric.rawValue) var useBiometric = true

    /// 生体認証の可否・種類は body のたびに LAContext を作ると重いため、ロック表示時に1回だけ評価してキャッシュする
    private var cachedBiometric: (canUse: Bool, name: String)?

    var canUseBiometric: Bool {
        if let c = cachedBiometric { return c.canUse }
        let context = LAContext()
        var error: NSError?
        let canUse = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
        let name = biometricTypeName(with: context, canUse: canUse)
        cachedBiometric = (canUse, name)
        return canUse
    }

    var biometricTypeName: String {
        if let c = cachedBiometric { return c.name }
        let context = LAContext()
        var error: NSError?
        let canUse = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
        let name = biometricTypeName(with: context, canUse: canUse)
        cachedBiometric = (canUse, name)
        return name
    }

    private func biometricTypeName(with context: LAContext, canUse: Bool) -> String {
        guard canUse else { return "生体認証" }
        switch context.biometryType {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        default: return "生体認証"
        }
    }

    func removePasscode() {
        KeychainPasscode.delete()
    }

    /// 生体認証のみ（指紋 or Face ID）
    func authenticateWithBiometric() async -> Bool {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else { return false }
        do {
            return try await context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: "アプリのロックを解除")
        } catch {
            return false
        }
    }

    /// iPhone本体のパスコード or 生体認証で解除（共通）
    func authenticateWithDevice() async -> Bool {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else { return false }
        do {
            return try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "アプリのロックを解除")
        } catch {
            return false
        }
    }

    func lock() {
        isUnlocked = false
        cachedBiometric = nil
    }

    func unlock() {
        isUnlocked = true
    }
}

// MARK: - ロック画面（iPhone本体パスコード＋生体認証で解除）
/// 初回描画で LAContext を呼ばないよう、生体認証の表示文言は onAppear で遅延取得する
struct AppLockScreenView: View {
    @ObservedObject var lockState: AppLockState
    @State private var errorMessage: String?
    @State private var biometricLabel: String = "パスコードで解除"
    @State private var biometricCaption: String = "生体認証"
    @State private var biometricIcon: String = "lock.open"

    private var cyan: Color { AppGlassStyle.accent }

    var body: some View {
        ZStack {
            AppGlassStyle.background
                .ignoresSafeArea()
            VStack(spacing: 28) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 48))
                    .foregroundColor(cyan.opacity(0.9))
                Text("アプリがロックされています")
                    .font(.headline)
                    .foregroundColor(.white)
                Text("本体のパスコードまたは\(biometricCaption)で解除")
                    .font(AppTypography.annotation)
                    .foregroundColor(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                if let msg = errorMessage {
                    Text(msg)
                        .font(AppTypography.annotation)
                        .foregroundColor(.red)
                        .padding(.top, 4)
                }
                Button {
                    Task {
                        if await lockState.authenticateWithDevice() {
                            await MainActor.run {
                                lockState.unlock()
                                errorMessage = nil
                                HapticUtil.notification(.success)
                            }
                        } else {
                            await MainActor.run {
                                errorMessage = "認証に失敗しました"
                            }
                        }
                    }
                } label: {
                    Label(biometricLabel, systemImage: biometricIcon)
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(cyan)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 14)
                }
                .padding(.top, 24)
            }
            .padding(40)
        }
        .onAppear {
            // 初回描画後に LAContext を参照（メインスレッドブロックで固まらないよう遅延）
            DispatchQueue.main.async {
                let name = lockState.biometricTypeName
                let canUse = lockState.canUseBiometric
                biometricCaption = name
                biometricLabel = canUse ? (name + " / パスコードで解除") : "パスコードで解除"
                biometricIcon = name == "Face ID" ? "faceid" : (name == "Touch ID" ? "touchid" : "lock.open")
            }
            if lockState.useBiometric {
                Task {
                    try? await Task.sleep(nanoseconds: 400_000_000)
                    if lockState.canUseBiometric, await lockState.authenticateWithDevice() {
                        await MainActor.run { lockState.unlock(); errorMessage = nil; HapticUtil.notification(.success) }
                    }
                }
            }
        }
    }
}

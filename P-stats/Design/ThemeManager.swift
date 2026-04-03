import Combine
import SwiftUI

// MARK: - 現在のスキン配信
//
// 設定画面の `AppTheme` enum（ダーク固定等）とは別で、**見た目のトークン**（`ApplicationTheme`）を
// 全画面に渡すためのマネージャーです。
//
// 言語上、プロトコルを型として持つ場合は `any ApplicationTheme` と書きます（指示の `ApplicationTheme` と同義）。

/// 現在選択中の `ApplicationTheme` を保持し、`@Published` でビューへ反映する。
@MainActor
final class ThemeManager: ObservableObject {
    /// 現在有効なスキン。
    @Published var currentTheme: any ApplicationTheme
    /// 設定画面の Picker 等と同期する選択中スキン。
    @Published private(set) var selectedSkin: PStatsSkin

    /// アプリ全体で共有するインスタンス（`EnvironmentObject` 注入用）。
    static let shared = ThemeManager()

    private init() {
        let raw = UserDefaults.standard.string(forKey: PStatsSkin.storageKey)
        let skin = raw.flatMap { PStatsSkin(rawValue: $0) } ?? .standard
        selectedSkin = skin
        currentTheme = skin.resolveTheme()
    }

    /// プリセットスキンに切り替え（永続化する）。
    func applySkin(_ skin: PStatsSkin) {
        selectedSkin = skin
        currentTheme = skin.resolveTheme()
        UserDefaults.standard.set(skin.rawValue, forKey: PStatsSkin.storageKey)
    }

    /// 任意の `ApplicationTheme` を直接適用する（デバッグ等）。永続化しない。
    func applyTheme(_ theme: any ApplicationTheme) {
        currentTheme = theme
    }
}

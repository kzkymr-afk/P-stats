import Combine
import SwiftUI

// MARK: - アプリ共通の見た目トークン配信
//
// 設定の `AppTheme`（ダーク固定等）とは別。パネル・文字色・チャート色は `DefaultTheme` を経由して統一する。
// 将来スキン切替を再導入する場合は `currentTheme` の差し替えポイントをここに集約する。
//
// プロトコルを型として持つ場合は `any ApplicationTheme` と書く。

/// 現在有効な `ApplicationTheme` を保持し、`@Published` でビューへ反映する。
@MainActor
final class ThemeManager: ObservableObject {
    @Published var currentTheme: any ApplicationTheme

    static let shared = ThemeManager()

    private init() {
        currentTheme = DefaultTheme.shared
    }
}

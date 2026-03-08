import Foundation

/// パチンコ店以外と判断する名前で除外すべきか（Swift 6 並行対応）。配列はメソッド内ローカルで MainActor 隔離を避ける。
enum PlaceSearchFilter: Sendable {
    static nonisolated func shouldExclude(name: String) -> Bool {
        let excluded: [String] = [
            "ラウンドワン", "Round One", "ラウンド1",
            "セガ", "SEGA",
        ]
        let lower = name.localizedLowercase
        return excluded.contains { sub in
            lower.contains(sub.localizedLowercase)
        }
    }
}

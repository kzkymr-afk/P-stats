import Foundation

enum UnitDisplaySettings {
    /// 表示末尾に付ける単位ラベル（ユーザー手入力）。例: "pt", "ポイント", "p", "単位" など。
    /// 審査観点で特定通貨（円など）をプリセットしない。
    static let unitSuffixKey = "unitDisplaySuffix"

    static func currentSuffix() -> String {
        let raw = UserDefaults.standard.string(forKey: unitSuffixKey) ?? "pt"
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return "" }
        // 見た目の統一のため、先頭にスペースを付ける（既存表示と同様）
        return " \(t)"
    }
}


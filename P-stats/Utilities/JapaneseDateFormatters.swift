import Foundation

/// アプリ全体で統一する日本語ロケールの日付文字列（重複定義を避ける）
enum JapaneseDateFormatters {
    /// 例: 2026年3月20日
    static let yearMonthDay: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ja_JP")
        f.dateFormat = "yyyy年M月d日"
        return f
    }()

    /// 例: 2026年3月（カレンダー見出し等）
    static let yearMonth: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ja_JP")
        f.dateFormat = "yyyy年M月"
        return f
    }()
}

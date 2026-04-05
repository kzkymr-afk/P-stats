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

    /// 例: 2026年　3月（分析ドックの月ドラム。年と月の間は全角スペース）
    static let yearMonthDock: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ja_JP")
        f.calendar = Calendar(identifier: .gregorian)
        f.dateFormat = "yyyy年\u{3000}M月"
        return f
    }()

    /// 時刻のみ（日本語ロケール・例: 21:30）。端末の現地タイムゾーン。
    static let timeShort: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ja_JP")
        f.dateStyle = .none
        f.timeStyle = .short
        return f
    }()

    /// 日本標準時（東京）で日付＋時刻。例: 2026年4月5日 14:30
    static let dateTimeTokyo: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ja_JP")
        f.timeZone = TimeZone(identifier: "Asia/Tokyo")
        f.dateFormat = "yyyy年M月d日 H:mm"
        return f
    }()

    /// 日本標準時（東京）で時刻のみ（例: 14:30）
    static let timeShortTokyo: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ja_JP")
        f.timeZone = TimeZone(identifier: "Asia/Tokyo")
        f.dateStyle = .none
        f.timeStyle = .short
        return f
    }()
}

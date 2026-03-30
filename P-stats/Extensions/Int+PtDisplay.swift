import SwiftUI

// MARK: - ポイント表示（統計シミュレーション用・カンマ区切り + pt）
extension Int {
    /// 表示用：数値をカンマ区切りで返す（例: 12345 → "12,345"）
    var formattedPt: String { formatted(.number) }
    /// 表示用：数値 + " pt" 単位（例: 12345 → "12,345 pt"）
    var formattedPtWithUnit: String { formatted(.number) + " pt" }

    /// コンパクト表示（ホーム星取り下など）。例: +3k, -30k, +1.2k
    var formattedPtCompactK: String {
        if self == 0 { return "0" }
        let sign = self >= 0 ? "+" : "-"
        let a = abs(self)
        if a >= 10_000 {
            let v = Double(a) / 10_000.0
            let s = v >= 10 ? String(format: "%.0f", v) : String(format: "%.1f", v)
            return "\(sign)\(s)万"
        }
        if a >= 1000 {
            let k = a / 1000
            let rem = a % 1000
            if rem == 0 { return "\(sign)\(k)k" }
            let v = Double(a) / 1000.0
            let s = v >= 10 ? String(format: "%.0f", v) : String(format: "%.1f", v)
            return "\(sign)\(s)k"
        }
        return "\(sign)\(a)"
    }
}

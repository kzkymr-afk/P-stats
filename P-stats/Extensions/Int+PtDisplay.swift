import SwiftUI

// MARK: - ポイント表示（統計シミュレーション用・カンマ区切り + pt）
extension Int {
    /// 表示用：数値をカンマ区切りで返す（例: 12345 → "12,345"）
    var formattedPt: String { formatted(.number) }
    /// 表示用：数値 + " pt" 単位（例: 12345 → "12,345 pt"）
    var formattedPtWithUnit: String { formatted(.number) + UnitDisplaySettings.currentSuffix() }

    /// コンパクト表示（ホーム星取り下など）。pt を千円換算し **k** で統一（例: +10k, -0.5k, +1.2k）
    var formattedPtCompactK: String {
        if self == 0 { return "0" }
        let sign = self >= 0 ? "+" : "-"
        let a = abs(self)
        let k = Double(a) / 1000.0
        var s = k.displayFormat("%.1f")
        if s.hasSuffix(".0") {
            s = String(s.dropLast(2))
        }
        return "\(sign)\(s)k"
    }
}

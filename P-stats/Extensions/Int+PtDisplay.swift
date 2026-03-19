import SwiftUI

// MARK: - ポイント表示（統計シミュレーション用・カンマ区切り + pt）
extension Int {
    /// 表示用：数値をカンマ区切りで返す（例: 12345 → "12,345"）
    var formattedPt: String { formatted(.number) }
    /// 表示用：数値 + " pt" 単位（例: 12345 → "12,345 pt"）
    var formattedPtWithUnit: String { formatted(.number) + " pt" }
}

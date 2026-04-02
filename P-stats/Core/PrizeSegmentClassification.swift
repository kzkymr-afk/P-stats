import Foundation

// MARK: - プリセット賞球文字列から当たり種別を判定（キーワードを列挙型で表現）

/// `heso_prizes` / `denchu_prizes` のセグメント内で、RUSH 相当とみなすマーカー。
private enum HesoPrizeRushMarker: CaseIterable {
    case lt
    case heaven
    case rushLabel

    func matches(_ segment: String) -> Bool {
        switch self {
        case .lt:
            return segment.contains("LT")
        case .heaven:
            return segment.contains("天国")
        case .rushLabel:
            return segment.contains("RUSH")
        }
    }
}

enum PrizeSegmentClassification {
    /// 通常時用セグメント（例: `10R(1500個)-RUSH`）から `WinType` を決定。
    static func winTypeForHesoSegment(_ segment: String) -> WinType {
        if HesoPrizeRushMarker.allCases.contains(where: { $0.matches(segment) }) {
            return .rush
        }
        return .normal
    }

    /// RUSH 時用セグメントで「特別扱い」か（天国・上乗せ）
    static func isDenchuSpecialSegment(_ segment: String) -> Bool {
        if segment.contains("天国") { return true }
        if segment.contains("上乗せ") { return true }
        return false
    }
}

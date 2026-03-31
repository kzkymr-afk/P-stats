import Foundation

/// P-Sync/GAS の heso_prizes をパースした1件（通常時・特図1）
struct ParsedHesoItem: Identifiable {
    let id = UUID()
    /// ボタン表示用（例: "(1500個)"。R数は含めない）
    let displayLabel: String
    /// 払い出し玉数（パースできなければ nil）
    let balls: Int?
    /// キーワード判定: "RUSH" → .rush, "通常" 等 → .normal
    let winType: WinType
}

/// P-Sync/GAS の denchu_prizes をパースした1件（RUSH時・特図2）
struct ParsedDenchuItem: Identifiable {
    let id = UUID()
    let displayLabel: String
    let balls: Int?
    /// 「天国」「上乗せ」等を含む場合は true（ボタン強調用）
    let isSpecial: Bool
}

enum PrizeStringParser {
    private static let roundsPattern = try? NSRegularExpression(pattern: #"(\d+)\s*R"#)
    private static let ballsInParenPattern = try? NSRegularExpression(pattern: #"\((\d+)\s*個\)"#)
    private static let ballsStandalonePattern = try? NSRegularExpression(pattern: #"(\d+)\s*個"#)

    /// 通常時用 heso_prizes をカンマ区切りでパース（例: "10R(1500個)-RUSH,2R(300個)-通常"）
    static func parseHesoPrizes(_ string: String) -> [ParsedHesoItem] {
        let raw = string.trimmingCharacters(in: .whitespaces)
        guard !raw.isEmpty else { return [] }
        return raw.components(separatedBy: ",")
            .map { segment in parseHesoSegment(segment.trimmingCharacters(in: .whitespaces)) }
            .compactMap { $0 }
    }

    /// RUSH時用 denchu_prizes をカンマ区切りでパース（例: "10R(1500個)-RUSH,300個-RUSH,10R(1500個)-天国"）
    static func parseDenchuPrizes(_ string: String) -> [ParsedDenchuItem] {
        let raw = string.trimmingCharacters(in: .whitespaces)
        guard !raw.isEmpty else { return [] }
        return raw.components(separatedBy: ",")
            .map { segment in parseDenchuSegment(segment.trimmingCharacters(in: .whitespaces)) }
            .compactMap { $0 }
    }

    private static func parseHesoSegment(_ segment: String) -> ParsedHesoItem? {
        guard !segment.isEmpty else { return nil }
        let winType: WinType
        if segment.contains("LT") || segment.contains("天国") {
            winType = .rush
        } else if segment.contains("RUSH") {
            winType = .rush
        } else {
            winType = .normal
        }
        let displayLabel = labelFromSegment(segment)
        let balls = extractBalls(segment)
        return ParsedHesoItem(displayLabel: displayLabel, balls: balls, winType: winType)
    }

    private static func parseDenchuSegment(_ segment: String) -> ParsedDenchuItem? {
        guard !segment.isEmpty else { return nil }
        let displayLabel = labelFromSegment(segment)
        let balls = extractBalls(segment)
        let isSpecial = segment.contains("天国") || segment.contains("上乗せ")
        return ParsedDenchuItem(displayLabel: displayLabel, balls: balls, isSpecial: isSpecial)
    }

    /// 表示ラベル（"-RUSH" 等の suffix を除き、○R を除去した部分。例: "10R(1500個)" → "(1500個)"）
    private static func labelFromSegment(_ segment: String) -> String {
        var s = segment
        if let dash = segment.lastIndex(of: "-"), dash != segment.startIndex {
            s = String(segment[..<dash]).trimmingCharacters(in: .whitespaces)
        }
        // ○R を除去（表示にR数を使わない）
        if let r = roundsPattern?.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)),
           let range = Range(r.range, in: s) {
            s = s.replacingCharacters(in: range, with: "").trimmingCharacters(in: .whitespaces)
        }
        return s
    }

    private static func extractBalls(_ segment: String) -> Int? {
        var balls: Int? = nil
        let nsRange = NSRange(segment.startIndex..., in: segment)
        if let b = ballsInParenPattern?.firstMatch(in: segment, range: nsRange) {
            let at1 = b.range(at: 1)
            if let swiftRange = Range(at1, in: segment) {
                balls = Int(segment[swiftRange])
            }
        }
        if balls == nil, let b = ballsStandalonePattern?.firstMatch(in: segment, range: nsRange) {
            let at1 = b.range(at: 1)
            if let swiftRange = Range(at1, in: segment) {
                balls = Int(segment[swiftRange])
            }
        }
        return balls
    }
}

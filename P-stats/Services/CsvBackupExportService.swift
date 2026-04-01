import Foundation

// MARK: - プレミアム向け：ローカルデータの CSV バックアップ（Excel / Numbers 想定、UTF-8 BOM 付き）

enum CsvBackupExportService {

    enum ExportError: Error, LocalizedError {
        case writeFailed(String)

        var errorDescription: String? {
            switch self {
            case .writeFailed(let message): return message
            }
        }
    }

    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    /// RFC 4180 風にフィールドをエスケープ（カンマ・改行・ダブルクォートを含む場合は全体を引用）
    nonisolated static func escapeCSVField(_ raw: String) -> String {
        let mustQuote = raw.contains(",") || raw.contains("\"") || raw.contains("\n") || raw.contains("\r")
        if !mustQuote { return raw }
        return "\"" + raw.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    /// UTF-8 BOM 付きで一時ファイルに書き込み（Excel が文字化けしにくい）
    private static func writeBOMCSV(_ csvBody: String, to url: URL) throws {
        var data = Data([0xEF, 0xBB, 0xBF])
        guard let body = csvBody.data(using: .utf8) else {
            throw ExportError.writeFailed("文字エンコードに失敗しました")
        }
        data.append(body)
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            throw ExportError.writeFailed(error.localizedDescription)
        }
    }

    private static func tempFileURL(suffix: String) -> URL {
        let name = "P-stats-\(suffix)-\(Int(Date().timeIntervalSince1970)).csv"
        return FileManager.default.temporaryDirectory.appendingPathComponent(name, isDirectory: false)
    }

    // MARK: - ビルド

    static func buildGameSessionsCSV(_ sessions: [GameSession]) -> String {
        let header = [
            "id", "date_iso8601", "machineName", "shopName", "manufacturerName",
            "inputCash", "totalHoldings", "normalRotations", "totalUsedBalls",
            "payoutCoefficient", "totalRealCost", "expectationRatioAtSave", "theoreticalValue",
            "rushWinCount", "normalWinCount", "formulaBorderPer1k", "effectiveBorderPer1kAtSave",
            "realRotationRateAtSave", "firstHitRealCostPt", "settlementModeRaw",
            "exchangeCashProceedsPt", "chodamaBalanceDeltaBalls", "isCashflowOnlyRecord",
            "performance", "deficitSurplus", "editSessionPhasesJSON"
        ].joined(separator: ",")

        var lines = [header]
        for s in sessions {
            let firstHit = s.firstHitRealCostPt.map { String(format: "%.6f", $0) } ?? ""
            let phases = s.editSessionPhasesJSON
            let row = [
                s.id.uuidString,
                isoFormatter.string(from: s.date),
                s.machineName,
                s.shopName,
                s.manufacturerName,
                String(s.inputCash),
                String(s.totalHoldings),
                String(s.normalRotations),
                String(s.totalUsedBalls),
                String(format: "%.10g", s.payoutCoefficient),
                String(format: "%.10g", s.totalRealCost),
                String(format: "%.10g", s.expectationRatioAtSave),
                String(s.theoreticalValue),
                String(s.rushWinCount),
                String(s.normalWinCount),
                String(format: "%.10g", s.formulaBorderPer1k),
                String(format: "%.10g", s.effectiveBorderPer1kAtSave),
                String(format: "%.10g", s.realRotationRateAtSave),
                firstHit,
                s.settlementModeRaw,
                String(s.exchangeCashProceedsPt),
                String(s.chodamaBalanceDeltaBalls),
                s.isCashflowOnlyRecord ? "1" : "0",
                String(s.performance),
                String(s.deficitSurplus),
                phases
            ].map(escapeCSVField)
            lines.append(row.joined(separator: ","))
        }
        return lines.joined(separator: "\r\n")
    }

    static func buildMachinesCSV(_ machines: [Machine]) -> String {
        let header = [
            "name", "masterID", "supportLimit", "timeShortRotations", "defaultPrize",
            "probability", "border", "machineTypeRaw", "countPerRound", "manufacturer",
            "hesoAtariStorage", "denchu_prizes", "prizeEntriesSummary"
        ].joined(separator: ",")

        var lines = [header]
        for m in machines {
            let prizes = m.prizeEntries.map { "\($0.label):\($0.balls)" }.joined(separator: "|")
            let row = [
                m.name,
                m.masterID ?? "",
                String(m.supportLimit),
                String(m.timeShortRotations),
                String(m.defaultPrize),
                m.probability,
                m.border,
                m.machineTypeRaw,
                String(m.countPerRound),
                m.manufacturer,
                m.hesoAtariStorage,
                m.denchu_prizes,
                prizes
            ].map(escapeCSVField)
            lines.append(row.joined(separator: ","))
        }
        return lines.joined(separator: "\r\n")
    }

    static func buildShopsCSV(_ shops: [Shop]) -> String {
        let header = [
            "name", "ballsPerCashUnit", "payoutCoefficient", "holdingsBallsPerButton", "supportsChodamaService",
            "chodamaBalanceBalls", "placeID", "address",
            "specificDayOfMonthStorage", "specificLastDigitsStorage", "specificDayRulesStorage"
        ].joined(separator: ",")

        var lines = [header]
        for s in shops {
            let row = [
                s.name,
                String(s.ballsPerCashUnit),
                String(format: "%.10g", s.payoutCoefficient),
                String(s.holdingsBallsPerButton),
                s.supportsChodamaService ? "1" : "0",
                String(s.chodamaBalanceBalls),
                s.placeID ?? "",
                s.address,
                s.specificDayOfMonthStorage,
                s.specificLastDigitsStorage,
                s.specificDayRulesStorage
            ].map(escapeCSVField)
            lines.append(row.joined(separator: ","))
        }
        return lines.joined(separator: "\r\n")
    }

    static func buildMyMachinePresetsCSV(_ presets: [MyMachinePreset]) -> String {
        let header = [
            "name", "probability", "defaultRounds", "countPerRound", "netPerRoundBase",
            "machineTypeRaw", "supportLimit", "timeShortRotations", "defaultPrize",
            "border", "entryRate", "continuationRate", "averagePrize", "lastUsedAt_iso8601"
        ].joined(separator: ",")

        var lines = [header]
        for p in presets {
            let last = p.lastUsedAt.map { isoFormatter.string(from: $0) } ?? ""
            let row = [
                p.name,
                p.probability,
                String(p.defaultRounds),
                String(p.countPerRound),
                String(format: "%.10g", p.netPerRoundBase),
                p.machineTypeRaw,
                String(p.supportLimit),
                String(p.timeShortRotations),
                String(p.defaultPrize),
                p.border,
                String(format: "%.10g", p.entryRate),
                String(format: "%.10g", p.continuationRate),
                String(format: "%.10g", p.averagePrize),
                last
            ].map(escapeCSVField)
            lines.append(row.joined(separator: ","))
        }
        return lines.joined(separator: "\r\n")
    }

    static func buildPrizeSetsCSV(_ sets: [PrizeSet]) -> String {
        let header = ["name", "balls", "displayOrder"].joined(separator: ",")
        var lines = [header]
        for ps in sets {
            let row = [ps.name, String(ps.balls), String(ps.displayOrder)].map(escapeCSVField)
            lines.append(row.joined(separator: ","))
        }
        return lines.joined(separator: "\r\n")
    }

    // MARK: - 一括書き出し

    /// 共有シートに渡す CSV ファイルの URL 一覧（一時ディレクトリ）。利用後は削除推奨。
    static func makeExportFileURLs(
        sessions: [GameSession],
        machines: [Machine],
        shops: [Shop],
        myPresets: [MyMachinePreset],
        prizeSets: [PrizeSet]
    ) throws -> [URL] {
        var urls: [URL] = []

        let sURL = tempFileURL(suffix: "sessions")
        try writeBOMCSV(buildGameSessionsCSV(sessions), to: sURL)
        urls.append(sURL)

        let mURL = tempFileURL(suffix: "machines")
        try writeBOMCSV(buildMachinesCSV(machines), to: mURL)
        urls.append(mURL)

        let shURL = tempFileURL(suffix: "shops")
        try writeBOMCSV(buildShopsCSV(shops), to: shURL)
        urls.append(shURL)

        let mpURL = tempFileURL(suffix: "my-presets")
        try writeBOMCSV(buildMyMachinePresetsCSV(myPresets), to: mpURL)
        urls.append(mpURL)

        let psURL = tempFileURL(suffix: "prize-sets")
        try writeBOMCSV(buildPrizeSetsCSV(prizeSets), to: psURL)
        urls.append(psURL)

        return urls
    }

    static func removeTemporaryFiles(at urls: [URL]) {
        for u in urls {
            try? FileManager.default.removeItem(at: u)
        }
    }
}

import Foundation
import SwiftData

// MARK: - 実戦履歴 CSV インポート（プレミアム向け）

/// 自アプリの `sessions` 書き出しに加え、列名エイリアス付きの簡易書式も受け付ける。
enum CsvSessionImportService {

    enum ImportError: Error, LocalizedError {
        case emptyFile
        case noHeaderRow
        case columnMismatch(expected: Int, row: Int)
        case noSessionColumns

        var errorDescription: String? {
            switch self {
            case .emptyFile: return "ファイルが空です"
            case .noHeaderRow: return "ヘッダー行がありません"
            case .columnMismatch(let expected, let row):
                return "行 \(row): 列数がヘッダー（\(expected) 列）と一致しません"
            case .noSessionColumns:
                return "実戦履歴として解釈できる列（日時・投資など）が見つかりません"
            }
        }
    }

    // MARK: - 公開型

    struct ParsedSessionRow: Identifiable, Equatable {
        let id: UUID
        /// 元 CSV の行番号（1 始まり、ヘッダー除く）
        let sourceLineNumber: Int
        /// CSV 上の機種名・店名（紐づけ UI 用）
        let csvMachineName: String
        let csvShopName: String
        /// 取り込みに必要な数値・日付は揃っているか
        let canImport: Bool
        let issues: [String]
        /// フル書き出し行か（分析用フィールドをそのまま復元する）
        let isFullExportRow: Bool
        /// パース済みペイロード
        fileprivate let payload: RowPayload
    }

    fileprivate enum RowPayload: Equatable {
        case full(FullRow)
        case sparse(SparseRow)
    }

    fileprivate struct FullRow: Equatable {
        var date: Date
        var inputCash: Int
        var totalHoldings: Int
        var normalRotations: Int
        var totalUsedBalls: Int
        var payoutCoefficient: Double
        var totalRealCost: Double
        var expectationRatioAtSave: Double
        var theoreticalValue: Int
        var rushWinCount: Int
        var normalWinCount: Int
        var formulaBorderPer1k: Double
        var effectiveBorderPer1kAtSave: Double
        var realRotationRateAtSave: Double
        var firstHitRealCostPt: Double?
        var settlementModeRaw: String
        var exchangeCashProceedsPt: Int
        var chodamaBalanceDeltaBalls: Int
        var isCashflowOnlyRecord: Bool
        var editSessionPhasesJSON: String
        var manufacturerName: String
    }

    fileprivate struct SparseRow: Equatable {
        var date: Date
        var inputCash: Int
        /// 回収は玉数。未指定なら `recoveryPt` と店舗の払出係数から算出
        var totalHoldings: Int?
        var recoveryPt: Int?
        var normalRotations: Int
        var totalUsedBalls: Int?
        var rushWinCount: Int
        var normalWinCount: Int
        var manufacturerName: String
        var payoutCoefficientHint: Double?
        var totalRealCost: Double?
        var expectationRatioAtSave: Double?
        var theoreticalValue: Int?
        var formulaBorderPer1k: Double?
    }

    // MARK: - パース

    static func parseSessionsTable(_ csvText: String) throws -> [ParsedSessionRow] {
        let trimmed = csvText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ImportError.emptyFile }
        let table = RFC4180CSV.parseTables(trimmed)
        guard let headerRow = table.first else { throw ImportError.noHeaderRow }
        let headerCount = headerRow.count
        guard headerCount > 0 else { throw ImportError.noSessionColumns }

        let keyToIndex = columnIndexMap(headerRow)
        guard hasMinimumSessionKeys(keyToIndex) else { throw ImportError.noSessionColumns }

        let isFull = looksLikeFullExport(keyToIndex)
        var out: [ParsedSessionRow] = []
        for (i, cells) in table.dropFirst().enumerated() {
            let lineNo = i + 2
            if cells.count != headerCount {
                throw ImportError.columnMismatch(expected: headerCount, row: lineNo)
            }
            var dict: [String: String] = [:]
            for (h, c) in zip(headerRow, cells) {
                dict[normalizeHeaderKey(h).lowercased()] = c
            }
            if isFull, let row = parseFullRow(dict: dict, line: lineNo) {
                out.append(row)
            } else if let row = parseSparse(dict: dict, line: lineNo) {
                out.append(row)
            }
        }
        return out
    }

    // MARK: - 重複検知（安全側の「警告」用途）

    /// 既存データと「ほぼ同一」とみなすための比較キー（厳密一致ではなく、警告用）。
    struct DuplicateKey: Hashable {
        let dateMinute: Int
        let machineName: String
        let shopName: String
        let inputCash: Int
        let totalHoldings: Int
    }

    static func duplicateKey(for row: ParsedSessionRow, selectedMachineName: String, selectedShopName: String, payoutCoefficientForShop: Double) -> DuplicateKey? {
        switch row.payload {
        case .full(let fr):
            let minute = Int(fr.date.timeIntervalSince1970 / 60.0)
            return DuplicateKey(
                dateMinute: minute,
                machineName: normalizeName(selectedMachineName),
                shopName: normalizeName(selectedShopName),
                inputCash: max(0, fr.inputCash),
                totalHoldings: max(0, fr.totalHoldings)
            )
        case .sparse(let sp):
            guard let holdings = resolveHoldings(sp: sp, payoutCoefficientForShop: payoutCoefficientForShop) else { return nil }
            let minute = Int(sp.date.timeIntervalSince1970 / 60.0)
            return DuplicateKey(
                dateMinute: minute,
                machineName: normalizeName(selectedMachineName),
                shopName: normalizeName(selectedShopName),
                inputCash: max(0, sp.inputCash),
                totalHoldings: max(0, holdings)
            )
        }
    }

    static func duplicateKey(for session: GameSession) -> DuplicateKey {
        let minute = Int(session.date.timeIntervalSince1970 / 60.0)
        return DuplicateKey(
            dateMinute: minute,
            machineName: normalizeName(session.machineName),
            shopName: normalizeName(session.shopName),
            inputCash: max(0, session.inputCash),
            totalHoldings: max(0, session.totalHoldings)
        )
    }

    private static func normalizeName(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func resolveHoldings(sp: SparseRow, payoutCoefficientForShop: Double) -> Int? {
        if let balls = sp.totalHoldings { return max(0, balls) }
        if let rpt = sp.recoveryPt, payoutCoefficientForShop > 0 {
            return max(0, Int((Double(rpt) / payoutCoefficientForShop).rounded()))
        }
        return nil
    }

    // MARK: - 紐づけ候補

    static func bestMatchingMachine(csvName: String, machines: [Machine]) -> Machine? {
        let q = csvName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return nil }
        if let ex = machines.first(where: { $0.name == q }) { return ex }
        let ql = q.lowercased()
        let candidates = machines.filter { m in
            let n = m.name
            let nl = n.lowercased()
            return n == q || nl == ql || n.localizedCaseInsensitiveContains(q) || q.localizedCaseInsensitiveContains(n)
        }
        return candidates.sorted { $0.name.count < $1.name.count }.first
    }

    static func bestMatchingShop(csvName: String, shops: [Shop]) -> Shop? {
        let q = csvName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return nil }
        if let ex = shops.first(where: { $0.name == q }) { return ex }
        let ql = q.lowercased()
        let candidates = shops.filter { s in
            let n = s.name
            let nl = n.lowercased()
            return n == q || nl == ql || n.localizedCaseInsensitiveContains(q) || q.localizedCaseInsensitiveContains(n)
        }
        return candidates.sorted { $0.name.count < $1.name.count }.first
    }

    // MARK: - GameSession 生成

    @MainActor
    static func insertSession(
        from row: ParsedSessionRow,
        machine: Machine,
        shop: Shop,
        modelContext: ModelContext
    ) {
        let s: GameSession
        switch row.payload {
        case .full(let fr):
            s = GameSession(
                machineName: machine.name,
                shopName: shop.name,
                manufacturerName: fr.manufacturerName.isEmpty ? machine.manufacturer : fr.manufacturerName,
                inputCash: fr.inputCash,
                totalHoldings: fr.totalHoldings,
                normalRotations: fr.normalRotations,
                totalUsedBalls: fr.totalUsedBalls,
                payoutCoefficient: fr.payoutCoefficient > 0 ? fr.payoutCoefficient : shop.interpretedPayoutCoefficientPtPerBall,
                totalRealCost: fr.totalRealCost,
                expectationRatioAtSave: fr.expectationRatioAtSave,
                rushWinCount: fr.rushWinCount,
                normalWinCount: fr.normalWinCount,
                formulaBorderPer1k: fr.formulaBorderPer1k
            )
            s.date = fr.date
            s.id = UUID()
            s.effectiveBorderPer1kAtSave = fr.effectiveBorderPer1kAtSave
            s.realRotationRateAtSave = fr.realRotationRateAtSave
            s.firstHitRealCostPt = fr.firstHitRealCostPt
            s.settlementModeRaw = fr.settlementModeRaw
            s.exchangeCashProceedsPt = fr.exchangeCashProceedsPt
            s.chodamaBalanceDeltaBalls = fr.chodamaBalanceDeltaBalls
            s.isCashflowOnlyRecord = fr.isCashflowOnlyRecord
            s.editSessionPhasesJSON = fr.editSessionPhasesJSON
            s.theoreticalValue = fr.theoreticalValue
            if fr.payoutCoefficient <= 0 {
                s.payoutCoefficient = shop.interpretedPayoutCoefficientPtPerBall
            }
        case .sparse(let sp):
            let rate = sp.payoutCoefficientHint ?? shop.interpretedPayoutCoefficientPtPerBall
            let tHoldings: Int
            if let balls = sp.totalHoldings {
                tHoldings = balls
            } else if let rpt = sp.recoveryPt, rate > 0 {
                tHoldings = Int((Double(rpt) / rate).rounded())
            } else {
                tHoldings = 0
            }
            let realCost = sp.totalRealCost ?? Double(sp.inputCash)
            let expRatio = sp.expectationRatioAtSave ?? 1.0
            let formula = sp.formulaBorderPer1k ?? parseFormulaBorder(machine.border)
            let usedBalls: Int
            if let u = sp.totalUsedBalls {
                usedBalls = u
            } else {
                let ballsPer1000 = Double(shop.ballsPerCashUnit * 2)
                usedBalls = ballsPer1000 > 0
                    ? Int(Double(sp.inputCash) / 1000.0 * ballsPer1000)
                    : max(0, Int((Double(sp.inputCash) / 1000.0 * 250.0).rounded()))
            }
            s = GameSession(
                machineName: machine.name,
                shopName: shop.name,
                manufacturerName: sp.manufacturerName.isEmpty ? machine.manufacturer : sp.manufacturerName,
                inputCash: sp.inputCash,
                totalHoldings: tHoldings,
                normalRotations: sp.normalRotations,
                totalUsedBalls: max(0, usedBalls),
                payoutCoefficient: rate,
                totalRealCost: realCost,
                expectationRatioAtSave: expRatio,
                rushWinCount: sp.rushWinCount,
                normalWinCount: sp.normalWinCount,
                formulaBorderPer1k: formula > 0 ? formula : 0
            )
            s.date = sp.date
            s.id = UUID()
            s.effectiveBorderPer1kAtSave = 0
            s.realRotationRateAtSave = 0
            s.firstHitRealCostPt = nil
            s.isCashflowOnlyRecord = true
            if let tv = sp.theoreticalValue {
                s.theoreticalValue = tv
            }
        }
        modelContext.insert(s)
    }

    // MARK: - ヘッダー・行デコード

    private static func normalizeHeaderKey(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func columnIndexMap(_ headerRow: [String]) -> [String: Int] {
        var m: [String: Int] = [:]
        for (i, h) in headerRow.enumerated() {
            let k = normalizeHeaderKey(h)
            if m[k] == nil { m[k] = i }
            let lower = k.lowercased()
            if m[lower] == nil { m[lower] = i }
        }
        return m
    }

    private static func cell(_ dict: [String: String], keys: [String]) -> String? {
        for k in keys {
            let lk = k.lowercased()
            if let v = dict[lk], !v.isEmpty { return v }
        }
        return nil
    }

    private static func hasMinimumSessionKeys(_ map: [String: Int]) -> Bool {
        let keys = Set(map.keys.map { $0.lowercased() })
        let hasDate = keys.contains("date_iso8601") || keys.contains("date") || keys.contains("日時")
        let hasInvest = keys.contains("inputcash") || keys.contains("投資")
        return hasDate && hasInvest
    }

    private static func looksLikeFullExport(_ map: [String: Int]) -> Bool {
        let keys = Set(map.keys.map { $0.lowercased() })
        return keys.contains("date_iso8601") && keys.contains("machinename")
            && keys.contains("shopname") && keys.contains("totalrealcost")
            && keys.contains("expectationratioatsave")
    }

    private static func parseFullRow(dict: [String: String], line: Int) -> ParsedSessionRow? {
        guard
            let dateStr = cell(dict, keys: ["date_iso8601", "date", "日時"]),
            let date = parseDate(dateStr),
            let inputCash = Int(cell(dict, keys: ["inputCash", "投資"]) ?? "")
        else {
            return nil
        }
        let mName = cell(dict, keys: ["machineName", "machine", "機種"]) ?? ""
        let sName = cell(dict, keys: ["shopName", "shop", "店舗"]) ?? ""
        let totalHoldings = Int(cell(dict, keys: ["totalHoldings", "回収玉"]) ?? "") ?? 0
        let normalRotations = Int(cell(dict, keys: ["normalRotations", "通常回転", "総回転数"]) ?? "") ?? 0
        let totalUsedBalls = Int(cell(dict, keys: ["totalUsedBalls"]) ?? "") ?? 0
        let payout = Double(cell(dict, keys: ["payoutCoefficient", "払出係数"]) ?? "") ?? 0
        let totalReal = Double(cell(dict, keys: ["totalRealCost"]) ?? "") ?? Double(inputCash)
        let expRatio = Double(cell(dict, keys: ["expectationRatioAtSave"]) ?? "") ?? 0
        let theoretical = Int(cell(dict, keys: ["theoreticalValue", "期待値"]) ?? "") ?? 0
        let rush = Int(cell(dict, keys: ["rushWinCount"]) ?? "") ?? 0
        let normal = Int(cell(dict, keys: ["normalWinCount"]) ?? "") ?? 0
        let formula = Double(cell(dict, keys: ["formulaBorderPer1k"]) ?? "") ?? 0
        let eff = Double(cell(dict, keys: ["effectiveBorderPer1kAtSave"]) ?? "") ?? 0
        let realRate = Double(cell(dict, keys: ["realRotationRateAtSave"]) ?? "") ?? 0
        let firstHitStr = cell(dict, keys: ["firstHitRealCostPt"])
        let firstHit = firstHitStr.flatMap { Double($0) }
        let settlement = cell(dict, keys: ["settlementModeRaw"]) ?? ""
        let exCash = Int(cell(dict, keys: ["exchangeCashProceedsPt"]) ?? "") ?? 0
        let cho = Int(cell(dict, keys: ["chodamaBalanceDeltaBalls"]) ?? "") ?? 0
        let cashOnly = (cell(dict, keys: ["isCashflowOnlyRecord"]) ?? "").trimmingCharacters(in: .whitespaces).lowercased()
        let isCashOnly = cashOnly == "1" || cashOnly == "true" || cashOnly == "yes"
        let phases = cell(dict, keys: ["editSessionPhasesJSON"]) ?? ""
        let mfr = cell(dict, keys: ["manufacturerName", "メーカー"]) ?? ""

        let fr = FullRow(
            date: date,
            inputCash: inputCash,
            totalHoldings: totalHoldings,
            normalRotations: normalRotations,
            totalUsedBalls: totalUsedBalls,
            payoutCoefficient: payout,
            totalRealCost: totalReal,
            expectationRatioAtSave: expRatio,
            theoreticalValue: theoretical,
            rushWinCount: rush,
            normalWinCount: normal,
            formulaBorderPer1k: formula,
            effectiveBorderPer1kAtSave: eff,
            realRotationRateAtSave: realRate,
            firstHitRealCostPt: firstHit,
            settlementModeRaw: settlement,
            exchangeCashProceedsPt: exCash,
            chodamaBalanceDeltaBalls: cho,
            isCashflowOnlyRecord: isCashOnly,
            editSessionPhasesJSON: phases,
            manufacturerName: mfr
        )
        return ParsedSessionRow(
            id: UUID(),
            sourceLineNumber: line,
            csvMachineName: mName,
            csvShopName: sName,
            canImport: true,
            issues: [],
            isFullExportRow: true,
            payload: .full(fr)
        )
    }

    private static func parseSparse(dict: [String: String], line: Int) -> ParsedSessionRow? {
        var issues: [String] = []
        guard let dateStr = cell(dict, keys: ["date_iso8601", "date", "日時"]) else {
            return nil
        }
        let mName = cell(dict, keys: ["machinename", "machine", "機種"]) ?? ""
        let sName = cell(dict, keys: ["shopname", "shop", "店舗"]) ?? ""
        guard let date = parseDate(dateStr) else {
            issues.append("日時を解釈できません")
            return ParsedSessionRow(
                id: UUID(),
                sourceLineNumber: line,
                csvMachineName: mName,
                csvShopName: sName,
                canImport: false,
                issues: issues,
                isFullExportRow: false,
                payload: .sparse(
                    SparseRow(
                        date: Date(),
                        inputCash: 0,
                        totalHoldings: nil,
                        recoveryPt: nil,
                        normalRotations: 0,
                        totalUsedBalls: nil,
                        rushWinCount: 0,
                        normalWinCount: 0,
                        manufacturerName: "",
                        payoutCoefficientHint: nil,
                        totalRealCost: nil,
                        expectationRatioAtSave: nil,
                        theoreticalValue: nil,
                        formulaBorderPer1k: nil
                    )
                )
            )
        }
        guard let invStr = cell(dict, keys: ["inputcash", "投資", "investment"]),
              let inv0 = Int(invStr) else {
            issues.append("投資（inputCash）がありません")
            let sp = SparseRow(
                date: date,
                inputCash: 0,
                totalHoldings: nil,
                recoveryPt: nil,
                normalRotations: 0,
                totalUsedBalls: nil,
                rushWinCount: 0,
                normalWinCount: 0,
                manufacturerName: "",
                payoutCoefficientHint: nil,
                totalRealCost: nil,
                expectationRatioAtSave: nil,
                theoreticalValue: nil,
                formulaBorderPer1k: nil
            )
            return ParsedSessionRow(
                id: UUID(),
                sourceLineNumber: line,
                csvMachineName: mName,
                csvShopName: sName,
                canImport: false,
                issues: issues,
                isFullExportRow: false,
                payload: .sparse(sp)
            )
        }
        let inv = max(0, inv0)
        if inv0 < 0 { issues.append("投資が負数です（0として扱います）") }
        let totalHoldings = cell(dict, keys: ["totalholdings", "回収玉", "balls"]).flatMap { Int($0) }
        let recoveryPt = cell(dict, keys: ["recovery_pt", "recoverypt", "回収pt"]).flatMap { Int($0) }
        let hasRecovery = totalHoldings != nil || recoveryPt != nil
        if !hasRecovery {
            issues.append("回収（totalHoldings または recovery_pt）のどちらかが必要です")
        }
        let rot = cell(dict, keys: ["normalrotations", "通常回転"]).flatMap { Int($0) } ?? 0
        if rot < 0 { issues.append("通常回転が負数です（0として扱います）") }
        let used = cell(dict, keys: ["totalusedballs"]).flatMap { Int($0) }
        let rush = cell(dict, keys: ["rushwincount", "rush", "rush当選"]).flatMap { Int($0) } ?? 0
        let normal = cell(dict, keys: ["normalwincount", "normal", "通常当選"]).flatMap { Int($0) } ?? 0
        let winTotal = cell(dict, keys: ["wincount", "当選回数", "大当たり"]).flatMap { Int($0) }
        let nWin: Int
        if let wt = winTotal {
            nWin = max(0, wt - rush)
        } else {
            nWin = normal
        }
        let mfr = cell(dict, keys: ["manufacturername", "メーカー"]) ?? ""
        let payoutHint = cell(dict, keys: ["payoutcoefficient"]).flatMap { Double($0) }
        let totalReal = cell(dict, keys: ["totalrealcost"]).flatMap { Double($0) }
        let expR = cell(dict, keys: ["expectationratioatsave"]).flatMap { Double($0) }
        let theo = cell(dict, keys: ["theoreticalvalue", "期待値"]).flatMap { Int($0) }
        let formula = cell(dict, keys: ["formulaborderper1k"]).flatMap { Double($0) }

        let sp = SparseRow(
            date: date,
            inputCash: inv,
            totalHoldings: totalHoldings,
            recoveryPt: recoveryPt,
            normalRotations: max(0, rot),
            totalUsedBalls: used,
            rushWinCount: rush,
            normalWinCount: nWin,
            manufacturerName: mfr,
            payoutCoefficientHint: payoutHint,
            totalRealCost: totalReal,
            expectationRatioAtSave: expR,
            theoreticalValue: theo,
            formulaBorderPer1k: formula
        )
        let ok = hasRecovery
        if mName.isEmpty && sName.isEmpty {
            issues.append("機種名・店名が空です。取り込み時に紐づけを選んでください")
        }
        return ParsedSessionRow(
            id: UUID(),
            sourceLineNumber: line,
            csvMachineName: mName,
            csvShopName: sName,
            canImport: ok,
            issues: issues,
            isFullExportRow: false,
            payload: .sparse(sp)
        )
    }

    private static func parseDate(_ raw: String) -> Date? {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.isEmpty { return nil }
        let isoFrac = ISO8601DateFormatter()
        isoFrac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = isoFrac.date(from: s) { return d }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        if let d = iso.date(from: s) { return d }
        let df = DateFormatter()
        df.calendar = Calendar(identifier: .gregorian)
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone.current
        df.dateFormat = "yyyy-MM-dd HH:mm:ss"
        if let d = df.date(from: s) { return d }
        df.dateFormat = "yyyy-MM-dd"
        return df.date(from: s)
    }

    private static func parseFormulaBorder(_ borderStr: String) -> Double {
        let s = borderStr.trimmingCharacters(in: .whitespaces)
        if let v = Double(s), v > 0 { return v }
        let numStr = s.filter { $0.isNumber || $0 == "." }
        if !numStr.isEmpty, let v = Double(numStr), v > 0 { return v }
        return 0
    }
}

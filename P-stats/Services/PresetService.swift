import Foundation

/// 機種マスターデータ1件（正確な機種名とメーカー。管理人のみがリストを更新）
struct MachineMasterItem: Codable, Identifiable {
    var name: String
    var manufacturer: String?
    var id: String { "\(name)#\(manufacturer ?? "")" }
}

/// 管理人用マスターデータ1件（サーバーJSONまたはスプレッドシートCSV）。管理人だけが編集し、ユーザーは参照のみ。
struct PresetFromServer: Codable {
    var name: String
    var machineTypeRaw: String?
    var supportLimit: Int?
    /// 通常大当たり後の時短ゲーム数（マスターデータ）
    var timeShortRotations: Int?
    var defaultPrize: Int?
    var probability: String?
    var border: String?
    var prizeEntries: [PrizeEntryFromServer]?
    /// 実質ボーダー用（任意）
    var entryRate: Double?
    var continuationRate: Double?
    var countPerRound: Int?
    var netPerRoundBase: Double?
    var manufacturer: String?
    /// P-Sync/スプレッドシート用：特図1内訳（通常時）。CSVの「特図1内訳」列から設定。
    var heso_prizes: String?
    /// P-Sync/スプレッドシート用：特図2内訳（RUSH時）。CSVの「特図2内訳」列から設定。
    var denchu_prizes: String?
    /// 導入日（表示・ソート用）。CSVの「導入日」列。"2024-03-01" 形式など。新しい順で並べるときに使用。
    var introductionDateRaw: String?
    /// LT有無。CSVの「LT有無」列。"あり" のとき RUSH/LT パネルを分けて表示する。
    var ltRaw: String?
    /// DMMぱちタウン用機種ID。p-town.dmm.com/machines/{machineId} の {machineId} に使用。CSVの「機種ID」「machine_id」等。
    var machineId: String?

    enum CodingKeys: String, CodingKey {
        case name, machineTypeRaw, supportLimit, timeShortRotations, defaultPrize, probability, border
        case prizeEntries, entryRate, continuationRate, countPerRound, netPerRoundBase, manufacturer
        case heso_prizes, denchu_prizes, introductionDateRaw, ltRaw
        case machineId = "machineId"
        case machineIdSnake = "machine_id"
        case machineID = "machineID"
        case machineIdJapanese = "機種ID"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        machineTypeRaw = try c.decodeIfPresent(String.self, forKey: .machineTypeRaw)
        supportLimit = try c.decodeIfPresent(Int.self, forKey: .supportLimit)
        timeShortRotations = try c.decodeIfPresent(Int.self, forKey: .timeShortRotations)
        defaultPrize = try c.decodeIfPresent(Int.self, forKey: .defaultPrize)
        probability = try c.decodeIfPresent(String.self, forKey: .probability)
        border = try c.decodeIfPresent(String.self, forKey: .border)
        prizeEntries = try c.decodeIfPresent([PrizeEntryFromServer].self, forKey: .prizeEntries)
        entryRate = try c.decodeIfPresent(Double.self, forKey: .entryRate)
        continuationRate = try c.decodeIfPresent(Double.self, forKey: .continuationRate)
        countPerRound = try c.decodeIfPresent(Int.self, forKey: .countPerRound)
        netPerRoundBase = try c.decodeIfPresent(Double.self, forKey: .netPerRoundBase)
        manufacturer = try c.decodeIfPresent(String.self, forKey: .manufacturer)
        heso_prizes = try c.decodeIfPresent(String.self, forKey: .heso_prizes)
        denchu_prizes = try c.decodeIfPresent(String.self, forKey: .denchu_prizes)
        introductionDateRaw = try c.decodeIfPresent(String.self, forKey: .introductionDateRaw)
        ltRaw = try c.decodeIfPresent(String.self, forKey: .ltRaw)
        func decodeMachineId(_ key: CodingKeys) -> String? {
            (try? c.decodeIfPresent(String.self, forKey: key))
                ?? (try? c.decodeIfPresent(Int.self, forKey: key)).map { String($0) }
        }
        machineId = decodeMachineId(.machineId)
            ?? decodeMachineId(.machineIdSnake)
            ?? decodeMachineId(.machineID)
            ?? decodeMachineId(.machineIdJapanese)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(name, forKey: .name)
        try c.encodeIfPresent(machineTypeRaw, forKey: .machineTypeRaw)
        try c.encodeIfPresent(supportLimit, forKey: .supportLimit)
        try c.encodeIfPresent(timeShortRotations, forKey: .timeShortRotations)
        try c.encodeIfPresent(defaultPrize, forKey: .defaultPrize)
        try c.encodeIfPresent(probability, forKey: .probability)
        try c.encodeIfPresent(border, forKey: .border)
        try c.encodeIfPresent(prizeEntries, forKey: .prizeEntries)
        try c.encodeIfPresent(entryRate, forKey: .entryRate)
        try c.encodeIfPresent(continuationRate, forKey: .continuationRate)
        try c.encodeIfPresent(countPerRound, forKey: .countPerRound)
        try c.encodeIfPresent(netPerRoundBase, forKey: .netPerRoundBase)
        try c.encodeIfPresent(manufacturer, forKey: .manufacturer)
        try c.encodeIfPresent(heso_prizes, forKey: .heso_prizes)
        try c.encodeIfPresent(denchu_prizes, forKey: .denchu_prizes)
        try c.encodeIfPresent(introductionDateRaw, forKey: .introductionDateRaw)
        try c.encodeIfPresent(ltRaw, forKey: .ltRaw)
        try c.encodeIfPresent(machineId, forKey: .machineId)
    }

    /// CSVパース等で手動構築する用（CodingKeys 使用時は自動の memberwise init がなくなるため）。Task.detached から呼ぶため nonisolated。
    nonisolated init(name: String, machineTypeRaw: String?, supportLimit: Int?, timeShortRotations: Int?, defaultPrize: Int?, probability: String?, border: String?, prizeEntries: [PrizeEntryFromServer]?, entryRate: Double?, continuationRate: Double?, countPerRound: Int?, netPerRoundBase: Double?, manufacturer: String?, heso_prizes: String?, denchu_prizes: String?, introductionDateRaw: String?, ltRaw: String?, machineId: String?) {
        self.name = name
        self.machineTypeRaw = machineTypeRaw
        self.supportLimit = supportLimit
        self.timeShortRotations = timeShortRotations
        self.defaultPrize = defaultPrize
        self.probability = probability
        self.border = border
        self.prizeEntries = prizeEntries
        self.entryRate = entryRate
        self.continuationRate = continuationRate
        self.countPerRound = countPerRound
        self.netPerRoundBase = netPerRoundBase
        self.manufacturer = manufacturer
        self.heso_prizes = heso_prizes
        self.denchu_prizes = denchu_prizes
        self.introductionDateRaw = introductionDateRaw
        self.ltRaw = ltRaw
        self.machineId = machineId
    }

    struct PrizeEntryFromServer: Codable {
        var label: String?
        var rounds: Int
        var balls: Int
    }
}

/// マスタ一覧を参照で渡すためのホルダー。Task.detached でコピーせず渡し、メインスレッドのブロックを防ぐ。
final class PresetListHolder: @unchecked Sendable {
    let items: [PresetFromServer]
    init(_ items: [PresetFromServer]) { self.items = items }
}

enum PresetService {
    /// バンドル内 MachinesMaster.json を読み込み。同梱マスター用（PresetFromServer 形式）。
    static func loadBundleMaster() -> [PresetFromServer] {
        guard let url = Bundle.main.url(forResource: "MachinesMaster", withExtension: "json") else { return [] }
        do {
            let data = try Data(contentsOf: url)
            return (try JSONDecoder().decode([PresetFromServer].self, from: data))
        } catch {
            return []
        }
    }

    /// バンドル分とURL取得分をマージ。同名は先に出た方を採用（バンドル優先）。
    static func mergeBundleAndServer(bundle: [PresetFromServer], server: [PresetFromServer]?) -> [PresetFromServer] {
        var result = bundle
        let bundleNames = Set(bundle.map(\.name))
        for s in server ?? [] {
            if !bundleNames.contains(s.name) { result.append(s) }
        }
        return result
    }

    /// 機種マスタURLから [機種名, メーカー] 一覧を取得。JSON: [{ "name": "", "manufacturer": "" }, ...]
    static func fetchMachineMaster(from urlString: String) async -> [MachineMasterItem]? {
        guard !urlString.isEmpty, let url = URL(string: urlString) else { return nil }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            return try JSONDecoder().decode([MachineMasterItem].self, from: data)
        } catch {
            return nil
        }
    }

    /// 指定URLからプリセット一覧を取得。Googleスプレッドシート（CSVエクスポート）またはJSON。失敗時は nil。15秒でタイムアウト。
    static func fetchPresets(from urlString: String) async -> [PresetFromServer]? {
        guard !urlString.isEmpty, let url = URL(string: urlString) else {
            print("[PresetService] fetchPresets: URLが空または不正です")
            return nil
        }
        do {
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = 15
            config.timeoutIntervalForResource = 20
            config.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
            var request = URLRequest(url: url)
            request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
            let (data, _) = try await URLSession(configuration: config).data(for: request)
            let isCSV = isSpreadsheetCSVURL(urlString)
            let list: [PresetFromServer]? = await Task.detached(priority: .userInitiated) {
                if isCSV {
                    return parsePresetsFromCSV(data: data)
                }
                return try? JSONDecoder().decode([PresetFromServer].self, from: data)
            }.value
            guard let list = list else {
                print("[PresetService] fetchPresets: パース失敗")
                return nil
            }
            print("[PresetService] fetchPresets: 取得成功 \(list.count) 件")
            return list
        } catch {
            print("[PresetService] fetchPresets 失敗: \(error)")
            return nil
        }
    }

    /// GoogleスプレッドシートのCSVエクスポートURLかどうか
    private static func isSpreadsheetCSVURL(_ urlString: String) -> Bool {
        urlString.contains("docs.google.com/spreadsheets") && urlString.contains("export")
    }

    /// CSVデータをパースして [PresetFromServer] に変換。1行目をヘッダーとして列名でマッピング。Task.detached から呼ぶため nonisolated。
    private static nonisolated func parsePresetsFromCSV(data: Data) -> [PresetFromServer]? {
        guard var raw = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .utf16) else { return nil }
        if raw.hasPrefix("\u{FEFF}") { raw = String(raw.dropFirst()) }
        let lines = raw.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard lines.count >= 2 else { return [] }
        let headers = parseCSVLine(lines[0])
        guard !headers.isEmpty else { return [] }
        let headerMap: [String: Int] = Dictionary(uniqueKeysWithValues: headers.enumerated().map { (headers[$0.offset].trimmingCharacters(in: .whitespaces), $0.offset) })
        func col(_ names: [String]) -> Int? {
            for n in names {
                if let i = headerMap[n] { return i }
                let lower = n.lowercased()
                if let (k, _) = headerMap.first(where: { $0.key.lowercased() == lower }) { return headerMap[k] }
            }
            return nil
        }
        var list: [PresetFromServer] = []
        for lineIndex in 1..<lines.count {
            let values = parseCSVLine(lines[lineIndex])
            guard !values.isEmpty else { continue }
            func v(_ names: String...) -> String {
                guard let i = col(Array(names)), i < values.count else { return "" }
                return values[i].trimmingCharacters(in: .whitespaces)
            }
            let name = v("機種名", "名前", "name", "機種")
            if name.isEmpty { continue }
            let probability = v("確率", "大当り確率", "probability")
            let manufacturer = v("メーカー", "manufacturer")
            let heso = v("特図1内訳", "heso_prizes")
            let denchu = v("特図2内訳", "denchu_prizes")
            let border = v("ボーダー", "border")
            let countPerRoundStr = v("賞球数", "countPerRound", "カウント数")
            let countPerRound = Int(countPerRoundStr) ?? 10
            let mtRaw = v("機種タイプ", "machineTypeRaw", "ST/確変")
            let machineTypeRaw = mtRaw.isEmpty ? nil : mtRaw
            let supportStr = v("電サポ", "supportLimit")
            let supportLimit = Int(supportStr) ?? 0
            let timeShortStr = v("時短", "timeShortRotations")
            let timeShortRotations = Int(timeShortStr) ?? 0
            let defaultPrizeStr = v("デフォルト出玉", "defaultPrize")
            let defaultPrize = Int(defaultPrizeStr) ?? 1500
            let introDate = v("導入日", "introductionDate", "導入日付")
            let ltYn = v("LT有無", "LT")
            let machineIdStr = v("機種ID", "machine_id", "machineId", "DMM機種ID", "dmm_id")
            list.append(PresetFromServer(
                name: name,
                machineTypeRaw: machineTypeRaw?.isEmpty == false ? machineTypeRaw : nil,
                supportLimit: supportLimit,
                timeShortRotations: timeShortRotations,
                defaultPrize: defaultPrize,
                probability: probability.isEmpty ? nil : probability,
                border: border.isEmpty ? nil : border,
                prizeEntries: nil,
                entryRate: nil,
                continuationRate: nil,
                countPerRound: countPerRound,
                netPerRoundBase: nil,
                manufacturer: manufacturer.isEmpty ? nil : manufacturer,
                heso_prizes: heso.isEmpty ? nil : heso,
                denchu_prizes: denchu.isEmpty ? nil : denchu,
                introductionDateRaw: introDate.isEmpty ? nil : introDate,
                ltRaw: ltYn.isEmpty ? nil : ltYn,
                machineId: machineIdStr.isEmpty ? nil : machineIdStr
            ))
        }
        return list
    }

    /// 1行をCSVとしてパース（ダブルクォート内のカンマは無視）。parsePresetsFromCSV から呼ぶため nonisolated。
    private static nonisolated func parseCSVLine(_ line: String) -> [String] {
        var result: [String] = []
        var current = ""
        var inQuotes = false
        for ch in line {
            if ch == "\"" {
                inQuotes.toggle()
            } else if (ch == "," && !inQuotes) {
                result.append(current)
                current = ""
            } else {
                current.append(ch)
            }
        }
        result.append(current)
        return result
    }

    /// サーバー用プリセットの1Rあたり平均純増
    static func averageNetPerRound(_ s: PresetFromServer) -> Double {
        guard let entries = s.prizeEntries, !entries.isEmpty else {
            let prize = Double(s.defaultPrize ?? 1500)
            return prize / 10.0
        }
        let totalBalls = entries.reduce(0) { $0 + $1.balls }
        let totalRounds = entries.reduce(0) { $0 + $1.rounds }
        return totalRounds > 0 ? Double(totalBalls) / Double(totalRounds) : 0
    }
}

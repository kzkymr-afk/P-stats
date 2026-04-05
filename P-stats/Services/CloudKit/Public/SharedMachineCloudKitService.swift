import Foundation
import CloudKit

// MARK: - セットアップ
// Xcode: ターゲット → Signing & Capabilities → + Capability → iCloud を追加し、
// 「CloudKit」にチェック、使用するコンテナ（例: iCloud.$(CFBundleIdentifier)）を指定。
// CloudKit Dashboard で Public Database にレコードタイプ "SharedMachine" を作成し、
// フィールド name(String), manufacturer(String), machineTypeRaw(String), supportLimit(Int),
// timeShortRotations(Int), defaultPrize(Int), probability(String), border(String),
// entryRate(Double), continuationRate(Double), countPerRound(Int), netPerRoundBase(Double),
// prizeEntriesJSON(String), sharedAt(Date/Time) を追加する。

// MARK: - Public Database 境界（共有マスタ専用）

/// **CloudKit Public Database へのアクセスはこの型経由に限定する。**
/// `privateCloudDatabase` はここでは使用しない（個人の実戦データは `UserSessionSyncService`）。
private enum SharedMachinePublicCloudDatabaseGateway {
    static var database: CKDatabase {
        CKContainer.default().publicCloudDatabase
    }
}

/// CloudKit Public Database に保存される「ユーザー共有機種」1件。
/// 検索結果で PresetFromServer と同様に扱い、マイリスト追加時に Machine に変換する。
///
/// - Important: 実戦の店舗名・収支・メモ等の個人データはこの型では扱わない。
///   誤って Public に送らないよう、ペイロードは機種スペックのみとする。
struct SharedMachineFromCloud: Identifiable {
    let id: String
    var name: String
    var machineTypeRaw: String?
    var supportLimit: Int?
    var timeShortRotations: Int?
    var defaultPrize: Int?
    var probability: String?
    var border: String?
    var prizeEntries: [PresetFromServer.PrizeEntryFromServer]?
    var entryRate: Double?
    var continuationRate: Double?
    var countPerRound: Int?
    var netPerRoundBase: Double?
    var manufacturer: String?
    /// 共有日時（表示用）
    var sharedAt: Date?

    /// PresetFromServer と互換の形にして PresetService.averageNetPerRound や addToMyList で流用
    var asPresetFromServer: PresetFromServer {
        PresetFromServer(
            name: name,
            machineTypeRaw: machineTypeRaw,
            supportLimit: supportLimit,
            timeShortRotations: timeShortRotations,
            defaultPrize: defaultPrize,
            probability: probability,
            border: border,
            prizeEntries: prizeEntries,
            entryRate: entryRate,
            continuationRate: continuationRate,
            countPerRound: countPerRound,
            netPerRoundBase: netPerRoundBase,
            manufacturer: manufacturer,
            hesoAtari: nil,
            denchu_prizes: nil,
            introductionDateRaw: nil,
            machineId: nil
        )
    }
}

private let recordType = "SharedMachine"
private let keyName = "name"
private let keyManufacturer = "manufacturer"
private let keyMachineTypeRaw = "machineTypeRaw"
private let keySupportLimit = "supportLimit"
private let keyTimeShortRotations = "timeShortRotations"
private let keyDefaultPrize = "defaultPrize"
private let keyProbability = "probability"
private let keyBorder = "border"
private let keyEntryRate = "entryRate"
private let keyContinuationRate = "continuationRate"
private let keyCountPerRound = "countPerRound"
private let keyNetPerRoundBase = "netPerRoundBase"
private let keyPrizeEntriesJSON = "prizeEntriesJSON"
private let keySharedAt = "sharedAt"

/// みんなで共有する**機種マスタ**の CloudKit 経路。`publicCloudDatabase` のみ使用。
///
/// - Warning: `GameSession`・`GameLog`・店舗の実名・収支は **絶対に** このサービスから送らないこと。
enum SharedMachineCloudKitService {

    /// Public DB のみ（`privateCloudDatabase` への参照は持たない）
    private static var publicDatabase: CKDatabase {
        SharedMachinePublicCloudDatabaseGateway.database
    }

    /// 機種データを CloudKit Public Database に保存する。失敗時は throw（呼び出し元でログのみでも可）
    static func saveToCloud(
        name: String,
        manufacturer: String,
        machineTypeRaw: String,
        supportLimit: Int,
        timeShortRotations: Int,
        defaultPrize: Int,
        probability: String,
        border: String,
        entryRate: Double,
        continuationRate: Double,
        countPerRound: Int,
        netPerRoundBase: Double,
        prizeEntries: [(label: String, balls: Int)]
    ) async throws {
        let record = CKRecord(recordType: recordType)
        record[keyName] = name
        record[keyManufacturer] = manufacturer.isEmpty ? nil : manufacturer
        record[keyMachineTypeRaw] = machineTypeRaw
        record[keySupportLimit] = supportLimit
        record[keyTimeShortRotations] = timeShortRotations
        record[keyDefaultPrize] = defaultPrize
        record[keyProbability] = probability.isEmpty ? nil : probability
        record[keyBorder] = border.isEmpty ? nil : border
        record[keyEntryRate] = entryRate
        record[keyContinuationRate] = continuationRate
        record[keyCountPerRound] = countPerRound
        record[keyNetPerRoundBase] = netPerRoundBase
        record[keySharedAt] = Date()

        struct PrizeEntryEncode: Encodable {
            let label: String
            let balls: Int
        }
        let entriesData = prizeEntries.map { PrizeEntryEncode(label: $0.label, balls: $0.balls) }
        if let jsonData = try? JSONEncoder().encode(entriesData),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            record[keyPrizeEntriesJSON] = jsonString
        }

        _ = try await publicDatabase.save(record)
    }

    /// CloudKit からユーザー共有機種を取得。searchText が空でなければ name / manufacturer で CONTAINS 検索（大文字小文字無視はアプリ側でフィルタ）。
    static func fetchSharedMachines(searchText: String?) async -> [SharedMachineFromCloud] {
        let predicate: NSPredicate
        if let key = searchText?.trimmingCharacters(in: .whitespaces), !key.isEmpty {
            predicate = NSPredicate(format: "name CONTAINS[c] %@ OR manufacturer CONTAINS[c] %@", key, key)
        } else {
            predicate = NSPredicate(value: true)
        }
        let query = CKQuery(recordType: recordType, predicate: predicate)
        query.sortDescriptors = [NSSortDescriptor(key: keySharedAt, ascending: false)]

        do {
            let (results, _) = try await publicDatabase.records(matching: query, resultsLimit: 100)
            return results.compactMap { _, result -> SharedMachineFromCloud? in
                guard case .success(let record) = result else { return nil }
                return parseRecord(record)
            }
        } catch {
            return []
        }
    }

    private static func parseRecord(_ record: CKRecord) -> SharedMachineFromCloud? {
        guard let name = record[keyName] as? String else { return nil }
        let id = record.recordID.recordName
        var prizeEntries: [PresetFromServer.PrizeEntryFromServer]?
        if let jsonString = record[keyPrizeEntriesJSON] as? String,
           let data = jsonString.data(using: .utf8) {
            struct PrizeEntryDecode: Decodable {
                let label: String?
                let balls: Int
                var rounds: Int? = nil  // 後方互換で読み捨て（デコード時は上書き可能にするため var）
            }
            if let decoded = try? JSONDecoder().decode([PrizeEntryDecode].self, from: data) {
                prizeEntries = decoded.map { PresetFromServer.PrizeEntryFromServer(label: $0.label, balls: $0.balls) }
            }
        }
        return SharedMachineFromCloud(
            id: id,
            name: name,
            machineTypeRaw: record[keyMachineTypeRaw] as? String,
            supportLimit: record[keySupportLimit] as? Int,
            timeShortRotations: record[keyTimeShortRotations] as? Int,
            defaultPrize: record[keyDefaultPrize] as? Int,
            probability: record[keyProbability] as? String,
            border: record[keyBorder] as? String,
            prizeEntries: prizeEntries,
            entryRate: record[keyEntryRate] as? Double,
            continuationRate: record[keyContinuationRate] as? Double,
            countPerRound: record[keyCountPerRound] as? Int,
            netPerRoundBase: record[keyNetPerRoundBase] as? Double,
            manufacturer: record[keyManufacturer] as? String,
            sharedAt: record[keySharedAt] as? Date
        )
    }
}

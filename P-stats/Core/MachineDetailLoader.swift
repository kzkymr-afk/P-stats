import Foundation

/// index.json と machines/[id].json を取得し、新マスターJSON（MachineFullMaster）を返す。
/// 旧形式（MachineDetail）も読み取り、MachineFullMaster に変換して返す。
/// 既存の PresetService / machines.json はそのまま。こちらは「モード・当たり詳細」専用。
enum MachineDetailLoader {
    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        return d
    }()

    private static let session: URLSession = {
        let c = URLSessionConfiguration.default
        c.timeoutIntervalForRequest = 15
        c.timeoutIntervalForResource = 20
        return URLSession(configuration: c)
    }()

    /// ファイル名に使えない文字を除去した machine_id。
    static func sanitizeMachineId(_ machineId: String) -> String {
        var s = machineId.trimmingCharacters(in: .whitespaces)
        let bad = CharacterSet(charactersIn: "/\\:*?\"<>|")
        s = s.unicodeScalars.map { bad.contains($0) ? "-" : Character($0) }.map(String.init).joined()
        s = s.replacingOccurrences(of: " ", with: "_")
        s = s.trimmingCharacters(in: CharacterSet(charactersIn: "._ "))
        return s.isEmpty ? "unknown" : s
    }

    /// ベースURL（末尾スラッシュなし）から index.json の URL を組み立てる。
    static func indexURL(baseURL: String) -> URL? {
        let base = baseURL.trimmingCharacters(in: .whitespaces)
        guard !base.isEmpty else { return nil }
        let path = base.hasSuffix("/") ? base + "index.json" : base + "/index.json"
        return URL(string: path)
    }

    /// ベースURL と machine_id から machines/[id].json の URL を組み立てる。
    static func machineDetailURL(baseURL: String, machineId: String) -> URL? {
        let base = baseURL.trimmingCharacters(in: .whitespaces)
        guard !base.isEmpty else { return nil }
        let safe = sanitizeMachineId(machineId)
        let path = base.hasSuffix("/") ? base + "machines/\(safe).json" : base + "/machines/\(safe).json"
        return URL(string: path)
    }

    /// index.json を取得し、機種一覧にデコードする。失敗時は nil。ネット失敗時はバンドル内 index.json があればそれを返す。
    static func fetchIndex(baseURL: String? = nil) async -> [MachineMasterIndexEntry]? {
        let base = baseURL?.trimmingCharacters(in: .whitespaces).isEmpty == false
            ? baseURL!
            : PresetServiceConfig.defaultMachineDetailBaseURL
        if let url = indexURL(baseURL: base) {
            do {
                let (data, _) = try await session.data(from: url)
                let list = try decoder.decode([MachineMasterIndexEntry].self, from: data)
                print("[MachineDetailLoader] fetchIndex: \(list.count) 件")
                return list
            } catch {
                print("[MachineDetailLoader] fetchIndex 失敗: \(error)")
            }
        }
        if let data = Bundle.main.url(forResource: "index", withExtension: "json", subdirectory: "master_out")
            .flatMap({ try? Data(contentsOf: $0) }) {
            if let list = try? decoder.decode([MachineMasterIndexEntry].self, from: data) {
                print("[MachineDetailLoader] fetchIndex: バンドルから \(list.count) 件")
                return list
            }
        }
        return nil
    }

    /// 指定した machine_id の machines/[id].json を取得し、MachineFullMaster にデコードする。
    /// 旧形式（MachineDetail）の場合も読み取り、MachineFullMaster に変換して返す。
    /// 失敗時は nil。ネット失敗時はバンドル内があればそれを返す。
    static func fetchMachineDetail(machineId: String, baseURL: String? = nil) async -> MachineFullMaster? {
        let base = baseURL?.trimmingCharacters(in: .whitespaces).isEmpty == false
            ? baseURL!
            : PresetServiceConfig.defaultMachineDetailBaseURL
        let safe = sanitizeMachineId(machineId)
        if let url = machineDetailURL(baseURL: base, machineId: machineId) {
            do {
                let (data, _) = try await session.data(from: url)
                if let master = try? decoder.decode(MachineFullMaster.self, from: data) {
                    return master
                }
                let legacy = try decoder.decode(MachineDetail.self, from: data)
                return MachineFullMaster.fromLegacy(legacy)
            } catch {
                print("[MachineDetailLoader] fetchMachineDetail 失敗 machineId=\(machineId): \(error)")
            }
        }
        if let url = Bundle.main.url(forResource: safe, withExtension: "json", subdirectory: "master_out/machines"),
           let data = try? Data(contentsOf: url),
           let master = (try? decoder.decode(MachineFullMaster.self, from: data))
            ?? (try? decoder.decode(MachineDetail.self, from: data)).map(MachineFullMaster.fromLegacy) {
            print("[MachineDetailLoader] fetchMachineDetail: バンドルから machineId=\(machineId)")
            return master
        }
        return nil
    }

    /// 機種ID または機種名から MachineFullMaster を取得する。masterID が空でも機種名で index を検索して取得を試みる。
    /// - Parameters:
    ///   - machineId: 機種ID（DMM機種IDや master_out の machine_id）。空の場合は機種名で検索。
    ///   - machineName: 機種名。IDで取得できない場合に index.json から同名を探して取得する。
    ///   - baseURL: 取得元ベースURL。nil の場合は PresetServiceConfig.defaultMachineDetailBaseURL を使用。
    /// - Returns: 取得した MachineFullMaster。取得できない場合は nil。
    static func fetchMachineDetail(machineId: String?, machineName: String?, baseURL: String? = nil) async -> MachineFullMaster? {
        let base = baseURL?.trimmingCharacters(in: .whitespaces).isEmpty == false
            ? baseURL!
            : PresetServiceConfig.defaultMachineDetailBaseURL
        let idTrimmed = machineId?.trimmingCharacters(in: .whitespaces) ?? ""
        if !idTrimmed.isEmpty {
            if let detail = await fetchMachineDetail(machineId: idTrimmed, baseURL: base) {
                return detail
            }
        }
        let nameTrimmed = machineName?.trimmingCharacters(in: .whitespaces) ?? ""
        guard !nameTrimmed.isEmpty else { return nil }
        guard let indexList = await fetchIndex(baseURL: base) else { return nil }
        let match = indexList.first { entry in
            entry.name.trimmingCharacters(in: .whitespaces) == nameTrimmed
        }
        ?? indexList.first { entry in
            entry.name.trimmingCharacters(in: .whitespaces).contains(nameTrimmed)
                || nameTrimmed.contains(entry.name.trimmingCharacters(in: .whitespaces))
        }
        guard let entry = match else {
            print("[MachineDetailLoader] 機種名で index に一致なし: \(nameTrimmed)")
            return nil
        }
        print("[MachineDetailLoader] 機種名で解決: \(nameTrimmed) -> machineId=\(entry.machineId)")
        return await fetchMachineDetail(machineId: entry.machineId, baseURL: base)
    }
}

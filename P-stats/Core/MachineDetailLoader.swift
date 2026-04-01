import Foundation
import os

/// `index.json` と `machines/{id}.json`（MachineFullMaster）を取得する。本番は GitHub Pages（`defaultMachineDetailBaseURL`）。バンドル内 `master_out` は任意のオフライン用。
enum MachineDetailLoader {
    private static let decoder = JSONDecoder()

    private static let session: URLSession = {
        let c = URLSessionConfiguration.default
        c.timeoutIntervalForRequest = 15
        c.timeoutIntervalForResource = 20
        return URLSession(configuration: c)
    }()

    static func sanitizeMachineId(_ machineId: String) -> String {
        var s = machineId.trimmingCharacters(in: .whitespaces)
        let bad = CharacterSet(charactersIn: "/\\:*?\"<>|")
        s = s.unicodeScalars.map { bad.contains($0) ? "-" : Character($0) }.map(String.init).joined()
        s = s.replacingOccurrences(of: " ", with: "_")
        s = s.trimmingCharacters(in: CharacterSet(charactersIn: "._ "))
        return s.isEmpty ? "unknown" : s
    }

    static func indexURL(baseURL: String) -> URL? {
        let base = baseURL.trimmingCharacters(in: .whitespaces)
        guard !base.isEmpty else { return nil }
        let path = base.hasSuffix("/") ? base + "index.json" : base + "/index.json"
        return URL(string: path)
    }

    static func machineDetailURL(baseURL: String, machineId: String) -> URL? {
        let base = baseURL.trimmingCharacters(in: .whitespaces)
        guard !base.isEmpty else { return nil }
        let safe = sanitizeMachineId(machineId)
        let path = base.hasSuffix("/") ? base + "machines/\(safe).json" : base + "/machines/\(safe).json"
        return URL(string: path)
    }

    /// `baseURL` が空・nil のときは既定のマスターURL。
    private static func resolvedMasterBaseURL(_ baseURL: String?) -> String {
        if let b = baseURL?.trimmingCharacters(in: .whitespacesAndNewlines), !b.isEmpty { return b }
        return PresetServiceConfig.defaultMachineDetailBaseURL
    }

    static func fetchIndex(baseURL: String? = nil) async -> [MachineMasterIndexEntry]? {
        let base = resolvedMasterBaseURL(baseURL)
        if let url = indexURL(baseURL: base) {
            do {
                let (data, _) = try await session.data(from: url)
                let list = try decoder.decode([MachineMasterIndexEntry].self, from: data)
                AppLog.machineMaster.debug("fetchIndex count=\(list.count, privacy: .public)")
                return list
            } catch {
                AppLog.machineMaster.error("fetchIndex failed: \(error.localizedDescription, privacy: .public)")
            }
        }
        if let data = Bundle.main.url(forResource: "index", withExtension: "json", subdirectory: "master_out")
            .flatMap({ try? Data(contentsOf: $0) }) {
            if let list = try? decoder.decode([MachineMasterIndexEntry].self, from: data) {
                AppLog.machineMaster.debug("fetchIndex bundle count=\(list.count, privacy: .public)")
                return list
            }
        }
        return nil
    }

    static func fetchMachineDetail(machineId: String, baseURL: String? = nil) async -> MachineFullMaster? {
        let base = resolvedMasterBaseURL(baseURL)
        let safe = sanitizeMachineId(machineId)
        if let url = machineDetailURL(baseURL: base, machineId: machineId) {
            do {
                let (data, _) = try await session.data(from: url)
                return try decoder.decode(MachineFullMaster.self, from: data)
            } catch {
                AppLog.machineMaster.error("fetchMachineDetail failed id=\(machineId, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
        if let url = Bundle.main.url(forResource: safe, withExtension: "json", subdirectory: "master_out/machines"),
           let data = try? Data(contentsOf: url),
           let master = try? decoder.decode(MachineFullMaster.self, from: data) {
            AppLog.machineMaster.debug("fetchMachineDetail bundle id=\(machineId, privacy: .public)")
            return master
        }
        return nil
    }

    static func fetchMachineDetail(machineId: String?, machineName: String?, baseURL: String? = nil) async -> MachineFullMaster? {
        let base = resolvedMasterBaseURL(baseURL)
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
            AppLog.machineMaster.debug("index no match for name=\(nameTrimmed, privacy: .public)")
            return nil
        }
        AppLog.machineMaster.debug("resolved name=\(nameTrimmed, privacy: .public) -> id=\(entry.machineId, privacy: .public)")
        return await fetchMachineDetail(machineId: entry.machineId, baseURL: base)
    }
}

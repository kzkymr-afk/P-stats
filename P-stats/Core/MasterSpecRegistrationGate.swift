import Foundation

/// サーバー側プリセット（CSV 等）を `index.json` と突き合わせ、マスターに載っている機種だけに絞り込む。
/// `MachineDetailLoader.fetchIndex` が取れる一覧を基準にし、未登録・機種 ID なしの行は除外する。
enum MasterSpecRegistrationGate {
    struct IndexFilter: Sendable {
        private let allowedIds: Set<String>

        init(indexEntries: [MachineMasterIndexEntry]) {
            let qualifying = Self.qualifyingEntries(indexEntries)
            var set = Set<String>()
            for e in qualifying {
                let id = MachineDetailLoader.sanitizeMachineId(e.machineId)
                if !id.isEmpty, id != "unknown" {
                    set.insert(id)
                }
            }
            allowedIds = set
        }

        func includes(_ preset: PresetFromServer) -> Bool {
            guard let raw = preset.machineId?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
                return false
            }
            let safe = MachineDetailLoader.sanitizeMachineId(raw)
            return allowedIds.contains(safe)
        }

        /// ステータスが「対象外」の行を除く（導入から6年経過など）。それ以外は完了に限らず一覧に含める。
        private static func qualifyingEntries(_ indexEntries: [MachineMasterIndexEntry]) -> [MachineMasterIndexEntry] {
            indexEntries.filter { entry in
                let s = (entry.status ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                return s != "対象外"
            }
        }
    }

    static func filterPresetsForRegistration(_ presets: [PresetFromServer], indexEntries: [MachineMasterIndexEntry]) -> [PresetFromServer] {
        let gate = IndexFilter(indexEntries: indexEntries)
        return presets.filter { gate.includes($0) }
    }

    /// `index.json` を正とし、**対象外**以外の全機種を検索に載せる。`machines.json` に詳細がある ID はそちらを採用し、無い行は `PresetFromServer.minimalFromIndexEntry` で補う。
    static func mergeServerPresetsWithIndex(_ server: [PresetFromServer]?, indexEntries: [MachineMasterIndexEntry]?) -> [PresetFromServer] {
        guard let indexEntries, !indexEntries.isEmpty else { return server ?? [] }
        var richById: [String: PresetFromServer] = [:]
        for p in server ?? [] {
            guard let raw = p.machineId?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { continue }
            let sid = MachineDetailLoader.sanitizeMachineId(raw)
            if !sid.isEmpty, sid != "unknown" { richById[sid] = p }
        }
        var out: [PresetFromServer] = []
        for entry in indexEntries {
            let st = (entry.status ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if st == "対象外" { continue }
            let sid = MachineDetailLoader.sanitizeMachineId(entry.machineId)
            guard !sid.isEmpty, sid != "unknown" else { continue }
            if let rich = richById[sid] {
                out.append(rich)
            } else {
                out.append(PresetFromServer.minimalFromIndexEntry(entry))
            }
        }
        return out
    }
}

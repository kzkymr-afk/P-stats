import Foundation

/// 続きから用：遊技ログを永続化し、アプリ終了・バックグラウンド後も復元できるようにする
enum ResumableStateStore {
    private static let fileName = "resumable_session.json"

    private static var fileURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(fileName)
    }

    /// 現在のログ状態を保存（保存して終了時・バックグラウンド時に呼ぶ）
    static func save(from log: GameLog) {
        let state = ResumableState(
            machineName: log.selectedMachine.name,
            shopName: log.selectedShop.name,
            initialHoldings: log.initialHoldings,
            totalRotations: log.totalRotations,
            normalRotations: log.normalRotations,
            initialDisplayRotation: log.initialDisplayRotation,
            currentState: log.currentState,
            remainingSupportCount: log.remainingSupportCount,
            supportPhaseInitialCount: log.supportPhaseInitialCount,
            isTimeShortMode: log.isTimeShortMode,
            adjustedNetPerRound: log.adjustedNetPerRound,
            winRecords: log.winRecords,
            lendingRecords: log.lendingRecords,
            currentModeID: log.currentModeID
        )
        guard let data = try? JSONEncoder().encode(state) else { return }
        try? data.write(to: fileURL)
    }

    /// 永続化した状態を読み込む。無いか壊れていれば nil
    static func load() -> ResumableState? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(ResumableState.self, from: data)
    }

    /// 永続化データを削除（新規スタート時）
    static func clear() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}

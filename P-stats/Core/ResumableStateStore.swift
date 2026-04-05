import Foundation

/// 続きから用：遊技ログを永続化し、アプリ終了・バックグラウンド後も復元できるようにする
enum ResumableStateStore {
    private static let fileName = "resumable_session.json"

    /// 通常のオートセーブ（タスクループ等）で短時間に連続書き込みしないための間隔。inactive/background は無視される
    private static var lastAutosaveAt: Date?
    private static let autosaveMinInterval: TimeInterval = 25

    private static var fileURL: URL {
        (FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory)
            .appendingPathComponent(fileName)
    }

    /// バッテリー・I/O 配慮付きオートセーブ。
    /// - `force: true` … 非アクティブ化・バックグラウンド等。間隔制限なしで必ず保存。
    /// - `force: false` … 実戦中の定期保存。`autosaveMinInterval` 秒以内の再呼び出しはスキップ。
    static func autosave(from log: GameLog, force: Bool) {
        if !force {
            let now = Date()
            if let t = lastAutosaveAt, now.timeIntervalSince(t) < autosaveMinInterval { return }
        }
        save(from: log)
    }

    /// 現在のログ状態を保存（セッション確定時・明示保存用。スロットルなし）
    static func save(from log: GameLog) {
        lastAutosaveAt = Date()
        let state = ResumableState(
            machineName: log.selectedMachine.name,
            shopName: log.selectedShop.name,
            sessionStartedAt: log.sessionStartedAt,
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
            currentModeID: log.currentModeID,
            currentModeUiRole: log.currentModeUiRole,
            undoStackEntries: log.persistedUndoStack(),
            isBigHitMode: log.isBigHitMode,
            bigHitChainCount: log.bigHitChainCount,
            bigHitSessionNormalRotationsAtWin: log.bigHitSessionNormalRotationsAtWin,
            bigHitSessionTotalRotationsAtWin: log.bigHitSessionTotalRotationsAtWin,
            normalSegmentHoldingsReconcileAccumulator: log.normalSegmentHoldingsReconcileAccumulator,
            stashedNormalHoldingsReconcileForBigHit: log.stashedNormalHoldingsReconcileForBigHit,
            bigHitSegmentHoldingsReconcileAccumulator: log.bigHitSegmentHoldingsReconcileAccumulator
        )
        do {
            let data = try JSONEncoder().encode(state)
            // 破損リスク低減（途中終了でも既存ファイルが壊れにくい）
            try data.write(to: fileURL, options: .atomic)
        } catch {
            // 続きからは必須機能ではないため、保存失敗は黙殺（ただし既存ファイルは .atomic で保全される）
            return
        }
    }

    /// 永続化した状態を読み込む。無いか壊れていれば nil
    static func load() -> ResumableState? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        do {
            return try JSONDecoder().decode(ResumableState.self, from: data)
        } catch {
            // 壊れている可能性が高いので隔離（次回以降の読み込み失敗ループを避ける）
            let stamp = Int(Date().timeIntervalSince1970)
            let quarantined = fileURL.deletingLastPathComponent()
                .appendingPathComponent("resumable_session.corrupt.\(stamp).json")
            try? FileManager.default.moveItem(at: fileURL, to: quarantined)
            return nil
        }
    }

    /// 永続化データを削除（新規スタート時）
    static func clear() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}

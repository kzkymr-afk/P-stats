import Foundation
import SwiftData
import SwiftUI

// MARK: - 実戦セッションの永続化窓口（将来のクラウド同期などはここに集約）

/// `GameSession` の読み書きを抽象化。View はこのプロトコル越しにのみ保存する。
protocol GameSessionRepository: AnyObject {
    func fetchAll() throws -> [GameSession]
    func save(_ session: GameSession) throws
    func delete(_ session: GameSession) throws
}

// MARK: - SwiftData 実装

@MainActor
final class SwiftDataGameSessionRepository: GameSessionRepository {
    private let context: ModelContext
    /// 個人データは Private 同期キューのみ（`UserSessionSyncService`）。nil なら同期フックなし。
    private let sessionUploadQueue: (any UserSessionSyncQueueing)?

    /// - Note: `sessionUploadQueue` のデフォルトは `nil`（`UserSessionSyncService.shared` はデフォルト引数に書けない）。ルートで `MainContentWithContainer` から明示的に渡すこと。
    init(
        context: ModelContext,
        sessionUploadQueue: (any UserSessionSyncQueueing)? = nil
    ) {
        self.context = context
        self.sessionUploadQueue = sessionUploadQueue
    }

    func fetchAll() throws -> [GameSession] {
        let descriptor = FetchDescriptor<GameSession>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        return try context.fetch(descriptor)
    }

    func save(_ session: GameSession) throws {
        context.insert(session)
        try context.save()
        sessionUploadQueue?.enqueueAfterSuccessfulLocalSave(session)
    }

    func delete(_ session: GameSession) throws {
        context.delete(session)
        try context.save()
    }
}

// MARK: - SwiftUI 環境

private enum GameSessionRepositoryEnvironmentKey: EnvironmentKey {
    /// ルートで `MainContentWithContainer` が注入する。未注入のビューでは nil。
    static var defaultValue: (any GameSessionRepository)? { nil }
}

extension EnvironmentValues {
    var gameSessionRepository: (any GameSessionRepository)? {
        get { self[GameSessionRepositoryEnvironmentKey.self] }
        set { self[GameSessionRepositoryEnvironmentKey.self] = newValue }
    }
}

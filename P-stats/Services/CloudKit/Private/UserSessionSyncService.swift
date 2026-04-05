import CloudKit
import Foundation
import SwiftData

// MARK: - Private Database 境界（個人の実戦のみ）

/// 将来、個人の `GameSession` を **Private Cloud Database** に同期するときのゲートウェイ。
/// 実装完了まで **実際のネットワーク処理は行わない**（キュー登録のみ）。
///
/// - Important: `publicCloudDatabase` は使用しない。共有マスタは `SharedMachineCloudKitService` のみ。
private enum UserSessionPrivateCloudDatabaseGateway {
    /// 実戦同期を実装する際は、このプロパティ経由でのみ Private DB にアクセスすること。
    static var database: CKDatabase {
        CKContainer.default().privateCloudDatabase
    }
}

/// ローカル保存成功後に呼ばれ、将来の Private 同期用キューへ載せる。
@MainActor
protocol UserSessionSyncQueueing: AnyObject {
    /// SwiftData の保存が成功した直後に呼ぶ。現状はスタブ（通信なし）。
    func enqueueAfterSuccessfulLocalSave(_ session: GameSession)
}

/// 個人データ（実戦）の CloudKit 同期パイプラインの入口。**Private DB 専用**をコードで固定する。
///
/// - Warning: `GameSession` の店舗名・収支・`snapshotData`・スランプ JSON 等は Public に送らないこと。
@MainActor
final class UserSessionSyncService: UserSessionSyncQueueing {

    static let shared = UserSessionSyncService()

    private init() {}

    /// スタブ用：アップロード待ちとして記録した `PersistentIdentifier`（デバッグ・将来のドレイン用）
    private(set) var enqueuedPersistentIDs: [PersistentIdentifier] = []

    func enqueueAfterSuccessfulLocalSave(_ session: GameSession) {
        // パイプライン確保：ローカル save 成功 → 同期キューへ（通信は未実装）
        enqueuedPersistentIDs.append(session.persistentModelID)
    }
}

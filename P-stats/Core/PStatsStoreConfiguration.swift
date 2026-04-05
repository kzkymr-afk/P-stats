import SwiftData

// MARK: - SwiftData ストアの単一設定（バックアップ・移行・サポート問い合わせ用）

/// アプリ本体の永続ストア設定。コンテナ生成は **`AppModelContainerLoader` からのみ** 行う。
enum PStatsStoreConfiguration {

    /// Application Support 配下のストア識別子（ファイル名のベース）。変更すると既存ユーザーは新規 DB 扱いになるため **リリース後は変えない**。
    static let persistentStoreName = "PStats"

    /// ローカル SwiftData。マネージド CloudKit 同期は無効（実戦・店・機種は端末優先。共有は `Services/CloudKit` の CK API で別経路）。
    static func modelConfiguration(schema: Schema) -> ModelConfiguration {
        ModelConfiguration(
            persistentStoreName,
            schema: schema,
            cloudKitDatabase: .none
        )
    }
}

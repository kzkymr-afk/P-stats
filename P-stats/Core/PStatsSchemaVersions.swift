import SwiftData

// MARK: - VersionedSchema（データ互換の足場）

/// 現在のストアのスキーマ版（`Schema.Version` と対応）。サポート・リリースノート用。
enum PStatsReleasedSchema {
    /// リリース中の VersionedSchema。`schemas` の **最後**が最新とみなされる。
    static let latest: Schema.Version = PStatsSchemaV1.versionIdentifier
}

/// 未リリースの開発段階では、スキーマを増やして移行する必要はない。
/// いまの `@Model` 群をそのまま **初期版（V1）** として扱い、VersionedSchema は 1 つに統一する。
enum PStatsSchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [
            Machine.self,
            Shop.self,
            GameSession.self,
            PrizeSet.self,
            MachinePrize.self,
            PresetMachine.self,
            PresetMachinePrize.self,
            MyMachinePreset.self
        ]
    }
}

// MARK: - 将来 V2 を切るときの手順（ここにコメントで固定）

/*
 1. **新しい enum** `PStatsSchemaV2: VersionedSchema` を追加し、`versionIdentifier` を `(2,0,0)` にする。
 2. `models` に **V2 時点の全モデル**を列挙する（削除した型は含めない）。
 3. `@Model` にプロパティを追加する場合は V2 側の「新ストア」の形に合わせ、V1 ストアからは `MigrationStage` で埋める。
 4. `PStatsMigrationPlan.schemas` を `[PStatsSchemaV1.self, PStatsSchemaV2.self]` の順にする（古い→新しい）。
 5. `stages` に V1→V2 のステージを 1 つ追加する。例（軽量移行が足りる場合）:

    static let migrateV1toV2 = MigrationStage.lightweight(
        fromVersion: PStatsSchemaV1.self,
        toVersion: PStatsSchemaV2.self
    )

    カスタム移行（バックフィル・リネーム）が必要な場合は `MigrationStage.custom` と
    `willMigrate` / `didMigrate` で `ModelContext` を用いる（Apple ドキュメント参照）。
 6. **意味のあるデフォルト**が「0 や空で誤解を生む」場合は、ステージ内か `PStatsDataNormalizer` の
    `currentNormalizationRevision` を上げて起動時正規化に追加する（冪等に書く）。
 7. **リネーム・削除**はデータ損失につながるため、必ずリリースノートとバックアップ導線を用意する。
 8. `PStatsStoreConfiguration.persistentStoreName` は **既存ユーザー互換のため変更しない**。
 */

/// 将来リリース後に `@Model` を変更する場合は、上記コメントの手順で V2 以降を定義し、移行ステージを追加する。
struct PStatsMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [PStatsSchemaV1.self]
    }

    /// V1 のみのときは空でよい（ストアは `VersionedSchema` の版管理下に乗る）。
    static var stages: [MigrationStage] {
        []
    }
}

import SwiftData

// MARK: - VersionedSchema（データ互換の足場）

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

/// 将来リリース後に `@Model` を変更する場合は、ここで V2 以降を定義し、移行ステージを追加する。
struct PStatsMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [PStatsSchemaV1.self]
    }

    /// V1 のみのときは空でよい（ストアは `VersionedSchema` の版管理下に乗る）。
    static var stages: [MigrationStage] {
        []
    }
}

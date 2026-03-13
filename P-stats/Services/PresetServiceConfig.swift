import Foundation

/// マスターデータの取得元。GitHub の machines.json（raw URL）または JSON/CSV の URL。設定で変更可能。
enum PresetServiceConfig {
    /// 機種マスターデータのデフォルト取得元（GitHub リポジトリの machines.json）。
    static let defaultMachineMasterDataURL = "https://raw.githubusercontent.com/kzkymr-afk/P-stats/main/machines.json"

    /// モード・当たり詳細（index.json / machines/[id].json）の取得元ベースURL。末尾スラッシュなし。
    /// 例: https://raw.githubusercontent.com/kzkymr-afk/P-stats/main/master_out
    static let defaultMachineDetailBaseURL = "https://raw.githubusercontent.com/kzkymr-afk/P-stats/main/master_out"
}

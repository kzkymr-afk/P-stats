import Foundation

/// マスターデータの取得元。公開 JSON は GitHub Pages（gh-pages）に集約。設定で URL を変更可能。
enum PresetServiceConfig {
    /// 機種マスターデータ（プリセット一覧）のデフォルト取得元。Pages 配下の machines.json（`master_out` と同じサイト）。
    static let defaultMachineMasterDataURL = "https://kzkymr-afk.github.io/P-stats/machines.json"

    /// モード・当たり詳細（index.json / machines/[id].json）の取得元ベースURL。末尾スラッシュなし。
    /// 例: https://kzkymr-afk.github.io/P-stats/master_out
    static let defaultMachineDetailBaseURL = "https://kzkymr-afk.github.io/P-stats/master_out"
}

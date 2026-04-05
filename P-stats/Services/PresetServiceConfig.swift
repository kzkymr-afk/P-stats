import Foundation

/// マスターデータの取得元。公開 JSON は GitHub Pages（gh-pages）に集約。設定で URL を変更可能。
enum PresetServiceConfig {
    /// 機種マスターデータ（プリセット一覧）のデフォルト取得元。Pages 配下の machines.json（`master_out` と同じサイト）。
    static let defaultMachineMasterDataURL = "https://kzkymr-afk.github.io/P-stats/machines.json"

    /// モード・当たり詳細（index.json / machines/[id].json）の取得元ベースURL。末尾スラッシュなし。
    /// 例: https://kzkymr-afk.github.io/P-stats/master_out
    static let defaultMachineDetailBaseURL = "https://kzkymr-afk.github.io/P-stats/master_out"

    /// 旧仕様・参照用。index 掲載は `scripts/convert_master_one_sheet.py` が決定（機種名＋導入開始日が揃えばステータス未完了でも掲載可）。アプリ側は `MasterSpecRegistrationGate` で「対象外」以外を許可。
    static let masterSpecReadyStatuses: Set<String> = ["完了", "公開"]

    /// 新規登録検索の index から除外するステータス（`index.json` にも載らない想定）。
    static func isExcludedFromMasterRegistration(status: String?) -> Bool {
        (status ?? "").trimmingCharacters(in: .whitespacesAndNewlines) == "対象外"
    }

    static func isMasterSpecReadyForRegistration(status: String?) -> Bool {
        let s = (status ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return masterSpecReadyStatuses.contains(s)
    }
}

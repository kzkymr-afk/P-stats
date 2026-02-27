import Foundation

/// 管理人用マスターデータの取得元URL。管理人だけがこのURLのJSONを編集する。
/// ユーザーはここから機種を検索してマイリストに追加できる（参照のみ）。
/// 空ならアプリ内プリセット（PresetMachine）をマスタとして表示。
enum PresetServiceConfig {
    static var presetListURL: String { "" }
}

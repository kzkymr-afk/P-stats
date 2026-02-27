import Foundation

/// 管理人用マスターデータ1件（サーバーJSON）。管理人だけが編集し、ユーザーは参照のみ。
struct PresetFromServer: Codable {
    var name: String
    var machineTypeRaw: String?
    var supportLimit: Int?
    /// 通常大当たり後の時短ゲーム数（マスターデータ）
    var timeShortRotations: Int?
    var defaultPrize: Int?
    var probability: String?
    var border: String?
    var prizeEntries: [PrizeEntryFromServer]?
    /// 実質ボーダー用（任意）
    var entryRate: Double?
    var continuationRate: Double?
    var countPerRound: Int?
    var netPerRoundBase: Double?
    var manufacturer: String?

    struct PrizeEntryFromServer: Codable {
        var label: String?
        var rounds: Int
        var balls: Int
    }
}

enum PresetService {
    /// 指定URLからプリセット一覧を取得。失敗時は nil。
    static func fetchPresets(from urlString: String) async -> [PresetFromServer]? {
        guard !urlString.isEmpty, let url = URL(string: urlString) else { return nil }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let list = try JSONDecoder().decode([PresetFromServer].self, from: data)
            return list
        } catch {
            return nil
        }
    }

    /// サーバー用プリセットの1Rあたり平均純増
    static func averageNetPerRound(_ s: PresetFromServer) -> Double {
        guard let entries = s.prizeEntries, !entries.isEmpty else {
            let prize = Double(s.defaultPrize ?? 1500)
            return prize / 10.0
        }
        let totalBalls = entries.reduce(0) { $0 + $1.balls }
        let totalRounds = entries.reduce(0) { $0 + $1.rounds }
        return totalRounds > 0 ? Double(totalBalls) / Double(totalRounds) : 0
    }
}

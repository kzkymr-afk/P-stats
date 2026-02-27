import Foundation
import SwiftData
import SwiftUI

// --- 1. 永続化データ ---

/// ユーザーが登録する「当たり種類」のライブラリ（例: 10R 1500玉）
@Model
final class PrizeSet {
    var name: String = ""   // 例: "10R（1500玉）"
    var rounds: Int = 10    // 回数（R）
    var balls: Int = 1500   // 出玉数

    init() {}

    init(name: String, rounds: Int, balls: Int) {
        self.name = name
        self.rounds = rounds
        self.balls = balls
    }

    /// 1Rあたりの平均純増数
    var netPerRound: Double {
        rounds > 0 ? Double(balls) / Double(rounds) : 0
    }
}

/// 機種に紐づく当たり種類（1機種に複数登録可能）
@Model
final class MachinePrize {
    var label: String = ""  // 例: "10R（1500玉）"
    var rounds: Int = 10
    var balls: Int = 1500
    var machine: Machine?

    init() {}

    init(label: String, rounds: Int, balls: Int) {
        self.label = label
        self.rounds = rounds
        self.balls = balls
    }

    /// 1Rあたりの平均純増数
    var netPerRound: Double {
        rounds > 0 ? Double(balls) / Double(rounds) : 0
    }
}

/// 機種の電サポ仕様（ST＝回数で自動復帰、確変＝次回まで継続）
enum MachineType: String, CaseIterable, Codable {
    case st = "st"           // STタイプ：電サポ回数で自動通常復帰
    case kakugen = "kakugen" // 確変タイプ：手動で通常復帰

    var displayName: String {
        switch self {
        case .st: return "STタイプ"
        case .kakugen: return "確変タイプ"
        }
    }
}

/// ユーザーのマイリスト用機種。実質ボーダー計算に必要な項目をすべて保持する。
/// 項目: 台名(name), 確変/ST(machineTypeRaw), 公式ボーダー(border), 大当たり種類(prizeEntries),
/// 出球(defaultPrize), 賞球数(countPerRound), 電サポゲーム数(supportLimit), 突入率・継続率・平均出玉・1R純増。
@Model
final class Machine {
    var name: String = ""
    /// STのときの電サポ回数（規定回で自動通常復帰）。確変では未使用
    var supportLimit: Int = 100
    /// 通常大当たり後の時短ゲーム数。この回転数までは球を消費せず、終了後から通常回転にカウント
    var timeShortRotations: Int = 0
    var defaultPrize: Int = 1500  // 実戦時のデフォルト出玉（未設定時は prizeEntries の先頭を使用）
    /// 確率（表示用・例: "1/319.5"）。ボーダー計算で分母を利用
    var probability: String = ""

    /// 確率の分母（"1/319.5" → 319.5）。パース失敗時は0
    var probabilityDenominator: Double {
        let s = probability.trimmingCharacters(in: .whitespaces)
        guard let slash = s.firstIndex(of: "/") else { return 0 }
        let after = s[ s.index(after: slash)... ].trimmingCharacters(in: .whitespaces)
        return Double(after) ?? 0
    }
    /// ボーダー（表示用）
    var border: String = ""
    /// 機種タイプ（"st" or "kakugen"）
    var machineTypeRaw: String = MachineType.kakugen.rawValue
    /// 突入率（%）。未設定時は100として計算
    var entryRate: Double = 100
    /// 継続率（%）。未設定時は100として計算
    var continuationRate: Double = 100
    /// 実戦の平均出玉。0なら公表値（effectiveDefaultPrize）を使用
    var averagePrize: Double = 0
    /// 1Rあたりの純増出玉（払出−打出）。未設定時0＝当たり種類から算出。デフォルト140（10カウント15賞球想定）
    var netPerRoundBase: Double = 0
    /// カウント数（賞球数）。打ち出し = ラウンド数×この値。10カウント=10、15賞球=15
    var countPerRound: Int = 10
    /// メーカー名（分析用・例: サミー、藤森）。空なら機種名から推定
    var manufacturer: String = ""

    @Relationship(deleteRule: .cascade, inverse: \MachinePrize.machine)
    var prizeEntries: [MachinePrize] = []

    init(name: String, supportLimit: Int, defaultPrize: Int) {
        self.name = name
        self.supportLimit = supportLimit
        self.defaultPrize = defaultPrize
    }

    var machineType: MachineType {
        MachineType(rawValue: machineTypeRaw) ?? .kakugen
    }

    /// STタイプなら true（電サポ回数カウントダウンで自動復帰）
    var isST: Bool { machineType == .st }

    /// 当たり1回のR数（先頭の当たり種類。なければ10R想定）
    var defaultRoundsPerHit: Int {
        prizeEntries.first?.rounds ?? 10
    }

    /// 払い出しから打ち出しを引いた純増。公式: 純増 = 払い出し - (ラウンド数 × カウント数)
    func netBallsForPrize(rounds: Int, payoutBalls: Int) -> Int {
        let feed = rounds * countPerRound
        return max(0, payoutBalls - feed)
    }

    /// 1Rあたりの純増出玉（管理人が設定した値優先。0なら当たり種類から純増で算出、それも無ければ defaultPrize を払出として純増算出）
    var averageNetPerRound: Double {
        if netPerRoundBase > 0 { return netPerRoundBase }
        guard !prizeEntries.isEmpty else {
            let r = defaultRoundsPerHit
            let net = netBallsForPrize(rounds: r, payoutBalls: defaultPrize)
            return r > 0 ? Double(net) / Double(r) : 0
        }
        let totalPayout = prizeEntries.reduce(0) { $0 + $1.balls }
        let totalRounds = prizeEntries.reduce(0) { $0 + $1.rounds }
        let totalFeed = totalRounds * countPerRound
        let totalNet = totalPayout - totalFeed
        return totalRounds > 0 ? Double(max(0, totalNet)) / Double(totalRounds) : 0
    }

    /// 実戦で使う当たり1回の持ち玉（純増ベース）。当たり種類があればその純増、なければ R数×1R純増
    var effectiveDefaultPrize: Int {
        if let first = prizeEntries.first {
            return netBallsForPrize(rounds: first.rounds, payoutBalls: first.balls)
        }
        return Int(round(Double(defaultRoundsPerHit) * averageNetPerRound))
    }

    /// 先頭当たりの払い出し（公表値）。表示用
    var effectivePayoutDisplay: Int {
        prizeEntries.first?.balls ?? defaultPrize
    }

    /// 実戦ボーダー計算用の1R純増（突入率・継続率・平均出玉を反映）
    var effectiveNetPerRoundForBorder: Double {
        let base = averageNetPerRound
        let entry = (entryRate > 0 ? entryRate : 100) / 100.0
        let cont = (continuationRate > 0 ? continuationRate : 100) / 100.0
        let prizeFactor = averagePrize > 0 ? averagePrize / Double(effectiveDefaultPrize) : 1.0
        return base * entry * cont * prizeFactor
    }
}

// MARK: - 管理人プリセット機種（ユーザーが「採用」して自分の機種として登録できる）

@Model
final class PresetMachinePrize {
    var label: String = ""
    var rounds: Int = 10
    var balls: Int = 1500
    var preset: PresetMachine?

    init() {}
    init(label: String, rounds: Int, balls: Int) {
        self.label = label
        self.rounds = rounds
        self.balls = balls
    }
    var netPerRound: Double { rounds > 0 ? Double(balls) / Double(rounds) : 0 }
}

@Model
final class PresetMachine {
    var name: String = ""
    var machineTypeRaw: String = MachineType.kakugen.rawValue
    var supportLimit: Int = 100
    /// 通常大当たり後の時短ゲーム数
    var timeShortRotations: Int = 0
    var defaultPrize: Int = 1500
    var probability: String = ""
    var border: String = ""
    /// 採用・検索で利用された日時（上位表示のソート用）
    var lastUsedAt: Date?

    @Relationship(deleteRule: .cascade, inverse: \PresetMachinePrize.preset)
    var prizeEntries: [PresetMachinePrize] = []

    init() {}
    init(name: String, supportLimit: Int, defaultPrize: Int) {
        self.name = name
        self.supportLimit = supportLimit
        self.defaultPrize = defaultPrize
    }
    var machineType: MachineType { MachineType(rawValue: machineTypeRaw) ?? .kakugen }
    var isST: Bool { machineType == .st }
    var averageNetPerRound: Double {
        guard !prizeEntries.isEmpty else { return Double(defaultPrize) / 10.0 }
        let totalBalls = prizeEntries.reduce(0) { $0 + $1.balls }
        let totalRounds = prizeEntries.reduce(0) { $0 + $1.rounds }
        return totalRounds > 0 ? Double(totalBalls) / Double(totalRounds) : 0
    }
    var effectiveDefaultPrize: Int { prizeEntries.first?.balls ?? defaultPrize }
}

@Model
final class Shop {
    var name: String = ""
    var ballsPerCashUnit: Int = 125
    var exchangeRate: Double = 4.0
    /// 毎月この日を特定日とする（カンマ区切り）。新UI用 specificDayRulesStorage が空のときのみ使用
    var specificDayOfMonthStorage: String = ""
    /// 日の下一桁がこの数字の日を特定日とする（カンマ区切り）。新UI用 specificDayRulesStorage が空のときのみ使用
    var specificLastDigitsStorage: String = ""
    /// 特定日ルールの追加順（最大4つ）。形式: "M13,L5,L7,L8" → M=毎月N日, L=Nのつく日。空なら旧2フィールドから復元
    var specificDayRulesStorage: String = ""
    init(name: String, ballsPerCashUnit: Int, exchangeRate: Double) {
        self.name = name; self.ballsPerCashUnit = ballsPerCashUnit; self.exchangeRate = exchangeRate
    }
}

/// ユーザーが保存するマイ機種プリセット（一撃呼び出し用）
@Model
final class MyMachinePreset {
    var name: String = ""
    var probability: String = ""
    /// ラウンド構成の代表（例: 10 → "10R"）
    var defaultRounds: Int = 10
    var countPerRound: Int = 10
    var netPerRoundBase: Double = 140
    var machineTypeRaw: String = MachineType.kakugen.rawValue
    var supportLimit: Int = 100
    var timeShortRotations: Int = 0
    var defaultPrize: Int = 1500
    var border: String = ""
    var entryRate: Double = 100
    var continuationRate: Double = 100
    var averagePrize: Double = 0
    var lastUsedAt: Date?

    init() {}
    var machineType: MachineType { MachineType(rawValue: machineTypeRaw) ?? .kakugen }
    var roundConfigLabel: String { "\(defaultRounds)R" }
}

// --- 2. 記録用構造体・列挙型 ---
enum WinType: String, Codable, CaseIterable {
    case rush = "確変/RUSH"
    case normal = "通常"
}

enum PlayState: String, Codable {
    case normal = "通常"
    case support = "電サポ"
}

enum LendingType: String, Codable {
    case cash = "現金"
    case holdings = "持ち玉"
}

struct WinRecord: Identifiable, Codable {
    var id: UUID = UUID()
    var type: WinType
    var prize: Int?
    var rotationAtWin: Int
}

struct LendingRecord: Identifiable, Codable {
    var id: UUID = UUID()
    var type: LendingType
    let timestamp: Date
    /// 持ち玉補充のときの実際の玉数（125未満は残り全額）。現金のときは nil（店の貸玉料金で計算）
    var balls: Int? = nil
}

// --- 3. テーマ定義 (⚠️ここが1回だけであることを確認！) ---

/// 起動画面の色（P-STATSフォント色と同色→黒へ変化で文字が徐々に見える）
enum LaunchAppearance {
    /// 起動直後の背景＝P-STATSのフォント色（シアン）と同色
    static let launchStartColor = Color(red: 0, green: 0.83, blue: 1.0)
    /// グラデーション終了・黒
    static let launchEndColor = Color(red: 28/255, green: 28/255, blue: 30/255)
    /// 従来の単色用（他で参照されている場合）
    static let iconBackgroundColor = launchEndColor
}

enum AppTheme: String, CaseIterable, Codable {
    case cyber = "プロ（サイバー）"
    case simple = "シンプル（ステルス）"
    
    var backgroundColor: Color {
        self == .cyber ? Color(red: 0.02, green: 0.02, blue: 0.05) : Color(white: 0.98)
    }
    
    var accentColor: Color {
        self == .cyber ? .cyan : .blue
    }
    
    var textColor: Color {
        self == .cyber ? .white : .black
    }
}

@Model
final class GameSession {
    var id: UUID = UUID()
    var date: Date = Date()
    var machineName: String = ""
    var shopName: String = ""
    var manufacturerName: String = ""  // 保存時メーカー（分析用）
    var investmentCash: Int = 0        // 現金投資
    var totalHoldings: Int = 0         // 回収玉数
    var normalRotations: Int = 0       // 総回転数（通常）
    var totalUsedBalls: Int = 0        // 総消費玉数
    var exchangeRate: Double = 0.0     // 交換率
    var totalRealCost: Double = 0      // 実質投資（円換算）
    var expectationRatioAtSave: Double = 0  // 保存時ボーダー比
    var theoreticalProfit: Int = 0     // 理論期待値（利益・円）
    var rushWinCount: Int = 0          // 実践で入力したRUSH大当たり回数
    var normalWinCount: Int = 0        // 実践で入力した通常大当たり回数
    /// 保存時の公式ボーダー（回/千円・等価）。実践回転率との差表示用
    var formulaBorderPer1k: Double = 0

    init(machineName: String, shopName: String, manufacturerName: String = "", investmentCash: Int, totalHoldings: Int, normalRotations: Int, totalUsedBalls: Int, exchangeRate: Double, totalRealCost: Double = 0, expectationRatioAtSave: Double = 0, rushWinCount: Int = 0, normalWinCount: Int = 0, formulaBorderPer1k: Double = 0) {
        self.machineName = machineName
        self.shopName = shopName
        self.manufacturerName = manufacturerName
        self.investmentCash = investmentCash
        self.totalHoldings = totalHoldings
        self.normalRotations = normalRotations
        self.totalUsedBalls = totalUsedBalls
        self.exchangeRate = exchangeRate
        self.totalRealCost = totalRealCost
        self.expectationRatioAtSave = expectationRatioAtSave
        self.theoreticalProfit = Int(round(totalRealCost * (expectationRatioAtSave - 1)))
        self.rushWinCount = rushWinCount
        self.normalWinCount = normalWinCount
        self.formulaBorderPer1k = formulaBorderPer1k
    }

    /// 実収支（円）
    var profit: Int {
        let recovery = Int(Double(totalHoldings) * exchangeRate)
        return recovery - investmentCash
    }

    /// 欠損・余剰（実収支 − 理論期待値）。正＝理論より得、負＝理論より損
    var deficitSurplus: Int { profit - theoreticalProfit }
}


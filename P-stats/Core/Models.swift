import Foundation
import SwiftData
import SwiftUI

// --- 1. 永続化データ ---

/// ユーザーが登録する「ボーナス種類」のライブラリ（出玉のみ。R数は廃止）
@Model
final class PrizeSet {
    var name: String = ""
    var balls: Int = 1500   // 出玉数
    /// ライブラリ一覧の表示順（小さいほど上）。手動並び替え用
    var displayOrder: Int = 0

    init() {}

    init(name: String, balls: Int) {
        self.name = name
        self.balls = balls
    }

    /// 1Rあたり純増（打ち出し10玉/1R想定）
    var netPerRound: Double { max(0, Double(balls - 10)) }
}

/// 機種に紐づくボーナス種類（電チュー用。出玉のみ。R数は廃止）
@Model
final class MachinePrize {
    var label: String = ""
    var balls: Int = 1500
    var machine: Machine?

    init() {}

    init(label: String, balls: Int) {
        self.label = label
        self.balls = balls
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

/// ヘソ当たり1件（マスタ書式: 出玉/RUSH(0or1)/時短ゲーム数）。0=時短へ、1=RUSH突入。
struct HesoAtariItem: Codable, Identifiable, Equatable {
    var payout: Int
    var rush: Int  // 0=時短へ、1=RUSH突入
    var timeShort: Int
    var id: String { "\(payout)/\(rush)/\(timeShort)" }
}

/// ユーザーのマイリスト用機種。実質ボーダー計算に必要な項目を保持する。
/// 項目: 台名(name), 確変/ST(machineTypeRaw), ボーダー(border), ボーナス種類(prizeEntries / hesoAtari・denchu_prizes),
/// 出球(defaultPrize), 賞球数(countPerRound), 電サポゲーム数(supportLimit)。
@Model
final class Machine {
    var name: String = ""
    /// 外部のJSONマスターデータと紐付けるための識別子（自作マスタ連携用）
    var masterID: String?
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
    /// カウント数（賞球数）。打ち出し = ラウンド数×この値。10カウント=10、15賞球=15
    var countPerRound: Int = 10
    /// メーカー名（分析用・例: サミー、藤森）
    var manufacturer: String = ""

    /// 通常時のヘソ当たり1〜5（JSON配列を文字列で保持）。空なら prizeEntries を利用。
    var hesoAtariStorage: String = ""
    /// ヘソ当たりリスト（hesoAtariStorage のデコード結果）。保存時は hesoAtariStorage に JSON を代入する。
    var hesoAtari: [HesoAtariItem] {
        guard !hesoAtariStorage.isEmpty,
              let data = hesoAtariStorage.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([HesoAtariItem].self, from: data) else { return [] }
        return decoded
    }
    /// P-Sync/GAS用：RUSH時の特図2内訳。カンマ区切り（例: "10R(1500個)-RUSH,300個-RUSH,10R(1500個)-天国"）。空なら prizeEntries を利用。
    var denchu_prizes: String = ""

    /// 従来のボーナス種類。heso_prizes/denchu_prizes が空のときのフォールバック。GAS連携時は非推奨。
    @Relationship(deleteRule: .cascade, inverse: \MachinePrize.machine)
    var prizeEntries: [MachinePrize] = []

    init(name: String, supportLimit: Int, defaultPrize: Int, masterID: String? = nil) {
        self.name = name
        self.supportLimit = supportLimit
        self.defaultPrize = defaultPrize
        self.masterID = masterID
    }

    var machineType: MachineType {
        MachineType(rawValue: machineTypeRaw) ?? .kakugen
    }

    /// STタイプなら true（電サポ回数カウントダウンで自動復帰）
    var isST: Bool { machineType == .st }

    /// 払い出しから1R打ち出しを引いた純増（R数は使わない。1当たり = 払い出し - countPerRound）
    func netBallsForPrize(payoutBalls: Int) -> Int {
        return max(0, payoutBalls - countPerRound)
    }

    /// 1Rあたりの純増出玉（ボーナス種類から算出。各当たりを1Rとみなす）
    var averageNetPerRound: Double {
        guard !prizeEntries.isEmpty else {
            return Double(netBallsForPrize(payoutBalls: defaultPrize))
        }
        let totalNet = prizeEntries.reduce(0) { $0 + netBallsForPrize(payoutBalls: $1.balls) }
        return Double(totalNet) / Double(prizeEntries.count)
    }

    /// 実戦で使う当たり1回の持ち玉（純増ベース）
    var effectiveDefaultPrize: Int {
        if let first = prizeEntries.first {
            return netBallsForPrize(payoutBalls: first.balls)
        }
        return netBallsForPrize(payoutBalls: defaultPrize)
    }

    /// 先頭当たりの払い出し（公表値）。表示用
    var effectivePayoutDisplay: Int {
        prizeEntries.first?.balls ?? defaultPrize
    }
}

/// P-Sync/GAS から機種を取得する際の「特図2内訳」フィールド用。ヘソ当たりは hesoAtari で管理。
struct MachineGASPrizeFields: Codable {
    /// GAS ヘッダー「特図2内訳」→ RUSH時ボタン用（例: "10R(1500個)-RUSH,10R(1500個)-天国"）
    var denchu_prizes: String?

    enum CodingKeys: String, CodingKey {
        case denchu_prizes = "特図2内訳"
    }
}

// MARK: - 管理人プリセット機種（ユーザーが「採用」して自分の機種として登録できる）

@Model
final class PresetMachinePrize {
    var label: String = ""
    var balls: Int = 1500
    var preset: PresetMachine?

    init() {}
    init(label: String, balls: Int) {
        self.label = label
        self.balls = balls
    }
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
        guard !prizeEntries.isEmpty else { return Double(defaultPrize) }
        let totalBalls = prizeEntries.reduce(0) { $0 + $1.balls }
        return Double(totalBalls) / Double(prizeEntries.count)
    }
    var effectiveDefaultPrize: Int { prizeEntries.first?.balls ?? defaultPrize }
}

@Model
final class Shop {
    var name: String = ""
    var ballsPerCashUnit: Int = 125
    /// 払出係数（1玉あたりのpt換算）。統計シミュレーション用
    var payoutCoefficient: Double = 4.0
    /// 店が貯玉（カウンター預かり）に対応しているか。実戦終了時の「貯玉」精算や端数の貯玉反映に使用。
    var supportsChodamaService: Bool = false
    /// その店の貯玉残高（玉数）。精算のたびに増加、店舗編集で手修正可能。
    var chodamaBalanceBalls: Int = 0
    /// Google Places API から取得した場所の一意なID（重複登録防止など）
    var placeID: String?
    /// 店舗の住所
    var address: String = ""
    /// 毎月この日を特定日とする（カンマ区切り）。新UI用 specificDayRulesStorage が空のときのみ使用
    var specificDayOfMonthStorage: String = ""
    /// 日の下一桁がこの数字の日を特定日とする（カンマ区切り）。新UI用 specificDayRulesStorage が空のときのみ使用
    var specificLastDigitsStorage: String = ""
    /// 特定日ルールの追加順（最大6つ）。形式: "M13,L5,L7,L8" → M=毎月N日, L=Nのつく日。空なら旧2フィールドから復元
    var specificDayRulesStorage: String = ""
    init(name: String, ballsPerCashUnit: Int, payoutCoefficient: Double, placeID: String? = nil, address: String = "") {
        self.name = name
        self.ballsPerCashUnit = ballsPerCashUnit
        self.payoutCoefficient = payoutCoefficient
        self.placeID = placeID
        self.address = address
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
enum WinType: String, CaseIterable {
    case rush = "確変/RUSH"
    case normal = "通常"
}

extension WinType: Codable {
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        let raw = try c.decode(String.self)
        switch raw {
        case Self.rush.rawValue: self = .rush
        case Self.normal.rawValue: self = .normal
        case "LT": self = .rush
        default: self = .normal
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(rawValue)
    }
}

enum PlayState: String, CaseIterable {
    case normal = "通常"
    case support = "電サポ"
}

extension PlayState: Codable {
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        let raw = try c.decode(String.self)
        if let v = PlayState(rawValue: raw) {
            self = v
        } else if raw == "LT" {
            self = .normal
        } else {
            self = .normal
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(rawValue)
    }
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
    /// 大当たり入力時刻（liveChartPoints で win と lending を時系列結合するため）。既存データは nil
    var timestamp: Date? = nil
    /// 当選時点の総回転数（電サポ・時短を除く通常ゲーム累積）。収支グラフ横軸用。既存データは nil のとき rotationAtWin で代替
    var normalRotationsAtWin: Int? = nil
    /// フェーズ3: 当たり発生時の mode_id（マスタ由来。0=通常系、非0はRUSH系等）
    var modeIdAtWin: Int? = nil
    /// フェーズ3: この当たり後の遷移先 mode_id。既存データは nil
    var nextModeId: Int? = nil
    /// フェーズ3: 当たり名称（データ駆動用）。既存データは nil
    var bonusName: String? = nil
    /// RUSH終了時にユーザーが入力した「このRUSHで遊んだ総ゲーム数」（時短抜け含む）。RUSH 1 run のみ使用
    var rushGamesPlayed: Int? = nil
    /// 大当たりモード終了時に確定した「この区間の大当たり回数（連チャン含む）」。旧データは nil
    var bonusSessionHitCount: Int? = nil
}

struct LendingRecord: Identifiable, Codable {
    var id: UUID = UUID()
    var type: LendingType
    let timestamp: Date
    /// 持ち玉補充のときの実際の玉数（125未満は残り全額）。現金のときは nil（店の貸玉料金で計算）
    var balls: Int? = nil
}

/// 大当たり記録直前の回転・モード状態（Undo で復元する）
struct RotationModeSnapshot: Codable, Equatable {
    var totalRotations: Int
    var normalRotations: Int
    var currentState: PlayState
    var currentModeID: Int
    var currentModeUiRole: Int
    var remainingSupportCount: Int
    var supportPhaseInitialCount: Int
    var isTimeShortMode: Bool
    /// 大当たりモード（Undo 復元用）。旧データは nil
    var isBigHitMode: Bool? = nil
    var bigHitChainCount: Int? = nil
}

/// Undo スタックの永続化用（当たりは `RotationModeSnapshot` 付き）
struct PersistedUndoEntry: Codable, Equatable {
    var isWin: Bool
    var recordId: UUID
    var modeSnapshot: RotationModeSnapshot?
}

/// 続きから用：遊技ログのスナップショット（保存して終了・バックグラウンド時に永続化）
struct ResumableState: Codable {
    var machineName: String
    var shopName: String
    var initialHoldings: Int
    var totalRotations: Int
    var normalRotations: Int
    var initialDisplayRotation: Int
    var currentState: PlayState
    var remainingSupportCount: Int
    var supportPhaseInitialCount: Int
    var isTimeShortMode: Bool
    var adjustedNetPerRound: Double?
    var winRecords: [WinRecord]
    var lendingRecords: [LendingRecord]
    /// フェーズ3: 現在の滞在モードID（マスタ由来。0=通常）
    var currentModeID: Int? = nil
    /// 現在のモードの UI ロール（0=通常系, 1=RUSH系）。nil のときは currentModeID から推定
    var currentModeUiRole: Int? = nil
    /// Undo スタック（最大3件）。旧データは nil
    var undoStackEntries: [PersistedUndoEntry]? = nil
    /// 大当たりモード（通常画面と切り替え）。旧データは nil
    var isBigHitMode: Bool? = nil
    var bigHitChainCount: Int? = nil
    /// 大当たり突入時に確定した「当選時点の通常回転」。旧データは nil
    var bigHitSessionNormalRotationsAtWin: Int? = nil
    /// 当選時点の総回転（ランプ想定）。旧データは nil
    var bigHitSessionTotalRotationsAtWin: Int? = nil
}

// --- 3. テーマ定義 (⚠️ここが1回だけであることを確認！) ---

/// 起動画面の色（P-STATSフォント色と同色→黒へ変化で文字が徐々に見える）
enum LaunchAppearance {
    /// 起動直後の背景＝アクセントと同色（`DesignTokens.Color.accent*` と整合）
    static let launchStartColor = Color(
        red: DesignTokens.Color.accentR,
        green: DesignTokens.Color.accentG,
        blue: DesignTokens.Color.accentB
    )
    /// グラデーション終了・黒
    static let launchEndColor = Color(red: 28/255, green: 28/255, blue: 30/255)
    /// 従来の単色用（他で参照されている場合）
    static let iconBackgroundColor = launchEndColor
}

enum AppTheme: String, CaseIterable, Codable {
    /// 保存キー（表示名変更に強い）
    case dark = "dark"
    case light = "light"

    /// 設定画面などの表示用（システムのダークモードとは別：アプリ内配色）
    var settingsDisplayName: String {
        switch self {
        case .dark: return "ダーク（黒ベース）"
        case .light: return "ライト（白ベース）"
        }
    }

    /// 旧 `@AppStorage` / バックアップの生文字列から復元
    init(migratingRawValue: String) {
        if let v = AppTheme(rawValue: migratingRawValue) {
            self = v
            return
        }
        switch migratingRawValue {
        case "プロ（サイバー）", "cyber", "Cyber":
            self = .dark
        case "シンプル（ステルス）", "simple", "Simple":
            self = .light
        default:
            self = .dark
        }
    }

    var backgroundColor: Color {
        switch self {
        case .dark: return Color(red: 0.02, green: 0.02, blue: 0.05)
        case .light: return Color(red: 0.96, green: 0.97, blue: 0.99)
        }
    }

    var accentColor: Color {
        switch self {
        case .dark: return .cyan
        case .light:
            return Color(red: 0.12, green: 0.45, blue: 0.85)
        }
    }

    var textColor: Color {
        switch self {
        case .dark: return .white
        case .light: return Color(red: 0.1, green: 0.1, blue: 0.12)
        }
    }

    // MARK: - 実戦画面（PlayView）のベース色

    var playScreenBase: Color {
        switch self {
        case .dark: return Color(hex: DesignTokens.Color.backgroundHex)
        case .light: return Color(red: 0.93, green: 0.94, blue: 0.96)
        }
    }

    var playHeaderBackground: Color {
        switch self {
        case .dark: return .black
        case .light: return Color(red: 0.98, green: 0.98, blue: 0.99)
        }
    }

    var playPanelBackground: Color {
        switch self {
        case .dark: return Color.black.opacity(0.93)
        case .light: return Color.white.opacity(0.92)
        }
    }

    /// ドロワー背後のスクリーム
    var playDrawerScrim: Color {
        switch self {
        case .dark: return Color.black.opacity(0.35)
        case .light: return Color.black.opacity(0.22)
        }
    }

    /// 実戦ヘッダー・パネル上の主テキスト
    var playLabelPrimary: Color {
        switch self {
        case .dark: return .white
        case .light: return Color(red: 0.12, green: 0.12, blue: 0.14)
        }
    }

    var playLabelSecondary: Color {
        switch self {
        case .dark: return .white.opacity(0.75)
        case .light: return Color(red: 0.12, green: 0.12, blue: 0.14).opacity(0.62)
        }
    }

    var playMutedIcon: Color {
        switch self {
        case .dark: return .white.opacity(0.35)
        case .light: return Color.black.opacity(0.28)
        }
    }
}

@Model
final class GameSession {
    var id: UUID = UUID()
    var date: Date = Date()
    var machineName: String = ""
    var shopName: String = ""
    var manufacturerName: String = ""  // 保存時メーカー（分析用）
    var inputCash: Int = 0             // 投入（現金）
    var totalHoldings: Int = 0         // 回収玉数
    var normalRotations: Int = 0       // 総回転数（通常）
    var totalUsedBalls: Int = 0        // 総消費玉数
    var payoutCoefficient: Double = 0.0 // 払出係数（統計シミュレーション用）
    var totalRealCost: Double = 0      // 実質投入（pt換算）
    var expectationRatioAtSave: Double = 0  // 保存時ボーダー比
    var theoreticalValue: Int = 0      // 期待値（pt）
    var rushWinCount: Int = 0          // 実戦で入力したRUSH当選回数
    var normalWinCount: Int = 0        // 実戦で入力した通常当選回数
    /// 保存時の機種ボーダー（回/1k・等価・補正前）。`border` を数値化したもの（SwiftData フィールド名は互換のため `formulaBorderPer1k` のまま）
    var formulaBorderPer1k: Double = 0
    /// 保存時点の店補正後ボーダー（回/1k）。貸玉・払出係数を反映（`GameLog.dynamicBorder` と同定義）
    var effectiveBorderPer1kAtSave: Double = 0
    /// 保存時点の実質回転率（回/単位）。`normalRotations ÷ effectiveUnitsForBorder`（`GameLog.realRate` と同定義）
    var realRotationRateAtSave: Double = 0
    /// 初当たり時点までの実質投入（pt）。実戦からの保存時のみ埋まる。手入力・旧データは nil
    var firstHitRealCostPt: Double? = nil
    /// 実戦終了時の精算区分。空＝未記録（アップデート前データ）
    var settlementModeRaw: String = ""
    /// 「換金」を選んだときの 500pt 刻みの換金額。貯玉のみのときは 0。
    var exchangeCashProceedsPt: Int = 0
    /// この実戦の保存で店舗の貯玉残高に加算した玉数（貯玉精算＝全玉、換金＝端数玉）。
    var chodamaBalanceDeltaBalls: Int = 0
    /// シンプル入力など「投入・回収のみ」の行。分析では回転率・ボーダー差・ボーダー比の平均から除外（実成績・期待値の合計は従来どおり）。
    var isCashflowOnlyRecord: Bool = false
    /// 詳細編集の「初当たりブロック」JSON（空＝未使用・旧フォーム相当）
    var editSessionPhasesJSON: String = ""

    init(machineName: String, shopName: String, manufacturerName: String = "", inputCash: Int, totalHoldings: Int, normalRotations: Int, totalUsedBalls: Int, payoutCoefficient: Double, totalRealCost: Double = 0, expectationRatioAtSave: Double = 0, rushWinCount: Int = 0, normalWinCount: Int = 0, formulaBorderPer1k: Double = 0) {
        self.machineName = machineName
        self.shopName = shopName
        self.manufacturerName = manufacturerName
        self.inputCash = inputCash
        self.totalHoldings = totalHoldings
        self.normalRotations = normalRotations
        self.totalUsedBalls = totalUsedBalls
        self.payoutCoefficient = payoutCoefficient
        self.totalRealCost = totalRealCost
        self.expectationRatioAtSave = expectationRatioAtSave
        self.theoreticalValue = Int(round(totalRealCost * (expectationRatioAtSave - 1)))
        self.rushWinCount = rushWinCount
        self.normalWinCount = normalWinCount
        self.formulaBorderPer1k = formulaBorderPer1k
    }

    /// 成績（回収 − 投入・pt）
    var performance: Int {
        let recovery = Int(Double(totalHoldings) * payoutCoefficient)
        return recovery - inputCash
    }

    /// 欠損・余剰（成績 − 期待値）。正＝期待値より得、負＝期待値より損
    var deficitSurplus: Int { performance - theoreticalValue }
}

// MARK: - 分析での母集団（帳簿のみ行の扱い）

extension GameSession {
    /// 分析の「回転・期待値系」から外す行（フラグ付き、または旧DBでシンプル入力と同型の行）
    var excludesFromRotationExpectationAnalytics: Bool {
        if isCashflowOnlyRecord { return true }
        return normalRotations == 0
            && expectationRatioAtSave == 1.0
            && rushWinCount == 0 && normalWinCount == 0
    }

    /// 実戦で記録した当選回数の合計（通常・RUSH）
    var totalRecordedWinCount: Int { rushWinCount + normalWinCount }

    /// 加重回転率・グループ平均回転率に含める
    var participatesInRotationRateAnalytics: Bool { !excludesFromRotationExpectationAnalytics }

    /// ボーダーとの差（分析では通常回転数加重平均の重みに含める）に含める。新規は店補正ボーダー＋realRate、旧データは等価ベースのボーダー＋totalRealCost 基準で比較可能なとき
    var participatesInBorderDiffAnalytics: Bool {
        sessionBorderDiffPer1k != nil
    }

    /// ボーダーとの差（回/1k、実質回転率 − 店補正後ボーダー）。新規は保存済みの2値の差。旧データは `totalRealCost` 基準の回転率 − 等価ベースのボーダー（近似）
    var sessionBorderDiffPer1k: Double? {
        if excludesFromRotationExpectationAnalytics { return nil }
        if effectiveBorderPer1kAtSave > 0, realRotationRateAtSave > 0 {
            return realRotationRateAtSave - effectiveBorderPer1kAtSave
        }
        guard formulaBorderPer1k > 0, totalRealCost > 0, normalRotations > 0 else { return nil }
        let rate = (Double(normalRotations) / totalRealCost) * 1000.0
        return rate - formulaBorderPer1k
    }

    /// 保存時ボーダー比の平均に含める
    var participatesInExpectationRatioAggregate: Bool {
        !excludesFromRotationExpectationAnalytics && expectationRatioAtSave > 0
    }

    /// 通算実戦回転率の加重平均の分母（pt）。`totalRealCost` を優先し、0 の旧データは `inputCash`（pt）で代替（実戦保存時の補正と同趣旨）。
    var rotationRateDenominatorPt: Double {
        if totalRealCost > 0 { return totalRealCost }
        return Double(inputCash)
    }
}


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
/// 出玉(defaultPrize), 賞球数(countPerRound), 電サポゲーム数(supportLimit)。
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
    /// 貸玉数（500pt あたり玉数）。未設定の解釈は `interpretedBallsPer500Pt`（`PersistedDataSemantics`）。
    var ballsPerCashUnit: Int = PersistedDataSemantics.defaultBallsPer500Pt
    /// 交換率（1玉あたりのpt＝店レート設定の「交換率」）。未設定の解釈は `interpretedPayoutCoefficientPtPerBall`。
    var payoutCoefficient: Double = PersistedDataSemantics.defaultPayoutCoefficientPtPerBall
    /// 持ち玉払い出し数（投資ボタン1回で消費する玉数）。**0** のときは `ballsPerCashUnit`（貸玉数）と同じ扱い。
    var holdingsBallsPerButton: Int = 0
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
    init(name: String, ballsPerCashUnit: Int, payoutCoefficient: Double, placeID: String? = nil, address: String = "", holdingsBallsPerButton: Int = 0) {
        self.name = name
        self.ballsPerCashUnit = ballsPerCashUnit
        self.payoutCoefficient = payoutCoefficient
        self.placeID = placeID
        self.address = address
        self.holdingsBallsPerButton = holdingsBallsPerButton
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
    /// 当選までの通常時に「現在の持ち玉数に合わせる」で積算した持ち玉投資調整（玉）。旧データは nil
    var normalPhaseHoldingsReconcileBalls: Int? = nil
    /// この当たり区間（大当たりモード／赤残）中に同機能で積算した調整（玉）。旧データは nil
    var bonusPhaseHoldingsReconcileBalls: Int? = nil
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
    /// 実戦開始時刻（「続きから」復元用）。旧データは nil
    var sessionStartedAt: Date? = nil
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
    /// 直前の通常区間で「現在の持ち玉数に合わせる」の調整玉の積算。旧データは nil
    var normalSegmentHoldingsReconcileAccumulator: Int? = nil
    /// 大当たり突入時に直前通常区間分として退避した調整玉。旧データは nil
    var stashedNormalHoldingsReconcileForBigHit: Int? = nil
    /// 大当たりモード中の同機能の調整玉の積算。旧データは nil
    var bigHitSegmentHoldingsReconcileAccumulator: Int? = nil
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
    static let launchEndColor = Color(
        red: DesignTokens.System.rootBackgroundR,
        green: DesignTokens.System.rootBackgroundG,
        blue: DesignTokens.System.rootBackgroundB
    )
    /// 従来の単色用（他で参照されている場合）
    static let iconBackgroundColor = launchEndColor
}

enum AppTheme: String, CaseIterable, Codable {
    /// 保存キー（表示名変更に強い）
    case dark = "dark"

    /// 設定画面などの表示用（システムのダークモードとは別：アプリ内配色）
    var settingsDisplayName: String {
        "ダーク（黒ベース）"
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
        default:
            self = .dark
        }
    }

    var backgroundColor: Color {
        Color(
            red: DesignTokens.System.appChromeBackgroundR,
            green: DesignTokens.System.appChromeBackgroundG,
            blue: DesignTokens.System.appChromeBackgroundB
        )
    }

    var accentColor: Color {
        Color(
            red: DesignTokens.Semantic.Standard.highlightAccentR,
            green: DesignTokens.Semantic.Standard.highlightAccentG,
            blue: DesignTokens.Semantic.Standard.highlightAccentB
        )
    }

    var textColor: Color {
        .white
    }

    // MARK: - 実戦画面（PlayView）のベース色

    var playScreenBase: Color {
        Color(hex: DesignTokens.Color.backgroundHex)
    }

    var playHeaderBackground: Color {
        .black
    }

    var playPanelBackground: Color {
        Color.black.opacity(DesignTokens.Surface.BlackOverlay.playLogPanelFill)
    }

    /// ドロワー背後のスクリーム
    var playDrawerScrim: Color {
        Color.black.opacity(DesignTokens.Surface.BlackOverlay.playIntegerPadWell)
    }

    /// 実戦ヘッダー・パネル上の主テキスト
    var playLabelPrimary: Color {
        .white
    }

    var playLabelSecondary: Color {
        Color.white.opacity(DesignTokens.Surface.WhiteOnDark.playSecondaryText)
    }

    var playMutedIcon: Color {
        Color.white.opacity(DesignTokens.Surface.WhiteOnDark.playMutedGlyph)
    }
}

/// 個人の遊技記録（店舗名・収支・内部 JSON・スナップショット等を含む）。
///
/// - Important: CloudKit **Public Database** には送信しないこと。将来クラウド同期する場合は
///   `UserSessionSyncService`（Private DB）経路のみを想定する。共有マスタは `SharedMachineCloudKitService`。
@Model
final class GameSession {
    var id: UUID = UUID()
    /// 履歴一覧・分析の月別・日別キー。実戦保存時は `endedAt` と揃える（日付またぎは「終了した日」側に計上）。
    var date: Date = Date()
    /// 実戦開始時刻（実戦フロー）。旧データは nil
    var startedAt: Date? = nil
    /// 実戦終了時刻（保存時刻）。旧データは nil
    var endedAt: Date? = nil
    var machineName: String = ""
    /// 実店舗の識別に近い個人情報。Public 同期ペイロードに含めないこと。
    var shopName: String = ""
    var manufacturerName: String = ""  // 保存時メーカー（分析用）
    var inputCash: Int = 0             // 投資（現金）
    var totalHoldings: Int = 0         // 回収玉数
    var normalRotations: Int = 0       // 総回転数（通常）
    var totalUsedBalls: Int = 0        // 総消費玉数
    var payoutCoefficient: Double = 0.0 // 払出係数（統計シミュレーション用）
    var totalRealCost: Double = 0      // 実質投資（pt換算）
    var expectationRatioAtSave: Double = 0  // 保存時ボーダー比
    var theoreticalValue: Int = 0      // 期待値（pt）
    var rushWinCount: Int = 0          // 実戦で入力したRUSH当選回数
    var normalWinCount: Int = 0        // 実戦で入力した通常当選回数
    /// 保存時の機種ボーダー（回/1k・等価・補正前）。`border` を数値化したもの（SwiftData フィールド名は互換のため `formulaBorderPer1k` のまま）
    var formulaBorderPer1k: Double = 0
    /// 保存時点の店補正後ボーダー（回/1k）。貸玉・払出係数を反映（`GameLog.dynamicBorder` と同定義）
    var effectiveBorderPer1kAtSave: Double = 0
    /// 保存時点の実質回転率（回/千pt実費）。`normalRotations ÷ (totalRealCost÷1000)`（`GameLog.realRate` と同定義）
    var realRotationRateAtSave: Double = 0
    /// 初当たり時点までの実質投資（pt）。実戦からの保存時のみ埋まる。手入力・旧データは nil
    var firstHitRealCostPt: Double? = nil
    /// 実戦終了時の精算区分。空＝未記録（アップデート前データ）
    var settlementModeRaw: String = ""
    /// 「換金」を選んだときの 500pt 刻みの換金額。貯玉のみのときは 0。
    var exchangeCashProceedsPt: Int = 0
    /// この実戦の保存で店舗の貯玉残高に加算した玉数（貯玉精算＝全玉、換金＝端数玉）。
    var chodamaBalanceDeltaBalls: Int = 0
    /// シンプル入力など「投資・回収のみ」の行。分析では回転率・ボーダー差・ボーダー比の平均から除外（実成績・期待値の合計は従来どおり）。
    var isCashflowOnlyRecord: Bool = false
    /// 詳細編集の「初当たりブロック」JSON（空＝未使用・旧フォーム相当）
    var editSessionPhasesJSON: String = ""
    /// 履歴スランプグラフ用：保存時点の `WinRecord` / `LendingRecord`（ISO8601 JSON）。空＝旧データはフェーズ／2点近似
    var slumpChartWinRecordsJSON: String = ""
    var slumpChartLendingRecordsJSON: String = ""
    var slumpChartInitialHoldings: Int = 0
    var slumpChartInitialDisplayRotation: Int = 0
    /// 0 のときは `SessionSlumpChartForSessionView` 側で 125 を仮定
    var slumpChartHoldingsBallsPerTap: Int = 0
    /// `GameSessionSnapshot` を JSON エンコードしたバイト列。nil＝未保存の旧データ。
    var snapshotData: Data? = nil
    /// シンプル入力の「通常時／セッション」タイムライン（JSON）。空＝未使用・旧データ
    var simplePlayTimelineJSON: String = ""

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
        self.theoreticalValue = PStatsCalculator.theoreticalValuePt(
            totalRealCostPt: totalRealCost,
            expectationRatio: expectationRatioAtSave
        )
        self.rushWinCount = rushWinCount
        self.normalWinCount = normalWinCount
        self.formulaBorderPer1k = formulaBorderPer1k
    }

    /// 成績（回収 − 投資・pt）。永続データで `totalHoldings` が負のときは回収 0 扱い（`PStatsCalculator` と整合）。
    var performance: Int {
        PStatsCalculator.performancePt(
            inputCashPt: inputCash,
            totalHoldingsBalls: max(0, totalHoldings),
            payoutCoefficientPtPerBall: payoutCoefficient
        )
    }

    /// 欠損・余剰（成績 − 期待値）。正＝期待値より得、負＝期待値より損。期待値は `analyticsTheoreticalValuePt`（スナップショット優先）。
    var deficitSurplus: Int {
        PStatsCalculator.deficitSurplusPt(performancePt: performance, theoreticalValuePt: analyticsTheoreticalValuePt)
    }
}

// MARK: - 分析での母集団（帳簿のみ行の扱い）

extension GameSession {
    /// 実戦時間（秒）。開始/終了が無い、または不正な場合は nil。
    var playDurationSeconds: TimeInterval? {
        guard let s = startedAt, let e = endedAt else { return nil }
        let d = e.timeIntervalSince(s)
        guard d.isFinite, d > 0 else { return nil }
        return d
    }

    /// 時給（pt/h）。実戦時間が取れない場合は nil。
    var hourlyWagePt: Double? {
        guard let sec = playDurationSeconds else { return nil }
        let hours = sec / 3600.0
        guard hours > 0 else { return nil }
        let v = Double(performance) / hours
        return v.isFinite ? v : nil
    }

    /// 表示用の実質回転率（回/千pt実費）。`totalRealCost` を優先して再計算（保存値と定義が一致しない旧行を吸収）。
    var displayRealRotationRatePer1k: Double? {
        PStatsCalculator.realRotationRatePer1k(
            normalRotations: normalRotations,
            totalRealCostPt: totalRealCost,
            fallbackRateAtSave: realRotationRateAtSave
        )
    }

    /// 保存時の店補正ボーダー。保存値が 0 のときは nil（黙って 0 回/1k とみなさない）。
    var displayEffectiveBorderPer1kAtSave: Double? {
        effectiveBorderPer1kAtSave > 0 ? effectiveBorderPer1kAtSave : nil
    }

    /// 保存時期待値比。0 は「未保存/旧」扱いとして nil。
    var displayExpectationRatioAtSave: Double? {
        expectationRatioAtSave > 0 ? expectationRatioAtSave : nil
    }

    /// 分析の「回転・期待値系」から外す行（フラグ付き、または旧DBでシンプル入力と同型の行）
    var excludesFromRotationExpectationAnalytics: Bool {
        if isCashflowOnlyRecord { return true }
        return normalRotations == 0
            && expectationRatioAtSave == 1.0
            && rushWinCount == 0 && normalWinCount == 0
    }

    /// 実戦で記録した当選回数の合計（通常・RUSH）
    var totalRecordedWinCount: Int { rushWinCount + normalWinCount }

    /// 履歴スランプ用に保存した当たり・投資ログをデコード（失敗時は空）。
    func decodedSlumpWinsAndLendings() -> ([WinRecord], [LendingRecord]) {
        let wins: [WinRecord] = Self.decodeSlumpJSON(slumpChartWinRecordsJSON, as: [WinRecord].self) ?? []
        let lendings: [LendingRecord] = Self.decodeSlumpJSON(slumpChartLendingRecordsJSON, as: [LendingRecord].self) ?? []
        return (wins, lendings)
    }

    private static func decodeSlumpJSON<T: Decodable>(_ json: String, as: T.Type) -> T? {
        guard !json.isEmpty, let data = json.data(using: .utf8) else { return nil }
        if let v = try? JSONDecoder.slumpChart.decode(T.self, from: data) { return v }
        return try? JSONDecoder.slumpChartLenient.decode(T.self, from: data)
    }

    /// 加重回転率・グループ平均回転率に含める
    var participatesInRotationRateAnalytics: Bool { !excludesFromRotationExpectationAnalytics }

    /// ボーダーとの差（分析では通常回転数加重平均の重みに含める）に含める。新規は店補正ボーダー＋realRate、旧データは等価ベースのボーダー＋totalRealCost 基準で比較可能なとき
    var participatesInBorderDiffAnalytics: Bool {
        sessionBorderDiffPer1k != nil
    }

    /// ボーダーとの差（回/1k、実質回転率 − 店補正後ボーダー）。`displayRealRotationRatePer1k`（実費ベース）を優先。
    var sessionBorderDiffPer1k: Double? {
        PStatsCalculator.sessionBorderDiffPer1k(
            excludesFromRotationExpectationAnalytics: excludesFromRotationExpectationAnalytics,
            normalRotations: normalRotations,
            totalRealCost: totalRealCost,
            realRotationRateAtSave: realRotationRateAtSave,
            effectiveBorderPer1kAtSave: effectiveBorderPer1kAtSave,
            formulaBorderPer1k: formulaBorderPer1k
        )
    }

    /// 保存時ボーダー比の平均に含める（スナップショット再計算値を優先）
    var participatesInExpectationRatioAggregate: Bool {
        !excludesFromRotationExpectationAnalytics && analyticsExpectationRatio > 0
    }

    /// 通算実戦回転率の加重平均の分母（pt）。`totalRealCost` を優先し、0 の旧データは `inputCash`（pt）で代替（実戦保存時の補正と同趣旨）。
    var rotationRateDenominatorPt: Double {
        PStatsCalculator.rotationRateDenominatorPt(totalRealCostPt: totalRealCost, inputCashPt: inputCash)
    }
}


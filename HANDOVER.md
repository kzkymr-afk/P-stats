# P-stats 引き継ぎサマリー

次のチャットで開発を続ける際の仕様・構成の整理です。

---

## 1. プロジェクト概要

- **P-stats**: 実戦中の回転カウント・投資・大当たり記録と、ボーダー・期待値の算出を行う iOS アプリ（SwiftUI + SwiftData）。
- **メイン画面**: 通常は **SENSING**（実戦計測）。右下の大きなタップエリアで回転カウント、左側で投資・大当たり・各種シートを操作。
- **デザイン方針**: アイコン・オーバーレイは **水色（cyan）** と **ダークネイビー** を基本トーンに。「収支は運、期待値は実力」など打ち手のメンタルに寄り添う表現を採用。

---

## 2. 用語・モード名（仕様上の呼び方）

| 用語 | 意味 |
|------|------|
| **SENSING** | 通常の実戦画面。回転カウント・投資・大当たり入力ができる状態。 |
| **Bonus Standby** | 待機モード。画面を暗くし中央の円が呼吸するように明滅。誤操作防止で入力をロック。長押しで進入、ダブルタップで結果入力へ。 |
| **FOCUS / 集中モード（右打ち中）** | あたり中のリアルタイムモニター（旧 BONUS MONITOR）。1R純増スライダーで実効ボーダーを表示。 |
| **RESULT / 結果入力（今回の回収）** | 連チャン終了時の一括入力。Set Count・Total Gain を入力し、1R実効純増を機種にフィードバック。 |
| **インサイトパネル** | 右端スワイプで開くドロワー。今日の期待値・あと何回でプラス転換などを表示（マルチタスク・暇つぶし用）。 |
| **PowerSavingModeView** | 省エネモード。ジェスチャー＋タップのミニマルUI。機種名長押しで起動。下部タップ=回転、左端スワイプ=1k投資。 |

---

## 3. 主要ファイルと役割

| ファイル | 役割 |
|----------|------|
| **PlayView.swift** | 実戦メイン画面。SENSING のレイアウト、カウントボタン、各種シート・オーバーレイの表示制御。インサイトパネル・Bonus Standby の入口もここ。 |
| **GameLog.swift** | 実戦セッションの状態（@Observable）。selectedMachine/Shop、回転数・投資・大当たり履歴、effective1RNetPerRound / dynamicBorder / expectationRatio / totalRealCost 等の計算。 |
| **Models.swift** | SwiftData モデル。Machine, Shop, MachinePrize, GameSession, WinRecord, LendingRecord 等。Machine の netPerRoundBase は連チャン結果入力で更新される。 |
| **BonusStandbyView.swift** | `BonusStandbyOverlay`（暗転・呼吸する円・ダブルタップでコールバック）、`ChainResultInputView`（Set Count / Total Gain 入力→1R純増フィードバック→「今回の期待値（仕事量）：＋◯◯円」「収支は運、期待値は実力」のフィードバック表示）。 |
| **BonusMonitorView.swift** | FOCUS（集中モード）。1R純増スライダー・実効ボーダー・期待値ゲージ。終了で「集中モードを終了」ダイアログ。 |
| **InsightPanelView.swift** | インサイトパネル本体。今回の期待値（円）、あと何回でプラス転換、今日の実戦サマリ。水色・ダークネイビー。左スワイプ／×／dim タップで閉じる。 |
| **PowerSavingModeView.swift** | 省エネモード。ジェスチャー＋タップ、周辺発光・波紋。 |
| **MachineShopSelectionView.swift** | 機種・店舗選択。保存済み Machine/Shop の選択と log への反映。 |
| **AnalyticsDashboardView.swift** / **AnalyticsEngine.swift** | 保存セッションの分析（店舗・機種・メーカー別）。 |

---

## 4. 実装済み機能の要点

### 4.1 連チャン終了時の一括集計

- **進入**: 通常画面で**カウントエリアを長押し** → Bonus Standby → **ダブルタップ**で結果入力シート。
- **入力**: Set Count（連チャン数）、Total Gain（最終獲得玉数）。銀行振込風の清潔なUI。
- **計算**: 実測玉数 ÷ (連チャン数 × 1当たりR数) で 1R あたり実効純増を算出し、50〜250 でクランプして `machine.netPerRoundBase` に反映。今回の期待値（仕事量）＝ totalRealCost × (現在回転率/新ボーダー − 1)。
- **フィードバック**: 「今回の期待値（仕事量）：＋◯◯円」を大きく水色で表示。「収支は運、期待値は実力」でメンタルサポート。タップで SENSING に戻る。

### 4.2 インサイトパネル（マルチタスク用）

- **開く**: 画面**右端 24pt を左方向にスワイプ**。
- **表示**: 今回の期待値（円）、あと何回でプラス転換、回転数・実質コスト・実戦B・期待値比。
- **閉じる**: パネル上で左スワイプ、×ボタン、背面の dim タップ、**画面を伏せる**（UIDevice.orientation == .faceDown）。
- **重要**: パネル表示中も**右下のカウントボタンは .zIndex(1) で最前面**にあり、タップで回転カウント可能（カウントを逃さない）。

### 4.3 その他

- **FOCUS**: タイトル「FOCUS」＋サブ「集中モード（右打ち中）」、ボタン「終了」、確認「集中モードを終了」。
- **PowerSavingModeView**: 省エネモード。機種名長押しで起動。`showPowerSavingMode` で表示。

---

## 5. データ・計算の参照先

- **実質コスト**: `GameLog.totalRealCost`（現金＋持ち玉を円換算）。
- **通常回転数**: `GameLog.normalRotations`。
- **実戦ボーダー**: `GameLog.dynamicBorder`（回転/1000円）。
- **期待値比**: `GameLog.expectationRatio`（現在回転率 ÷ 実戦ボーダー）。1.0 でボーダー、>1 で上回り。
- **1R純増の更新**: `ChainResultInputView` の確定時に `machine.netPerRoundBase` を書き換え（@Bindable で同一インスタンスを渡しているため永続化対象に反映）。

---

## 6. 次のチャットでやりたいことの例

- インサイトパネルに「過去の分析データ・統計グラフ」を追加する。
- パフォーマンス改善（重くなってきたとのことなので、不要な再計算・View の見直しなど）。
- 新機能追加時は、用語（SENSING / FOCUS / RESULT）と水色・ダークネイビーのトーンを引き継ぐと一貫する。

---

## 7. キーパス一覧（検索用）

- 実戦メイン: `P-stats/PlayView.swift`
- セッション状態: `P-stats/GameLog.swift`
- モデル: `P-stats/Models.swift`
- 連チャン結果・Bonus Standby: `P-stats/BonusStandbyView.swift`
- 集中モード: `P-stats/BonusMonitorView.swift`
- インサイトパネル: `P-stats/InsightPanelView.swift`
- 省エネモード: `P-stats/PowerSavingModeView.swift`
- 機種・店舗選択: `P-stats/MachineShopSelectionView.swift`

この `HANDOVER.md` を次のチャットの最初に共有すると、仕様とファイル構成をすぐ引き継げます。

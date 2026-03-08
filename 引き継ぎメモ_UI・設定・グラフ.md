# 引き継ぎメモ（UI・設定・あたり中グラフまわり）

新しいチャットで続きの作業をするときのための要点まとめです。

---

## 1. あたり中グラフ（ChanceModeView / RushFocusView）

### 仕様
- **横軸**: 総回転数。左端 0G、右端 1000G。1001G 以降は 100G 刻みで表示範囲がスライド（100–1100G、200–1200G …）。
- **データ**: `GameLog.chartPointsByRotation`（回転数, 損益円）を使用。
- **タイトル**: 「収支グラフ」（パネル内に収める。フォント size 12、padding で枠内表示）。
- **枠線**: パネル内側のグラフ外周枠線はなし。**軸と収支 0 ラインのみ**表示。
- **縦軸**: 1000円刻みでメモリ、10000円単位で数値ラベル（例: +1万, 0, -1万）。ラベルはチャート左内側に配置。
- **横軸**: 100G ごとにメモリとラベル（0, 100, 200, … 1000 または窓の範囲）。

### 実装箇所
- **ChanceModeView.swift**: `profitLineChartView(height:)`、`yTickValues` / `yLabelValues` / `xTickValues`、`private extension Double`（`rounded(downTo:)` / `rounded(upTo:)`）。**拡張の末尾に `}` が必要**（過去に閉じ括弧漏れでビルドエラーあり）。
- **RushFocusView.swift**: 上記と同様のチャートロジック。RUSH 用パネル（`panelBg`, `glassStroke`, 角丸 14）でラップ。`chartPointsByRotation` 使用、`roundedRush(downTo:)` / `roundedRush(upTo:)` は別名で拡張。

### 窓の計算
- `leftRot = totalRot > 1000 ? ((totalRot - 1) / 100) * 100 : 0`
- `rightRot = leftRot + 1000`

---

## 2. フレームまわりのランタイムエラー対策

- **Invalid frame dimension (negative or non-finite)** を防ぐため、チャート高さや `height` をそのまま `.frame(height:)` に渡さない。
- **ChanceModeView / RushFocusView**: `safeHeight = (height.isFinite && height > 0) ? height : 44`、`chartH = max(1, safeHeight - 24)` または `max(1, safeHeight - 44)`。`.frame(height: chartH)` には `max(1, chartH)` を渡す。
- **PowerSavingModeView**: 同様に `mainH` / `topHalfH` などを `max(44, ...)` などで正の有限値にしている。

---

## 3. ドロワー（InsightPanelView）

- **今回の収支**
  - 上段: ラベル「**実際の収支**」。収入−現金投資（現金投資に対する回収金額）。
  - 下段: ラベル「**期待値収支（理論上の損益）**」。実費×（期待値比−1）。
- **修正**: 「**大当たり回数を修正**」を追加。RUSH 回数・通常回数を編集するシート（`WinCountCorrectView`）を表示。`GameLog.setWinCounts(rush:normal:)` で `winRecords` を差し替え（持ち玉数は変更しない）。
- **設定**: ヘッダー直下に「**設定**」ボタンを常時表示（通常モード中もドロワーから設定へ遷移可能）。

---

## 4. 通常大当たり後の画面遷移

- **変更**: 通常大当たり入力後に **ChanceModeView（通常あたりモード）へ移行しない**。メインの PlayView のまま。
- **PlayView**: `tempWinType == .normal && timeShortRotations > 0` のときに `showChanceMode = true` にしていた処理を削除済み。

---

## 5. 設定「デフォルト設定」と投資ボタン表示

### 設定画面（P_statsApp.swift）
- カードタイトルを「新規遊技時のデフォルト設定」→「**デフォルト設定**」に変更。
- 追加項目: **「常に現金投資・持ち玉投資両方を表示」**（オン/オフ）。
  - キー: `UserDefaults` の `alwaysShowBothInvestmentButtons`（デフォルト true）。
  - 説明: オフ時は持ち玉 0 なら現金のみ、持ち玉ありなら持ち玉のみ表示（ボタンは 2 つ分の大きさ）。

### 通常モードの投資ボタン（PlayView.centerActionRow）
- **両方表示オン**: 現金投資・持ち玉投資の 2 ボタンを従来どおり表示。
- **両方表示オフ**:
  - 持ち玉数 0 → **現金投資ボタンのみ**（`frame(maxWidth: .infinity).frame(height: height)` で 2 つ分の大きさ）。
  - 持ち玉数 > 0 → **持ち玉投資ボタンのみ**（同様に 2 つ分の大きさ）。
- `@AppStorage("alwaysShowBothInvestmentButtons")` で設定を参照。

---

## 6. 持ち玉投資の 125 玉以下

- **仕様**: 持ち玉が 125 玉未満（例: 50 玉）のときは、押下時にその残り玉数（50 玉）を 1 回の投資として記録し、回転率計算にもその玉数で反映する。
- **実装**: `GameLog.addLending(type: .holdings)` で `deduct = min(holdingsBallsPerTap, max(0, totalHoldings))` を使用。`LendingRecord(..., balls: deduct)` で記録。`holdingsInvestedBalls` は `($1.balls ?? holdingsBallsPerTap)` で合算。**変更なしで仕様どおり。**

---

## 7. 関連ファイル一覧

| ファイル | 主な変更・役割 |
|----------|----------------|
| **ChanceModeView.swift** | あたり中グラフ（総回転数・収支グラフ・軸メモリ）、extension Double の閉じ括弧 |
| **RushFocusView.swift** | 上記と同仕様のグラフ、RUSH パネルでラップ |
| **InsightPanelView.swift** | 今回の収支ラベル、大当たり回数修正ボタン、設定ボタン |
| **PlayView.swift** | 通常大当たり後の ChanceMode 移行削除、投資ボタン表示制御（alwaysShowBothInvestmentButtons）、WinCountCorrect シート |
| **GameLog.swift** | `setWinCounts(rush:normal:)` |
| **P_statsApp.swift** | 設定「デフォルト設定」、常に両方表示トグル |

---

## 8. パフォーマンスの最適化と入力バリデーション（2026/03最新）

### GameLog クラスのキャッシュ化
- 状態変更ごとに重い計算が走るのを防ぐため、計算の依存プロパティからハッシュ（`chartStateHash`, `expectationStateHash`）を生成。
- 状態ハッシュが変わらない限り `@ObservationIgnored` に保存したキャッシュを返すように修正。
- `liveChartPoints` の計算において、M件×N件ループになっていた箇所を、日付順ソート済みの配列をインデックスで進める O(N+M) に改善。

### AnalyticsDashboardView の再計算削減
- `@Query` の結果（`sessions`）を computed property 内で毎度 `filter`・`map` して子Viewの `ForEach` 等に渡していたため、広範囲で再描画や重い処理が走る問題があった。
- `@State private var cachedFilteredSessions`, `cachedAllGroups` などの状態プロパティを持たせ、`.onChange`（Query結果、フィルタ変更時）と `.onAppear` でのみ `updateCaches()` を実行してキャッシュ配列に格納。これにより無駄な再計算を防止。

### 各入力画面のバリデーション強化
- **MachineEditView**: 確率分母（1/xxx）のフォーマットやゼロ以下入力、各種回数・ボーダーの負の数、空の機種名をブロックしてエラーアラートを表示。
- **ShopEditView**: 貸玉料金や交換率が0以下の入力をブロック。
- **MachineShopSelectionView**: 新規遊技開始時に「開始時回転数」や「開始時持ち玉」に負の数が入力されるのを `.onChange` で防ぎつつ、遊技開始ボタン押下時にも再検証する仕組みを追加。
- **AnalyticsDashboardView / GameSessionEditView**: 実戦履歴の編集（保存）時に、選択忘れ（nil）の防止と、すべての数値項目（投資、回収、回転数など）の負の数入力をブロック。
- **PlayView 各種ポップアップ**: 当たり入力や同期（`SyncInputView`, `WinCountCorrectView`）、最終回収出玉の確認ダイアログでも、負の数が入力された際の決定をブロック。

### UIの改善・明記
- `GameSessionEditView` の「実践データ」セクションフッターに `総回転数＝通常回転のみ（時短・電サポ除く）` と明記し、データの入力ミス・解釈ミスを防ぐよう文言を追加。

---

## 9. 次のチャットで続ける場合の例

- あたり中グラフの見た目調整（フォントサイズ・メモリ間隔・ラベル位置）。
- 設定項目の追加や、他画面への「両方表示」設定の反映。
- ドロワーや分析画面の表示・ナビゲーション改善。

# デザイン直書き（色・線・影）監査チェックリスト

**運用原則・今後のルール**は `docs/デザイン・トークン原則.md` を正とする。機械チェックは `./scripts/check_design_literals.sh`（数値直書きのみ検出）。

パネル類を CSS のように **1か所に完全集約** するには至っていない。以下は **「まだ View 内に `Color.white/black` や `Color(red:…)` が多いファイル」** を機械カウントした優先度リスト（スナップショット）。

## カウント方法（再現用）

リポジトリルートで:

```bash
grep -R -l -E 'Color\.(white|black)\.opacity|Color\(red:' P-stats --include='*.swift' \
  | while read f; do
      n=$(grep -c -E 'Color\.(white|black)\.opacity|Color\(red:' "$f")
      echo "$n $f"
    done | sort -t' ' -k1 -nr
```

- **含まない**: `AppGlassStyle.accent` のような名前付き参照、`.shadow` のみ、UIKit の `UIColor`。
- **参考値**: トークン定義ファイル（`AppGlassStyle.swift` 等）は件数が多くても「定義の集中」なので優先度は下げる。

## 優先度リスト（件数多い順・上記 grep 基準・2026-04 時点）

※ 件数は `Color.white/black.opacity` と `Color(red:` の **行マッチ数**。再スキャンで変わる。

| 優先 | 件数 | ファイル | メモ |
|:---:|:---:|:---|:---|
| ☑ 済 | 0 | `SessionSlumpLineChartView.swift` / `SessionSlumpChartForSessionView.swift` | 描画は **`Design/SessionSlumpChartShared.swift`** に集約（当該パターンの直書きなし） |
| ☑ 集約先 | 7 | `Design/SessionSlumpChartShared.swift` | スランプチャートの色・線・パネルはここだけを見ればよい |
| 1 | 55 | `Features/Play/PlayView.swift` | 実戦固有の `glassStroke`・`playButtonChrome`・シート・大当たり演出など |
| 2 | 39 | `Features/Analytics/AnalyticsDashboardView.swift` | チャート・カード・ナビ。`pstatsPanelStyle` 併用箇所あり |
| 3 | 32 | `Features/Common/Share/SessionShareTemplates.swift` | **共有画像用**のため独自パレットは意図的。共通化はテンプレ単位で十分 |
| — | 18 | `Design/AppGlassStyle.swift` | **定義の集中**。件数は多いが削減対象ではない |
| — | 12 | `Design/AppTheme.swift` | 同上 |
| — | 9 | `Design/ApplicationTheme.swift` | 同上（Neon 等のスキン実装） |
| 4 | 11 | `Features/MachineShop/MachineShopSelectionView.swift` | リスト＋ゲート UI |
| 5 | 11 | `Features/MachineShop/MachineEditView.swift` | フォーム行背景の直書きが多い |
| 6 | 10 | `Features/Play/PlaySessionSwipeHintBar.swift` | ネオン風シャドウ |
| 7 | 8 | `Features/Play/SlideToConfirmBigHitRail.swift` | スライドレール |
| 8 | 7 | `App/SettingsTabView.swift` | 設定タブ |
| 9 | 5 | `App/HistoryAndManagementViews.swift` | 一部グラフ・シャドウ |
| 10 | ≤4 | 広告・精算・省電力・Home パネル・Composer 等 | 必要に応じて `AppGlassStyle` / テーマへ寄せる |

## 既存の「集約の核」（参照用）

- **数値トークン**: `Design/DesignTokens.swift`
- **スキン契約（フェーズ1 拡張済み）**: `Design/ApplicationTheme.swift`  
  - サーフェス: `panelSecondaryBackground`, `inputFieldBackground`, `panelElevatedSecondaryBackground`, `listRowBackground`  
  - セマンティック: `investmentColor`, `recoveryColor`, `jackpotColor`（＋既存の `play*` / インサイト）  
  - シャドウ: `ThemeShadowSpec` と `cardShadow` / `interactiveSurfaceShadow*` / `listSelectionShadow` / `compactLabelShadow` / `railShadow` / `splash*`  
  - `View.themeShadow(_:)` は `Design/ViewModifiers.swift`
- **ダークグラス色（既定スキン＝`DefaultTheme.shared` に追従）**: `Design/AppGlassStyle.swift`
- **パネル部品**: `Design/AppPanels.swift`（`AppGlassPanel` / `pstatsPanel`）
- **スキン連動パネル**: `Design/ViewModifiers.swift`（`pstatsPanelStyle()`）
- **スランプチャート**: `Design/SessionSlumpChartShared.swift`（`SessionSlumpChartStyle`）

## フェーズ6（2026-04）メモ

- **`DesignTokens.Surface`** … 暗背景上の白オーバーレイ階層・黒スクリム・アクセント薄塗りの不透明度を集約。`Opacity.panelSecondary*` は `Surface` を参照。
- **`DesignTokens.Elevation` / `Thickness`** … 既定テーマのシャドウ半径・オフセット、ヘアライン幅。
- **`ApplicationTheme`** … `surfacePrimary` / `surfaceSecondary` / `overlayDark` / `cautionForegroundColor` / `highlightAccentColor` を追加。`chartTheoreticalAccentColor` は `Semantic` のトークン化済みシアン／オレンジ相当 RGB。
- システム色置換の例: `PlayView` の `Color.cyan`/`Color.red`、`InsightPanelView` / `CsvSessionImportSheetView` の `Color.orange`、`AppTheme.accentColor` の `.cyan`。

## 次の一手（提案）

1. `PlayView` の繰り返しグラデ（白〜ティント枠）を `AppGlassStyle` または `ApplicationTheme` のメソッドに寄せる。
2. `MachineEditView` の `Color.white.opacity(0.08)` 行を `AppGlassPanel(variant: .row)` 等へ置換。
3. `SessionSlumpChartForSessionView` と同型の **別チャート** が増えたら `SessionSlumpChartCanvas` を再利用。

# P-stats デザインシステム（Surface 中心）

**数値の正**は常に `P-stats/Design/DesignTokens.swift`。**運用ルール**（直書き禁止・チェック方法）は `docs/デザイン・トークン原則.md`。

この文書は、**`DesignTokens.Surface` が「何のための階層か」**と、**新スキンを足すときの手順**をまとめた参照用です。

---

## 1. レイヤー構造の考え方

- **暗背景**を前提に、**白のオーバーレイ不透明度**（`WhiteOnDark`）と**黒のスクリム**（`BlackOverlay`）を分ける。
- **色の色相**（アクセント・RUSH・投資など）は **`ApplicationTheme`**（スキン）側。**どれだけ乗せるか**のスカラーは **`Surface` / `AccentTint` / `Thickness` / `Elevation`** に寄せる。
- 画面固有の演出が必要なら、まず **`Surface.Play`** のように **名前空間で閉じる**（汎用階層の汚染を防ぐ）。

---

## 2. `Surface.WhiteOnDark` — 暗背景上の「白」の意図

### 2.1 面の階段（薄い → 濃い）

| トークン | 使う場面の目安 |
|---------|----------------|
| `ultraLow`〜`medium` | ガラス面のうすい膜、チャートのごく淡いグリッド、フォーム深部（`formDeep` 系は Neon 用のより弱い段もあり） |
| `elevated` | パネル上の二次面、メタルボタンのハイライト寄りの帯（`playButtonChrome` の上端など） |
| `outlineSubtle`〜`strong` | 枠・区切りで「線」として見せたい白 |
| `high` | ややはっきりしたオーバーレイ（汎用の濃いめ帯） |
| `hairlineStrong` | 細いがコントラスト欲しい線（チャート軸寄り） |

**原理**: 同じ「0.1 前後」でも **文脈が違えば別名**にする。新規 UI では「近い既存トークンに寄せる」か「意味が違うなら新名で `DesignTokens` に追加」する。

### 2.2 テキスト・ラベル（読みの階層）

| トークン | 使う場面の目安 |
|---------|----------------|
| `textPrimary` | 本体ラベル（約 0.92 相当の主文） |
| `nearOpaqueLabel` | シート内の強いラベル・破壊的操作でも視認性を落としたくない白 |
| `textSecondary` / `textTertiary` | 補助説明の段階的な弱め |
| `captionOnPanel` | キャプション・注意書きの一段弱い白 |
| `disabled` | トグルオフや無効時のグレーアウト文字 |
| `sheetIntro` | シート先頭の説明文 |
| `footnoteOnSheet` | 脚注・補足（`info` ボタンや長めの注釈） |
| `supportingLabel` | サブ行・説明の二段目 |
| `metaHint` | メタ情報・さらに弱いヒント |

### 2.3 チャート・ゲージ

| トークン | 使う場面の目安 |
|---------|----------------|
| `chartRule` / `chartGrid`〜`chartFaint` | ルール線・主／副グリッドの強弱 |
| `chartAxis` / `chartLabelY` / `chartLabelX` など | 軸・目盛ラベルの視認性バランス |
| `chartBarBaseline` | 棒グラフ下のベースライン |
| `borderMeterTrack`〜`borderMeterMuted` | 実戦ボーダーメーターのトラック・目盛・マーカーまわり |
| `gaugeLine` / `divider` / `separatorFaint` | 汎用の細線・区切り |

### 2.4 フォーム・クロム

| トークン | 使う場面の目安 |
|---------|----------------|
| `formDeep` / `formMuted` / `formMid` / `formDeepNeon` | フォームキャンバスの深い階層（標準／Neon で段数調整） |
| `chromeBorder` | シート・クロム UI の枠 |
| `strokeInputWell` | 数値パッド・入力井のストローク |
| `analyticsAuxiliaryRowNeon` | 分析まわりの補助行（Neon スキン向けの弱い面） |

### 2.5 実戦・演出専用（汎用に流用しない）

| トークン | 使う場面の目安 |
|---------|----------------|
| `winHistoryAccentStroke` | 大当たり履歴で虹帯時などの強調ストローク |
| `rainbowSubtitle` | 連チャンカードの副題（虹背景時） |

---

## 3. `Surface.BlackOverlay` — スクリム・バー・影の土台

| 系統 | 使う場面の目安 |
|------|----------------|
| `shadowLight`〜`shadowCompact` | カード／コンパクト UI の落ち影の黒の強さ |
| `splashDepthStrong` / `splashDepthWeak` | スプラッシュの奥行き |
| `navigationBar` / `navigationBarNeon` | ナビバー背後のスクリム |
| `bottomToolbar` / `bottomToolbarNeon` | 下ツールバー・オーバーレイ |
| `auxiliaryRow` / `datePill` | 補助行・日付ピル |
| `chromeBackdrop` / `chromeBackdropNeon` | 内蔵ブラウザ・クロムシートの背面 |
| `sheetNearOpaque` | ほぼ不透明に近いシート背景 |
| `playSheetBackdrop` / `playToolbarBackground` / `playIntegerPadWell` | **実戦シート**全面・ツールバー・整数パッドの井 |

**原理**: 「バーとシートで同じ不透明度」を共通化したい場合でも、**文脈名**を分けておくと後から片方だけ調整しやすい。

---

## 4. `Surface.AccentTint` — アクセント色を「薄塗り」するとき

実戦の RUSH 帯、警告パネル、リスト選択の光、スプラッシュの光彩など、**色相はスキンのアクセント**、**アルファだけ固定したい**ときに使う。

---

## 5. `Surface.Play` — 実戦クロム専用

| 内側 enum | 役割 |
|-----------|------|
| `GlassChrome` | パネル枠グラデ（`rimOpacityBase` とハイライト／ティント混合比） |
| `ButtonMetal` | メタル風ボタン塗りの黒グラデ中段・下段 |
| `BorderGauge` | ゲージ端ラベル（±5 の赤青）や未信頼ヒントの不透明度 |

**ここにない演出**が増えたら、**`Play` 以下にサブ enum を足す**形を優先する。

---

## 6. `Thickness` / `Elevation`（概要）

- **`Thickness`**: 1pt ライン、Neon 枠、メーターの目盛太さ、シート主ボタンの枠など **線幅の固定値**。
- **`Elevation`**: シャドウの `radius` / `offset`。スキン（標準 vs Neon）で別定数を使い分け。

---

## 7. 「攻め」のステップ（ロードマップ）

### 7.1 水平展開（`Design/` 外の数値直書き）

設定・共有テンプレ・スワイプヒント・スライドレール・広告・省電力などは **`Surface.Settings` / `Interaction` / `ShareCard.Template*` 等**へ集約済み（`P-stats/Design/` **以外**で `check_design_literals.sh` は **exit 0**）。

- チェック: リポジトリルートで `./scripts/check_design_literals.sh`
- `Design/` 内（`AppGlassStyle` 等）の直書きは別タスク。監査メモ: `docs/DESIGN_INLINE_AUDIT.md`

### 7.2 スキン・ビルダーとしての追加

新しい見た目（例: CyberBlue、ClassicPachi）は、**`ApplicationTheme` に準拠した struct を1つ**足し、**`PStatsSkin` に case を追加**して `resolveTheme()` で返す、が基本形です。

1. **色の数値** … 専用なら `DesignTokens` に `enum CyberBlue { static let accentR: Double ... }` のようにまとめる（`NeonCyber` / `Semantic` と同パターン）。
2. **実装** … `NeonCyberTheme` をコピー元にし、`DefaultTheme` のように `DesignTokens.Surface` を参照して `Color.white.opacity(...)` を **トークン名**で組む。
3. **登録** … `PStatsSkin` に `case cyberBlue = "cyberBlue"` などを追加し、設定画面の Picker が `CaseIterable` で拾えるようにする。
4. **必須プロパティ** … `ApplicationTheme` の全要求プロパティを実装する（コンパイラが一覧を出す）。

`ThemeManager.applySkin` が永続化するのは **`PStatsSkin` の rawValue** だけなので、**新 case の `rawValue` は安定させる**（後から文字列を変えない）。

### 7.3 ドキュメント

- **運用・禁止事項** … `docs/デザイン・トークン原則.md`
- **Surface の意味（本書）** … `docs/DESIGN_SYSTEM.md`
- **直書き残りのファイル傾向** … `docs/DESIGN_INLINE_AUDIT.md`

---

## 8. 関連コード一覧（迷ったらここから開く）

| 内容 | パス |
|------|------|
| 数値トークン本体 | `P-stats/Design/DesignTokens.swift` |
| スキン契約 | `P-stats/Design/ApplicationTheme.swift`（`protocol ApplicationTheme`） |
| 既定・ネオン実装 | `DefaultTheme` / `NeonCyberTheme`（同ファイル） |
| スキン enum・永続化キー | `PStatsSkin`（同ファイル） |
| 環境への配信 | `P-stats/Design/ThemeManager.swift` |
| プレビュー用ラッパ | `P-stats/Design/ThemePreviewContainer.swift` |
| 機械チェック | `scripts/check_design_literals.sh` |

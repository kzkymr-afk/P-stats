# 実戦画面（PlayView）仕様・運用メモ

次のチャットで実戦画面の修正を続けるときのためのまとめです。

---

## 1. レイアウト（縦方向）

- **ヘッダー下**: 情報群との間に **12pt** のマージン（Spacer）。
- **ヘッダー**: 上マージン＝画面上端〜**ダイナミックアイランド下端**（`playPanelBackground` で塗る）。ヘッダー本体（タイトル・ボタン）はその直下から表示。上マージン高さはキーウィンドウの `safeAreaInsets.top` を `onAppear` で取得（`headerTopInset`）し使用。`max(headerTopInset, 20)` で最低 20pt 確保。ヘッダーバー高さは **5%**（`h2`）。白アイコン・白テキスト。ヘッダー右側は**設定（歯車）のみ**（電サポボタンはなし）。**ジェスチャーモード**はインサイトパネル（ドロワー）の「閲覧」内に配置。
- **情報行（infoRow）**: 画面の **20%**（`h20info`）。左＝ゲージ（半円）、右＝総回転数・期待値・総投入・持ち玉投資・持ち玉などの各パネル（RUSH/通常の回数は最上段の大当たり回数パネル）。
- **ゲージの縦方向**: 行全体の高さで表示。**ゲージの中心（円の中心）が表示エリアの縦中央**に来るように配置。R = min(幅/2, 高さ/2) ではみ出し防止。左右の位置は「左＝ゲージ、右＝パネル群」。
- **大当たり履歴**: **10%**（`h10`）。
- **スワイプバー**: 高さ **48pt**、角丸 4pt、左右 **16pt** マージンのフローティング。背景 #1A1B1E グラデーション、ハニカム opacity(0.1)、横方向の微細な直線グラデーション（ヘアライン・金属削り出し感）、上端シアン・下端マゼンタの 0.5pt ネオンライン＋shadow(radius: 4)。中央「SWIPE for Information」font(.caption2).bold()。
- **中央行（現金・持ち玉・カウント）**: **22%**（`h22center`）。
- **下部バー（大当たり・遊技終了）**: **min(画面22%, 108pt)**（`barHeight`）。外枠パネルなし。ボタン間隔は **4pt**（`bottomBarSpacing`）。通常時は「大当たり」で `BigHitModeView` へ。

---

## 2. 背景

- **実戦画面の背景**: 設定で「ホームと同じ」または「別の画像」を選択可能。`playViewBackgroundStyle` / `playViewBackgroundImagePath`。
- **画面下端まで表示**: body の `GeometryReader` に `.ignoresSafeArea(edges: .all)` を付け、`geo` をフル画面サイズにする。背景高さは `geo.size.height`（`fullHeight`）。`playBackgroundLayer` にも `.ignoresSafeArea(edges: .all)` を適用。
- **画像読み込み**: `PlayBackgroundStore` / `HomeBackgroundStore`。`loadPlayBackgroundImage()` で `onAppear` と各設定の `onChange` 時に再読み込み。

---

## 3. パネル・ボタンのスタイル

- **共通背景**: `playPanelBackground` = `Color.black.opacity(0.75)`（75%不透明）。
- **指定パネルデザイン**: 角丸 20pt（`infoPanelCornerRadius`）、左右マージン 16pt（`infoPanelHorizontalMargin`）、シアン極細ストローク（0.5pt）。大当たり履歴・情報行の各パネル・ゲージの枠・中央/下部ボタンに適用。
- **持ち玉ボタン**: 他より薄く見えないよう `tintOverlayOpacity: 0.14`、ラベルは白（`.white.opacity(0.95)` 等）。`zoneButton` は `tintOverlayOpacity` のデフォルト 0.08。

---

## 4. ゲージ（BorderMeterView）

- **形状**: **上半円・下弦**（弦が下）。**3時・9時より上だけ**表示（12時が上端、9時・3時が下端）。`.frame(width: 2R, height: R)` でクリップ。
- **目盛**: 9時＝**ボーダー-5**、12時＝**ボーダー**、3時＝**ボーダー+5**。大目盛はこの3点。中目盛は **1刻み**（B-4〜B-1, B+1〜B+4）。
- **針**: `realRate` を (B-5)〜(B+5) にマッピングし、-90°〜+90° で表示。
- **色**: `gaugeColor` でボーダーとの差に応じて青/水色/白/黄オレンジ/赤。

---

## 5. 下部ボタン群

- **外枠**: 大当たり・遊技終了を包む**外枠パネルはなし**（以前の ultraThinMaterial の枠は削除済み）。
- **セーフエリア**: `.padding(.bottom, 8 + geo.safeAreaInsets.bottom)` で角丸に隠れないように配置。
- **左右マージン**: `floatingBarHorizontalMargin(geo)`（画面幅の約4%、12〜20pt）。

---

## 6. その他

- **最上部**: `VStack` に `.ignoresSafeArea(edges: .top)`。ヘッダー領域は `ZStack(alignment: .bottom)` で高さ `geo.safeAreaInsets.top + h2` を確保し、上マージン〜ヘッダーバーを同色で描画。
- **大当たり履歴**: ラベル「大当たり履歴」は**常に左上固定**。0回転位置に控えめな横線。`WinHistoryBarChartView`。
- **PlayBackgroundStore**: `saveCustomImage` 内では `imageFileName` を参照せず文字列リテラル `"PlayBackground.jpg"` を使用（Main actor 分離のため）。

---

## 7. 主なファイル・キー

| 内容 | ファイル / キー |
|------|-----------------|
| 実戦画面本体 | `PlayView.swift` |
| ゲージ | `BorderMeterView`（同ファイル内） |
| 背景保存・読み込み | `App/PlayBackgroundStore.swift` と `PlayView` の `playBackgroundLayer`（カスタム画像選択は `App/SettingsTabView.swift`） |
| 設定（実戦画面の背景） | `App/SettingsTabView.swift` の `playViewBackgroundStyle` / `playViewBackgroundImagePath` |

---

*このメモはここまでの実装に基づいています。続きのチャットでは「PLAY_VIEW_SPEC に従って」「実戦画面の〇〇を〜」のように参照すると続きやすいです。*

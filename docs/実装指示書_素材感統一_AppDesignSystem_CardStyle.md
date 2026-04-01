# 指示書：素材感（マテリアル）と質感の統一（AppDesignSystem.CardStyle 徹底適用）

## 目的（1文）
アプリ全体のカード/ボタン/入力欄の「角丸・影・ハイライト・ストローク・押下時の沈み」を 1種類の規格に統一し、寄せ集め感を消して“触れたくなる上質さ”に揃える。

## ゴール（受け入れ条件）
- カード（パネル/行/一覧カード/詳細パネル）が同じ角丸・同じ線・同じ影で統一されている
- ボタン（Primary/Secondary/Destructive）が同じ押下挙動（沈み・影変化）で統一されている
- 入力欄（TextField系/カスタムPad系）の枠・背景・角丸が統一されている
- 画面ごとに RoundedRectangle(cornerRadius: 12/14/16/20) や shadow(...) のマジックナンバーが散らばらない
- ビルドが通る（見た目が崩れてもクラッシュしない）

## 変更方針（最小で最大効果）
- まずは“共通Modifier/Style”を作り、画面側は置換するだけにする
- いきなり全画面の数値を直書きで修正しない（後戻りしにくい）
- List/ScrollView/Sheet の構造は基本維持し、見た目だけを統一する
- 既存の AppGlassStyle / DesignTokens は壊さず、AppDesignSystem に寄せる

## 新規 or 更新するファイル（上限目安：3）
- `P-stats/Design/AppTheme.swift`（既存：AppDesignSystem）
  - CardStyle を ViewModifier/関数として使いやすく拡張
- `P-stats/Design/AppMaterial.swift`（新規推奨）
  - カード/ボタン/入力の統一スタイルをここに集約（ViewModifier / ButtonStyle）
- （必要なら）`P-stats/Extensions/View+Material.swift`（新規）
  - `.appCard()` `.appButtonPrimary()` のような短い呼び出しを提供

## 実装タスク（最大10）

### A. カード（Card）
- AppCardStyle を定義（Cardの規格）
  - cornerRadius（例：AppDesignSystem.CardStyle.cornerRadius）
  - fill（例：AppDesignSystem.CardStyle.fill）
  - stroke（例：AppDesignSystem.CardStyle.stroke + lineWidth）
  - shadow（通常時/押下時の2段階）
  - 内側paddingの標準値（例：14）
- View 拡張で appCard() を用意（使う側の記述量を削減）
- 既存の settingsCard(...) / detailPanel(...) / HistorySessionCard / AnalyticsSessionCardView を appCard() に置換

### B. ボタン（Button）
- AppPressableButtonStyle を定義
  - 押下時の scale（例：0.97）
  - 影の弱化（radius/opacity down）
  - Reduce Motion 対応
- Primary/Secondary/Destructive の3種を規格化
  - Primary：accent塗り＋黒文字（現状踏襲）
  - Secondary：白10%塗り＋白文字
  - Destructive：赤系＋白文字
- 主要ボタン（下部固定ボタン、共有、編集など）を buttonStyle 統一

### C. 入力（Input）
- AppInputFieldStyle を定義（TextField/Pad系で共通見た目）
  - 背景（黒/白10%）
  - ストローク（薄い白）
  - cornerRadius（カードと同系）
  - フォーカス時のaccent強調（線 or glow）
- TextField に .textFieldStyle(...) ではなく、必要なら ViewModifier で統一
- IntegerPadTextField/DecimalPadTextField を包むコンテナ側の見た目（背景/枠）を統一

### D. 置換と掃除
- cornerRadius: や shadow( の直書きを段階的に削減（重要画面→残り）

## 置換優先順位（上から順）
1. 履歴詳細（下部ボタン・パネルが多く差が出やすい）
2. 分析詳細 / リストカード
3. 設定（カードが多く統一感が最も効く）
4. 実戦（PlayView）（独自UIが多いので最後に合わせる）

## やらないこと（スコープ外）
- レイアウト変更（情報の増減・順番変更）は別指示書で扱う
- SwiftData/計算ロジック/広告ロジックの変更はしない
- “新しい見た目を画面ごとに増やす”のは禁止（規格は増やさない）

## 確認項目（最大8）
- カードの角丸が全画面で同一に見える
- ストロークの太さ/透明度が揃っている
- 影の方向・強さが揃っている（押下で沈む）
- List行/カード/詳細パネルの素材感が揃っている
- ボタンの押下アニメが統一されている
- 入力欄の枠と背景が統一されている
- Reduce Motion ON でも不自然にならない
- ビルドが通る


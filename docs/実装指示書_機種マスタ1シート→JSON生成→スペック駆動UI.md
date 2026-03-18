# 実装指示書：機種マスタ（1シート）→ JSON生成 → スペック駆動UI

## 0. ゴール

スプレッドシート（**1シート・1機種1行**）から、アプリが参照する以下を生成する。

- `master_out/index.json`（機種一覧）
- `master_out/machines/{機種ID}.json`（機種ごとの統合JSON）
- `master_out/export_status.csv`（スキップ/エラーの報告）

アプリは、選択中機種の `{機種ID}.json` を読み、以下を**仕様どおりに解釈してUIを出す**。

- **モード**（ユーザーがいま滞在している状態）
- **当たり候補**（滞在モードに応じて候補が出る）
- **遷移**（当たり後にどのモードへ行くか）
- **上乗せ**（ユニット出玉 × 回数）
- **分岐**（同名当たりが複数ある場合、分岐ラベルで選ばせる）

---

## 1. 入力（スプレッドシート）仕様

### 1.1 ヘッダー（現状）

列は **当たり最大12列**（当たり1〜12）、**モード8列**（モード0〜7）。

```
導入開始日	機種名	メーカー	確率	機種タイプ	スペック	特徴タグ	機種ID	ステータス	モード0	モード1	モード2	モード3	モード4	モード5	モード6	モード7	当たり1	当たり2	当たり3	当たり4	当たり5	当たり6	当たり7	当たり8	当たり9	当たり10	当たり11	当たり12
```

> **重要**: 実装はこの列順を真実のソースとする（列名→インデックスで解決する）。  
> 機種ID列は **「機種ID」列（ヘッダー名一致）**を参照し、列位置（何列目か）に依存しないこと。

### 1.2 行の出力可否（ステータス）

- `ステータス` が **出力対象のみ** JSON生成する
- それ以外（空、作業中、無効、スキップ等）はスキップし、`export_status.csv` に理由を出す

運用に合わせて固定する（例）:

- **完了のみ出力**: `完了` 以外は `status_not_ready`
- **完了|公開のみ出力**: `完了` または `公開` 以外は `status_not_ready`

### 1.3 モードセル仕様（確定）

**形式**: `mode_id/mode_name/densapo`

例:

- `0/通常時/0`
- `1/海門決戦/134`

ルール:

- `mode_id`: 0〜7 の整数
- `mode_name`: 表示名
- `densapo`: 整数（通常時は常に 0）
- 将来の「∞電サポ（次回まで）」に備え、`densapo` に **`INF` / `∞`** を許容

### 1.4 当たりセル仕様（確定）

**形式**: `あたり名/基本出玉/ユニット出玉/最大連結数/滞在ID/移行先ID/分岐ラベル`

例:

- `決戦BONUS/750/0/0/0/0/`
- `カバネリBONUS/1500/0/0/0/1/上位へ`
- `ツラヌキBONUS/3000/3000/3/1/1/上乗せ`

ルール:

- `分岐ラベル`: 分岐する場合のみ入力（空OK）
- `最大連結数`:
  - `0` のとき上乗せなし
  - `1+` のとき「上乗せボタン」を最大回数として扱う
- **同一 stay_mode_id の中で同一 name が複数**ある場合:
  - `branch_label` が全て空 → **エラー**（管理人が修正）

---

## 2. 生成JSON仕様（アプリに渡す形式）

### 2.1 `master_out/index.json`（一覧）

用途: アプリの機種選択UI

最低限（例）:

```json
[
  {
    "machine_id": "4935",
    "name": "e 甲鉄城のカバネリ2 咲かせや燦然",
    "manufacturer": "サミー",
    "probability": "1/319.7",
    "machine_type": "デジパチ",
    "intro_start": "Mon Mar 02 2026 17:00:00 GMT+0900 (日本標準時)",
    "status": "完了"
  }
]
```

方針:

- スプレッドの列をそのまま載せてOK（検索で使うものは後から追加可）
- `機種ID` を `machine_id` として入れる

### 2.2 `master_out/machines/{機種ID}.json`（機種ごと統合）

推奨スキーマ（UI実装が楽になる形）:

```json
{
  "machine_id": "4935",
  "name": "e 甲鉄城のカバネリ2 咲かせや燦然",
  "manufacturer": "サミー",
  "probability": "1/319.7",
  "machine_type": "デジパチ",
  "intro_start": "Mon Mar 02 2026 17:00:00 GMT+0900 (日本標準時)",
  "spec": "",
  "tags": "",
  "modes": [
    { "mode_id": 0, "name": "通常時", "densapo": 0 },
    { "mode_id": 1, "name": "海門決戦", "densapo": 134 }
  ],
  "bonuses": [
    {
      "name": "決戦BONUS",
      "base_payout": 750,
      "unit_payout": 0,
      "max_concat": 0,
      "stay_mode_id": 0,
      "next_mode_id": 0,
      "branch_label": ""
    }
  ]
}
```

方針:

- `modes`: モード列から生成（空セルは無視）
- `bonuses`: 当たり列（当たり1〜12）から生成（空セルは無視）
- 既存実装の `modes[].bonuses` に分配してもよいが、**同名分岐/上乗せ**があるため、まずは `bonuses` をフラットに持ち、UI側で `stay_mode_id` で絞る形が単純

---

## 3. 変換（スプレッド → JSON）指示

### 3.1 スクリプト方針

- 既存 `scripts/convert_mode_bonus.py` は「1当たり1行CSV」前提のため、本仕様（1機種1行・横持ち）には合わない
- 新規に横持ち専用の変換スクリプトを用意する（例: `scripts/build_master_from_sheet.py`）

### 3.2 パース仕様（必須）

- 文字コード: UTF-8（BOM許容）
- 区切り: TSV/CSV どちらでもよいが、Google CSVは引用符が絡むため **CSVライブラリで厳密にパース**する

#### 機種ID（machine_id）

- 空 → スキップ（reason: `missing_machine_id`）
- 重複 → スキップ（reason: `duplicate_machine_id`）

#### ステータス

- 出力対象外 → スキップ（reason: `status_not_ready`）

#### モードセル

- `/` で 3要素に分割（3要素必須）
- `mode_id`: 0〜7
- `densapo`: 整数、または `INF|∞`

#### 当たりセル

- `/` で **7要素**に分割（不足/過剰はエラー扱いでスキップ or 警告）
- 数値項目:
  - `base_payout`, `unit_payout`, `max_concat`, `stay_mode_id`, `next_mode_id` は整数
- `branch_label`: 文字列（空可）

### 3.3 検証ルール（エラーとして弾く）

機種ごとの `bonuses` について、`stay_mode_id` 単位で次を検証する。

1) 同一 `stay_mode_id` の中で同一 `name` が複数ある場合  
- `branch_label` が全て空 → **エラー**（reason: `duplicate_bonus_name_without_branch`）

2) 同一 `stay_mode_id` の中で同一 `(name, next_mode_id, branch_label)` が複数  
- 重複（reason: `duplicate_bonus_row`）

方針:

- 「同名が複数あるなら分岐ラベルで区別されているべき」
- 「同一移行先でも複数行」は許す（上乗せ条件違い等）。ただし **区別できないならエラー**。

### 3.4 `export_status.csv`（必須）

出力例（1行1機種）:

- columns: `machine_id, status, reason, detail`
- status: `exported|skipped|error`
- reason例:
  - `status_not_ready`
  - `missing_machine_id`
  - `duplicate_machine_id`
  - `duplicate_bonus_name_without_branch`
  - `duplicate_bonus_row`
  - `parse_error_mode`
  - `parse_error_bonus`

---

## 4. アプリ側：データ解釈とUI動作仕様

前提: アプリは選択中機種の `{machine_id}.json` をロードし、`modes` と `bonuses` を保持する。

### 4.1 モード（滞在状態）

- アプリ内の「現在モード」＝ユーザーが滞在している状態
- `mode_id=0` は常に通常（表示名はマスタ由来でOKだが意味は通常固定）
- `mode_id>=1` は電サポ等の「通常以外」モード

densapo の扱い（今回の仕様）:

- **カウントダウン処理はしない**
- `densapo` は「現実の遊技で通常復帰した時点で画面回転数が増えている」ことに合わせるための情報
- 将来の「∞電サポ」対応:
  - `densapo=INF|∞` のモードは UI上「∞」表示
  - 回転数調整は手動復帰時に入力する運用に寄せる（実装側は数値加算しない）

### 4.2 当たりボタン（モード0時）

ステップ1：当たり名一覧ポップアップ

- 条件: 現在モードが 0 のとき「当たり」ボタンを押す
- 表示: `stay_mode_id == 0` の bonuses を抽出し、当たり名（name）の一覧を表示
- 一覧は `name` でユニーク化（同名が複数行あり得る）

ステップ2：分岐がある場合のみ第2ポップアップ

- ユーザーが当たり名Xを選択
- `stay_mode_id==0 && name==X` の行を集める
- 行が1件 → その行を確定（移行先も確定）
- 行が複数件 → 第2ポップアップ
  - 表示内容: `branch_label` のみ
  - 選択により行を確定

エラー:

- 複数件あるのに `branch_label` が空の行が混ざる/全て空 → データ不整合
  - 推奨: 選択不可＋「データ不整合」表示（マスタ修正を促す）

### 4.3 非通常モード（モード1〜）での当たりボタン

- 現在モードID = k のとき `stay_mode_id == k` を抽出し、同様に当たり名一覧
- 同名が複数なら分岐ラベル第2ポップアップ

### 4.4 上乗せ（ユニット出玉×回数）UI

対象: 確定した bonus に対して `max_concat >= 1` かつ `unit_payout > 0`

表示要件:

- 現在の予定獲得出玉（`base_payout + unit_payout * selectedCount`）を画面に明確に表示

操作要件（ユーザー指定）:

- 回数選択 → ボタン連打の2段階
  1) まず「上乗せ回数」を `0〜max_concat` で選ぶ（Stepper/Picker等）
  2) 「+ユニット出玉」ボタンを連打すると、選択回数まで増えていく（0から開始、タップごとに +1、上限で無効）

確定時:

- 記録する payout は `base_payout + unit_payout * 実タップ回数`
- `max_concat=0` または `unit_payout=0` の場合は上乗せUIを出さない

---

## 5. 画面遷移（モード更新）

確定した bonus の `next_mode_id` に応じて「現在モード」を更新する。

- `next_mode_id` が空・不正 → 0 とみなす（推奨はエラー扱いでデータ修正）

---

## 6. 既存コードへの当てはめ指針

- JSONロードは既存の `MachineDetailLoader`（`index.json` と `machines/{id}.json`）路線を踏襲してよい
- ただし現行 `MachineDetail` 型は `modes[].bonuses` 前提のため、本スキーマに合わせて
  - 新型 `MachineFullMaster`（仮）を定義
  - Loader をその型でデコード
  - UI側の当たり選択は `bonuses` を `stay_mode_id` で絞り込み、同名分岐は `branch_label` で第2ポップアップ
  - 上乗せUIは `unit_payout/max_concat` により自動出し分け

---

## 7. 完了条件

- 1シートから `index.json / machines/{機種ID}.json / export_status.csv` を生成できる
- アプリが `index.json` から機種一覧を出せる
- アプリが選択機種 `{機種ID}.json` を参照し:
  - 現在モードに応じた当たり候補を出せる
  - 同名当たりの分岐は分岐ラベル第2ポップアップで選べる
  - 上乗せ（unit×回数、上限=max_concat）がUIで操作でき、予定出玉が明確に表示される
  - 確定後に `next_mode_id` へ遷移できる
- 「同名当たりが複数なのに分岐ラベルなし」は変換時にエラー検出し、`export_status.csv` に出る（またはアプリ側で明示エラー）

---

## 補足：同名・同一移行先が複数行の具体例

演出上はどちらも「カバネリBONUS」だが、内部的に「上乗せ条件が違う」などで別管理したいケース。

- 行A: `カバネリBONUS/1500/0/0/0/1/通常ルート`
- 行B: `カバネリBONUS/1500/300/2/0/1/上乗せルート`

どちらも移行先は mode1 だが、上乗せ可否が違うため行が分かれる。ユーザーは第2ポップアップで **通常ルート / 上乗せルート** を選ぶ。


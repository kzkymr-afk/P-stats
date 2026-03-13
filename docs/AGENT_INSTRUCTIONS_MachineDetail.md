# MachineDetail シート仕様（モード・当たり・遷移の真実のソース）

## 概要

Google スプレッドシートの **シート名: MachineDetail**（既存の機種一覧シートとは別シート）を、「1当たり1行」のマスタとして定義する。  
このシートから `index.json` と `machines/[machine_id].json` を生成する Python スクリプトは `scripts/convert_mode_bonus.py` で用意する。  
既存の「1機種1行」シート／既存 `update_machines.py` はそのまま残し、本シートは **モード・当たり・遷移専用** とする。

---

## 1. 新シートの構成

- **シート名**: `MachineDetail`（既存の機種一覧シートとは別シートとする）

### 列（ヘッダー）

| 列 | ヘッダー名    | 型     | 説明 |
|----|---------------|--------|------|
| A  | machine_id    | 文字列 | 機種を一意に識別するID（既存の機種IDやDMMの数値IDなど、他シート・JSONと統一） |
| B  | machine_name  | 文字列 | 機種名（index.json の name や表示用。同一 machine_id では同じ値で揃える） |
| C  | mode_id       | 数値   | 滞在モードのID（0=通常、1=RUSH、2=LT など。機種内で一意） |
| D  | mode_name     | 文字列 | モードの表示名（例: 通常、戦MODE、黄金RUSH、LT） |
| E  | bonus_name    | 文字列 | 当たりの名称（例: 超大当り3000、戦BONUS） |
| F  | payout        | 数値   | 出玉数（払い出し玉数。純増でない場合の扱いは仕様で定義） |
| G  | ratio         | 数値   | 振り分け率（%）。任意。未入力は 0 や空でよい |
| H  | densapo       | 数値   | 終了後の電サポ回数。0 の場合は時短なし／手動復帰等 |
| I  | next_mode_id  | 数値   | この当たり後に遷移する mode_id（通常に戻る=0 など） |
| J  | notes         | 文字列 | （任意）メモ（c時短の有無など）。将来の拡張用 |

- **1行** = 1つの「モードで発生しうる1種類の当たり」。
- 同一 `(machine_id, mode_id)` に複数行 = そのモードで選べる当たりが複数ある場合。

---

## 2. 出力JSONの形

### index.json（機種一覧）

- 新シートの `machine_id` をユニークに集め、各機種について `machine_id` と `machine_name`（先頭行の値）を持つ。
- 既存の「機種名・メーカー・確率・ボーダー」を使う場合は、既存シートのCSVと machine_id で突き合わせるか、index にメーカー等の列を追加するかは別途決定。

### machines/[machine_id].json（機種ごと詳細）

当該 `machine_id` の行だけを対象に、次の階層で出力する。

```json
{
  "machine_id": "e-keiji-ougon",
  "name": "e花の慶次〜黄金の一撃",
  "modes": [
    {
      "mode_id": 0,
      "name": "通常",
      "bonuses": [
        { "name": "超大当り3000", "payout": 3000, "ratio": 50.0, "densapo": 100, "next_mode_id": 2 },
        { "name": "戦BONUS", "payout": 1500, "ratio": 50.0, "densapo": 10, "next_mode_id": 1 }
      ]
    }
  ]
}
```

- `ratio` / `densapo` が空の場合は 0 や省略でよい（アプリ側でデフォルトを決める）。

---

## 3. 変換スクリプト

- **スクリプト**: `scripts/convert_mode_bonus.py`
- **入力**: MachineDetail シートのCSV（Googleスプレッドシートの「ファイル → ダウンロード → CSV」または公開エクスポートURL。環境変数 `MACHINEDETAIL_CSV_URL` で指定可能）
- **出力**:
  - `master_out/index.json`: 全機種の machine_id, machine_name のリスト
  - `master_out/machines/<machine_id>.json`: 上記形式の機種別JSON（machine_id に使えない文字はファイル名用にサニタイズ）
- **既存との関係**: 既存の `scripts/update_machines.py` は変更せず、従来の「1機種1行」CSV → machines.json は従来どおり。本スクリプトは MachineDetail シート専用。

---

## 4. 完了条件（フェーズ1）

- [ ] MachineDetail シートのヘッダーとサンプル行（例: e花の慶次で5行以上）が用意されている。
- [ ] `convert_mode_bonus.py` を実行すると、`index.json` と `machines/*.json` が生成される。
- [ ] 生成されたJSONが、後続フェーズで想定する Decodable 構造（Mode / Bonus / next_mode_id）と整合している。

# Google Apps Script（P-stats マスタ連携）

- **`gas.gs`** … スプレッドシート連携・`get_machine_json` 等。`scripts/convert_master_one_sheet.py` と同一のマスタ解釈（mode_0〜7・当たり9項目）。
- **マスター配信** … メニューから GitHub Actions（`deploy-master-out-pages.yml`）を `workflow_dispatch` で起動。別アプリからは `doPost` の `mode=trigger_master_out_deploy`（要 `MASTER_DEPLOY_WEBHOOK_SECRET`）。詳細は **`docs/MASTER_OUT_DEPLOY_GAS.md`**。
- **`appsscript.json`** … プロジェクトメタ（タイムゾーン等）

## clasp でアップロード（push）

リポジトリでは **`.clasp.json` をコミットしない**（`.gitignore`）ため、**各マシンで一度だけ**紐付けが必要です。コミット可能なテンプレートは **`gas_project/.clasp.json.example`**（`scriptId` を書き換えて `.clasp.json` にリネーム／コピー）。

### Script ID の取得方法

1. 対象のスプレッドシートを開く
2. **拡張機能** → **Apps Script**
3. 左の **プロジェクトの設定**（歯車アイコン）
4. **スクリプト ID** をコピー（長い英数字の文字列）

### スクリプト ID とスプレッドシート ID の違い

| 種類 | 用途の例 | どこにあるか |
|------|----------|--------------|
| **スクリプト ID** | `clasp` がどの GAS プロジェクトに push するか | Apps Script の **プロジェクトの設定** |
| **スプレッドシート ID** | `gas.gs` の `SS_ID` など、どのシートを読むか | ブラウザのスプレッドシート URL の `/d/` と `/edit` のあいだ |

**clasp や `.clasp.json` にはスプレッドシート ID は不要**（紐づくのは GAS プロジェクト）。混同すると `Project settings not found` や意図しないプロジェクトへの push の原因になる。

### 初回セットアップ（2通り）

**案 A: `clasp clone` で紐づけ**

```bash
npm i -g @google/clasp   # 未導入なら
clasp login

cd gas_project
clasp clone <SCRIPT_ID>   # .clasp.json が作成される
# clone により gas.gs が GAS 側の内容で上書きされる場合あり。リポジトリ版が新しいなら gas.gs を復元してから:
clasp push
```

**案 B: `.clasp.json.example` をコピー（clone なし）**

```bash
cd gas_project
cp .clasp.json.example .clasp.json
# .clasp.json の scriptId を、上記で取得したスクリプト ID に書き換える（YOUR_SCRIPT_ID_HERE を置換）
clasp push
```

`clasp clone` を使わず、既にローカルにある `gas.gs` をそのまま push したい場合は **案 B** が向いている。

### 運用

```bash
cd gas_project
clasp push   # gas.gs を Apps Script に反映
```

Web アプリとしてデプロイしている場合は、push 後に GAS エディタで **デプロイ → 既存のデプロイを管理 → バージョン更新** が必要なことがあります。

### トラブルシュート

| 現象 | 原因の目安 | 対処 |
|------|------------|------|
| `Project settings not found` | `gas_project/.clasp.json` がない／`scriptId` が無効・誤り／`gas_project` 以外で実行 | **案 A または案 B**で `.clasp.json` を作り直し、**スクリプト ID**（スプレッドシート ID ではない）を確認してから `cd gas_project && clasp push` |
| `clasp clone` 後に `gas.gs` が古い | clone はリモートのファイル一覧でローカルを揃えるため、GAS 側が古いとローカルも古くなる | Git で `gas.gs` をリポジトリ最新に戻すか、エディタで上書きしてから `clasp push`。**初回から案 B**ならローカル `gas.gs` は勝手に置き換わらない |

## 手動反映

`gas.gs` の内容を Apps Script エディタに貼り付けて保存・デプロイしても同じです。clasp が動かない間はこの方法で反映可能。

# GitHub Pages で master_out を配信する手順（週1更新）

## 目的

- スプレッドシート（1シート・1機種1行）→ CSV → JSON 変換で生成した `master_out/` を GitHub Pages で配信し、アプリが常に最新マスターを参照できるようにする。
- 同じ **gh-pages** サイトのルートに **`machines.json`**（`main` ブランチの同名ファイルをコピー）も載せ、**公開用 JSON を Pages 配下に集約**する。
- アプリが参照するURL（デフォルト）:
  - スペックマスタ: `https://kzkymr-afk.github.io/P-stats/master_out`
  - プリセット一覧: `https://kzkymr-afk.github.io/P-stats/machines.json`

---

## 1. GitHub Pages を有効化

GitHub リポジトリの Settings → Pages で、以下を設定:

- **Build and deployment**:
  - Source: **Deploy from a branch**
  - Branch: **gh-pages**
  - Folder: **/** (root)

保存後、反映まで数分かかることがあります。

---

## 2. Repository Variables を設定

Settings → Secrets and variables → Actions → Variables に以下を登録:

- **`MASTER_ONE_SHEET_CSV_URL`**（必須）
  - 例: `https://docs.google.com/spreadsheets/d/<ID>/export?format=csv&gid=<GID>`

- **`MASTER_EXPORT_STATUS_VALUES`**（任意）
  - 例: `完了`（デフォルト）
  - 例: `完了|公開`

### スプレッドシートを「制限付き」共有にしたとき（401 対策）

匿名の `.../export?format=csv&gid=...` は **401** になるため、CI では **Google Sheets API** で読みます。

1. [Google Cloud Console](https://console.cloud.google.com/) でプロジェクトを作成し、**Google Sheets API** を有効化する。
2. **サービスアカウント**を作成し、**JSON キー**をダウンロードする。
3. GitHub リポジトリの **Settings → Secrets and variables → Actions → Secrets** に  
   **`GOOGLE_SERVICE_ACCOUNT_JSON`** という名前で、**JSON ファイルの中身をそのまま**貼り付けて保存する（改行含めて全文）。
4. Google スプレッドシートの **共有**で、JSON 内の `client_email`（`…@….iam.gserviceaccount.com`）を **閲覧者**として追加する。

週次の **`マスターデータ週次更新`** と **`master_out を GitHub Pages に配信`** の両方で、このシークレットが渡るようにしてある（未設定のままだと従来どおり匿名 GET のみ）。

---

## 3. 配信ジョブの実行

Actions → `master_out を GitHub Pages に配信` を開き、以下のどちらか:

- **Run workflow**（手動実行）
- またはスケジュール（毎週土曜 0:00 UTC / 日本時間 土曜 9:00）で自動実行

成功すると `gh-pages` ブランチに **`master_out/`** と **`machines.json`**（および `.nojekyll`）が配置され、Pages URL で参照可能になります。`main` に `machines.json` が無いとデプロイは失敗します。

---

## 4. アプリ側が参照するもの

- プリセット（検索一覧用）: サイトルートの **`machines.json`**（`PresetServiceConfig.defaultMachineMasterDataURL`）
- スペック一覧: `master_out/index.json`
- 機種ごとの統合マスタ: `master_out/machines/<machine_id>.json`（`PresetServiceConfig.defaultMachineDetailBaseURL`）

**週次「マスターデータ週次更新」**で `main` の `machines.json` が更新されたあと、**同じワークフロー内で gh-pages の `machines.json` だけを差し替える**ため、Pages 上のプリセットも追従します（`gh-pages` が未作成の初回のみ、先に本ワークフローを1回実行してください）。


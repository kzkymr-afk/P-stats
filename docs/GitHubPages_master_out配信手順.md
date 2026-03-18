# GitHub Pages で master_out を配信する手順（週1更新）

## 目的

- スプレッドシート（1シート・1機種1行）→ CSV → JSON 変換で生成した `master_out/` を GitHub Pages で配信し、アプリが常に最新マスターを参照できるようにする。
- アプリが参照するURL（デフォルト）: `https://kzkymr-afk.github.io/P-stats/master_out`

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

---

## 3. 配信ジョブの実行

Actions → `master_out を GitHub Pages に配信` を開き、以下のどちらか:

- **Run workflow**（手動実行）
- またはスケジュール（毎週土曜 0:00 UTC / 日本時間 土曜 9:00）で自動実行

成功すると `gh-pages` ブランチに `master_out/` が配置され、Pages URL で参照可能になります。

---

## 4. アプリ側が参照するもの

- 機種一覧: `master_out/index.json`
- 機種ごと: `master_out/machines/<machine_id>.json`

アプリは `PresetServiceConfig.defaultMachineDetailBaseURL`（デフォルト）を参照します。


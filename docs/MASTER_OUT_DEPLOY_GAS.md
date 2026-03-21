# master_out デプロイ（GAS メニュー / Webhook）

スプレッドシート更新後、**GitHub Actions**（`deploy-master-out-pages.yml`）を起動して CSV → 機種別 JSON → GitHub Pages 配信まで進める仕組み。

## 前提

- リポジトリの **Repository variables** に `MASTER_ONE_SHEET_CSV_URL`（スプレッドシートの **ウェブに公開** した CSV の URL）が設定されていること。
- シートを編集したあと、公開 CSV が最新になるまで **数十秒〜1分程度** 空けると安全（Google の反映遅延対策）。

## 1. GAS の Script Properties（必須）

スクリプトエディタ → **プロジェクトの設定** → **スクリプトのプロパティ** に追加:

| プロパティ | 説明 |
|-----------|------|
| `GITHUB_PAT` | GitHub の Personal Access Token。**classic**: `repo` + `workflow`。**Fine-grained**: Repository 対象で **Actions: Write**、**Metadata: Read**。 |
| `GITHUB_REPO` | `owner/repo` 例: `kzkymr-afk/P-stats` |
| `GITHUB_WORKFLOW_FILE` | 省略可。既定 `deploy-master-out-pages.yml` |
| `GITHUB_REF` | 省略可。既定 `main`（ワークフローが走るブランチ） |
| `MASTER_DEPLOY_WEBHOOK_SECRET` | **任意**。設定すると「別アプリから Webhook で起動」が有効になる（下記 §3）。十分に長いランダム文字列を推奨。 |

`clasp push` 後、**コンテナバインド**のスプレッドシートを開き直すとメニュー **「マスター配信」→「GitHub Actions で master_out をデプロイ」** が表示される。

## 2. スプレッドシートからの操作（案1）

1. マスターシートを保存する（必要なら CSV 公開の反映を少し待つ）。
2. **マスター配信** → **GitHub Actions で master_out をデプロイ**。
3. GitHub の **Actions** タブで `master_out を GitHub Pages に配信` の実行を確認。

## 3. データ入力専用アプリ（別アプリ）からの起動

GAS を **ウェブアプリ**としてデプロイしている場合（既存の `doPost` と同じ URL）、次のパラメータで **同じデプロイ**を起動できる。

### 条件

- Script Properties に **`MASTER_DEPLOY_WEBHOOK_SECRET`** を設定済みであること。
- リクエストの `secret`（または `deploy_secret`）がその値と**完全一致**すること。

### HTTP

- **メソッド**: `POST`（既存 `doPost` と同じエンドポイント）
- **Content-Type**: `application/x-www-form-urlencoded` 推奨（既存クライアントと揃える）

### パラメータ

| 名前 | 値 |
|------|-----|
| `mode` | `trigger_master_out_deploy` |
| `secret` | `MASTER_DEPLOY_WEBHOOK_SECRET` と同じ文字列（`deploy_secret` でも可） |

### レスポンス（JSON）

成功例:

```json
{ "ok": true, "github_status": 204 }
```

失敗例:

```json
{ "ok": false, "error": "forbidden" }
```

```json
{ "ok": false, "github_status": 401, "github_body": "..." }
```

### curl 例

```bash
curl -sS -X POST "https://script.google.com/macros/s/＜デプロイID＞/exec" \
  -d "mode=trigger_master_out_deploy" \
  -d "secret=＜MASTER_DEPLOY_WEBHOOK_SECRET＞"
```

※ ウェブアプリの URL は GAS エディタの **デプロイ** からコピーする。リダイレクトがある場合は `curl -L` を付ける。

### 別アプリ実装時の注意

- **ブラウザから直接** GAS URL に POST すると **CORS** でブロックされやすい。入力アプリが **ネイティブ / サーバー** から POST するか、自前の **バックエンドプロキシ** 経由にすると確実。
- `secret` は **アプリの安全なストレージ**（Keychain、サーバー環境変数など）に置き、リポジトリにコミットしない。

## 4. トラブルシュート

| 現象 | 確認 |
|------|------|
| HTTP 401 / 403 | `GITHUB_PAT` の権限・期限、リポジトリ名 `GITHUB_REPO` |
| HTTP 404 | ワークフローファイル名、`GITHUB_REF` のブランチに YAML が存在するか |
| Actions は動くが JSON が古い | `MASTER_ONE_SHEET_CSV_URL` が正しいシートか、公開 CSV の反映待ち |
| メニューが出ない | `onOpen` が走るようシートを再読み込み、または `clasp push` 漏れ |

## 5. 関連ファイル

- ワークフロー: `.github/workflows/deploy-master-out-pages.yml`
- 変換: `scripts/convert_master_one_sheet.py`
- GAS 本体: `gas_project/gas.gs`

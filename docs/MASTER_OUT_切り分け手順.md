# master_out「更新されているが中身が変わらない」切り分け手順

**ゴール**: どの段階で「変化が止まっているか」を一つずつ特定する。

---

## 前提の確認（ここを間違えると全部ムダ）

| 確認 | 意味 |
|------|------|
| 見ているブランチは **`gh-pages`** か | `master_out/` の JSON は **`main` には載らない**。コード画面のブランチを **`gh-pages`** に切り替えてから `master_out/index.json` を開く。 |
| 開いている URL は **生の JSON** か | ブラウザが **キャッシュ**した古い内容を見ていることがある。**シークレットウィンドウ**か **curl** で取り直す（後述 Step 5）。 |

---

## Step 1 — Actions は本当に「今回のコミット」で動いているか

### Step 1 の具体的な確認方法（画面操作）

1. ブラウザで対象リポジトリを開く（例: `https://github.com/＜owner＞/＜repo＞`）。**別の fork を見ていないか**も確認。
2. 上部タブから **「Actions」** をクリック。
3. 左サイドバーの **「Workflows」** 一覧で **「master_out を GitHub Pages に配信」** を選ぶ。
4. 右側に並ぶ **実行一覧**のうち、**一番上（最新）**の行をクリックして詳細を開く。  
   - **手動実行**したなら、その日時に近い実行を選ぶ。
5. 実行ページ左上の **ステータス**を見る。  
   - **緑のチェック** … 成功（Step 1 の「動いた」条件は満たす。次へ進める）。  
   - **赤の X** … 失敗（ログで失敗したステップを直すまで Step 2 に進めない）。
6. **どのコミットで動いたか**を確認する（どちらかでよい）:
   - **方法 A**: 実行ページで **「build-and-deploy」** ジョブを開き、左のステップ **「リポジトリを取得」** のログを展開する。`Fetching the repository` や `ref` / **`commit` の SHA**（7桁が短縮表示）が出るので、**Code → main の最新コミット**と目視で合わせる。
   - **方法 B**: **Code** タブ → ブランチ **`main`** → 一覧の **最新コミット**のメッセージ右側の **SHA**（短縮）をメモし、「デプロイを実行した**あと**にこのコミットが `main` の先頭だったか」を思い出して照合する。
7. **push の有無**: 手元だけ修正して **GitHub に push していない**と、Actions は **古い `main`** のまましか取れない。**Code** の **main** に、必要な変更が**既にマージ／push 済み**か確認する。

**Step 1 の完了条件（OK なら Step 2 へ）**

- 最新の **「master_out を GitHub Pages に配信」** の実行が **緑（成功）**。
- その実行が、配信したい内容を含む **`main` の状態**で走ったと判断できる（別リポジトリ・未 push ではない）。

**ここで止まる典型**: ローカルだけ直して **push していない**、別リポジトリを見ている、ワークフロー **失敗**のまま。

---

## Step 2 — ワークフローが読んでいる CSV が「最新のシート」か

CI は **Repository variables の `MASTER_ONE_SHEET_CSV_URL`** だけを見る（手元の CSV ファイルは使わない）。

1. GitHub → **Settings** → **Secrets and variables** → **Actions** → **Variables** → **`MASTER_ONE_SHEET_CSV_URL`** の値をコピーする。
2. ブラウザでその URL を開く（または **curl** で先頭数行を取得）。

```bash
curl -sS "＜MASTER_ONE_SHEET_CSV_URL を貼り付け＞" | head -5
```

3. **1行目（ヘッダー）**が **`docs/機種マスター1シート仕様.md` §2.1** と一致しているか（30列・`更新対象`・`mode_N` 用の列など）。
4. **編集した行**が、想定どおり **2行目以降に反映**されているか（セル保存後、**数十秒〜1分**空けると安全）。

**ここで止まる典型**:

- URL が **別シート・別 gid** のまま。
- スプレッドシートは直したが **「ファイル → ウェブに公開」** の対象が古い／別 URL。
- ヘッダーが旧形式のまま → **パースで全部スキップ** → `index.json` が空または中身が変わらない。

---

## Step 3 — 変換結果が「中身として変わる」状態か（ローカルで再現）

手元で **同じ URL** を使い、CI と同じスクリプトを叩く。

```bash
cd ＜P-stats リポジトリのルート＞
export MASTER_ONE_SHEET_CSV_URL="＜Variables と同じ URL＞"
python scripts/convert_master_one_sheet.py
```

1. ログに **`配信JSON行数=…`** や **`index.json: 更新`** が出るか。
2. 生成された **`master_out/index.json`** を開き、**機種ID・件数**が期待どおりか。
3. **`master_out/export_status.csv`** を開き、**`skipped` / `error` / `not_update_target`** が多すぎないか。

**ここで止まる典型**:

- ステータスが **`完了`** になっていない（`MASTER_EXPORT_STATUS_VALUES` 既定は「完了」）。
- **更新対象**が **`対象外`** の行だけが増えている。
- **モード／当たり**の書式エラーで **行ごとエラー**。

---

## Step 4 — `gh-pages` 上のファイルが Step 3 の結果と一致するか

1. Actions ログの **「配信確認（gh-pages の先端コミット）」** で、**最新コミット**と **`master_out/` 以下のパス**が列挙されているか確認する。
2. リポジトリでブランチ **`gh-pages`** → **`master_out/index.json`** を開く。
3. Step 3 でローカルに出た **`index.json`** と、**中身（機種数・先頭の machine_id）**を比較する。

**一致しない**: push 失敗・別リポジトリ・**Step 1 のワークフローが別ブランチ**など。

**一致するのに「アプリだけ古い」**: Step 5 へ。

---

## Step 5 — ブラウザ／GitHub Pages のキャッシュ

1. **シークレット**で Pages の URL を開き直す。  
   例: `https://＜ユーザー＞.github.io/＜リポジトリ＞/master_out/index.json`
2. または **curl** で取得し、内容を確認する。

```bash
curl -sS "https://＜ユーザー＞.github.io/＜リポジトリ＞/master_out/index.json" | head -c 500
```

3. **Settings → Pages** で、配信元が **`gh-pages` ブランチ**（この運用の場合）になっているか確認する。**Source が「GitHub Actions」のみ**だと、ブランチ push だけでは表示が変わらないことがある（`docs/MASTER_OUT_DEPLOY_GAS.md` §4.2）。

---

## Step 6 — 差分更新で「ファイルは書き換わっていない」だけの場合

`convert_master_one_sheet.py` は **JSON の意味が同じなら `machines/*.json` をスキップ**する。

- **CSV は変わったが JSON の内容が同じ**（同じ機種・同じフィールド）→ **タイムスタンプだけ変わらない**のは仕様どおり。
- **強制的に全部書き換え**したいときは CI 用に **`MASTER_OUT_FORCE_FULL_WRITE=1`** を Variables で渡す（ワークフロー側で `env` に追加する必要がある場合あり）。

---

## チェックリスト（印刷用）

```
□ gh-pages ブランチで master_out を見ている（main ではない）
□ MASTER_ONE_SHEET_CSV_URL が正しいシートの公開 URL
□ curl で CSV 先頭を取り、ヘッダーが現行30列仕様
□ ローカルで同じ URL を convert し index の件数・内容が期待どおり
□ Actions 成功 + 配信確認ステップで gh-pages が更新されている
□ curl で Pages の index.json を取り、gh-pages 上の内容と一致
□ 中身が同じなら差分スキップ or FORCE_FULL_WRITE を検討
```

---

## 関連ドキュメント

- `docs/機種マスター1シート仕様.md` … 列定義・モード／当たり形式
- `docs/MASTER_OUT_DEPLOY_GAS.md` … GAS からの起動・Pages 設定
- `master_out/README.md` … サンプル CSV の使い方

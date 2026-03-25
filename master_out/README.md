# master_out（ローカル・gh-pages）

- **本番の CSV** はスプレッドシートの「ウェブに公開」URL（`MASTER_ONE_SHEET_CSV_URL`）。列定義は **`docs/機種マスター1シート仕様.md`**（**9列・A〜I**、導入開始日〜ステータス）。
- **`index.json`** は機種一覧（CSV の全行）。**`machines/<id>.json`** は配信条件を満たした行のみ（**`main` では Git 追跡外**。正は **gh-pages** の `master_out/machines/`）。
- **`master_one_sheet_sample.csv`** はローカル検証用。**1行目は `scripts/convert_master_one_sheet.py` の `HEADER_NAMES` と一致**させる。モード・当たり列は廃止（JSON では `modes` / `bonuses` は空配列）。
- GitHub 上の **`gh-pages` ブランチ**の `master_out/` が Pages 配信物。`main` には **`index.json` / `export_status.csv` / サンプル CSV 等**のみ残し、**`machines/*.json` はコミットしない**（`.gitignore` 済み）。

```bash
# サンプルで変換確認
python scripts/convert_master_one_sheet.py master_out/master_one_sheet_sample.csv
```

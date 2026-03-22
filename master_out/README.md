# master_out（ローカル・gh-pages）

- **本番の CSV** はスプレッドシートの「ウェブに公開」URL（`MASTER_ONE_SHEET_CSV_URL`）。列定義は **`docs/機種マスター1シート仕様.md`**（30列・J=更新対象・K〜=モード0〜）。
- **`index.json`** は機種一覧（ステータス・更新対象に関係なく全行）。**`machines/<id>.json`** は配信条件を満たした行のみ（**`main` では Git 追跡外**。正は **gh-pages** の `master_out/machines/`）。
- **`master_one_sheet_sample.csv`** はローカル検証用。**1行目は `scripts/convert_master_one_sheet.py` の `HEADER_NAMES` と一致**させる。モード列は `mode_0/表示名/densapo` 形式、当たり列はスラッシュ9項目（空セル可）。
- GitHub 上の **`gh-pages` ブランチ**の `master_out/` が Pages 配信物。`main` には **`index.json` / `export_status.csv` / サンプル CSV 等**のみ残し、**`machines/*.json` はコミットしない**（`.gitignore` 済み）。

```bash
# サンプルで変換確認
python scripts/convert_master_one_sheet.py master_out/master_one_sheet_sample.csv
```

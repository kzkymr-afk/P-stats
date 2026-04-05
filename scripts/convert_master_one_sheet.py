#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
1シート・1機種1行のCSVを読み、index.json / machines/{機種ID}.json / export_status.csv を生成する。

仕様（2026-03 改定）:
- スプレッドシートは **A〜I の9列のみ**（導入開始日〜ステータス）。モード列・当たり列・更新対象列は廃止。
- 各 machines/{id}.json は `modes: []` / `bonuses: []` のメタデータのみ（アプリは空配列でもデコード可能）。
- **導入開始日からカレンダー6年を経過した日の翌日以降**は、ステータスを **対象外** とみなす（CSV が「完了」でも変換時に上書き）。
- **index.json** および **machines/*.json** には **対象外** の行を含めない（新規登録検索から除外）。
- `MASTER_EXPORT_STATUS_VALUES` を **未設定**にすると、対象外・ステータス空以外はすべて JSON 化。設定時はその集合に加えて対象外を除外。
- **機種名**と**導入開始日**（または導入日）が両方入っている行は、ステータスが「完了」でなくても（空でも）index / machines に含める（検索対象）。それ以外の行は従来どおりステータスでフィルタ。

使い方:
  python scripts/convert_master_one_sheet.py [CSVのパス]
  MASTER_ONE_SHEET_CSV_URL="https://..." python scripts/convert_master_one_sheet.py

出力:
  master_out/index.json, master_out/machines/<id>.json, master_out/export_status.csv

差分更新（既定）:
  既存の master_out/machines/*.json があるとき、JSON を意味比較し変更がない機種はファイルを書き換えない。
  今回のエクスポート対象に含まれない safe_id の *.json は削除。
  全件上書き: 環境変数 MASTER_OUT_FORCE_FULL_WRITE=1
"""

from __future__ import annotations

import csv
import io
import json
import os
import re
import sys
from datetime import date, datetime
from pathlib import Path
from typing import Optional

try:
    import requests
except ImportError:
    requests = None

_SCRIPTS_DIR = Path(__file__).resolve().parent
if str(_SCRIPTS_DIR) not in sys.path:
    sys.path.insert(0, str(_SCRIPTS_DIR))
from google_sheets_csv import fetch_spreadsheet_csv

REPO_ROOT = Path(__file__).resolve().parent.parent
OUTPUT_DIR = Path(os.environ.get("MASTER_ONE_SHEET_OUTPUT_DIR", str(REPO_ROOT / "master_out")))
MACHINES_SUBDIR = "machines"
REQUEST_TIMEOUT = 20
FORCE_FULL_WRITE = os.environ.get("MASTER_OUT_FORCE_FULL_WRITE", "").strip().lower() in ("1", "true", "yes")

# A〜I（列名で解決。順序は不問）
HEADER_NAMES = [
    "導入開始日",
    "機種ID",
    "機種名",
    "メーカー",
    "確率",
    "機種タイプ",
    "スペック",
    "特徴タグ",
    "ステータス",
]

_export_status_env = (os.environ.get("MASTER_EXPORT_STATUS_VALUES") or "").strip()
# None = 「対象外」以外はすべてエクスポート。非空なら指定ステータスのみ（対象外は常に除外）
EXPORT_STATUS_VALUES: Optional[set[str]] = (
    {s.strip() for s in _export_status_env.split("|") if s.strip()} if _export_status_env else None
)


def _normalize(s: str) -> str:
    return (s or "").strip().lower()


def _col_index(headers: list[str]) -> dict[str, int]:
    result: dict[str, int] = {}
    aliases = {
        "機種ID": ["機種id", "machine_id", "machine id"],
        "機種名": ["name", "machine_name", "machine name"],
        "ステータス": ["status"],
        "導入開始日": ["導入日", "introduction_date", "introduction date"],
        "機種タイプ": ["type", "machine_type", "machine type"],
    }
    for canon in HEADER_NAMES:
        if canon in result:
            continue
        for i, h in enumerate(headers):
            key = (h or "").strip()
            if key == canon:
                result[canon] = i
                break
            if _normalize(key) in aliases.get(canon, []):
                result[canon] = i
                break
    return result


def _canonical_json(obj) -> str:
    return json.dumps(obj, ensure_ascii=False, sort_keys=True, separators=(",", ":"))


def _sanitize_machine_id(machine_id: str) -> str:
    s = (machine_id or "").strip()
    s = re.sub(r"[/\\:*?\"<>|]", "-", s)
    s = re.sub(r"\s+", "_", s)
    s = s.strip("._ ")
    return s or "unknown"


def _add_calendar_years(d: date, years: int) -> date:
    y = d.year + years
    try:
        return date(y, d.month, d.day)
    except ValueError:
        return date(y, d.month, 28)


def _parse_intro_date(raw: str) -> Optional[date]:
    s = (raw or "").strip()
    if not s or s in ("-", "—", "不明"):
        return None
    for fmt in ("%Y/%m/%d", "%Y-%m-%d", "%Y.%m.%d"):
        try:
            return datetime.strptime(s.replace(".", "/"), fmt).date()
        except ValueError:
            continue
    m = re.match(r"^(\d{4})[年/](\d{1,2})[月/](\d{1,2})", s)
    if m:
        y, mo, da = int(m.group(1)), int(m.group(2)), int(m.group(3))
        try:
            return date(y, mo, da)
        except ValueError:
            return None
    return None


def _effective_status_from_row(
    values: list,
    idx: dict[str, int],
    today: date,
) -> str:
    def cell(key: str, default: str = "") -> str:
        if key not in idx or idx[key] >= len(values):
            return default
        return (values[idx[key]] or "").strip() or default

    raw_status = cell("ステータス")
    intro_raw = cell("導入開始日") or cell("導入日")
    intro = _parse_intro_date(intro_raw)
    if intro is not None and today > _add_calendar_years(intro, 6):
        return "対象外"
    return raw_status


def _should_skip_machine_export(status: str) -> bool:
    s = (status or "").strip()
    if not s:
        return True
    if s == "対象外":
        return True
    if EXPORT_STATUS_VALUES is not None:
        return s not in EXPORT_STATUS_VALUES
    return False


def _row_has_name_and_intro(values: list, idx: dict[str, int]) -> bool:
    """機種名と導入開始日（または導入日）が両方非空なら True（ステータスに関わらず検索用マスタへ載せる）。"""

    def cell(key: str, default: str = "") -> str:
        if key not in idx or idx[key] >= len(values):
            return default
        return (values[idx[key]] or "").strip() or default

    name = cell("機種名", "")
    intro = cell("導入開始日") or cell("導入日")
    return bool(name.strip()) and bool(intro.strip())


def fetch_csv_from_url(url: str) -> str:
    if requests is None:
        raise RuntimeError("requests がインストールされていません: pip install requests")
    return fetch_spreadsheet_csv(url, timeout=REQUEST_TIMEOUT)


def load_and_validate_rows(csv_content: str, today: Optional[date] = None):
    """戻り値: valid_rows, catalog_rows, skip_report"""
    ref_day = today or date.today()
    lines = [line for line in csv_content.splitlines() if line.strip()]
    if len(lines) < 2:
        return [], [], [(0, "", "error", "empty_csv")]
    reader = csv.reader(io.StringIO(csv_content))
    rows = list(reader)
    headers = rows[0]
    idx = _col_index(headers)

    if "機種ID" not in idx or "機種名" not in idx:
        return [], [], [(0, "", "error", "ヘッダーに機種ID・機種名がありません")]

    def v(values: list, key: str, default: str = "") -> str:
        if key not in idx or idx[key] >= len(values):
            return default
        return (values[idx[key]] or "").strip() or default

    seen_ids: set[str] = set()
    valid_rows: list[dict] = []
    catalog_rows: list[dict] = []
    skip_report: list[tuple[int, str, str, str]] = []

    for row_no, values in enumerate(rows[1:], start=2):
        machine_id = v(values, "機種ID")
        effective_status = _effective_status_from_row(values, idx, ref_day)

        catalog_entry: dict = {
            "machine_id": machine_id,
            "name": v(values, "機種名", machine_id or ""),
            "manufacturer": v(values, "メーカー"),
            "probability": v(values, "確率"),
            "machine_type": v(values, "機種タイプ"),
            "intro_start": v(values, "導入開始日") or v(values, "導入日"),
            "status": effective_status,
        }
        if "更新対象" in idx:
            catalog_entry["update_target"] = v(values, "更新対象")
        catalog_rows.append(catalog_entry)

        if not machine_id:
            skip_report.append((row_no, machine_id, "skipped", "missing_machine_id"))
            continue
        if machine_id in seen_ids:
            skip_report.append((row_no, machine_id, "skipped", "duplicate_machine_id"))
            continue
        seen_ids.add(machine_id)

        if effective_status == "対象外":
            skip_report.append((row_no, machine_id, "skipped", "taishogai"))
            continue

        has_name_and_intro = _row_has_name_and_intro(values, idx)

        if not has_name_and_intro and _should_skip_machine_export(effective_status):
            detail = "status_excluded_or_empty"
            if not (v(values, "ステータス") or "").strip():
                detail = "status_empty"
            elif EXPORT_STATUS_VALUES is not None:
                detail = "status_not_in_MASTER_EXPORT_STATUS_VALUES"
            skip_report.append((row_no, machine_id, "skipped", detail))
            continue

        valid_rows.append(
            {
                "machine_id": machine_id,
                "name": v(values, "機種名", machine_id),
                "manufacturer": v(values, "メーカー"),
                "probability": v(values, "確率"),
                "machine_type": v(values, "機種タイプ"),
                "intro_start": v(values, "導入開始日") or v(values, "導入日"),
                "spec": v(values, "スペック"),
                "tags": v(values, "特徴タグ"),
                "status": effective_status,
                "modes": [],
                "bonuses": [],
            }
        )

    for r in valid_rows:
        skip_report.append((0, r["machine_id"], "exported", ""))
    return valid_rows, catalog_rows, skip_report


def build_index(rows: list[dict]) -> list[dict]:
    out: list[dict] = []
    for r in rows:
        st = (r.get("status") or "").strip()
        if st == "対象外":
            continue
        item = {
            "machine_id": r["machine_id"],
            "name": r["name"],
            "manufacturer": r.get("manufacturer") or "",
            "probability": r.get("probability") or "",
            "machine_type": r.get("machine_type") or "",
            "intro_start": r.get("intro_start") or "",
            "status": st,
        }
        if "update_target" in r:
            item["update_target"] = r.get("update_target") or ""
        out.append(item)
    return out


def build_machine_json(row: dict) -> dict:
    return {
        "machine_id": row["machine_id"],
        "name": row["name"],
        "manufacturer": row.get("manufacturer") or "",
        "probability": row.get("probability") or "",
        "machine_type": row.get("machine_type") or "",
        "intro_start": row.get("intro_start") or "",
        "spec": row.get("spec") or "",
        "tags": row.get("tags") or "",
        "modes": row.get("modes") or [],
        "bonuses": row.get("bonuses") or [],
    }


def main() -> None:
    if len(sys.argv) > 1 and sys.argv[1] in ("-h", "--help"):
        print(__doc__.strip(), flush=True)
        sys.exit(0)

    print(
        f"[convert_master_one_sheet] MASTER_EXPORT_STATUS_VALUES env={_export_status_env!r} -> "
        f"filter={sorted(EXPORT_STATUS_VALUES) if EXPORT_STATUS_VALUES is not None else '（未指定・対象外以外すべて）'}",
        flush=True,
    )

    csv_source = os.environ.get("MASTER_ONE_SHEET_CSV_URL")
    local_path = sys.argv[1].strip() if len(sys.argv) > 1 else None

    csv_content: Optional[str] = None
    if local_path:
        path = Path(local_path)
        if path.is_file():
            csv_content = path.read_text(encoding="utf-8")
            print(f"[convert_master_one_sheet] ローカルCSV: {path}", flush=True)
        else:
            print(f"[convert_master_one_sheet] ファイルが見つかりません: {path}", flush=True)
    if csv_content is None and csv_source:
        print(f"[convert_master_one_sheet] 取得元URL: {csv_source}", flush=True)
        csv_content = fetch_csv_from_url(csv_source)
    if csv_content is None:
        sample = REPO_ROOT / "master_out" / "master_one_sheet.csv"
        if sample.is_file():
            csv_content = sample.read_text(encoding="utf-8")
            print(f"[convert_master_one_sheet] サンプルCSV: {sample}", flush=True)
    if not csv_content:
        print(
            "[convert_master_one_sheet] 入力がありません。MASTER_ONE_SHEET_CSV_URL を設定するか、"
            "CSV ファイルパスを引数で指定してください。",
            flush=True,
        )
        sys.exit(1)

    valid_rows, catalog_rows, skip_report = load_and_validate_rows(csv_content)

    try:
        from collections import Counter

        reason_counter = Counter()
        for _, _, st, detail in skip_report:
            if detail:
                reason = (detail.split(":")[0] or "").strip()
            else:
                reason = ""
            key = st + ":" + reason if reason else st
            reason_counter[key] += 1
        top = reason_counter.most_common(8)
        print(f"[convert_master_one_sheet] skip_report top={top}", flush=True)
    except Exception:
        pass

    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    machines_dir = OUTPUT_DIR / MACHINES_SUBDIR
    machines_dir.mkdir(parents=True, exist_ok=True)

    index = build_index(catalog_rows)
    index_path = OUTPUT_DIR / "index.json"
    if FORCE_FULL_WRITE:
        with open(index_path, "w", encoding="utf-8") as f:
            json.dump(index, f, ensure_ascii=False, indent=2)
        print(f"[convert_master_one_sheet] index.json: 全件書き込み {len(index)} 機種 -> {index_path}", flush=True)
    else:
        write_index = True
        if index_path.is_file():
            try:
                old_index = json.loads(index_path.read_text(encoding="utf-8"))
                if _canonical_json(old_index) == _canonical_json(index):
                    write_index = False
            except (json.JSONDecodeError, OSError):
                pass
        if write_index:
            with open(index_path, "w", encoding="utf-8") as f:
                json.dump(index, f, ensure_ascii=False, indent=2)
            print(f"[convert_master_one_sheet] index.json: 更新 {len(index)} 機種 -> {index_path}", flush=True)
        else:
            print(f"[convert_master_one_sheet] index.json: 変更なし（スキップ） {len(index)} 機種", flush=True)

    expected_safe_ids: set[str] = set()
    for row in valid_rows:
        expected_safe_ids.add(_sanitize_machine_id(row["machine_id"]))
    n_written = n_unchanged = 0
    for row in valid_rows:
        detail = build_machine_json(row)
        safe_id = _sanitize_machine_id(row["machine_id"])
        out_path = machines_dir / f"{safe_id}.json"
        if not FORCE_FULL_WRITE and out_path.is_file():
            try:
                old_obj = json.loads(out_path.read_text(encoding="utf-8"))
                if _canonical_json(old_obj) == _canonical_json(detail):
                    n_unchanged += 1
                    continue
            except (json.JSONDecodeError, OSError):
                pass
        with open(out_path, "w", encoding="utf-8") as f:
            json.dump(detail, f, ensure_ascii=False, indent=2)
        n_written += 1
    n_removed = 0
    for p in machines_dir.glob("*.json"):
        if p.stem not in expected_safe_ids:
            try:
                p.unlink()
                n_removed += 1
            except OSError:
                pass
    print(
        f"[convert_master_one_sheet] machines/*.json: 新規・更新={n_written}, 変更なしスキップ={n_unchanged}, "
        f"削除={n_removed}, 配信JSON行数={len(valid_rows)} -> {machines_dir}"
        + (" [FORCE_FULL_WRITE]" if FORCE_FULL_WRITE else ""),
        flush=True,
    )

    status_path = OUTPUT_DIR / "export_status.csv"
    with open(status_path, "w", encoding="utf-8", newline="") as f:
        w = csv.writer(f)
        w.writerow(["row_no", "machine_id", "status", "reason", "detail"])
        for row_no, mid, st, detail in skip_report:
            reason = detail.split(":")[0].strip() if detail else ""
            w.writerow([row_no, mid, st, reason, detail])
    print(f"[convert_master_one_sheet] export_status.csv: {len(skip_report)} 行 -> {status_path}", flush=True)


if __name__ == "__main__":
    main()

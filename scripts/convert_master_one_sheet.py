#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
1シート・1機種1行のCSV/TSV（マスター）を読み、
index.json / machines/{機種ID}.json / export_status.csv を生成する。

新仕様:
- モードセル: mode_id/mode_name/densapo（densapo は int または INF/∞）
- 当たりセル: name/base/unit/max_concat/stay_mode_id/next_mode_id/branch_label

＝＝＝ 使い方 ＝＝＝

  python scripts/convert_master_one_sheet.py [CSVのパス]
  MASTER_ONE_SHEET_CSV_URL="https://docs.google.com/.../export?format=csv&gid=0" python scripts/convert_master_one_sheet.py

出力:
  master_out/index.json            … 機種一覧（machine_id, name）
  master_out/machines/<機種ID>.json … 機種ごと統合JSON（アプリ互換）
  master_out/export_status.csv     … スキップした行の報告
"""

import csv
import io
import json
import os
import re
import sys
from pathlib import Path
from typing import Optional

try:
    import requests
except ImportError:
    requests = None

REPO_ROOT = Path(__file__).resolve().parent.parent
OUTPUT_DIR = Path(os.environ.get("MASTER_ONE_SHEET_OUTPUT_DIR", str(REPO_ROOT / "master_out")))
MACHINES_SUBDIR = "machines"
REQUEST_TIMEOUT = 20

# 列インデックス（0-based）。ヘッダー名で解決する（列位置に依存しない）。
HEADER_NAMES = [
    "導入開始日", "機種名", "メーカー", "確率", "機種タイプ", "スペック", "特徴タグ", "機種ID", "ステータス",
    "モード0", "モード1", "モード2", "モード3", "モード4", "モード5", "モード6", "モード7",
    "当たり1", "当たり2", "当たり3", "当たり4", "当たり5", "当たり6",
    "当たり7", "当たり8", "当たり9", "当たり10", "当たり11", "当たり12",
]

# 出力対象ステータス（デフォルト: 完了 のみ）
EXPORT_STATUS_VALUES = {s.strip() for s in os.environ.get("MASTER_EXPORT_STATUS_VALUES", "完了").split("|") if s.strip()}
SKIP_STATUS_VALUES = {"スキップ", "無効", "skip", "invalid", "スキップ ", "無効 "}


def _normalize(s: str) -> str:
    return (s or "").strip().lower()


def _col_index(headers: list[str]) -> dict[str, int]:
    """ヘッダー行から列名→0-basedインデックスのマップを返す。"""
    normalized = [_normalize(h or "") for h in headers]
    result = {}
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


def _sanitize_machine_id(machine_id: str) -> str:
    """ファイル名に使えない文字を除去・置換する。"""
    s = (machine_id or "").strip()
    s = re.sub(r"[/\\:*?\"<>|]", "-", s)
    s = re.sub(r"\s+", "_", s)
    s = s.strip("._ ")
    return s or "unknown"


def _parse_int(s: str) -> Optional[int]:
    s = (s or "").strip()
    if not s:
        return None
    try:
        return int(float(s))
    except ValueError:
        return None


def _should_skip_status(status: str) -> bool:
    s = (status or "").strip()
    if not s:
        return True
    if s in EXPORT_STATUS_VALUES:
        return False
    return _normalize(s) in {t.lower() for t in SKIP_STATUS_VALUES}


def _parse_densapo(s: str):
    t = (s or "").strip()
    if not t:
        return 0
    if t.lower() in {"inf", "∞"}:
        return "INF"
    v = _parse_int(t)
    return v if v is not None else 0


def _parse_mode_cell(cell: str) -> Optional[dict]:
    raw = (cell or "").strip()
    if not raw:
        return None
    parts = [p.strip() for p in raw.split("/")]
    if len(parts) != 3:
        return None
    mode_id = _parse_int(parts[0])
    if mode_id is None or not (0 <= mode_id <= 7):
        return None
    name = parts[1] or ""
    densapo = _parse_densapo(parts[2])
    return {"mode_id": mode_id, "name": name, "densapo": densapo}


def _parse_bonus_cell(cell: str) -> Optional[dict]:
    """
    当たりセルをパースする。
    形式（7要素）:
      name/base_payout/unit_payout/max_concat/stay_mode_id/next_mode_id/branch_label
    """
    cell = (cell or "").strip()
    if not cell:
        return None
    parts = [p.strip() for p in cell.split("/")]
    if len(parts) != 7:
        return None
    name = parts[0] or ""
    if not name:
        return None
    base_payout = _parse_int(parts[1])
    unit_payout = _parse_int(parts[2])
    max_concat = _parse_int(parts[3])
    stay = _parse_int(parts[4])
    nxt = _parse_int(parts[5])
    if base_payout is None or unit_payout is None or max_concat is None or stay is None or nxt is None:
        return None
    if not (0 <= stay <= 7) or not (0 <= nxt <= 7):
        return None
    branch_label = parts[6] or ""
    return {
        "name": name,
        "base_payout": max(0, base_payout),
        "unit_payout": max(0, unit_payout),
        "max_concat": max(0, max_concat),
        "stay_mode_id": stay,
        "next_mode_id": nxt,
        "branch_label": branch_label,
    }


def fetch_csv_from_url(url: str) -> str:
    if requests is None:
        raise RuntimeError("requests がインストールされていません: pip install requests")
    r = requests.get(url, timeout=REQUEST_TIMEOUT)
    r.raise_for_status()
    r.encoding = "utf-8"
    raw = r.text
    if raw.startswith("\uFEFF"):
        raw = raw[1:]
    return raw


def load_and_validate_rows(csv_content: str):
    """
    CSV をパースし、(有効行のリスト, スキップ報告のリスト) を返す。
    有効行: 機種IDが空でない・重複でない・ステータスでスキップでない。
    スキップ報告: (行番号1-based, 機種ID, 理由)
    """
    lines = [line for line in csv_content.splitlines() if line.strip()]
    if len(lines) < 2:
        return [], []
    reader = csv.reader(io.StringIO(csv_content))
    rows = list(reader)
    headers = rows[0]
    idx = _col_index(headers)

    if "機種ID" not in idx or "機種名" not in idx:
        return [], [(0, "", "ヘッダーに機種ID・機種名がありません")]

    def v(values: list, key: str, default: str = "") -> str:
        if key not in idx or idx[key] >= len(values):
            return default
        return (values[idx[key]] or "").strip() or default

    seen_ids: set[str] = set()
    valid_rows: list[dict] = []
    skip_report: list[tuple[int, str, str, str]] = []

    for row_no, values in enumerate(rows[1:], start=2):
        machine_id = v(values, "機種ID")
        status = v(values, "ステータス")

        if not machine_id:
            skip_report.append((row_no, machine_id, "skipped", "missing_machine_id"))
            continue
        if machine_id in seen_ids:
            skip_report.append((row_no, machine_id, "skipped", "duplicate_machine_id"))
            continue
        if _should_skip_status(status):
            skip_report.append((row_no, machine_id, "skipped", "status_not_ready"))
            continue

        seen_ids.add(machine_id)
        # モード 0〜7
        modes: list[dict] = []
        mode_parse_errors: list[str] = []
        for i in range(8):
            raw = v(values, f"モード{i}", "")
            if not raw:
                continue
            parsed = _parse_mode_cell(raw)
            if not parsed:
                mode_parse_errors.append(f"モード{i}={raw}")
            else:
                modes.append(parsed)

        # 当たり1〜12
        bonuses: list[dict] = []
        bonus_parse_errors: list[str] = []
        for i in range(1, 13):
            cell = v(values, f"当たり{i}")
            if not cell:
                continue
            parsed = _parse_bonus_cell(cell)
            if not parsed:
                bonus_parse_errors.append(f"当たり{i}={cell}")
            else:
                bonuses.append(parsed)

        if mode_parse_errors:
            skip_report.append((row_no, machine_id, "error", "parse_error_mode: " + "; ".join(mode_parse_errors[:3])))
            continue
        if bonus_parse_errors:
            skip_report.append((row_no, machine_id, "error", "parse_error_bonus: " + "; ".join(bonus_parse_errors[:3])))
            continue

        # 検証: stay_mode_id 内の同名分岐
        by_stay: dict[int, list[dict]] = {}
        for b in bonuses:
            by_stay.setdefault(b["stay_mode_id"], []).append(b)
        bad_dup = []
        bad_rowdup = []
        for stay, lst in by_stay.items():
            by_name = {}
            for b in lst:
                by_name.setdefault(b["name"], []).append(b)
            for name, items in by_name.items():
                if len(items) > 1:
                    if all((it.get("branch_label") or "").strip() == "" for it in items):
                        bad_dup.append(f"stay={stay},name={name}")
                seen = set()
                for it in items:
                    key = (it["name"], it["next_mode_id"], (it.get("branch_label") or "").strip())
                    if key in seen:
                        bad_rowdup.append(f"stay={stay},name={name}")
                    seen.add(key)
        if bad_dup:
            skip_report.append((row_no, machine_id, "error", "duplicate_bonus_name_without_branch: " + ", ".join(bad_dup[:3])))
            continue
        if bad_rowdup:
            skip_report.append((row_no, machine_id, "error", "duplicate_bonus_row: " + ", ".join(bad_rowdup[:3])))
            continue

        valid_rows.append({
            "machine_id": machine_id,
            "name": v(values, "機種名", machine_id),
            "manufacturer": v(values, "メーカー"),
            "probability": v(values, "確率"),
            "machine_type": v(values, "機種タイプ"),
            "intro_start": v(values, "導入開始日") or v(values, "導入日"),
            "spec": v(values, "スペック"),
            "tags": v(values, "特徴タグ"),
            "status": status,
            "modes": modes,
            "bonuses": bonuses,
        })

    # 成功行も export_status に出す
    for r in valid_rows:
        skip_report.append((0, r["machine_id"], "exported", ""))
    return valid_rows, skip_report


def build_index(rows: list[dict]) -> list[dict]:
    out = []
    for r in rows:
        out.append({
            "machine_id": r["machine_id"],
            "name": r["name"],
            "manufacturer": r.get("manufacturer") or "",
            "probability": r.get("probability") or "",
            "machine_type": r.get("machine_type") or "",
            "intro_start": r.get("intro_start") or "",
            "status": r.get("status") or "",
        })
    return out


def build_machine_json(row: dict) -> dict:
    """1行分のデータから machines/{id}.json 用 dict を組み立てる（新仕様）。"""
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

    csv_source = os.environ.get("MASTER_ONE_SHEET_CSV_URL")
    local_path = sys.argv[1].strip() if len(sys.argv) > 1 else None

    csv_content = None
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

    valid_rows, skip_report = load_and_validate_rows(csv_content)

    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    machines_dir = OUTPUT_DIR / MACHINES_SUBDIR
    machines_dir.mkdir(parents=True, exist_ok=True)

    # index.json
    index = build_index(valid_rows)
    index_path = OUTPUT_DIR / "index.json"
    with open(index_path, "w", encoding="utf-8") as f:
        json.dump(index, f, ensure_ascii=False, indent=2)
    print(f"[convert_master_one_sheet] index.json: {len(index)} 機種 -> {index_path}", flush=True)

    # machines/{id}.json
    for row in valid_rows:
        detail = build_machine_json(row)
        safe_id = _sanitize_machine_id(row["machine_id"])
        out_path = machines_dir / f"{safe_id}.json"
        with open(out_path, "w", encoding="utf-8") as f:
            json.dump(detail, f, ensure_ascii=False, indent=2)
    print(f"[convert_master_one_sheet] machines/*.json: {len(valid_rows)} ファイル -> {machines_dir}", flush=True)

    # export_status.csv
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

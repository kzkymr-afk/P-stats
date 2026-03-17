#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
1シート・1機種1行のCSV（マスター）を読み、
index.json / machines/{機種ID}.json / export_status.csv を生成する。

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

# 列インデックス（0-based）。ヘッダーがこの順で並ぶことを想定。別名は _col_index でマッチさせる。
# 現行（スプレッドシート）: A=導入開始日, B=機種ID, C=機種名, D=メーカー, E=確率, F=機種タイプ, G=スペック, H=特徴タグ, I=ステータス, J〜Q=モード0〜7, R〜AA=当たり1〜10
HEADER_NAMES = [
    "導入開始日", "機種ID", "機種名", "メーカー", "確率", "機種タイプ", "スペック", "特徴タグ",
    "モード0", "モード1", "モード2", "モード3", "モード4", "モード5", "モード6", "モード7",
    "当たり1", "当たり2", "当たり3", "当たり4", "当たり5", "当たり6",
    "当たり7", "当たり8", "当たり9", "当たり10", "当たり11", "当たり12",
    "ステータス",
]

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
    return _normalize(status) in {t.lower() for t in SKIP_STATUS_VALUES}


def _parse_bonus_cell(cell: str) -> Optional[dict]:
    """
    当たりセルをパースする。
    形式:
      - 新6要素（ユニット連結型）: 当たり名/基本出玉/ユニット出玉/最大連結数/滞在モード番号/移行先モード番号
      - 旧4要素（完結型）: 当たり名/出球数/滞在モード番号/移行先モード番号
      - 旧5要素（電サポ）: 当たり名/出球数/滞在モード番号/移行先モード番号/電サポ回数

    戻り値:
      - modes に振り分けするため stay_mode_id を返す（内部キー）。
      - BonusDetail 互換のキー: payout（=baseOut）, densapo, next_mode_id, ratio
      - ユニット連結型のキー: baseOut, unitOut, maxStack
    """
    cell = (cell or "").strip()
    if not cell:
        return None
    parts = [p.strip() for p in cell.split("/")]
    if len(parts) < 4:
        return None
    name = parts[0] or ""
    if not name:
        return None

    # 新6要素
    if len(parts) >= 6:
        base_out = _parse_int(parts[1]) or 0
        unit_out = _parse_int(parts[2]) or 0
        max_stack = _parse_int(parts[3]) or 1
        stay_mode_id = _parse_int(parts[4]) or 0
        next_mode_id = _parse_int(parts[5]) or 0
        stay_mode_id = max(0, min(7, stay_mode_id))
        next_mode_id = max(0, min(7, next_mode_id))
        max_stack = max(1, max_stack)
        return {
            "name": name,
            "payout": base_out,  # 旧互換（アプリ側が payout のみでも動くため）
            "baseOut": base_out,
            "unitOut": unit_out,
            "maxStack": max_stack,
            "ratio": 0,
            "densapo": 0,
            "next_mode_id": next_mode_id,
            "stay_mode_id": stay_mode_id,
        }

    # 旧4/旧5
    payout = _parse_int(parts[1]) or 0
    stay_mode_id = _parse_int(parts[2]) or 0
    next_mode_id = _parse_int(parts[3]) or 0
    densapo = _parse_int(parts[4]) if len(parts) > 4 else 0
    densapo = densapo or 0
    stay_mode_id = max(0, min(7, stay_mode_id))
    next_mode_id = max(0, min(7, next_mode_id))
    return {
        "name": name,
        "payout": payout,
        "baseOut": payout,
        "unitOut": 0,
        "maxStack": 1,
        "ratio": 0,
        "densapo": densapo,
        "next_mode_id": next_mode_id,
        "stay_mode_id": stay_mode_id,
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
    skip_report: list[tuple[int, str, str]] = []

    for row_no, values in enumerate(rows[1:], start=2):
        machine_id = v(values, "機種ID")
        status = v(values, "ステータス")

        if not machine_id:
            skip_report.append((row_no, machine_id, "機種IDが空"))
            continue
        if machine_id in seen_ids:
            skip_report.append((row_no, machine_id, "機種ID重複"))
            continue
        if _should_skip_status(status):
            skip_report.append((row_no, machine_id, "ステータスによりスキップ"))
            continue

        seen_ids.add(machine_id)
        # モード名 0〜7
        mode_names = [v(values, f"モード{i}", "") for i in range(8)]
        # 当たり1〜12 をパース
        bonuses_by_mode: dict[int, list[dict]] = {i: [] for i in range(8)}
        for i in range(1, 13):
            cell = v(values, f"当たり{i}")
            parsed = _parse_bonus_cell(cell)
            if parsed:
                stay = parsed.pop("stay_mode_id")
                bonuses_by_mode[stay].append(parsed)

        valid_rows.append({
            "machine_id": machine_id,
            "name": v(values, "機種名", machine_id),
            "manufacturer": v(values, "メーカー"),
            "probability": v(values, "確率"),
            "machine_type": v(values, "機種タイプ"),
            "introduction_date": v(values, "導入開始日") or v(values, "導入日"),
            "spec": v(values, "スペック"),
            "tags": v(values, "特徴タグ"),
            "mode_names": mode_names,
            "bonuses_by_mode": bonuses_by_mode,
        })

    return valid_rows, skip_report


def build_index(rows: list[dict]) -> list[dict]:
    return [{"machine_id": r["machine_id"], "name": r["name"]} for r in rows]


def build_machine_json(row: dict) -> dict:
    """1行分のデータからアプリ互換の machines/{id}.json 用 dict を組み立てる。"""
    modes = []
    for mode_id in range(8):
        name = (row["mode_names"][mode_id] or "").strip() or (f"モード{mode_id}" if mode_id > 0 else "通常")
        bonuses = row["bonuses_by_mode"].get(mode_id, [])
        modes.append({
            "mode_id": mode_id,
            "name": name,
            "bonuses": bonuses,
        })
    result = {
        "machine_id": row["machine_id"],
        "name": row["name"],
        "modes": modes,
    }
    # 拡張用にマスタ項目を付与（アプリは現状使わない）
    if row.get("manufacturer"):
        result["manufacturer"] = row["manufacturer"]
    if row.get("probability"):
        result["probability"] = row["probability"]
    if row.get("machine_type"):
        result["machine_type"] = row["machine_type"]
    if row.get("introduction_date"):
        result["introduction_date"] = row["introduction_date"]
    if row.get("spec"):
        result["spec"] = row["spec"]
    if row.get("tags"):
        result["tags"] = row["tags"]
    return result


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
        w.writerow(["行番号", "機種ID", "理由"])
        for row_no, mid, reason in skip_report:
            w.writerow([row_no, mid, reason])
    print(f"[convert_master_one_sheet] export_status.csv: {len(skip_report)} 件スキップ -> {status_path}", flush=True)


if __name__ == "__main__":
    main()

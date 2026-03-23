#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
1シート・1機種1行のCSVを読み、index.json / machines/{機種ID}.json / export_status.csv を生成する。

仕様（2026-03 固定）:
- モード列（モード0〜7）: 各セルは
    mode_N / 表示名 / densapo [/ ui_role]
  N は 0〜7 のみ。mode_0=通常、mode_1〜7=特殊モード。
  ui_role: n=通常系(0), r=RUSH系(1), l=LT(2)。省略時は mode_0→n、mode_1〜7→r。
- 当たり列（当たり1〜12）: スラッシュ9項目（必須）
    あたりID / あたり名 / 基本出玉 / ユニット出玉(カンマ区切りで複数可) / 最大連結数 /
    滞在モードID / 移行先モードID / 分岐ラベル / 昇格先あたりID
  モードIDは mode_0〜mode_7 または整数 0〜7。昇格先は - または空でなし。

使い方:
  python scripts/convert_master_one_sheet.py [CSVのパス]
  MASTER_ONE_SHEET_CSV_URL="https://..." python scripts/convert_master_one_sheet.py

制限付き共有（401 回避）:
  環境変数 GOOGLE_SERVICE_ACCOUNT_JSON にサービスアカウント鍵の JSON 文字列を設定し、
  スプレッドシートをそのメールに閲覧者共有。pip install google-auth が必要。

出力:
  master_out/index.json, master_out/machines/<id>.json, master_out/export_status.csv

index.json:
  CSV 上の全機種を列挙（機種IDが空でなく、重複しない先着行）。ステータス・更新対象に関係なく含める。
  「更新対象」列があるときは各要素に update_target を含める。

差分更新（既定）:
  既存の master_out/machines/*.json があるとき、JSON を意味比較し変更がない機種はファイルを書き換えない。
  今回のエクスポート対象に含まれない safe_id の *.json は削除（CSVから消えた・ステータスで落ちた機種）。
  「更新対象」列が「対象外」の行は JSON を書き換えず、既存ファイルも削除しない。
  CI では gh-pages 上の master_out を先に checkout してから本スクリプトを実行すること（workflow 参照）。
  全件上書き: 環境変数 MASTER_OUT_FORCE_FULL_WRITE=1
"""

from __future__ import annotations

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

_SCRIPTS_DIR = Path(__file__).resolve().parent
if str(_SCRIPTS_DIR) not in sys.path:
    sys.path.insert(0, str(_SCRIPTS_DIR))
from google_sheets_csv import fetch_spreadsheet_csv

REPO_ROOT = Path(__file__).resolve().parent.parent
OUTPUT_DIR = Path(os.environ.get("MASTER_ONE_SHEET_OUTPUT_DIR", str(REPO_ROOT / "master_out")))
MACHINES_SUBDIR = "machines"
REQUEST_TIMEOUT = 20
FORCE_FULL_WRITE = os.environ.get("MASTER_OUT_FORCE_FULL_WRITE", "").strip().lower() in ("1", "true", "yes")

HEADER_NAMES = [
    "導入開始日", "機種名", "メーカー", "確率", "機種タイプ", "スペック", "特徴タグ", "機種ID", "ステータス",
    "更新対象",
    "モード0", "モード1", "モード2", "モード3", "モード4", "モード5", "モード6", "モード7",
    "当たり1", "当たり2", "当たり3", "当たり4", "当たり5", "当たり6",
    "当たり7", "当たり8", "当たり9", "当たり10", "当たり11", "当たり12",
]

_export_status_env = (os.environ.get("MASTER_EXPORT_STATUS_VALUES") or "").strip()
# 環境変数が「未設定」ではなく「空文字」の場合、set が空になって全行スキップされるのを防ぐ。
_export_status_base = _export_status_env if _export_status_env else "完了"
EXPORT_STATUS_VALUES = {s.strip() for s in _export_status_base.split("|") if s.strip()}
SKIP_STATUS_VALUES = {"スキップ", "無効", "skip", "invalid", "スキップ ", "無効 "}

# 「更新対象」列が「対象外」のときは master_out へ書き出さず、既存 JSON は保持（削除しない）
UPDATE_TARGET_EXCLUDE_LABELS = {
    "対象外",
    "外",
    "しない",
    "no",
    "false",
    "0",
    "×",
    "x",
    "否",
    "－",
    "-",
}


def _normalize(s: str) -> str:
    return (s or "").strip().lower()


UPDATE_TARGET_EXCLUDE_NORMALIZED = {_normalize(s) for s in UPDATE_TARGET_EXCLUDE_LABELS}


def _col_index(headers: list[str]) -> dict[str, int]:
    result: dict[str, int] = {}
    aliases = {
        "機種ID": ["機種id", "machine_id", "machine id"],
        "機種名": ["name", "machine_name", "machine name"],
        "ステータス": ["status"],
        "更新対象": ["update_target", "update target"],
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
    """意味が同じなら一致する比較用文字列（キー順・空白差を無視）。"""
    return json.dumps(obj, ensure_ascii=False, sort_keys=True, separators=(",", ":"))


def _sanitize_machine_id(machine_id: str) -> str:
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


def _parse_unit_payout_list(token: str) -> Optional[list[int]]:
    """ユニット出玉列: 半角・全角カンマ区切りで複数可。空・不正なら None。"""
    t = (token or "").strip()
    if not t:
        return None
    pieces = [p.strip() for p in t.replace("，", ",").split(",")]
    pieces = [p for p in pieces if p]
    if not pieces:
        return None
    out: list[int] = []
    for p in pieces:
        v = _parse_int(p)
        if v is None:
            return None
        out.append(max(0, v))
    return out


def _should_skip_status(status: str) -> bool:
    s = (status or "").strip()
    # JSON 作成対象は、環境変数 `MASTER_EXPORT_STATUS_VALUES` に含まれるステータスのみ。
    # それ以外（例: 空以外の中間ステータス）は「未完了」とみなして machines/<id>.json を生成しない。
    if not s:
        return True
    return s not in EXPORT_STATUS_VALUES


def _is_export_update_target(values: list[str], idx: dict[str, int]) -> bool:
    """更新対象列が無い CSV は従来どおり全行が配信対象。

    列があるとき: 空白・「対象」は配信対象。「対象外」（および EXCLUDE 表記）のみ除外（既存 JSON は保持）。
    """
    if "更新対象" not in idx:
        return True
    col = idx["更新対象"]
    raw = (values[col] if col < len(values) else "") or ""
    s = raw.strip()
    if not s:
        return True  # 空白 = 「対象」と同じ
    if s in UPDATE_TARGET_EXCLUDE_LABELS:
        return False
    if _normalize(s) in UPDATE_TARGET_EXCLUDE_NORMALIZED:
        return False
    return True


def _parse_densapo(s: str):
    t = (s or "").strip()
    if not t:
        return 0
    if t.lower() in {"inf", "∞"}:
        return "INF"
    v = _parse_int(t)
    return v if v is not None else 0


def _parse_ui_role_letter(s: str) -> int:
    t = (s or "").strip().lower()
    if t in ("n", "normal", "通常"):
        return 0
    if t in ("l", "lt", "ＬＴ"):
        return 2
    return 1


def _parse_mode_cell(cell: str) -> Optional[dict]:
    """mode_N/表示名/densapo[/ui_role] のみ。N は 0〜7。"""
    raw = (cell or "").strip()
    if not raw:
        return None
    parts = [p.strip() for p in raw.split("/")]
    if len(parts) < 3:
        return None
    mm = re.match(r"(?i)^mode_(\d+)$", parts[0])
    if not mm:
        return None
    mode_id = int(mm.group(1))
    if not (0 <= mode_id <= 7):
        return None
    name = parts[1] or ""
    densapo = _parse_densapo(parts[2])
    if len(parts) >= 4 and (parts[3] or "").strip():
        ui_role = _parse_ui_role_letter(parts[3])
    else:
        # ui_role を省略した場合のデフォルトはアプリ側（MachineMasterModels.swift）の推論に揃える。
        # - mode_0: 通常(0)
        # - mode_2: LT(2)
        # - それ以外: RUSH(1)
        ui_role = 0 if mode_id == 0 else (2 if mode_id == 2 else 1)
    return {"mode_id": mode_id, "name": name, "densapo": densapo, "ui_role": ui_role}


def _parse_mode_ref(token: str) -> Optional[int]:
    t = (token or "").strip()
    if not t:
        return None
    mm = re.match(r"(?i)^mode_(\d+)$", t)
    if mm:
        v = int(mm.group(1))
        return v if 0 <= v <= 7 else None
    v = _parse_int(t)
    return v if v is not None and 0 <= v <= 7 else None


def _normalize_atari_id(token: str) -> str:
    """あたりIDを JSON 用に正規化（bonus_k 形式は数字部を統一）。その他はトリムのみ。"""
    t = (token or "").strip()
    if not t:
        return ""
    mm = re.match(r"(?i)^bonus_(\d+)$", t)
    if mm:
        return f"bonus_{int(mm.group(1))}"
    if t.isdigit():
        return f"bonus_{int(t)}"
    return t


def _normalize_promotion_id(token: str) -> Optional[str]:
    t = (token or "").strip()
    if not t or t == "-":
        return None
    return _normalize_atari_id(t) or None


def _parse_bonus_cell(cell: str) -> Optional[dict]:
    """9項目固定: id / name / base / unit / max / stay / next / branch / promotion"""
    cell = (cell or "").strip()
    if not cell:
        return None
    parts = [p.strip() for p in cell.split("/")]
    if len(parts) != 9:
        return None
    raw_bid = parts[0]
    name = parts[1] or ""
    if not raw_bid or not name:
        return None
    bonus_id = _normalize_atari_id(raw_bid)
    if not bonus_id:
        return None
    base_payout = _parse_int(parts[2])
    unit_raw = _parse_unit_payout_list(parts[3])
    max_concat = _parse_int(parts[4])
    stay = _parse_mode_ref(parts[5])
    nxt = _parse_mode_ref(parts[6])
    if base_payout is None or unit_raw is None or max_concat is None or stay is None or nxt is None:
        return None
    unit_payouts = [x for x in unit_raw if x > 0]
    unit_payout = unit_payouts[0] if unit_payouts else 0
    branch_label = parts[7] or ""
    promotion_id = _normalize_promotion_id(parts[8])

    return {
        "bonus_id": bonus_id,
        "name": name,
        "base_payout": max(0, base_payout),
        "unit_payouts": unit_payouts,
        "unit_payout": unit_payout,
        "max_concat": max(0, max_concat),
        "stay_mode_id": stay,
        "next_mode_id": nxt,
        "branch_label": branch_label,
        "promotion_id": promotion_id,
    }


def _enrich_bonuses_next_ui_role(bonuses: list[dict], modes: list[dict]) -> None:
    by_mid = {m["mode_id"]: m for m in modes}
    for b in bonuses:
        nm = b.get("next_mode_id")
        b["next_ui_role"] = by_mid[nm]["ui_role"] if nm in by_mid else None


def fetch_csv_from_url(url: str) -> str:
    if requests is None:
        raise RuntimeError("requests がインストールされていません: pip install requests")
    return fetch_spreadsheet_csv(url, timeout=REQUEST_TIMEOUT)


def load_and_validate_rows(csv_content: str):
    lines = [line for line in csv_content.splitlines() if line.strip()]
    if len(lines) < 2:
        return [], [], [], []
    reader = csv.reader(io.StringIO(csv_content))
    rows = list(reader)
    headers = rows[0]
    idx = _col_index(headers)

    if "機種ID" not in idx or "機種名" not in idx:
        return [], [], [], [(0, "", "error", "ヘッダーに機種ID・機種名がありません")]

    def v(values: list, key: str, default: str = "") -> str:
        if key not in idx or idx[key] >= len(values):
            return default
        return (values[idx[key]] or "").strip() or default

    seen_ids: set[str] = set()
    valid_rows: list[dict] = []
    preserve_rows: list[dict] = []
    catalog_rows: list[dict] = []
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
        seen_ids.add(machine_id)

        catalog_entry: dict = {
            "machine_id": machine_id,
            "name": v(values, "機種名", machine_id),
            "manufacturer": v(values, "メーカー"),
            "probability": v(values, "確率"),
            "machine_type": v(values, "機種タイプ"),
            "intro_start": v(values, "導入開始日") or v(values, "導入日"),
            "status": status,
        }
        if "更新対象" in idx:
            catalog_entry["update_target"] = v(values, "更新対象")
        catalog_rows.append(catalog_entry)

        # 更新対象が「対象外」の行は、ステータスが未完了でも既存 JSON を保持する。
        if not _is_export_update_target(values, idx):
            preserve_rows.append(
                {
                    "machine_id": machine_id,
                    "name": v(values, "機種名", machine_id),
                    "manufacturer": v(values, "メーカー"),
                    "probability": v(values, "確率"),
                    "machine_type": v(values, "機種タイプ"),
                    "intro_start": v(values, "導入開始日") or v(values, "導入日"),
                    "status": status,
                }
            )
            skip_report.append((row_no, machine_id, "skipped", "not_update_target"))
            continue

        if _should_skip_status(status):
            skip_report.append((row_no, machine_id, "skipped", "status_not_ready"))
            continue

        modes: list[dict] = []
        mode_parse_errors: list[str] = []
        for i in range(8):
            raw_m = v(values, f"モード{i}", "")
            if not raw_m:
                continue
            parsed_m = _parse_mode_cell(raw_m)
            if not parsed_m:
                mode_parse_errors.append(f"モード{i}={raw_m}")
            else:
                modes.append(parsed_m)

        bonuses: list[dict] = []
        bonus_parse_errors: list[str] = []
        for i in range(1, 13):
            cell = v(values, f"当たり{i}")
            if not cell:
                continue
            parsed_b = _parse_bonus_cell(cell)
            if not parsed_b:
                bonus_parse_errors.append(f"当たり{i}={cell}")
            else:
                bonuses.append(parsed_b)

        _enrich_bonuses_next_ui_role(bonuses, modes)

        mode_ids = {m["mode_id"] for m in modes}
        if mode_parse_errors:
            skip_report.append((row_no, machine_id, "error", "parse_error_mode: " + "; ".join(mode_parse_errors[:3])))
            continue
        if bonus_parse_errors:
            skip_report.append((row_no, machine_id, "error", "parse_error_bonus: " + "; ".join(bonus_parse_errors[:3])))
            continue

        if bonuses:
            if 0 not in mode_ids:
                skip_report.append((row_no, machine_id, "error", "missing_mode_0: 当たり行がある場合は mode_0（通常）の定義が必須です"))
                continue
            bids = [b["bonus_id"] for b in bonuses]
            if len(bids) != len(set(bids)):
                skip_report.append((row_no, machine_id, "error", "duplicate_bonus_id"))
                continue
            ref_errors: list[str] = []
            for b in bonuses:
                if b["stay_mode_id"] not in mode_ids:
                    ref_errors.append(f"stay_mode_id={b['stay_mode_id']}")
                if b["next_mode_id"] not in mode_ids:
                    ref_errors.append(f"next_mode_id={b['next_mode_id']}")
                pid = b.get("promotion_id")
                if pid and pid not in bids:
                    ref_errors.append(f"promotion_id={pid} not in bonus_ids")
            if ref_errors:
                skip_report.append((row_no, machine_id, "error", "invalid_ref: " + "; ".join(ref_errors[:8])))
                continue

        by_stay: dict[int, list[dict]] = {}
        for b in bonuses:
            by_stay.setdefault(b["stay_mode_id"], []).append(b)
        bad_dup: list[str] = []
        bad_rowdup: list[str] = []
        for stay, lst in by_stay.items():
            by_name: dict[str, list[dict]] = {}
            for b in lst:
                by_name.setdefault(b["name"], []).append(b)
            for name, items in by_name.items():
                if len(items) > 1 and all((it.get("branch_label") or "").strip() == "" for it in items):
                    bad_dup.append(f"stay={stay},name={name}")
                seen_keys: set[tuple] = set()
                for it in items:
                    key = (it["name"], it["next_mode_id"], (it.get("branch_label") or "").strip())
                    if key in seen_keys:
                        bad_rowdup.append(f"stay={stay},name={name}")
                    seen_keys.add(key)
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

    for r in valid_rows:
        skip_report.append((0, r["machine_id"], "exported", ""))
    return valid_rows, preserve_rows, catalog_rows, skip_report


def build_index(rows: list[dict]) -> list[dict]:
    out: list[dict] = []
    for r in rows:
        item = {
            "machine_id": r["machine_id"],
            "name": r["name"],
            "manufacturer": r.get("manufacturer") or "",
            "probability": r.get("probability") or "",
            "machine_type": r.get("machine_type") or "",
            "intro_start": r.get("intro_start") or "",
            "status": r.get("status") or "",
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

    valid_rows, preserve_rows, catalog_rows, skip_report = load_and_validate_rows(csv_content)

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
    for pr in preserve_rows:
        expected_safe_ids.add(_sanitize_machine_id(pr["machine_id"]))
    n_written = n_unchanged = 0
    for row in valid_rows:
        detail = build_machine_json(row)
        safe_id = _sanitize_machine_id(row["machine_id"])
        expected_safe_ids.add(safe_id)
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
        f"削除={n_removed}, 配信JSON行数={len(valid_rows)}, 対象外保持={len(preserve_rows)} -> {machines_dir}"
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

#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
MachineDetail シート（1当たり1行）の CSV を読み、
index.json と machines/[machine_id].json を生成する。

＝＝＝ 使い方 ＝＝＝

1) ローカルの CSV ファイルから変換する（いちばん簡単）
   python scripts/convert_mode_bonus.py  <CSVのパス>
   例: python scripts/convert_mode_bonus.py master_out/sample_mode_bonus.csv

2) Google スプレッドシートの CSV を URL で指定する
   スプレッドシートを「リンクを知っている全員が閲覧可」にし、
   「ファイル → ダウンロード → カンマ区切りの値 (.csv)」で URL は使わず、
   代わりに「共有」→「リンクをコピー」したスプレッドシートの ID を使い、
   次の形式の URL を環境変数に設定する:
   https://docs.google.com/spreadsheets/d/<スプレッドシートID>/export?format=csv&gid=<シートのgid>
   ※ gid はシートタブを右クリック→「リンクをコピー」の URL の末尾 #gid=1234567890 の数字。

   ターミナルで:
   export MACHINEDETAIL_CSV_URL="https://docs.google.com/..."
   python scripts/convert_mode_bonus.py

3) 引数も URL も指定しない場合
   master_out/sample_mode_bonus.csv があればそれを読み、同じく master_out/ に出力する。
   python scripts/convert_mode_bonus.py

出力先:
  master_out/index.json          … 機種一覧（machine_id, name）
  master_out/machines/<id>.json  … 機種ごとのモード・当たり詳細

出力フォルダを変えたい場合:
  export MODE_BONUS_OUTPUT_DIR="/path/to/out"
  python scripts/convert_mode_bonus.py ...
"""

import csv
import io
import json
import os
import re
import sys
from collections import defaultdict
from pathlib import Path
from typing import Optional, Union

try:
    import requests
except ImportError:
    requests = None

REPO_ROOT = Path(__file__).resolve().parent.parent
OUTPUT_DIR = Path(os.environ.get("MODE_BONUS_OUTPUT_DIR", str(REPO_ROOT / "master_out")))
MACHINES_SUBDIR = "machines"
REQUEST_TIMEOUT = 20

# ヘッダー名の候補（大文字小文字・前後空白無視でマッチ）
HEADER_MAP = {
    "machine_id": ["machine_id", "machine id", "機種ID"],
    "machine_name": ["machine_name", "machine name", "機種名", "name"],
    "mode_id": ["mode_id", "mode id"],
    "mode_name": ["mode_name", "mode name", "モード名"],
    "bonus_name": ["bonus_name", "bonus name", "当たり名", "当たり名称"],
    "payout": ["payout", "出玉", "出玉数"],
    "ratio": ["ratio", "振り分け率", "ratio%"],
    "densapo": ["densapo", "電サポ", "電サポ回数"],
    "next_mode_id": ["next_mode_id", "next mode id", "遷移先mode_id"],
    "notes": ["notes", "メモ", "note"],
}


def _normalize_header(h: str) -> str:
    return (h or "").strip().lower().replace(" ", "_").replace("　", "_")


def _col_index(headers: list[str]) -> dict[str, int]:
    """ヘッダー行から列名→インデックスのマップを返す。"""
    normalized = [_normalize_header(h) for h in headers]
    result = {}
    for key, aliases in HEADER_MAP.items():
        for alias in aliases:
            n = _normalize_header(alias)
            for i, h in enumerate(normalized):
                if h == n or (n and n in h):
                    result[key] = i
                    break
            if key in result:
                break
    return result


def _sanitize_machine_id(machine_id: str) -> str:
    """ファイル名に使えない文字を除去・置換する。"""
    s = (machine_id or "").strip()
    # スラッシュ・バックスラッシュ・コロン等をハイフンに
    s = re.sub(r"[/\\:*?\"<>|]", "-", s)
    # 空白をアンダースコアに
    s = re.sub(r"\s+", "_", s)
    # 先頭・末尾のピリオド・スペースを削除
    s = s.strip("._ ")
    return s or "unknown"


def _parse_number(s: str) -> Optional[Union[float, int]]:
    s = (s or "").strip()
    if not s:
        return None
    try:
        if "." in s:
            return float(s)
        return int(s)
    except ValueError:
        return None


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


def load_csv_rows(csv_content: str) -> list[dict]:
    """CSV 文字列をパースし、ヘッダーに合わせた辞書のリストを返す。"""
    lines = [line for line in csv_content.splitlines() if line.strip()]
    if len(lines) < 2:
        return []
    reader = csv.reader(io.StringIO(csv_content))
    rows = list(reader)
    headers = rows[0]
    idx = _col_index(headers)
    if "machine_id" not in idx or "bonus_name" not in idx:
        # 必須列が無い場合は空リスト（ヘッダーだけのCSV対策）
        return []

    result = []
    for values in rows[1:]:
        if len(values) <= max(idx.values()):
            continue
        mid = (values[idx["machine_id"]] or "").strip()
        bname = (values[idx["bonus_name"]] or "").strip()
        if not mid or not bname:
            continue

        def v(key: str, default=None):
            if key not in idx:
                return default
            i = idx[key]
            if i >= len(values):
                return default
            return (values[i] or "").strip() or default

        mode_id_raw = v("mode_id")
        mode_id = _parse_number(mode_id_raw)
        if mode_id is None:
            mode_id = 0
        elif isinstance(mode_id, float):
            mode_id = int(mode_id)

        payout = _parse_number(v("payout"))
        if payout is None:
            payout = 0
        ratio = _parse_number(v("ratio"))
        if ratio is None:
            ratio = 0.0
        densapo = _parse_number(v("densapo"))
        if densapo is None:
            densapo = 0
        elif isinstance(densapo, float):
            densapo = int(densapo)
        next_mode_id_raw = v("next_mode_id")
        next_mode_id = _parse_number(next_mode_id_raw)
        if next_mode_id is None:
            next_mode_id = 0
        elif isinstance(next_mode_id, float):
            next_mode_id = int(next_mode_id)

        result.append({
            "machine_id": mid,
            "machine_name": (v("machine_name") or mid),
            "mode_id": mode_id,
            "mode_name": v("mode_name") or "",
            "bonus_name": bname,
            "payout": payout,
            "ratio": ratio,
            "densapo": densapo,
            "next_mode_id": next_mode_id,
            "notes": v("notes") or "",
        })
    return result


def build_index(rows: list[dict]) -> list[dict]:
    """machine_id をキーにユニーク化し、index 用の { machine_id, name } のリストを返す。"""
    seen = {}
    for r in rows:
        mid = r["machine_id"]
        if mid not in seen:
            seen[mid] = r["machine_name"]
    return [{"machine_id": mid, "name": name} for mid, name in sorted(seen.items())]


def build_machine_detail(machine_id: str, machine_name: str, rows: list[dict]) -> dict:
    """当該 machine_id の行だけから、modes 階層を組み立てる。"""
    modes_by_id = defaultdict(list)
    for r in rows:
        bonus = {
            "name": r["bonus_name"],
            "payout": r["payout"],
            "ratio": r["ratio"],
            "densapo": r["densapo"],
            "next_mode_id": r["next_mode_id"],
        }
        # ratio/densapo が 0 の場合は省略可能（アプリ側デフォルト）。ここでは常に含めておく。
        modes_by_id[r["mode_id"]].append(bonus)

    mode_list = []
    for mode_id in sorted(modes_by_id.keys()):
        bonuses = modes_by_id[mode_id]
        mode_name = bonuses[0].get("mode_name") if bonuses else ""
        # 同一 mode_id の行から mode_name を取る（1行目で代表）
        for r in rows:
            if r["machine_id"] == machine_id and r["mode_id"] == mode_id:
                mode_name = r["mode_name"] or mode_name
                break
        mode_list.append({
            "mode_id": mode_id,
            "name": mode_name,
            "bonuses": bonuses,
        })

    return {
        "machine_id": machine_id,
        "name": machine_name,
        "modes": mode_list,
    }


def main() -> None:
    if len(sys.argv) > 1 and sys.argv[1] in ("-h", "--help"):
        print(__doc__.strip(), flush=True)
        print("\n【実行例】", flush=True)
        print("  python scripts/convert_mode_bonus.py                              # サンプルCSV使用", flush=True)
        print("  python scripts/convert_mode_bonus.py master_out/sample_mode_bonus.csv  # 指定CSV", flush=True)
        print("  MACHINEDETAIL_CSV_URL='https://...' python scripts/convert_mode_bonus.py  # スプレッドシートURL", flush=True)
        sys.exit(0)

    csv_source = os.environ.get("MACHINEDETAIL_CSV_URL")
    # パスにスペースが含まれるとシェルで分割されるので、引数全体を1つのパスとして結合する
    local_path = " ".join(sys.argv[1:]).strip() if len(sys.argv) > 1 else None

    csv_content = None
    if local_path:
        path = Path(local_path)
        if path.is_file():
            csv_content = path.read_text(encoding="utf-8")
            print(f"[convert_mode_bonus] ローカルCSV: {path}", flush=True)
        else:
            print(f"[convert_mode_bonus] 指定したファイルが見つかりません: {path}", flush=True)
            print(f"[convert_mode_bonus] （パスにスペースを含む場合は引用符で囲んでください: \"{local_path}\"）", flush=True)
    if csv_content is None and csv_source:
        print(f"[convert_mode_bonus] 取得元URL: {csv_source}", flush=True)
        csv_content = fetch_csv_from_url(csv_source)
    if csv_content is None:
        # サンプル用: 同梱サンプルがあれば使う
        sample = REPO_ROOT / "master_out" / "sample_mode_bonus.csv"
        if sample.is_file():
            csv_content = sample.read_text(encoding="utf-8")
            print(f"[convert_mode_bonus] サンプルCSV: {sample}", flush=True)
    if not csv_content:
        print(
            "[convert_mode_bonus] 入力がありません。MACHINEDETAIL_CSV_URL を設定するか、"
            "CSV ファイルパスを引数で指定するか、master_out/sample_mode_bonus.csv を用意してください。",
            flush=True,
        )
        sys.exit(1)

    rows = load_csv_rows(csv_content)
    if not rows:
        print("[convert_mode_bonus] 有効なデータ行が 0 件です。", flush=True)
        sys.exit(1)

    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    machines_dir = OUTPUT_DIR / MACHINES_SUBDIR
    machines_dir.mkdir(parents=True, exist_ok=True)

    index = build_index(rows)
    index_path = OUTPUT_DIR / "index.json"
    with open(index_path, "w", encoding="utf-8") as f:
        json.dump(index, f, ensure_ascii=False, indent=2)
    print(f"[convert_mode_bonus] index.json: {len(index)} 機種 -> {index_path}", flush=True)

    machine_ids = {r["machine_id"] for r in rows}
    for mid in machine_ids:
        machine_rows = [r for r in rows if r["machine_id"] == mid]
        name = machine_rows[0]["machine_name"] if machine_rows else mid
        detail = build_machine_detail(mid, name, machine_rows)
        safe_id = _sanitize_machine_id(mid)
        out_path = machines_dir / f"{safe_id}.json"
        with open(out_path, "w", encoding="utf-8") as f:
            json.dump(detail, f, ensure_ascii=False, indent=2)
    print(f"[convert_mode_bonus] machines/*.json: {len(machine_ids)} ファイル -> {machines_dir}", flush=True)


if __name__ == "__main__":
    main()

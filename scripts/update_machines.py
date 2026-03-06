#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Google スプレッドシートの CSV を取得し、アプリ用 machines.json を生成する。
列: 機種名, メーカー, 大当り確率, LT有無, 等価ボーダー, 導入日
環境変数 SPREADSHEET_CSV_URL で URL を指定。未設定時は DEFAULT_CSV_URL を使用。
"""

import csv
import io
import json
import os
import sys

import requests

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUTPUT_PATH = os.environ.get("MACHINES_JSON_PATH") or os.path.join(REPO_ROOT, "machines.json")

DEFAULT_CSV_URL = os.environ.get(
    "SPREADSHEET_CSV_URL",
    "https://docs.google.com/spreadsheets/d/1fSGx5EmcSOD68itgBRxjGyUGz0Wh5u1Lnbw-dyvchz4/export?format=csv&gid=1407912139",
)
REQUEST_TIMEOUT = 20


def _parse_csv_line(line: str) -> list[str]:
    """1行を CSV としてパース（ダブルクォート内のカンマは無視）。"""
    reader = csv.reader(io.StringIO(line))
    return next(reader)


def _col_index(headers: list[str], *names: str) -> int | None:
    """ヘッダーから列名に一致するインデックスを返す（大文字小文字無視）。"""
    h_lower = [h.strip().lower() for h in headers]
    for n in names:
        n_lower = n.strip().lower()
        for i, h in enumerate(h_lower):
            if h == n_lower:
                return i
    return None


def fetch_and_parse_csv(url: str) -> list[dict]:
    """CSV URL を取得し、アプリ用の辞書リストに変換する。"""
    r = requests.get(url, timeout=REQUEST_TIMEOUT)
    r.raise_for_status()
    # Google の CSV は UTF-8。CI 等で charset が渡らないと文字化けするため明示する
    r.encoding = "utf-8"
    raw = r.text
    if raw.startswith("\uFEFF"):
        raw = raw[1:]
    lines = [line for line in raw.splitlines() if line.strip()]
    if len(lines) < 2:
        # 0件または1行のみ → 診断出力（GoogleがHTMLログイン画面を返しているか確認）
        ct = r.headers.get("Content-Type", "")
        print(f"[update_machines] 診断: status={r.status_code}, Content-Type={ct}, 行数={len(lines)}, body長={len(raw)}", flush=True)
        head = raw.strip()[:600].replace("\r", " ").replace("\n", " ")
        print(f"[update_machines] body先頭: {head!r}", flush=True)
        if "<html" in raw.lower() or "sign in" in raw.lower() or "accounts.google" in raw.lower():
            print("[update_machines] → HTMLが返っています。スプレッドシートを「リンクを知っている全員が閲覧可」にしてください。", flush=True)
        return []
    headers = _parse_csv_line(lines[0])
    result = []
    for line in lines[1:]:
        values = _parse_csv_line(line)
        if not values:
            continue

        def v(*names: str) -> str:
            i = _col_index(headers, *names)
            if i is None or i >= len(values):
                return ""
            return (values[i] or "").strip()

        name = v("機種名", "名前", "name", "機種")
        if not name:
            continue

        probability = v("大当り確率", "確率", "probability") or ""
        border = v("等価ボーダー", "ボーダー", "border") or ""
        manufacturer = v("メーカー", "manufacturer") or ""
        intro_date = v("導入日", "introductionDate", "導入日付") or ""
        lt_yn = v("LT有無", "LT") or ""

        count_per_round = 10
        machine_type_raw = "kakugen"
        support_limit = 0
        time_short = 0
        prize_entries = [{"label": "10R 1500玉", "rounds": 10, "balls": 1500}]
        default_prize = 1500

        row = {
            "name": name[:200],
            "probability": probability,
            "border": border,
            "machineTypeRaw": machine_type_raw,
            "supportLimit": support_limit,
            "timeShortRotations": time_short,
            "countPerRound": count_per_round,
            "manufacturer": manufacturer[:100] if manufacturer else "",
            "defaultPrize": default_prize,
            "prizeEntries": prize_entries,
        }
        if intro_date:
            row["introductionDateRaw"] = intro_date
        result.append(row)
    if not result:
        # 行はあるが1件も採用されなかった（機種名列が空など）
        print(f"[update_machines] 診断: データ行は {len(lines)-1} 行ありますが、機種名列が空のため0件です。ヘッダー: {headers!r}", flush=True)
    return result


def main():
    url = os.environ.get("SPREADSHEET_CSV_URL", DEFAULT_CSV_URL)
    print(f"[update_machines] 取得元: {url}", flush=True)
    print(f"[update_machines] 出力先: {os.path.abspath(OUTPUT_PATH)}", flush=True)
    try:
        data = fetch_and_parse_csv(url)
    except Exception as e:
        print(f"[update_machines] 取得失敗: {e}", flush=True)
        sys.exit(1)
    if not data:
        print("[update_machines] 取得件数が 0 のため更新しません。", flush=True)
        sys.exit(1)
    with open(OUTPUT_PATH, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
    print(f"[update_machines] 書き込み完了: {len(data)} 件 -> {OUTPUT_PATH}", flush=True)


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
週次で実行され、machines.json を更新するスクリプト。
「ここにクロールやAPI取得の処理を書く」想定のひな形です。
"""

import json
import os

# リポジトリのルートで実行される想定
REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUTPUT_PATH = os.path.join(REPO_ROOT, "machines.json")


def fetch_master_data():
    """
    マスターデータを取得する。
    今は「既存の machines.json をそのまま使う」か「サンプル1件」を返すだけ。
    実際にはここで「クロール」「他API」「スプレッドシート」などから取得して
    list of dict を返すようにする。
    """
    # 例: 既存ファイルがあれば読み、なければサンプル
    if os.path.exists(OUTPUT_PATH):
        with open(OUTPUT_PATH, "r", encoding="utf-8") as f:
            return json.load(f)

    return [
        {
            "name": "サンプル機種",
            "probability": "1/319.5",
            "border": "18.0",
            "machineTypeRaw": "kakugen",
            "supportLimit": 0,
            "timeShortRotations": 100,
            "countPerRound": 10,
            "manufacturer": "",
            "prizeEntries": [
                {"label": "10R 1500玉", "rounds": 10, "balls": 1500}
            ],
        }
    ]


def main():
    data = fetch_master_data()
    with open(OUTPUT_PATH, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
    print("machines.json を更新しました。")


if __name__ == "__main__":
    main()

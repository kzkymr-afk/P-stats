import requests
from bs4 import BeautifulSoup
import re
import time
import json

# --- 設定 ---
GAS_WEBAPP_URL = "あなたのGAS_URL"

def get_pachi7_details(url):
    headers = {"User-Agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X)"}
    try:
        res = requests.get(url, headers=headers, timeout=15)
        res.encoding = res.apparent_encoding
        soup = BeautifulSoup(res.text, "html.parser")
    except:
        return None

    # 1. 機種名
    name_element = soup.select_one('h1')
    name = name_element.get_text(strip=True) if name_element else "不明"

    # 2. 基本スペック（確率）の取得
    probability = "-"
    spec_tables = soup.select('.m-machineSpecTable')
    for table in spec_tables:
        rows = table.select('tr')
        for row in rows:
            th = row.select_one('th')
            td = row.select_one('td')
            if th and td and "大当り確率" in th.get_text():
                # 「1/349.9（通常時）」から数値だけ抜く
                match = re.search(r"1/\d+\.?\d*", td.get_text())
                if match:
                    probability = match.group(0)
                    break

    # 3. 大当り振分け（特図1・特図2）の取得
    heso_prizes = []
    denchu_prizes = []

    # 「大当り振分け」という見出しを探す
    sections = soup.select('h3')
    for section in sections:
        if "振分け" in section.get_text() or "内訳" in section.get_text():
            # 見出しの直後にあるテーブルを取得
            table = section.find_next('table', class_='m-machineSpecTable')
            if not table: continue

            # そのセクションが「通常時（特図1）」か「右打ち（特図2）」か判定
            # sectionのテキストや、テーブル内のヘッダーから判断
            section_title = section.get_text()
            
            rows = table.select('tr')
            for row in rows:
                cols = row.select('td')
                if len(cols) >= 2:
                    # [出玉, 状態, 割合] のような並びを想定
                    prize_text = cols[0].get_text(strip=True) # 例: "750個"
                    status_text = cols[1].get_text(strip=True) # 例: "魔戒BURST突入"
                    
                    # ラウンド数を探す (例: 5R)
                    r_match = re.search(r"(\d+)R", row.get_text())
                    r_val = r_match.group(1) if r_match else "?"
                    
                    # 出玉数だけを抽出 (例: 750)
                    p_match = re.search(r"(\d+)個", prize_text)
                    p_val = p_match.group(1) if p_match else "0"

                    label = f"{r_val}R({p_val}個)-{status_text}"

                    if "通常時" in section_title or "ヘソ" in section_title:
                        if label not in heso_prizes: heso_prizes.append(label)
                    else:
                        if label not in denchu_prizes: denchu_prizes.append(label)

    return {
        "name": name,
        "manufacturer": "調査中", # 別途メーカー取得ロジック追加可
        "probability": probability,
        "heso_prizes": ",".join(heso_prizes),
        "denchu_prizes": ",".join(denchu_prizes),
        "border": ""
    }

# テスト実行
if __name__ == "__main__":
    test_url = "https://pachiseven.jp/machines/7340"
    data = get_pachi7_details(test_url)
    print(json.dumps(data, indent=2, ensure_ascii=False))

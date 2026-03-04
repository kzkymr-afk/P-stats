import requests
from bs4 import BeautifulSoup
import json
import os
import time
import re

BASE_URL = "https://p-town.dmm.com"
CALENDAR_URL = f"{BASE_URL}/machines/new_calendar"
REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUTPUT_PATH = os.path.join(REPO_ROOT, "machines.json")

def get_soup(url):
    headers = {"User-Agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"}
    try:
        response = requests.get(url, headers=headers, timeout=15)
        response.raise_for_status()
        return BeautifulSoup(response.content, "html.parser")
    except Exception as e:
        print(f"Error fetching {url}: {e}")
        return None

def fetch_detailed_data(machine_url):
    """詳細ページからボーダーと当たり内訳を抽出"""
    soup = get_soup(machine_url)
    if not soup: return {"border": "18.0", "prizeEntries": []}

    data = {"border": "18.0", "prizeEntries": []}
    
    # ボーダーの抽出 (等価/4.0円)
    border_section = soup.find("th", string=re.compile("等価|4\.0円"))
    if border_section:
        border_val = border_section.find_next_sibling("td")
        if border_val:
            match = re.search(r"(\d+\.\d+|\d+)", border_val.text)
            if match: data["border"] = match.group(1)

    # 当たり内訳の抽出 (簡易版: 10R 1500玉などのパターンを探す)
    # サイト構造により変動するため、テキストから正規表現で抽出
    text = soup.get_text()
    prize_matches = re.findall(r"(\d+)R.*?(\d{3,4})個", text)
    for r, balls in prize_matches:
        entry = {"label": f"{r}R {balls}玉", "rounds": int(r), "balls": int(balls)}
        if entry not in data["prizeEntries"]:
            data["prizeEntries"].append(entry)
            
    return data

def main():
    # 既存データの読み込み
    existing_data = []
    if os.path.exists(OUTPUT_PATH):
        with open(OUTPUT_PATH, "r", encoding="utf-8") as f:
            existing_data = json.load(f)
    
    existing_names = {m["name"] for m in existing_data}
    
    soup = get_soup(CALENDAR_URL)
    if not soup: return

    new_machines = []
    # 機種カードを取得 (パチンコのみ対象にする例)
    cards = soup.select(".p-machine_list_item")
    
    # 初回は300件、2回目以降は差分のみ
    limit = 300 if not existing_data else 999 
    count = 0

    for card in cards:
        if count >= limit: break
        
        name_tag = card.select_one(".p-machine_list_item__name")
        if not name_tag: continue
        name = name_tag.text.strip()
        
        # 差分チェック
        if name in existing_names: continue

        # 基本情報
        maker = card.select_one(".p-machine_list_item__maker").text.strip() if card.select_one(".p-machine_list_item__maker") else ""
        prob_text = card.select_one(".p-machine_list_item__spec").text.strip() if card.select_one(".p-machine_list_item__spec") else ""
        
        # 詳細ページURL
        link = card.select_one("a")["href"]
        detail_url = BASE_URL + link if link.startswith("/") else link
        
        print(f"Fetching details for: {name}")
        details = fetch_detailed_data(detail_url)
        time.sleep(1) # サーバー負荷軽減

        machine = {
            "name": name,
            "probability": prob_text.replace("大当り確率:", "").strip(),
            "border": details["border"],
            "machineTypeRaw": "kakugen",
            "manufacturer": maker,
            "prizeEntries": details["prizeEntries"]
        }
        new_machines.append(machine)
        count += 1

    # 新しいデータを先頭に追加して保存
    combined_data = new_machines + existing_data
    with open(OUTPUT_PATH, "w", encoding="utf-8") as f:
        json.dump(combined_data, f, ensure_ascii=False, indent=2)

if __name__ == "__main__":
    main()

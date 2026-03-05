import requests
from bs4 import BeautifulSoup
import json
import os
import time
import re

# --- 設定 ---
GAS_WEBAPP_URL = "https://script.google.com/macros/s/AKfycbyX48IuYB89g2CA3c-ZON626aaSaP9appshUGubnVSOn57SI1SJ66s-UANNUa4YgRGP/exec"
BASE_URL = "https://p-town.dmm.com"
CALENDAR_URL = f"{BASE_URL}/machines/new_calendar"

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
    """詳細ページからボーダー、RUSH情報、当たり内訳を抽出"""
    soup = get_soup(machine_url)
    if not soup: return {"border": "18.0", "prizeEntries": [], "rushRate": "", "rushCont": ""}

    res = {"border": "18.0", "prizeEntries": [], "rushRate": "", "rushCont": ""}
    text = soup.get_text()

    # ボーダー抽出 (等価)
    border_match = re.search(r"(?:等価|4\.0円).*?(\d+\.\d+|\d+)", text)
    if border_match: res["border"] = border_match.group(1)

    # 突入率・継続率の簡易抽出
    rush_rate = re.search(r"突入率[:：]?\s*(\d+%|約\d+%)", text)
    if rush_rate: res["rushRate"] = rush_rate.group(1)
    rush_cont = re.search(r"継続率[:：]?\s*(\d+%|約\d+%)", text)
    if rush_cont: res["rushCont"] = rush_cont.group(1)

    # 当たり内訳の抽出 (最大8種類)
    # サイトの構造に合わせて正規表現で「○R」と「○玉」のペアを探す
    patterns = re.findall(r"(\d+)R.*?(\d{3,4})個", text)
    unique_patterns = []
    for r, balls in patterns:
        label = f"{r}R"
        # 重複を避けつつ追加
        if not any(p['label'] == label and p['balls'] == int(balls) for p in unique_patterns):
            unique_patterns.append({"label": label, "rounds": int(r), "balls": int(balls)})
    
    res["prizeEntries"] = unique_patterns[:8]
    return res

def main():
    print("--- スクレイピング開始 ---")
    soup = get_soup(CALENDAR_URL)
    if not soup: return

    new_machines = []
    # 機種カード（パチンコ）を取得
    cards = soup.select(".p-machine_list_item")
    print(f"見つかった機種数: {len(cards)}")

    # 最新300件を対象にする
    for card in cards[:300]:
        name_tag = card.select_one(".p-machine_list_item__name")
        if not name_tag: continue
        name = name_tag.text.strip()
        
        maker = card.select_one(".p-machine_list_item__maker").text.strip() if card.select_one(".p-machine_list_item__maker") else ""
        spec = card.select_one(".p-machine_list_item__spec").text.strip() if card.select_one(".p-machine_list_item__spec") else ""
        
        link = card.select_one("a")["href"]
        detail_url = BASE_URL + link if link.startswith("/") else link
        
        print(f"詳細取得中: {name}")
        details = fetch_detailed_data(detail_url)
        time.sleep(1) # サーバー負荷軽減

        new_machines.append({
            "name": name,
            "probability": spec.replace("大当り確率:", "").strip(),
            "border": details["border"],
            "manufacturer": maker,
            "rushRate": details["rushRate"],
            "rushContinuation": details["rushCont"],
            "prizeEntries": details["prizeEntries"]
        })

    # スプレッドシートに送信
    print(f"スプレッドシートへ {len(new_machines)} 件送信します...")
    headers = {"Content-Type": "application/json"}
    response = requests.post(GAS_WEBAPP_URL, data=json.dumps(new_machines), headers=headers)
    print(f"結果: {response.text}")

if __name__ == "__main__":
    main()

print(f"送信データの中身: {new_machines[:1]}") # 最初の1件だけ表示してみる

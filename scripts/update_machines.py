import requests
from bs4 import BeautifulSoup
import re
import time
import json

# --- 設定 ---
GAS_WEBAPP_URL = "あなたのGASウェブアプリURL"
BASE_URL = "https://pachiseven.jp"
LIST_URL = "https://pachiseven.jp/machines/search?m_type=1&order=1" # パチンコ新着順

def get_pachi7_details(detail_url):
    headers = {"User-Agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X)"}
    try:
        res = requests.get(detail_url, headers=headers, timeout=15)
        res.encoding = res.apparent_encoding
        soup = BeautifulSoup(res.text, "html.parser")
    except:
        return None

    # 機種名
    name_el = soup.select_one('h1')
    if not name_el: return None
    name = name_el.get_text(strip=True)

    # メーカー名
    maker_el = soup.select_one('.m-machineMain_maker a')
    maker = maker_el.get_text(strip=True) if maker_el else "不明"

    # 大当り確率
    probability = "-"
    spec_tables = soup.select('.m-machineSpecTable')
    for table in spec_tables:
        for row in table.select('tr'):
            th = row.select_one('th')
            td = row.select_one('td')
            if th and td and "大当り確率" in th.get_text():
                match = re.search(r"1/\d+\.?\d*", td.get_text())
                if match:
                    probability = match.group(0)
                    break

    # 大当り振分け
    heso_prizes = []
    denchu_prizes = []
    sections = soup.select('h3')
    for section in sections:
        section_title = section.get_text()
        if "振分け" in section_title or "内訳" in section_title:
            table = section.find_next('table', class_='m-machineSpecTable')
            if not table: continue
            
            for row in table.select('tr'):
                cols = row.select('td')
                if len(cols) >= 2:
                    prize_text = cols[0].get_text(strip=True)
                    status_text = cols[1].get_text(strip=True)
                    r_match = re.search(r"(\d+)R", row.get_text())
                    r_val = r_match.group(1) if r_match else "?"
                    p_match = re.search(r"(\d+)個", prize_text)
                    p_val = p_match.group(1) if p_match else "0"
                    
                    label = f"{r_val}R({p_val}個)-{status_text}"
                    if any(x in section_title for x in ["通常時", "ヘソ", "特図1"]):
                        if label not in heso_prizes: heso_prizes.append(label)
                    else:
                        if label not in denchu_prizes: denchu_prizes.append(label)

    return {
        "name": name,
        "manufacturer": maker,
        "probability": probability,
        "heso_prizes": ",".join(heso_prizes),
        "denchu_prizes": ",".join(denchu_prizes)
    }

def main():
    headers = {"User-Agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X)"}
    print("🚀 巡回開始...")
    
    # 1. 一覧ページから機種URLを収集 (ここでは最初の1-2ページを対象)
    target_urls = []
    for page in range(1, 3):
        res = requests.get(f"{LIST_URL}&page={page}", headers=headers)
        soup = BeautifulSoup(res.text, "html.parser")
        links = soup.select('.m-machineList_item_ttl a')
        for a in links:
            url = BASE_URL + a['href']
            if "/machines/" in url:
                target_urls.append(url)
    
    # 2. 各機種の詳細を取得して送信
    batch_data = []
    for url in list(set(target_urls)): # 重複排除
        print(f"  [解析中] {url}")
        data = get_pachi7_details(url)
        if data and data['heso_prizes']: # 内訳があるものだけ
            batch_data.append(data)
            time.sleep(1.5) # 負荷軽減
        
        # 5件ごとに送信
        if len(batch_data) >= 5:
            requests.post(GAS_WEBAPP_URL, json=batch_data)
            print(f"  ✅ {len(batch_data)}件をGASへ送信しました")
            batch_data = []

    # 残りを送信
    if batch_data:
        requests.post(GAS_WEBAPP_URL, json=batch_data)
        print(f"  ✅ 残り{len(batch_data)}件を送信完了")

if __name__ == "__main__":
    main()

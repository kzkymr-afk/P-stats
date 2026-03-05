import requests
from bs4 import BeautifulSoup
import re
import time
import json

GAS_WEBAPP_URL = "https://script.google.com/macros/s/AKfycbxF17iitBnp-nLmY0xT0Q7phiYq0boWvbrKbdl67Daf8H3MHRNdq_bYImeZdQIEyIRL/exec"

def get_pachi7_details(machine_id):
    detail_url = f"https://pachiseven.jp/machines/{machine_id}"
    # ヘッダーをさらに一般ブラウザに近づける
    headers = {
        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36",
        "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8",
        "Accept-Language": "ja,en-US;q=0.7,en;q=0.3",
        "Referer": "https://pachiseven.jp/"
    }
    try:
        res = requests.get(detail_url, headers=headers, timeout=15)
        # ログ出力：アクセス状況を確認
        if res.status_code != 200:
            print(f"   ⚠️ ID:{machine_id} -> HTTP {res.status_code}")
            return None
            
        res.encoding = res.apparent_encoding
        soup = BeautifulSoup(res.text, "html.parser")
    except Exception as e:
        print(f"   ❌ ID:{machine_id} -> 接続エラー: {e}")
        return None

    # 機種名の取得
    name = ""
    name_el = soup.find('h1')
    if name_el:
        name = name_el.get_text(strip=True)
    
    if not name or "お探しのページ" in name:
        return None

    # メーカー・確率の取得
    maker = "不明"
    probability = "-"
    maker_el = soup.select_one('.m-machineMain_maker a')
    if maker_el: maker = maker_el.get_text(strip=True)

    # スペックテーブルから確率を抽出
    for table in soup.find_all('table'):
        if "大当り確率" in table.get_text():
            tds = table.find_all('td')
            for td in tds:
                match = re.search(r"1/\d+\.?\d*", td.get_text())
                if match:
                    probability = match.group(0)
                    break

    # 振分けの取得
    heso = []
    denchu = []
    # 全ての見出しとテーブルを走査
    curr_title = ""
    for tag in soup.find_all(['h3', 'h4', 'table']):
        if tag.name in ['h3', 'h4']:
            curr_title = tag.get_text()
        elif tag.name == 'table':
            if not any(x in curr_title for x in ["振分け", "内訳", "割合"]): continue
            for row in tag.find_all('tr'):
                cols = row.find_all('td')
                if len(cols) >= 2:
                    status = cols[1].get_text(strip=True)
                    r_match = re.search(r"(\d+)R", row.get_text())
                    p_match = re.search(r"(\d+)個", cols[0].get_text())
                    label = f"{r_match.group(1) if r_match else '?'}R({p_match.group(1) if p_match else '0'}個)-{status}"
                    
                    if any(x in curr_title for x in ["通常", "ヘソ", "初回"]):
                        heso.append(label)
                    else:
                        denchu.append(label)

    return {
        "name": name,
        "manufacturer": maker,
        "probability": probability,
        "heso_prizes": ",".join(list(dict.fromkeys(heso))),
        "denchu_prizes": ",".join(list(dict.fromkeys(denchu)))
    }

def main():
    print("🚀 修正版・生存確認モードで開始...")
    # 確実に存在する最近のIDから開始
    start_id = 7345 
    range_count = 30
    
    batch_data = []
    for i in range(range_count):
        target_id = start_id - i
        data = get_pachi7_details(target_id)
        
        if data:
            print(f"   ✅ 成功: {data['name']} [{data['probability']}]")
            batch_data.append(data)
            time.sleep(2) # 負荷軽減
        
        if len(batch_data) >= 3:
            print("📡 GAS送信中...")
            requests.post(GAS_WEBAPP_URL, json=batch_data)
            batch_data = []

    if batch_data:
        requests.post(GAS_WEBAPP_URL, json=batch_data)
    print("🏁 完了")

if __name__ == "__main__":
    main()

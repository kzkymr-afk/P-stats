import requests
from bs4 import BeautifulSoup
import re
import time
import json

GAS_WEBAPP_URL = "https://script.google.com/macros/s/AKfycbxF17iitBnp-nLmY0xT0Q7phiYq0boWvbrKbdl67Daf8H3MHRNdq_bYImeZdQIEyIRL/exec"

def get_pachi7_details(machine_id):
    detail_url = f"https://pachiseven.jp/machines/{machine_id}"
    headers = {
        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36",
        "Referer": "https://pachiseven.jp/"
    }
    try:
        res = requests.get(detail_url, headers=headers, timeout=15)
        if res.status_code != 200: return None
        res.encoding = res.apparent_encoding
        soup = BeautifulSoup(res.text, "html.parser")
    except:
        return None

    # --- 1. 機種名の取得 (複数の候補から探す) ---
    name = ""
    name_selectors = ['h1', '.m-machineMain_name', '.m-machineMain_ttl', '.ttl']
    for sel in name_selectors:
        el = soup.select_one(sel)
        if el:
            name = el.get_text(strip=True)
            break
    if not name or "お探しのページ" in name: return None

    # スマスロ・スロット除外 (LやSで始まる記号をチェック)
    if re.match(r'^[LS]\s', name) or "スロット" in res.text:
        if "パチンコ" not in res.text: return None

    # --- 2. メーカー・確率の取得 (全テーブルを走査) ---
    maker = "不明"
    probability = "-"
    
    maker_el = soup.select_one('.m-machineMain_maker a')
    if maker_el: maker = maker_el.get_text(strip=True)

    tables = soup.find_all('table')
    for table in tables:
        rows = table.find_all('tr')
        for row in rows:
            text = row.get_text()
            if "大当り確率" in text:
                td = row.find('td')
                if td:
                    # 1/319.7 のような形式を抽出
                    match = re.search(r"1/\d+\.?\d*", td.get_text())
                    probability = match.group(0) if match else td.get_text(strip=True).split('（')[0]

    # --- 3. 振分けの取得 ---
    heso_prizes = []
    denchu_prizes = []
    
    # 全ての見出し(h3, h4)とテーブルのペアをチェック
    elements = soup.find_all(['h3', 'h4', 'table'])
    current_section_title = ""
    
    for el in elements:
        if el.name in ['h3', 'h4']:
            current_section_title = el.get_text()
        elif el.name == 'table':
            if not any(x in current_section_title for x in ["振分け", "内訳", "割合", "詳細"]): continue
            
            for row in el.select('tr'):
                cols = row.select('td')
                if len(cols) >= 2:
                    prize_text = cols[0].get_text(strip=True) # 出玉
                    status_text = cols[1].get_text(strip=True) # 状態
                    
                    # R数の抽出
                    r_match = re.search(r"(\d+)R", row.get_text())
                    r_val = r_match.group(1) if r_match else "?"
                    # 出玉の抽出
                    p_match = re.search(r"(\d+)個", prize_text)
                    p_val = p_match.group(1) if p_match else "0"
                    
                    label = f"{r_val}R({p_val}個)-{status_text}"
                    
                    # 特図1/2判定
                    if any(x in current_section_title for x in ["通常時", "ヘソ", "特図1", "初回"]):
                        heso_prizes.append(label)
                    else:
                        denchu_prizes.append(label)

    if not heso_prizes and not denchu_prizes:
        return None # データが取れなかった場合は送信しない

    return {
        "name": name,
        "manufacturer": maker,
        "probability": probability,
        "heso_prizes": ",".join(list(dict.fromkeys(heso_prizes))),
        "denchu_prizes": ",".join(list(dict.fromkeys(denchu_prizes)))
    }

def main():
    print("🚀 高精度抽出モードで開始...")
    start_id = 7360 
    range_count = 100 # 少し広めに探索
    
    batch_data = []
    for i in range(range_count):
        target_id = start_id - i
        data = get_pachi7_details(target_id)
        if data:
            print(f"   ✅ 抽出成功: {data['name']} / {data['probability']}")
            batch_data.append(data)
            time.sleep(1.5)
        
        if len(batch_data) >= 3:
            print("📡 GASへ送信中...")
            try:
                res = requests.post(GAS_WEBAPP_URL, json=batch_data, timeout=20)
                print(f"📬 GASレスポンス: {res.text}")
                batch_data = []
            except:
                print("❌ 送信エラー")

    if batch_data:
        requests.post(GAS_WEBAPP_URL, json=batch_data)
    print("🏁 完了")

if __name__ == "__main__":
    main()

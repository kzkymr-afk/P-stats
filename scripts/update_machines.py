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
        # タイムアウトを少し長めに設定
        res = requests.get(detail_url, headers=headers, timeout=20)
        if res.status_code != 200: return None
        
        res.encoding = res.apparent_encoding
        soup = BeautifulSoup(res.text, "html.parser")
    except:
        return None

    # 機種名（これが取れない場合はページが存在しない）
    name_el = soup.select_one('h1')
    if not name_el or "お探しのページ" in name_el.get_text(): return None
    name = name_el.get_text(strip=True)

    # パチスロ除外（念のため）
    if any(x in res.text for x in ["パチスロ", "スマスロ", "スロット"]):
        # ただし「パチンコ」という単語が優先的に含まれる場合は続行
        if "パチンコ" not in res.text: return None

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
                probability = td.get_text(strip=True).split('（')[0]
                break

    heso_prizes = []
    denchu_prizes = []
    
    # 振分けテーブル抽出
    sections = soup.find_all(['h3', 'h4'])
    for section in sections:
        title = section.get_text()
        if not any(x in title for x in ["振分け", "内訳", "割合"]): continue
        
        table = section.find_next('table')
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
                if any(x in title for x in ["通常時", "ヘソ", "特図1", "初回"]):
                    heso_prizes.append(label)
                else:
                    denchu_prizes.append(label)

    return {
        "name": name,
        "manufacturer": maker,
        "probability": probability,
        "heso_prizes": ",".join(list(dict.fromkeys(heso_prizes))),
        "denchu_prizes": ",".join(list(dict.fromkeys(denchu_prizes)))
    }

def main():
    print("🚀 URL直接指定モードで開始...")
    
    # 最新機種のID（2024年3月現在、牙狼11が7340付近）から
    # 過去50件分をスキャンする
    start_id = 7360 
    range_count = 50
    
    batch_data = []
    for i in range(range_count):
        target_id = start_id - i
        print(f"🔍 ID:{target_id} をチェック中...")
        
        data = get_pachi7_details(target_id)
        if data and (data['heso_prizes'] or data['denchu_prizes']):
            print(f"   ✅ 抽出成功: {data['name']}")
            batch_data.append(data)
            time.sleep(2.0) # 非常に重要：ボット検知回避のため
        
        if len(batch_data) >= 3:
            print("📡 GASへ送信中...")
            try:
                res = requests.post(GAS_WEBAPP_URL, json=batch_data, timeout=20)
                print(f"📬 GASレスポンス: {res.text}")
                batch_data = []
            except:
                print("❌ 送信失敗")

    if batch_data:
        requests.post(GAS_WEBAPP_URL, json=batch_data)
    print("🏁 完了")

if __name__ == "__main__":
    main()

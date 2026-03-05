import requests
from bs4 import BeautifulSoup
import re
import time
import json

# ==========================================
# 1. あなたのGASウェブアプリURLをここに貼り付けてください
# ==========================================
GAS_WEBAPP_URL = "https://script.google.com/macros/s/AKfycbxF17iitBnp-nLmY0xT0Q7phiYq0boWvbrKbdl67Daf8H3MHRNdq_bYImeZdQIEyIRL/exec"

BASE_URL = "https://pachiseven.jp"
# パチンコ新着一覧（一番確実なURL）
LIST_URL = "https://pachiseven.jp/machines/search?m_type=1&order=1"

def get_pachi7_details(detail_url):
    headers = {"User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"}
    try:
        res = requests.get(detail_url, headers=headers, timeout=15)
        res.encoding = res.apparent_encoding
        soup = BeautifulSoup(res.text, "html.parser")
    except Exception as e:
        print(f"      エラー: 接続失敗 {e}")
        return None

    name_el = soup.select_one('h1')
    if not name_el: return None
    name = name_el.get_text(strip=True)

    maker_el = soup.select_one('.m-machineMain_maker a') or soup.select_one('td a[href*="/machines/maker/"]')
    maker = maker_el.get_text(strip=True) if maker_el else "不明"

    probability = "-"
    spec_tables = soup.select('.m-machineSpecTable')
    for table in spec_tables:
        for row in table.select('tr'):
            th = row.select_one('th')
            td = row.select_one('td')
            if th and td and "大当り確率" in th.get_text():
                text = td.get_text(strip=True)
                match = re.search(r"1/\d+\.?\d*", text)
                probability = match.group(0) if match else text
                break

    heso_prizes = []
    denchu_prizes = []
    
    # 全ての「大当り振分け」テーブルを取得
    # 見出し(h3)とその後のテーブルのセットを網羅的に探す
    sections = soup.find_all(['h3', 'h4'])
    for section in sections:
        title = section.get_text()
        if not any(x in title for x in ["振分け", "内訳", "割合"]): continue
        
        table = section.find_next('table')
        if not table: continue
        
        for row in table.select('tr'):
            cols = row.select('td')
            if len(cols) >= 2:
                # [出玉, 内容, 割合] のパターンを解析
                prize_text = cols[0].get_text(strip=True)
                status_text = cols[1].get_text(strip=True)
                
                r_match = re.search(r"(\d+)R", row.get_text())
                r_val = r_match.group(1) if r_match else "?"
                p_match = re.search(r"(\d+)個", prize_text)
                p_val = p_match.group(1) if p_match else "0"
                
                label = f"{r_val}R({p_val}個)-{status_text}"
                
                # 特図1と2の振り分け
                if any(x in title for x in ["通常時", "ヘソ", "特図1", "初回"]):
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
    if not GAS_WEBAPP_URL or "あなたの" in GAS_WEBAPP_URL:
        print("❌ GAS URLが未設定です。")
        return

    headers = {"User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"}
    print(f"🚀 巡回開始: {LIST_URL}")
    
    try:
        res = requests.get(LIST_URL, headers=headers)
        soup = BeautifulSoup(res.text, "html.parser")
        # href属性に "/machines/" を含み、末尾が数字のリンクをすべて抽出
        links = soup.find_all('a', href=re.compile(r'/machines/\d+$'))
        
        # 重複を除去しながらURLリストを作成
        target_urls = []
        for l in links:
            url = BASE_URL + l['href'] if l['href'].startswith('/') else l['href']
            if url not in target_urls:
                target_urls.append(url)
        
        print(f"📌 見つかった機種リンク数: {len(target_urls)}")
    except Exception as e:
        print(f"❌ リンク取得エラー: {e}")
        return

    batch_data = []
    for url in target_urls:
        print(f"🔍 解析中: {url}")
        data = get_pachi7_details(url)
        
        if data and (data['heso_prizes'] or data['denchu_prizes']):
            print(f"   ✅ 抽出成功: {data['name']} ({data['probability']})")
            batch_data.append(data)
        
        time.sleep(1.5)

        if len(batch_data) >= 3:
            print(f"📡 GASへ送信中...")
            try:
                post_res = requests.post(GAS_WEBAPP_URL, json=batch_data, timeout=20)
                print(f"📬 GASレスポンス: {post_res.status_code} - {post_res.text}")
                batch_data = []
            except Exception as e:
                print(f"❌ 送信失敗: {e}")

    if batch_data:
        requests.post(GAS_WEBAPP_URL, json=batch_data)

    print("🏁 完了しました。")

if __name__ == "__main__":
    main()

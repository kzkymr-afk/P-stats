import requests
from bs4 import BeautifulSoup
import re
import time
import json
import sys

# ==========================================
# 1. あなたのGASウェブアプリURLをここに貼り付けてください
# ==========================================
GAS_WEBAPP_URL = "あなたのGASウェブアプリURL"

BASE_URL = "https://pachiseven.jp"
LIST_URL = "https://pachiseven.jp/machines/search?m_type=1&order=1"

def get_pachi7_details(detail_url):
    headers = {"User-Agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X)"}
    try:
        res = requests.get(detail_url, headers=headers, timeout=15)
        res.encoding = res.apparent_encoding
        soup = BeautifulSoup(res.text, "html.parser")
    except Exception as e:
        print(f"      エラー: 接続失敗 {e}")
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
                text = td.get_text()
                match = re.search(r"1/\d+\.?\d*", text)
                probability = match.group(0) if match else text.split('(')[0].strip()
                break

    # 大当り振分け
    heso_prizes = []
    denchu_prizes = []
    sections = soup.select('h3')
    
    # h3が見つからない場合、テーブルの中身を直接走査するバックアップ
    if not sections:
        sections = [soup.select_one('.m-machineSpecTable')]

    for section in sections:
        if not section: continue
        section_title = section.get_text()
        
        # 振分けテーブルを特定
        table = section.find_next('table', class_='m-machineSpecTable')
        if not table: continue
        
        rows = table.select('tr')
        for row in rows:
            cols = row.select('td')
            # 列が2つ以上（出玉と状態）ある行が対象
            if len(cols) >= 2:
                prize_text = cols[0].get_text(strip=True)
                status_text = cols[1].get_text(strip=True)
                
                # R数、出玉の抽出
                r_match = re.search(r"(\d+)R", row.get_text())
                r_val = r_match.group(1) if r_match else "?"
                p_match = re.search(r"(\d+)個", prize_text)
                p_val = p_match.group(1) if p_match else "0"
                
                label = f"{r_val}R({p_val}個)-{status_text}"
                
                # ヘソか電チューかの判定（セクションタイトルまたはテーブル見出し）
                if any(x in section_title for x in ["通常時", "ヘソ", "特図1", "初回"]):
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
    if GAS_WEBAPP_URL == "あなたのGASウェブアプリURL":
        print("❌ 失敗: GAS_WEBAPP_URL が設定されていません。")
        return

    headers = {"User-Agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X)"}
    print(f"🚀 巡回開始: {LIST_URL}")
    
    try:
        res = requests.get(LIST_URL, headers=headers)
        soup = BeautifulSoup(res.text, "html.parser")
        links = soup.select('.m-machineList_item_ttl a')
        print(f"📌 見つかった機種リンク数: {len(links)}")
    except Exception as e:
        print(f"❌ リスト取得エラー: {e}")
        return

    batch_data = []
    for a in links:
        url = BASE_URL + a['href']
        print(f"🔍 解析中: {url}")
        
        data = get_pachi7_details(url)
        
        if data:
            if data['heso_prizes'] or data['denchu_prizes']:
                print(f"   ✅ 抽出成功: {data['name']}")
                print(f"      [特図1]: {data['heso_prizes'][:30]}...")
                batch_data.append(data)
            else:
                print(f"   ⚠️  警告: 内訳が空のためスキップします")
        else:
            print(f"   ❌ 解析失敗")
        
        time.sleep(1.2) # サイトへの負荷軽減

        # 3件溜まったら送信（デバッグしやすくするため少なめに設定）
        if len(batch_data) >= 3:
            print(f"📡 GASへ送信中 ({len(batch_data)}件)...")
            try:
                post_res = requests.post(GAS_WEBAPP_URL, json=batch_data, timeout=20)
                print(f"📬 GASレスポンス: {post_res.status_code} - {post_res.text}")
                batch_data = []
            except Exception as e:
                print(f"❌ 送信エラー: {e}")

    # 残りのデータを送信
    if batch_data:
        print(f"📡 残りのデータを送信中...")
        requests.post(GAS_WEBAPP_URL, json=batch_data)

    print("🏁 全工程が終了しました。")

if __name__ == "__main__":
    main()

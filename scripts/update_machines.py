import requests
from bs4 import BeautifulSoup
import json
import time
import re

# --- 設定 ---
GAS_WEBAPP_URL = "https://script.google.com/macros/s/AKfycbyX48IuYB89g2CA3c-ZON626aaSaP9appshUGubnVSOn57SI1SJ66s-UANNUa4YgRGP/exec"
BASE_URL = "https://p-town.dmm.com"
CALENDAR_URL = f"{BASE_URL}/machines/new_calendar"

def get_soup(url):
    # User-Agentを最新のChrome(Windows)に偽装して、ロボット判定を回避
    headers = {
        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
        "Accept-Language": "ja,en-US;q=0.9,en;q=0.8"
    }
    try:
        response = requests.get(url, headers=headers, timeout=15)
        response.raise_for_status()
        return BeautifulSoup(response.content, "html.parser")
    except Exception as e:
        print(f"Error fetching {url}: {e}")
        return None

def main():
    print("--- スクレイピング開始 ---")
    soup = get_soup(CALENDAR_URL)
    if not soup: return

    # 【修正】特定のクラス名に頼らず、機種詳細へのリンク(/machines/数字)を直接探す
    links = soup.find_all("a", href=re.compile(r"/machines/\d+"))
    
    # 重複排除
    seen_urls = set()
    target_links = []
    for l in links:
        url = l["href"]
        name = l.get_text().strip()
        if url not in seen_urls and len(name) > 2:
            target_links.append((name, url))
            seen_urls.add(url)

    print(f"解析対象の機種リンク数: {len(target_links)}")

    new_machines = []
    # まずは動作確認のため最新10件程度でテスト
    for name, url in target_links[:10]:
        detail_url = BASE_URL + url if url.startswith("/") else url
        print(f"詳細取得中: {name}")
        
        # 詳細ページも同様に取得
        d_soup = get_soup(detail_url)
        if not d_soup: continue
        
        d_text = d_soup.get_text()
        
        # 簡易的なデータ抽出
        border = re.search(r"(?:等価|4\.0円).*?(\d+\.\d+|\d+)", d_text)
        prob = re.search(r"大当り確率[:：]\s*(1/\d+\.?\d*)", d_text)

        new_machines.append({
            "name": name,
            "probability": prob.group(1) if prob else "調査中",
            "border": border.group(1) if border else "18.0",
            "manufacturer": "確認中",
            "prizeEntries": [{"label": "10R", "rounds": 10, "balls": 1500}] # テスト用固定
        })
        time.sleep(1) # サーバーへの優しさ

    if not new_machines:
        print("有効な機種データが抽出できませんでした。")
        return

    # スプレッドシートに送信
    print(f"スプレッドシートへ {len(new_machines)} 件送信します...")
    response = requests.post(
        GAS_WEBAPP_URL, 
        data=json.dumps(new_machines), 
        headers={"Content-Type": "application/json"}
    )
    print(f"GASレスポンス: {response.text}")

if __name__ == "__main__":
    main()

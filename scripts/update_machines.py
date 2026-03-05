import requests
from bs4 import BeautifulSoup
import json
import time
import re

# あなたのGASのURL
GAS_WEBAPP_URL = "https://script.google.com/macros/s/AKfycbyX48IuYB89g2CA3c-ZON626aaSaP9appshUGubnVSOn57SI1SJ66s-UANNUa4YgRGP/exec"

def get_soup(url):
    headers = {"User-Agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X)"}
    try:
        response = requests.get(url, headers=headers, timeout=15)
        response.raise_for_status()
        # P-WORLDはShift-JISの場合があるため、適切にデコード
        response.encoding = response.apparent_encoding
        return BeautifulSoup(response.text, "html.parser")
    except Exception as e:
        print(f"Error: {e}")
        return None

def parse_pworld_detail(code):
    url = f"https://www.p-world.co.jp/sp/kisyu.cgi?code={code}"
    soup = get_soup(url)
    if not soup: return None

    # 基本情報の抽出
    name = soup.select_one("h1").text.strip() if soup.select_one("h1") else "不明"
    
    # スペック表（テーブル）の解析
    specs = {}
    for tr in soup.select("table tr"):
        th = tr.select_one("th")
        td = tr.select_one("td")
        if th and td:
            specs[th.text.strip()] = td.text.strip()

    # 当たり内訳の解析 (正規表現で「10R」「1500個」などを探す)
    prize_entries = []
    text_content = soup.get_text()
    
    # 例: 「10R：50%」「1500個」などのパターンを抽出
    patterns = re.findall(r"(\d+)R.*?(\d{3,4})個", text_content)
    for r, balls in patterns[:8]: # 最大8種類
        prize_entries.append({
            "label": f"{r}R",
            "rounds": int(r),
            "balls": int(balls),
            "isRush": "RUSH" in text_content or "時短" in text_content
        })

    return {
        "name": name,
        "probability": specs.get("大当り確率", "調査中"),
        "border": "18.0", # ボーダーはP-WORLDには載っていないことが多いので一旦固定
        "manufacturer": specs.get("メーカー", "不明"),
        "prizeEntries": prize_entries
    }

def main():
    print("--- P-WORLD スクレイピング開始 ---")
    
    # 1. 新着機種一覧からコードを取得
    list_url = "https://www.p-world.co.jp/sp/machine.cgi?type=pachinko"
    soup = get_soup(list_url)
    if not soup: return

    # 機種ページのリンクから code=XXXXX を抜き出す
    links = soup.find_all("a", href=re.compile(r"code=\d+"))
    codes = []
    for l in links:
        match = re.search(r"code=(\d+)", l["href"])
        if match: codes.append(match.group(1))
    
    unique_codes = list(dict.fromkeys(codes))[:10] # まずは10件テスト
    print(f"取得対象コード数: {len(unique_codes)}")

    new_machines = []
    for code in unique_codes:
        print(f"解析中: {code}")
        data = parse_pworld_detail(code)
        if data:
            new_machines.append(data)
        time.sleep(1)

    # 2. スプレッドシートへ送信
    if new_machines:
        print(f"スプレッドシートへ {len(new_machines)} 件送信します...")
        res = requests.post(GAS_WEBAPP_URL, data=json.dumps(new_machines), headers={"Content-Type":"application/json"})
        print(f"結果: {res.text}")

if __name__ == "__main__":
    main()

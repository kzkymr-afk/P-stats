import requests
from bs4 import BeautifulSoup
import json
import time
import re
import sys
import logging
from datetime import datetime

# --- 設定 ---
GAS_WEBAPP_URL = "https://script.google.com/macros/s/AKfycbyowI0rxAsfvNVh4r5b95Rzyw9EohviNDmVpOhpD8V67su1Ey6zyYJClipb0ls-17mP/exec"
RETRY_COUNT = 3
EXCLUDE_WORDS = ["スロット", "パチスロ", "スマスロ", "設定L"]

# ログ設定
logging.basicConfig(
    filename=f'sync_log_{datetime.now().strftime("%Y%m%d")}.txt',
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)

def get_soup(url):
    headers = {"User-Agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X)"}
    for i in range(RETRY_COUNT):
        try:
            response = requests.get(url, headers=headers, timeout=15)
            response.encoding = response.apparent_encoding
            if response.status_code == 200:
                return BeautifulSoup(response.text, "html.parser")
        except Exception as e:
            logging.warning(f"Retry {i+1}: {url} - {e}")
            time.sleep(2)
    return None

def parse_pworld_detail(code):
    url = f"https://www.p-world.co.jp/sp/kisyu.cgi?code={code}"
    soup = get_soup(url)
    if not soup: return None

    name_tag = soup.select_one("h1")
    name = name_tag.get_text(strip=True) if name_tag else "不明"
    full_text = soup.get_text(" ", strip=True)

    def find_val(patterns):
        for p in patterns:
            res = re.search(p, full_text)
            if res: return res.group(1).strip()
        return "-"

    # 抽出ロジック（パチンコ特有のキーワードに対応）
    prob = find_val([r"大当り確率\s*[:：]?\s*(\d+/\d+\.?\d*)", r"確率\s*[:：]?\s*(\d+/\d+\.?\d*)"])
    maker = find_val([r"メーカー\s*[:：]?\s*([^\s\n\r]+)"])
    rush_rate = find_val([
        r"(?:RUSH|ST|時短)(?:突入率|突入)\s*[:：]?\s*(\d+(?:\.\d+)?%)",
        r"初回(?:突入率|突入)\s*[:：]?\s*(\d+(?:\.\d+)?%)",
        r"ヘソ.*?(\d+(?:\.\d+)?%)\s*で突入"
    ])
    rush_cont = find_val([
        r"(?:RUSH|ST|時短)(?:継続率|継続)\s*[:：]?\s*(\d+(?:\.\d+)?%)",
        r"継続率\s*[:：]?\s*(\d+(?:\.\d+)?%)"
    ])

    # 出玉情報（正規表現でR数と個数を抽出）
    raw_prizes = re.findall(r"(\d+)\s*R.*?(\d{3,4})\s*個", full_text)
    prize_list = []
    seen = set()
    for r, b in raw_prizes:
        combo = f"{r}-{b}"
        if combo not in seen:
            prize_list.append(f"{r}R({b}個)")
            seen.add(combo)
    
    prize_list.sort(key=lambda x: int(re.search(r'\d+', x).group()), reverse=True)
    prize_summary = " / ".join(prize_list) if prize_list else "調査中"

    return {
        "name": name,
        "probability": prob,
        "border": "18.0", # 将来的に計算式を導入
        "manufacturer": maker,
        "rushRate": rush_rate,
        "rushContinuation": rush_cont,
        "prizeEntries": prize_summary
    }

def main():
    # 引数判定: 'all' なら全件(300P)、それ以外（または引数なし）なら新台(3P)
    mode = sys.argv[1] if len(sys.argv) > 1 else "new"
    
    if mode == "all":
        target_pages = 300
        sort_param = ""
        print("🔄 【全件モード】全300ページをスキャンします...")
    else:
        target_pages = 3
        sort_param = "&sort=new"
        print("🆕 【新台モード】導入日順で最新3ページを更新します...")

    for page in range(1, target_pages + 1):
        print(f"\n--- Processing Page {page} / {target_pages} ---")
        list_url = f"https://www.p-world.co.jp/sp/machine.cgi?type=pachinko{sort_param}&page={page}"
        soup = get_soup(list_url)
        
        if not soup:
            print(f"⚠️ Page {page} をスキップします。")
            continue

        links = soup.find_all("a", href=re.compile(r"code=\d+"))
        codes = list(dict.fromkeys([re.search(r"code=(\d+)", l["href"]).group(1) for l in links]))
        
        batch_data = []
        for code in codes:
            try:
                data = parse_pworld_detail(code)
                if not data: continue
                
                # スロット除外
                if any(word in data["name"] for word in EXCLUDE_WORDS):
                    continue
                
                print(f"  [OK] {data['name']}")
                batch_data.append(data)
                time.sleep(1.2) # マナー的なウェイト

            except Exception as e:
                logging.error(f"Error at code {code}: {e}")
        
        # 1ページごとにGASへ送信
        if batch_data:
            try:
                resp = requests.post(GAS_WEBAPP_URL, json=batch_data, timeout=30)
                print(f"✅ Sync Page {page}: Status {resp.status_code}")
            except Exception as e:
                print(f"❌ Send Error: {e}")

    print("\n✨ 完了しました。")

if __name__ == "__main__":
    main()

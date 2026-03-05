import requests
from bs4 import BeautifulSoup
import re
import time
import sys

# --- 設定 ---
GAS_WEBAPP_URL = "https://script.google.com/macros/s/AKfycbyowI0rxAsfvNVh4r5b95Rzyw9EohviNDmVpOhpD8V67su1Ey6zyYJClipb0ls-17mP/exec"

def get_soup(url):
    headers = {"User-Agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X)"}
    try:
        response = requests.get(url, headers=headers, timeout=15)
        response.encoding = response.apparent_encoding
        if response.status_code == 200:
            return BeautifulSoup(response.text, "html.parser")
    except:
        return None
    return None

def parse_pworld_details(code):
    url = f"https://www.p-world.co.jp/sp/kisyu.cgi?code={code}"
    soup = get_soup(url)
    if not soup: return None

    name = soup.select_one("h1").get_text(strip=True) if soup.select_one("h1") else "不明"
    maker = "不明"
    full_text = soup.get_text(" ", strip=True)
    
    maker_match = re.search(r"メーカー\s*[:：]?\s*([^\s\n\r]+)", full_text)
    if maker_match: maker = maker_match.group(1)

    heso_prizes = []
    denchu_prizes = []

    # 大当り割合セクションのテーブルを探す
    tables = soup.find_all("table")
    current_mode = "heso" # デフォルトはヘソ

    for table in tables:
        table_text = table.get_text()
        
        # セクションの切り替わりを判定
        if "電チュー" in table_text or "特図2" in table_text or "右打ち中" in table_text:
            current_mode = "denchu"
        elif "ヘソ" in table_text or "特図1" in table_text or "通常時" in table_text:
            current_mode = "heso"

        rows = table.find_all("tr")
        for row in rows:
            cols = [c.get_text(strip=True) for c in row.find_all(["td", "th"])]
            if len(cols) < 2: continue
            
            row_str = " ".join(cols)
            # 正規表現で「R数」「出玉」「割合または詳細」を抽出
            # 例: "10R", "1500個", "50%"
            r_match = re.search(r"(\d+)R", row_str)
            p_match = re.search(r"(\d{3,5})個", row_str)
            
            if r_match and p_match:
                r_val = r_match.group(1)
                p_val = p_match.group(1)
                
                # 詳細（RUSHか通常かなど）を抽出
                detail = "詳細なし"
                if "RUSH" in row_str or "俺CHANCE" in row_str or "突入" in row_str or "天国" in row_str:
                    detail = "RUSH"
                elif "通常" in row_str or "終了" in row_str:
                    detail = "通常"
                elif "%" in row_str:
                    # 割合が入っていればそれを詳細とする
                    pct_match = re.search(r"(\d+%)", row_str)
                    detail = pct_match.group(1) if pct_match else "継続"

                prize_label = f"{r_val}R({p_val}個)-{detail}"
                
                if current_mode == "heso":
                    if prize_label not in heso_prizes: heso_prizes.append(prize_label)
                else:
                    if prize_label not in denchu_prizes: denchu_prizes.append(prize_label)

    return {
        "name": name,
        "manufacturer": maker,
        "heso_prizes": ",".join(heso_prizes),    # アプリ側で .split(",") する用
        "denchu_prizes": ",".join(denchu_prizes) # アプリ側で .split(",") する用
    }

def main():
    mode = sys.argv[1] if len(sys.argv) > 1 else "new"
    target_pages = 2 if mode == "new" else 300
    sort_param = "&sort=new" if mode == "new" else ""
    
    print(f"🚀 データ整備開始: {mode}モード")

    for page in range(1, target_pages + 1):
        list_url = f"https://www.p-world.co.jp/sp/machine.cgi?type=pachinko{sort_param}&page={page}"
        soup = get_soup(list_url)
        if not soup: continue

        links = soup.find_all("a", href=re.compile(r"code=\d+"))
        codes = list(dict.fromkeys([re.search(r"code=(\d+)", l["href"]).group(1) for l in links]))
        
        batch = []
        for code in codes:
            data = parse_pworld_details(code)
            if data:
                print(f"  [取得] {data['name']}")
                batch.append(data)
                time.sleep(1.0)
        
        # GASへ送信
        if batch:
            requests.post(GAS_WEBAPP_URL, json=batch)

if __name__ == "__main__":
    main()

import requests
from bs4 import BeautifulSoup
import re
import time
import sys

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
    # 詳細ページのURL（スペック表が確実にあるページを狙う）
    url = f"https://www.p-world.co.jp/sp/kisyu.cgi?code={code}"
    soup = get_soup(url)
    if not soup: return None

    # --- パチスロ除外チェック ---
    # タイトルや種別テキストに「パチスロ」「L」「スマスロ」が含まれていたらスキップ
    title_area = soup.select_one("h1").get_text(strip=True) if soup.select_one("h1") else ""
    type_text = soup.get_text()
    if "パチスロ" in type_text or "スマスロ" in type_text or "スロット" in type_text:
        return None

    # 基本情報
    name = title_area
    maker = "不明"
    probability = "-"
    
    # 全テキストからメーカーと確率を抽出
    full_text = soup.get_text(" ", strip=True)
    
    maker_match = re.search(r"メーカー\s*[:：]?\s*([^\s\n\r]+)", full_text)
    if maker_match: maker = maker_match.group(1)

    # 通常時の確率を抽出
    prob_match = re.search(r"(?:大当り確率|通常時|低確率)\s*[:：]?\s*(1/\d+\.?\d*)", full_text)
    if prob_match: probability = prob_match.group(1)

    heso_prizes = []
    denchu_prizes = []

    # --- 大当り割合（内訳）の抽出 ---
    # 全てのテーブルを精査
    tables = soup.find_all("table")
    current_mode = "heso"

    for table in tables:
        table_text = table.get_text()
        
        # セクション判定の強化
        if any(x in table_text for x in ["電チュー", "特図2", "右打ち", "RUSH中", "電入"]):
            current_mode = "denchu"
        elif any(x in table_text for x in ["ヘソ", "特図1", "通常時", "左打ち"]):
            current_mode = "heso"

        rows = table.find_all("tr")
        for row in rows:
            row_text = row.get_text(strip=True)
            # R（ラウンド）と個（出玉）の両方がある行をターゲットにする
            if "R" in row_text and "個" in row_text:
                # 数値抽出
                r_match = re.search(r"(\d+)R", row_text)
                p_match = re.search(r"(\d{2,5})個", row_text)
                
                if r_match and p_match:
                    r_val = r_match.group(1)
                    p_val = p_match.group(1)
                    
                    # 状態（RUSH/通常/時短）の判定
                    status = "継続"
                    if any(x in row_text for x in ["RUSH", "突入", "天国", "ST", "時短"]):
                        status = "RUSH"
                    elif "通常" in row_text or "終了" in row_text:
                        status = "通常"
                    
                    label = f"{r_val}R({p_val}個)-{status}"
                    
                    if current_mode == "heso":
                        if label not in heso_prizes: heso_prizes.append(label)
                    else:
                        if label not in denchu_prizes: denchu_prizes.append(label)

    # 必須データ（名前と確率）がない場合は失敗とする
    if not name or probability == "-":
        return None

    return {
        "name": name,
        "manufacturer": maker,
        "probability": probability,
        "heso_prizes": ",".join(heso_prizes),
        "denchu_prizes": ",".join(denchu_prizes)
    }

def main():
    mode = sys.argv[1] if len(sys.argv) > 1 else "new"
    # 新着は2ページ、全取得は500ページ以上を想定
    target_pages = 2 if mode == "new" else 500
    sort_param = "&sort=new" if mode == "new" else ""
    
    print(f"🚀 抽出開始: {mode}モード (パチンコのみ/スペック重視)")

    for page in range(1, target_pages + 1):
        list_url = f"https://www.p-world.co.jp/sp/machine.cgi?type=pachinko{sort_param}&page={page}"
        soup = get_soup(list_url)
        if not soup: break

        # 機種コードの抽出
        links = soup.find_all("a", href=re.compile(r"code=\d+"))
        codes = []
        for l in links:
            # スロットのアイコンや文字が入っているリンクを徹底除外
            parent_text = l.get_text()
            if "L " in parent_text or "S " in parent_text: continue
            
            c = re.search(r"code=(\d+)", l["href"])
            if c: codes.append(c.group(1))
        
        codes = list(dict.fromkeys(codes)) # 重複排除
        
        batch = []
        for code in codes:
            data = parse_pworld_details(code)
            if data:
                print(f"  [成功] {data['name']} / {data['probability']}")
                batch.append(data)
                time.sleep(1.2) # 負荷軽減
        
        if batch:
            res = requests.post(GAS_WEBAPP_URL, json=batch)
            print(f"✅ Page {page}: {len(batch)}件送信完了")

if __name__ == "__main__":
    main()

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
    url = f"https://www.p-world.co.jp/sp/kisyu.cgi?code={code}"
    soup = get_soup(url)
    if not soup: return None

    # スロット除外
    full_text = soup.get_text(" ", strip=True)
    if any(x in full_text for x in ["パチスロ", "スマスロ", "スロット"]): return None

    name = soup.select_one("h1").get_text(strip=True) if soup.select_one("h1") else "不明"
    
    # 確率抽出（より柔軟に）
    prob = "-"
    prob_match = re.search(r"(?:確率|通常時|低確率|1/)\s*[:：]?\s*(1/\d+\.?\d*)", full_text)
    if prob_match: prob = prob_match.group(1)

    # 内訳抽出ロジック
    heso_prizes = []
    denchu_prizes = []
    
    # 大当たり情報のセクションを特定して分割
    # 「ヘソ」「特図1」などのキーワードでテキストを強引に分ける
    parts = re.split(r"(電チュー|特図2|右打ち中|ヘソ|特図1|通常時)", full_text)
    
    current_mode = "heso"
    for part in parts:
        if any(x in part for x in ["電チュー", "特図2", "右打ち中"]):
            current_mode = "denchu"
        elif any(x in part for x in ["ヘソ", "特図1", "通常時"]):
            current_mode = "heso"
        
        # 「10R 1500個」のようなパターンを抽出
        matches = re.findall(r"(\d+)R.*?(\d{2,5})個", part)
        for r, p in matches:
            # 状態（RUSH/通常）の簡易判定
            status = "RUSH" if "RUSH" in part or "突入" in part else "通常"
            label = f"{r}R({p}個)-{status}"
            
            if current_mode == "heso":
                if label not in heso_prizes: heso_prizes.append(label)
            else:
                if label not in denchu_prizes: denchu_prizes.append(label)

    # 必須項目がない機種を無理やり通すとゴミが溜まるため
    if not heso_prizes and not denchu_prizes:
        # テーブル構造から再チャレンジ（前回のロジックの強化版）
        # ... (中略: テーブル検索)
        pass

    return {
        "name": name,
        "manufacturer": re.search(r"メーカー\s*[:：]?\s*([^\s]+)", full_text).group(1) if "メーカー" in full_text else "不明",
        "probability": prob,
        "heso_prizes": ",".join(list(dict.fromkeys(heso_prizes))),
        "denchu_prizes": ",".join(list(dict.fromkeys(denchu_prizes)))
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

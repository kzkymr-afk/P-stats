import requests
from bs4 import BeautifulSoup
import json
import time
import re

# --- あなたのGASのURL ---
GAS_WEBAPP_URL = "https://script.google.com/macros/s/AKfycbyX48IuYB89g2CA3c-ZON626aaSaP9appshUGubnVSOn57SI1SJ66s-UANNUa4YgRGP/exec"

def get_soup(url):
    headers = {
        "User-Agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1",
        "Accept-Language": "ja,en-US;q=0.9,en;q=0.8"
    }
    try:
        response = requests.get(url, headers=headers, timeout=15)
        response.raise_for_status()
        response.encoding = response.apparent_encoding
        return BeautifulSoup(response.text, "html.parser")
    except Exception as e:
        print(f"通信エラー ({url}): {e}")
        return None

def parse_pworld_detail(code):
    url = f"https://www.p-world.co.jp/sp/kisyu.cgi?code={code}"
    soup = get_soup(url)
    if not soup: return None

    name_tag = soup.select_one("h1")
    name = name_tag.get_text(strip=True) if name_tag else "不明"

    # 全テキストをスペース区切りで取得
    full_text = soup.get_text(" ", strip=True)

    def extract_by_regex(pattern, text):
        match = re.search(pattern, text)
        return match.group(1).strip() if match else None

    # --- P-WORLD特有のパターンで抽出 ---
    prob = extract_by_regex(r"大当り確率\s*[:：]?\s*(\d+/\d+\.?\d*)", full_text)
    maker = extract_by_regex(r"メーカー\s*[:：]?\s*([^\s\n\r]+)", full_text)
    rush_rate = extract_by_regex(r"突入率\s*[:：]?\s*(\d+%)", full_text)
    rush_cont = extract_by_regex(r"継続率\s*[:：]?\s*(\d+%)", full_text)

    # 当たり内訳（Rと個数のペア）
    prize_entries = []
    rounds_balls = re.findall(r"(\d+)\s*R.*?(\d{3,4})\s*個", full_text)
    
    unique_check = set()
    for r, b in rounds_balls:
        label = f"{r}R"
        if label not in unique_check:
            prize_entries.append({"label": label, "rounds": int(r), "balls": int(b)})
            unique_check.add(label)

    return {
        "name": name,
        "probability": prob if prob else "1/319.7",
        "border": "18.0",
        "manufacturer": maker if maker else "不明",
        "rushRate": rush_rate if rush_rate else "-",
        "rushContinuation": rush_cont if rush_cont else "-",
        "prizeEntries": prize_entries[:8],
        "raw_text": full_text # 判定用にテキストを保持
    }

def main():
    print("--- P-WORLD パチンコ限定スクレイピング開始 ---")
    
    list_url = "https://www.p-world.co.jp/sp/machine.cgi?type=pachinko"
    soup = get_soup(list_url)
    if not soup: return

    links = soup.find_all("a", href=re.compile(r"code=\d+"))
    codes = []
    for l in links:
        match = re.search(r"code=(\d+)", l["href"])
        if match: codes.append(match.group(1))
    
    unique_codes = list(dict.fromkeys(codes))[:20] # 少し多めに取得してフィルタリング
    print(f"取得対象候補: {len(unique_codes)}件")

    new_machines = []
    for code in unique_codes:
        data = parse_pworld_detail(code)
        if not data: continue

        # --- 強力なスロット除外ロジック ---
        name = data["name"]
        text = data["raw_text"]
        prob = data["probability"]

        # 1. 除外キーワード（これらが入っていたらスロット）
        ng_words = ["機械割", "スマスロ", "パチスロ", "スロット", "AT中", "ART中", "設定1", "設定L", "設定S"]
        if any(word in text or word in name for word in ng_words):
            print(f"スキップ（スロット判定）: {name}")
            continue

        # 2. 必須キーワード（パチンコなら通常これがある）
        # 「1/」という確率表記がないものは除外（スロットのAタイプ等との誤認回避）
        if "1/" not in prob:
            print(f"スキップ（確率表記なし）: {name}")
            continue

        # 判定用データは不要なので削除して送信リストへ
        del data["raw_text"]
        print(f"採用: {name} ({prob})")
        new_machines.append(data)
        time.sleep(1.5)

    # 2. GAS経由で送信
    if new_machines:
        print(f"スプレッドシートへ {len(new_machines)} 件送信します...")
        headers = {"Content-Type": "application/json"}
        try:
            res = requests.post(GAS_WEBAPP_URL, data=json.dumps(new_machines), headers=headers)
            print(f"GAS応答: {res.text}")
        except Exception as e:
            print(f"送信エラー: {e}")

if __name__ == "__main__":
    main()

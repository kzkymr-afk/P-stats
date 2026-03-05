# scripts/update_machines.py 最終版
import requests
from bs4 import BeautifulSoup
import json
import time
import re

GAS_WEBAPP_URL = "https://script.google.com/macros/s/AKfycbw2QCT2hn2gVoEiA4eT0SvQxpk4F-hHbI2wAFOMJgiAe3Ghhi4Fw7vAsBP5zafMK5ZF/exec"

def get_soup(url):
    headers = {"User-Agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X)"}
    try:
        response = requests.get(url, headers=headers, timeout=15)
        response.encoding = response.apparent_encoding
        return BeautifulSoup(response.text, "html.parser")
    except: return None

def parse_pworld_detail(code):
    url = f"https://www.p-world.co.jp/sp/kisyu.cgi?code={code}"
    soup = get_soup(url)
    if not soup: return None
    name = soup.select_one("h1").get_text(strip=True) if soup.select_one("h1") else "不明"
    full_text = soup.get_text(" ", strip=True)

    def find_val(patterns):
        for p in patterns:
            res = re.search(p, full_text)
            if res: return res.group(1).strip()
        return "-"

    prob = find_val([r"大当り確率\s*[:：]?\s*(\d+/\d+\.?\d*)", r"確率\s*[:：]?\s*(\d+/\d+\.?\d*)"])
    maker = find_val([r"メーカー\s*[:：]?\s*([^\s\n\r]+)"])
    rush_rate = find_val([r"(?:RUSH|ST|時短)突入率\s*[:：]?\s*(\d+(?:\.\d+)?%)", r"突入率\s*[:：]?\s*(\d+(?:\.\d+)?%)"])
    rush_cont = find_val([r"(?:RUSH|ST|時短)継続率\s*[:：]?\s*(\d+(?:\.\d+)?%)", r"継続率\s*[:：]?\s*(\d+(?:\.\d+)?%)"])

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
        "name": name, "probability": prob, "border": "18.0",
        "manufacturer": maker, "rushRate": rush_rate,
        "rushContinuation": rush_cont, "prizeEntries": prize_summary
    }

def main():
    # ページ範囲は必要に応じて調整 (1, 301) で全件
    for page in range(1, 2): 
        list_url = f"https://www.p-world.co.jp/sp/machine.cgi?type=pachinko&page={page}"
        soup = get_soup(list_url)
        if not soup: break
        links = soup.find_all("a", href=re.compile(r"code=\d+"))
        codes = list(dict.fromkeys([re.search(r"code=(\d+)", l["href"]).group(1) for l in links]))
        batch_data = []
        for code in codes:
            data = parse_pworld_detail(code)
            if not data or any(x in data["name"] for x in ["スロット", "パチスロ"]): continue
            batch_data.append(data)
            time.sleep(1)
        if batch_data:
            requests.post(GAS_WEBAPP_URL, data=json.dumps(batch_data), headers={"Content-Type": "application/json"})

if __name__ == "__main__":
    main()

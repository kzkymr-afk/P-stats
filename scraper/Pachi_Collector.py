import time
import re
from datetime import datetime
import requests
from playwright.sync_api import sync_playwright

GAS_URL = "https://script.google.com/macros/s/AKfycbzO6zlH-FQ7ERic0BbaFr0ITBhygY1Kul6Uoa8tVsVovVXJL1pWgdPgDI2hxkaDgA0y/exec"
BASE_URL = "https://p-town.dmm.com/machines/new_calendar"

# --- 追加：完了済みIDを一括取得 ---
def get_done_ids():
    try:
        print("📊 GASから完了済みIDリストをダウンロード中...")
        res = requests.post(GAS_URL, data={'mode': 'get_done_list'}, timeout=20)
        if not res.text:
            return set()
        # カンマ区切りを集合(set)にする。リストより検索が圧倒的に速い。
        return set(res.text.split(','))
    except Exception as e:
        print(f"⚠️ リスト取得失敗: {e}")
        return set()

def run_archive_scan():
    # 最初に1回だけ取得
    done_set = get_done_ids()
    print(f"✅ {len(done_set)}件のデータをスキップ対象としてロードしました。")

    # 当月の翌月を最新、今から4年前の同じ月まで遡る
    now = datetime.now()
    current_year, current_month = now.year, now.month
    if current_month == 12:
        end_year, end_month = current_year + 1, 1
    else:
        end_year, end_month = current_year, current_month + 1
    start_year, start_month = current_year - 4, current_month

    scan_list = []
    for y in range(start_year, end_year + 1):
        if y == start_year and y == end_year:
            months = range(start_month, end_month + 1)
        elif y == start_year:
            months = range(start_month, 13)
        elif y == end_year:
            months = range(1, end_month + 1)
        else:
            months = range(1, 13)
        scan_list.append((y, months))
    print(f"📅 取得期間: {start_year}年{start_month}月 ～ {end_year}年{end_month}月")

    with sync_playwright() as p:
        browser = p.chromium.launch(headless=False)
        page = browser.new_page()

        for year, months in scan_list:
            for month in months:
                target_url = f"{BASE_URL}?year={year}&month={month}&type=pachinko"
                print(f"📅 --- {year}年{month}月 ---")
                
                try:
                    page.goto(target_url, wait_until="domcontentloaded", timeout=60000)
                    time.sleep(2)

                    links = page.evaluate('''() => {
                        return [...new Set(Array.from(document.querySelectorAll('li'))
                            .filter(li => li.innerText.includes('パチンコ'))
                            .map(li => li.querySelector('a')?.href)
                            .filter(href => href && href.includes('/machines/')))];
                    }''')

                    for url in links:
                        m_id = url.split('/')[-1]

                        # --- 【超高速判定】通信なしでメモリ内検索 ---
                        if m_id in done_set:
                            # print(f"  ⏩ {m_id}: skip") # ログがうるさければコメントアウト
                            continue

                        # 未登録なら詳細ページへ
                        try:
                            print(f"  🚚 {m_id}: 解析中...")
                            page.goto(url, wait_until="domcontentloaded", timeout=60000)

                            # ページ全体のHTMLを取得（表面上のテキストではなくソース）
                            raw_html = page.content()
                            clean_html = re.sub(r'<script[\s\S]*?<\/script>', '', raw_html)
                            clean_html = re.sub(r'<style[\s\S]*?<\/style>', '', clean_html)
                            clean_html = re.sub(r'\s(?:class|id|style|data-[\w-]+|target|rel)="[^"]*"', '', clean_html)
                            clean_html = re.sub(r'\s+', ' ', clean_html).strip()
                            if "ゲームフロー" in clean_html:
                                clean_html = clean_html.split("ゲームフロー")[0]

                            # GASへ送信（HTMLを送る）
                            res = requests.post(GAS_URL, data={'text': clean_html, 'id': m_id})
                            print(f"  └ {m_id}: {res.text}")
                            
                            # 解析に成功したら、今回のセッション中も二度と行かないようにセットに追加
                            if "成功" in res.text or "完了" in res.text:
                                done_set.add(m_id)
                            
                        except Exception as e:
                            print(f"  ❌ 個別失敗: {m_id} {e}")
                            
                except Exception as e:
                    print(f"  ❌ 月間エラー: {e}")

        browser.close()
        print("✨ 完了！")

if __name__ == "__main__":
    run_archive_scan()

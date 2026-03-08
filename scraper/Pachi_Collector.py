import time
import re
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

    scan_list = [
        (2024, range(1, 13)), (2025, range(1, 13)), (2026, range(1, 4))
    ]

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
                            
                            raw_html = page.evaluate("() => document.body.innerHTML")
                            # (省略：既存の正規表現クレンジング)
                            clean_html = re.sub(r'<script[\s\S]*?<\/script>', '', raw_html)
                            clean_html = re.sub(r'<style[\s\S]*?<\/style>', '', clean_html)
                            clean_html = re.sub(r'\s(?:class|id|style|data-[\w-]+|target|rel)="[^"]*"', '', clean_html)
                            clean_html = re.sub(r'\s+', ' ', clean_html).strip()

                            # GASへ送信
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

def main():
    print("--- スクレイピング開始 ---")
    soup = get_soup(CALENDAR_URL)
    if not soup: 
        print("サイトの取得に失敗しました。")
        return

    new_machines = []
    
    # 【修正ポイント】より広い範囲で「機種詳細へのリンク」を探すように変更
    # 機種名が入っているリンク（/machines/の後が数字のパターン）を直接狙います
    machine_links = soup.find_all("a", href=re.compile(r"/machines/\d+"))
    
    # 重複を除去しながらリスト化
    seen_urls = set()
    unique_links = []
    for l in machine_links:
        url = l["href"]
        if url not in seen_urls:
            unique_links.append(l)
            seen_urls.add(url)

    print(f"見つかった機種リンク数: {len(unique_links)}")

    # 最新の台から順に処理（まずはテストのため件数を絞ってもOK）
    for link_tag in unique_links[:50]: # 300件は多いため、まずは50件でテスト推奨
        # リンクの中にあるテキストを機種名として取得
        name = link_tag.get_text().strip()
        if not name or len(name) < 2: continue # 短すぎる文字列は除外
        
        detail_url = BASE_URL + link_tag["href"] if link_tag["href"].startswith("/") else link_tag["href"]
        
        # メーカー名などは詳細ページから取るように変更（一覧から取れない場合があるため）
        print(f"詳細取得中: {name}")
        details = fetch_detailed_data(detail_url)
        time.sleep(1) 

        new_machines.append({
            "name": name,
            "probability": details.get("probability", "調査中"),
            "border": details["border"],
            "manufacturer": details.get("manufacturer", "不明"),
            "rushRate": details["rushRate"],
            "rushContinuation": details["rushCont"],
            "prizeEntries": details["prizeEntries"]
        })

    if not new_machines:
        print("最終的に取得できた機種が0件でした。")
        return

    # スプレッドシートに送信
    print(f"スプレッドシートへ {len(new_machines)} 件送信します...")
    headers = {"Content-Type": "application/json"}
    response = requests.post(GAS_WEBAPP_URL, data=json.dumps(new_machines), headers=headers)
    print(f"結果: {response.text}")

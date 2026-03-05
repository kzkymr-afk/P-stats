import requests
import json

GAS_WEBAPP_URL = "https://script.google.com/macros/s/AKfycbyX48IuYB89g2CA3c-ZON626aaSaP9appshUGubnVSOn57SI1SJ66s-UANNUa4YgRGP/exec"

def main():
    # DMMの検索APIエンドポイント（新台順）
    # ここはHTMLではなく、直接「データ（JSON）」を返してくれる場所です
    api_url = "https://p-town.dmm.com/api/v1/machines?sort=p_release_date_desc&per_page=50"
    
    headers = {
        "User-Agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1",
        "Referer": "https://p-town.dmm.com/machines/search"
    }

    try:
        print("APIから直接データを取得中...")
        response = requests.get(api_url, headers=headers)
        response.raise_for_status()
        data = response.json() # HTML解析不要！いきなりJSONが手に入る
        
        machines = data.get("data", [])
        new_machines = []
        
        for m in machines:
            new_machines.append({
                "name": m.get("name"),
                "probability": m.get("spec_name", "調査中"), # 「1/319」などが入る
                "border": "18.0", # ボーダーは詳細にしかないので一旦固定
                "manufacturer": m.get("maker_name", "不明"),
                "prizeEntries": []
            })
            
        if new_machines:
            print(f"{len(new_machines)} 件のデータを送信します。")
            res = requests.post(GAS_WEBAPP_URL, data=json.dumps(new_machines), headers={"Content-Type":"application/json"})
            print(f"結果: {res.text}")
            
    except Exception as e:
        print(f"エラー: {e}")

if __name__ == "__main__":
    main()

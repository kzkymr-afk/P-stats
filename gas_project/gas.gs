/**
 * 1. スプレッドシートメニュー
 */
function onOpen() {
  SpreadsheetApp.getUi().createMenu('★解析実行')
    .addItem('ここに貼り付け', 'showInputDialog').addToUi();
}

/**
 * 2. 入力ウィンドウ表示（手動用）
 */
function showInputDialog() {
  const html = `
    <html>
      <body style="font-family: sans-serif; padding: 15px; background-color: #f8f9fa;">
        <p style="font-size: 14px; font-weight: bold; color: #333;">URLとHTMLソースを貼り付け：</p>
        <input type="text" id="url" placeholder="機種ページのURLを貼り付け" style="width: 100%; padding: 8px; margin-bottom: 10px; border: 1px solid #ccc; border-radius: 4px;">
        <textarea id="txt" placeholder="Ctrl+Uで表示したソースを貼り付けてください"
          style="width: 100%; height: 230px; padding: 10px; border: 1px solid #ccc; border-radius: 4px; box-sizing: border-box; resize: none;"></textarea>
        <div style="margin-top: 15px; text-align: right;">
          <button onclick="run()" id="btn" style="padding: 10px 25px; background: #1a73e8; color: white; border: none; border-radius: 4px; cursor: pointer; font-weight: bold;">2行目に挿入</button>
        </div>
        <script>
          function run() {
            const urlValue = document.getElementById('url').value;
            const txtValue = document.getElementById('txt').value;
            if(!txtValue.trim()) return;
            const btn = document.getElementById('btn');
            btn.disabled = true;
            btn.innerText = '解析中...';
            google.script.run
              .withSuccessHandler(() => google.script.host.close())
              .withFailureHandler((err) => { alert('エラー: ' + err.message); btn.disabled = false; btn.innerText = '2行目に挿入'; })
              .processPachinkoText(txtValue, urlValue);
          }
        </script>
      </body>
    </html>`;
  SpreadsheetApp.getUi().showModalDialog(HtmlService.createHtmlOutput(html).setWidth(550).setHeight(420), '機種情報入力');
}

/**
 * 3. 外部（Python等）からの受付窓口
 */
function doPost(e) {
  try {
    const p = e.parameter;
    const mode = p.mode;
    const id = p.id || p.url || "";

    if (mode === "get_done_list") {
      const ss = SpreadsheetApp.openById("1fSGx5EmcSOD68itgBRxjGyUGz0Wh5u1Lnbw-dyvchz4");
      const sheet = ss.getSheets()[0];
      const lastRow = sheet.getLastRow();
      if (lastRow <= 1) return createResponse("");
      const data = sheet.getRange(2, 11, lastRow - 1, 2).getValues();
      const doneIds = data.filter(row => row[1] === "完了").map(row => row[0]);
      return createResponse(doneIds.join(","));
    }

    if (p.text) {
      const result = processPachinkoText(p.text, id);
      return createResponse(result);
    }
    return createResponse("Error: No data");
  } catch (err) {
    return createResponse("System Error: " + err.toString());
  }
}

function createResponse(msg) {
  return ContentService.createTextOutput(msg).setMimeType(ContentService.MimeType.TEXT);
}

/**
 * 4. 解析メイン処理
 */
function processPachinkoText(rawInput, manualUrl = "") {
  const SS_ID = "1fSGx5EmcSOD68itgBRxjGyUGz0Wh5u1Lnbw-dyvchz4";
  try {
    const ss = SpreadsheetApp.openById(SS_ID);
    const sheet = ss.getSheets()[0];
    const cleanInput = rawInput.split("ユーザー口コミ・評価詳細")[0];

    // --- ID特定 ---
    let mCode = "-";
    const mMatch = String(manualUrl).match(/\d+/);
    mCode = mMatch ? mMatch[0] : (cleanInput.match(/\/machines\/(\d+)/)?.[1] || "-");

    // --- 導入日 (A) ---
    const introMatch = cleanInput.match(/導入開始日[\s\S]*?(\d{4})年(\d{1,2})月(\d{1,2})日/);
    let introDate = introMatch ? introMatch[1] + "/" + ("0" + introMatch[2]).slice(-2) + "/" + ("0" + introMatch[3]).slice(-2) : "-";

    // --- 機種名 (B) ---
    let nameRaw = cleanInput.match(/<h1[^>]*>([\s\S]*?)<\/h1>/i)?.[1] || "不明";
    let name = nameRaw.replace(/<br\s*\/?>/gi, "\n").replace(/<[^>]*>/g, "").trim();
    name = name.split("\n")[0].split(/[\[(（｜|]/)[0].replace(/[ｅＰ]/g, s => String.fromCharCode(s.charCodeAt(0) - 0xFEE0)).trim();

    // --- メーカー (C) ---
    const makerMatch = cleanInput.match(/メーカー名[\s\S]*?<td[^>]*>([\s\S]*?)<\/td>/i);
    let maker = makerMatch ? makerMatch[1].replace(/<[^>]*>/g, "").split('\n')[0].split('（')[0].replace(/の掲載機種一覧.*/, "").trim() : "不明";

    // --- 大当り確率 (D) ---
    const probMatch = cleanInput.match(/大当り確率[\s\S]*?(?:約\s*)?([0-9１-９]{1,}\s?\/\s?[0-9１-９\.．]{1,})/);
    let probability = probMatch ? probMatch[1].replace(/[０-９．]/g, s => String.fromCharCode(s.charCodeAt(0) - 0xFEE0)).replace(/\s/g, "") : "-";

    // --- 等価ボーダー (E) ---
    const borderMatch = cleanInput.match(/4\.0円（25個）[\s\S]*?…(\d+\.\d+)回転/);
    const haneBorderMatch = cleanInput.match(/4\.0円（25個）[\s\S]*?…(\d+\.\d+)回/);
    let border = borderMatch ? borderMatch[1] : (haneBorderMatch ? haneBorderMatch[1] : "-");

    // --- 大当り出玉 (F) ---
    const payoutBlock = cleanInput.match(/大当り出玉[\s\S]+?(?=電サポ回転数|導入開始日|<th|$)/);
    let payout = payoutBlock ? payoutBlock[0].replace(/<[^>]*>/g, "").replace(/\+α/g, "").replace(/[^\d]+/g, "/").replace(/\/+/g, "/").replace(/^\/|\/$/g, "") : "-";

    // --- 電サポ回転数 (G) ---
    let densapoSet = new Set();
    const densapoDirect = cleanInput.match(/電サポ回転数[\s\S]*?<td[^>]*>([\s\S]{0,500}?(?=導入開始日|<th))/);
    if (densapoDirect) {
      const dNums = densapoDirect[1].match(/\d+/g);
      if (dNums) dNums.forEach(n => { if (parseInt(n) >= 10 && parseInt(n) <= 10000 && n != "319") densapoSet.add(n); });
    }
    let densapo = densapoSet.size > 0 ? Array.from(densapoSet).sort((a,b)=>b-a).join("/") : "-";

    // --- 解析範囲をさらに絞り込む（誤検知防止） ---
    // スペック表の周辺だけを見るようにし、ページ下部の「特集（LT特集など）」を完全に無視する
    const specArea = cleanInput.split("ゲームフロー")[0].split("お知らせ一覧")[0];

    // --- 特徴タグ (J) & タイプ (H) & スペック (I) ---
    let tagSet = new Set();
    let isHybrid = false;

    // 1. アイコン（alt属性）から正確に抽出
    const iconMatches = specArea.match(/alt="([^"]+)"/g) || [];
    
    iconMatches.forEach(m => {
      const altText = m.replace('alt=', '').replace(/"/g, '').trim();
      
      if (altText.includes("ST機")) {
        tagSet.add("ST");
      }
      // 「LT」という独立した単語、または「ラッキートリガー」という単語が含まれる場合のみ
      else if (altText.match(/\bLT\b|ラッキートリガー/i)) {
        tagSet.add("LT");
      }
      
      if (altText.includes("遊タイム")) tagSet.add("遊タイム");
      if (altText.includes("1種2種")) isHybrid = true;
      if (altText.includes("設定")) tagSet.add("設定付");
      if (altText.includes("コンプリート")) tagSet.add("コンプリート");
    });

    // 2. 補助判定（機種名や特定のキーワード）
    if (name.toLowerCase().startsWith("e")) tagSet.add("スマパチ");

    // テーブル内の文字から補足判定
    const specTable = specArea.match(/<table[^>]*>([\s\S]*?)<\/table>/i)?.[0] || "";
    if (specTable.match(/c時短|突然時短/i)) tagSet.add("c時短");
    if (specTable.match(/転落抽選|転落型/i)) tagSet.add("転落");

    // 各列の値を確定
    let tagString = tagSet.size > 0 ? Array.from(tagSet).join("/") : "なし";
    let machineType = isHybrid ? "1種2種混合機" : (probability === "-" && cleanInput.includes("羽根モノ") ? "羽根モノ" : "デジパチ");
    let denom = parseFloat(probability.split("/")[1]) || 0;
    let specType = (machineType === "羽根モノ") ? "羽根モノ" : (denom >= 300 ? "ミドル" : denom >= 150 ? "ライトミドル" : denom >= 50 ? "甘デジ" : "その他");

    // L. ステータス判定
    let crawlStatus = (machineType !== "羽根モノ" && (border === "-" || isNaN(parseFloat(border)))) ? "再取得対象" : "完了";

    // A-L列 書き込み
    const newRow = [introDate, name, maker, probability, border, payout, densapo, machineType, specType, tagString, mCode, crawlStatus];
    sheet.insertRowBefore(2);
    sheet.getRange(2, 1, 1, 12).setValues([newRow]);

    return "成功: " + name;
  } catch (e) {
    return "解析エラー: " + e.toString();
  }
}

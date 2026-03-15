/** マスターシートのスプレッドシートID */
var SS_ID = "1fSGx5EmcSOD68itgBRxjGyUGz0Wh5u1Lnbw-dyvchz4";

/**
 * 1行目のヘッダー。機種IDの後にヘソ当たり1〜5、最後に更新ステータス。
 */
var HEADER_ROW = [
  "導入日", "機種名", "メーカー", "大当り確率", "機種タイプ", "スペック", "特徴タグ", "機種ID",
  "ヘソ当たり1", "ヘソ当たり2", "ヘソ当たり3", "ヘソ当たり4", "ヘソ当たり5",
  "更新ステータス"
];

function onOpen() {
  SpreadsheetApp.getUi().createMenu('★解析実行')
    .addItem('ここに貼り付け', 'showInputDialog')
    .addToUi();
}

function showInputDialog() {
  var html = '<html><body style="font-family: sans-serif; padding: 15px; background-color: #f8f9fa;">' +
    '<p style="font-size: 14px; font-weight: bold; color: #333;">HTMLソースを貼り付け：</p>' +
    '<textarea id="txt" placeholder="機種ページで Ctrl+U で表示したソースをそのまま貼り付けてください" style="width: 100%; height: 320px; padding: 10px; border: 1px solid #ccc; border-radius: 4px; box-sizing: border-box; resize: none;"></textarea>' +
    '<div style="margin-top: 15px; text-align: right;">' +
    '<button onclick="run()" id="btn" style="padding: 10px 25px; background: #1a73e8; color: white; border: none; border-radius: 4px; cursor: pointer; font-weight: bold;">2行目に挿入</button></div>' +
    '<script>function run(){var txtValue=document.getElementById("txt").value;if(!txtValue.trim())return;var btn=document.getElementById("btn");btn.disabled=true;btn.innerText="解析中...";google.script.run.withSuccessHandler(function(){google.script.host.close();}).withFailureHandler(function(err){alert("エラー: "+err.message);btn.disabled=false;btn.innerText="2行目に挿入";}).processPachinkoText(txtValue,"");}</script></body></html>';
  SpreadsheetApp.getUi().showModalDialog(HtmlService.createHtmlOutput(html).setWidth(550).setHeight(450), '機種情報入力');
}

function doPost(e) {
  try {
    var p = e.parameter;
    var mode = p.mode;
    var id = p.id || p.url || "";

    if (mode === "get_done_list") {
      var ss = SpreadsheetApp.openById(SS_ID);
      var sheet = ss.getSheets()[0];
      var lastRow = sheet.getLastRow();
      if (lastRow <= 1) return createResponse("");
      var data = sheet.getRange(2, 8, lastRow - 1, 2).getValues();
      var doneIds = data.filter(function(row) { return row[1] === "完了"; }).map(function(row) { return String(row[0]); });
      return createResponse(doneIds.join(","));
    }

    if (p.text) {
      var result = processPachinkoText(p.text, id);
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
 * 解析メイン。取得するのは次の8項目のみ。それ以外は空欄（ユーザー入力用）。
 * 導入開始日・機種名・メーカー名・通常時大当り確率・機種タイプ・スペック・特徴タグ・機種ID
 */
function processPachinkoText(rawInput, manualUrl) {
  try {
    var ss = SpreadsheetApp.openById(SS_ID);
    var sheet = ss.getSheets()[0];
    var parseTarget = rawInput.split("ユーザー口コミ・評価詳細")[0].split("ゲームフロー")[0];

    var mCode = "-";
    if (manualUrl) {
      var mMatch = String(manualUrl).match(/\d+/);
      if (mMatch) mCode = mMatch[0];
    }
    if (mCode === "-") {
      var idInHtml = parseTarget.match(/\/machines\/(\d+)/);
      if (idInHtml) mCode = idInHtml[1];
    }

    var introMatch = parseTarget.match(/導入開始日[\s\S]*?(\d{4})年(\d{1,2})月(\d{1,2})日/);
    var introDate = introMatch ? introMatch[1] + "/" + ("0" + introMatch[2]).slice(-2) + "/" + ("0" + introMatch[3]).slice(-2) : "-";

    var nameRaw = parseTarget.match(/<h1[^>]*>([\s\S]*?)<\/h1>/i);
    var name = "不明";
    if (nameRaw && nameRaw[1]) {
      name = nameRaw[1].replace(/<br\s*\/?>/gi, "\n").replace(/<[^>]*>/g, "").trim();
      name = name.split("\n")[0].split(/[\[(（｜|]/)[0].replace(/[ｅＰ]/g, function(s) { return String.fromCharCode(s.charCodeAt(0) - 0xFEE0); }).trim();
    }

    var maker = "不明";
    var makerMatch = parseTarget.match(/メーカー名[\s\S]*?<td[^>]*>([\s\S]*?)<\/td>/i)
      || parseTarget.match(/メーカー[\s\S]*?<td[^>]*>([\s\S]*?)<\/td>/i)
      || parseTarget.match(/<th[^>]*>メーカー名?<\/th>\s*<td[^>]*>([\s\S]*?)<\/td>/i)
      || parseTarget.match(/メーカー名?<\/th>\s*<td[^>]*>([\s\S]*?)<\/td>/i);
    if (makerMatch && makerMatch[1]) {
      maker = makerMatch[1].replace(/<[^>]*>/g, " ").replace(/\s+/g, " ").split("（")[0].split("の掲載機種")[0].trim();
      if (!maker) maker = "不明";
    }

    var probMatch = parseTarget.match(/大当り確率[\s\S]*?(?:約\s*)?([0-9１-９]{1,}\s?\/\s?[0-9１-９\.．]{1,})/);
    var probability = "-";
    if (probMatch && probMatch[1]) {
      probability = probMatch[1].replace(/[０-９．]/g, function(s) { return String.fromCharCode(s.charCodeAt(0) - 0xFEE0); }).replace(/\s/g, "");
    }

    var specArea = parseTarget.split("お知らせ一覧")[0];
    var tagSet = {};
    var isHybrid = false;
    var iconMatches = specArea.match(/alt="([^"]+)"/g) || [];
    for (var im = 0; im < iconMatches.length; im++) {
      var altText = iconMatches[im].replace(/alt=|\"/g, "").trim();
      if (altText.indexOf("ST機") !== -1) tagSet["ST"] = true;
      else if (altText.match(/\bLT\b|ラッキートリガー/i)) tagSet["LT"] = true;
      if (altText.indexOf("遊タイム") !== -1) tagSet["遊タイム"] = true;
      if (altText.indexOf("1種2種") !== -1) isHybrid = true;
      if (altText.indexOf("設定") !== -1) tagSet["設定付"] = true;
      if (altText.indexOf("コンプリート") !== -1) tagSet["コンプリート"] = true;
    }
    if (name.toLowerCase().indexOf("e") === 0) tagSet["スマパチ"] = true;
    var specTable = specArea.match(/<table[^>]*>([\s\S]*?)<\/table>/i);
    if (specTable && specTable[0] && specTable[0].match(/c時短|突然時短/i)) tagSet["c時短"] = true;
    if (specTable && specTable[0] && specTable[0].match(/転落抽選|転落型/i)) tagSet["転落"] = true;
    var tagKeys = Object.keys(tagSet);
    var tagString = tagKeys.length > 0 ? tagKeys.join("/") : "なし";
    var machineType = isHybrid ? "1種2種混合機" : (probability === "-" && parseTarget.indexOf("羽根モノ") !== -1 ? "羽根モノ" : "デジパチ");
    var denom = parseFloat(probability.split("/")[1]) || 0;
    var specType = (machineType === "羽根モノ") ? "羽根モノ" : (denom >= 300 ? "ミドル" : denom >= 150 ? "ライトミドル" : denom >= 50 ? "甘デジ" : "その他");

    var vals = [introDate, name, maker, probability, machineType, specType, tagString, mCode, "", "", "", "", ""];
    var incomplete = vals.some(function(v) { var s = String(v || "").trim(); return s === "" || s === "-" || s === "不明" || s === "要確認"; });
    var crawlStatus = incomplete ? "要確認" : "完了";
    var newRow = vals.concat(crawlStatus);

    sheet.insertRowBefore(2);
    sheet.getRange(2, 1, 1, HEADER_ROW.length).setValues([newRow]);

    return "成功: " + name;
  } catch (e) {
    return "解析エラー: " + e.toString();
  }
}

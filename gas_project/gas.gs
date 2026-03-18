/** マスターシートのスプレッドシートID */
var SS_ID = "1fSGx5EmcSOD68itgBRxjGyUGz0Wh5u1Lnbw-dyvchz4";
// デプロイ版の動作確認用（Webアプリがどのコードを動かしているか判別）
var BUILD_TAG = "2026-03-18_disable_status_autofill_v2";

/**
 * 実際のスプレッドシートのヘッダー（A〜AC = 29列）。
 * A=導入開始日, B=機種ID, C=機種名, D=メーカー, E=確率, F=機種タイプ, G=スペック, H=特徴タグ, I=ステータス, J〜Q=モード0〜7, R〜AC=当たり1〜12
 */
var HEADER_ROW = [
  "導入開始日", "機種ID", "機種名", "メーカー", "確率", "機種タイプ", "スペック", "特徴タグ", "ステータス",
  "モード0", "モード1", "モード2", "モード3", "モード4", "モード5", "モード6", "モード7",
  "当たり1", "当たり2", "当たり3", "当たり4", "当たり5", "当たり6", "当たり7", "当たり8", "当たり9", "当たり10", "当たり11", "当たり12"
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

    if (mode === "ping") {
      return createJsonResponse({
        ok: true,
        build_tag: BUILD_TAG,
        notes: "I列(ステータス)は自動入力しない仕様",
        header_len: HEADER_ROW.length
      });
    }

    if (mode === "get_done_list") {
      var ss = SpreadsheetApp.openById(SS_ID);
      var sheet = ss.getSheets()[0];
      var lastRow = sheet.getLastRow();
      if (lastRow <= 1) return createResponse("");
      // 29列: 列B(2)=機種ID, 列I(9)=ステータス
      var data = sheet.getRange(2, 1, lastRow - 1, 29).getValues();
      var doneIds = data.filter(function(row) { return row[8] === "完了"; }).map(function(row) { return String(row[1]); });
      return createResponse(doneIds.join(","));
    }

    // Collector用: A〜H がすべて埋まっている機種ID一覧（=再取得不要のスキップ対象）
    if (mode === "get_skip_ids") {
      var ssSkip = SpreadsheetApp.openById(SS_ID);
      var sheetSkip = ssSkip.getSheets()[0];
      var lastRowSkip = sheetSkip.getLastRow();
      if (lastRowSkip <= 1) return createResponse("");
      var dataSkip = sheetSkip.getRange(2, 1, lastRowSkip - 1, 29).getValues();
      var ids = dataSkip
        .filter(function(row) {
          var idv = String(row[1] || "").trim(); // B列
          if (!idv) return false;
          for (var c = 0; c < 8; c++) {
            if (String(row[c] || "").trim() === "") return false; // A〜H
          }
          return true;
        })
        .map(function(row) { return String(row[1] || "").trim(); });
      return createResponse(ids.join(","));
    }

    if (mode === "get_machine_json") {
      if (!id) return createJsonResponse({ ok: false, error: "missing_id" });
      var machine = buildMachineJsonById(String(id));
      if (!machine) return createJsonResponse({ ok: false, error: "not_found", machine_id: String(id) });
      return createJsonResponse({ ok: true, machine: machine });
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

function createJsonResponse(obj) {
  return ContentService
    .createTextOutput(JSON.stringify(obj))
    .setMimeType(ContentService.MimeType.JSON);
}

function toNumberOr(value, fallback) {
  var n = Number(String(value).trim());
  return isFinite(n) ? n : fallback;
}

function findRowIndexByMachineId_(sheet, machineId) {
  var lastRow = sheet.getLastRow();
  if (lastRow <= 1) return -1;
  var idValues = sheet.getRange(2, 2, lastRow - 1, 1).getValues(); // B列
  for (var i = 0; i < idValues.length; i++) {
    if (String(idValues[i][0] || "").trim() === machineId) return i + 2;
  }
  return -1;
}

function hasAnyBlankAtoH_(rowAtoH) {
  for (var i = 0; i < 8; i++) {
    if (String(rowAtoH[i] || "").trim() === "") return true;
  }
  return false;
}

/**
 * 当たりセルをパース（後方互換あり）
 * - 新6要素: name/base/unit/max/currentMode/nextMode
 * - 旧4要素: name/payout/currentMode/nextMode（unit=0,max=1）
 * - 旧5要素: name/payout/currentMode/nextMode/densapo（unit=0,max=1）
 */
function parseAtariCell(cell) {
  var raw = String(cell == null ? "" : cell).trim();
  if (!raw) return null;
  var parts = raw.split("/").map(function(x) { return String(x).trim(); });
  if (parts.length < 4) return null;

  if (parts.length >= 6) {
    var name = parts[0];
    var baseOut = toNumberOr(parts[1], 0);
    var unitOut = toNumberOr(parts[2], 0);
    var maxStack = Math.max(1, toNumberOr(parts[3], 1));
    var currentMode = toNumberOr(parts[4], 0);
    var nextMode = toNumberOr(parts[5], 0);
    return {
      name: name,
      baseOut: baseOut,
      unitOut: unitOut,
      maxStack: maxStack,
      currentMode: currentMode,
      nextMode: nextMode,
      totalMaxOut: baseOut + unitOut * maxStack
    };
  }

  // 旧4/旧5
  var oldName = parts[0];
  var payout = toNumberOr(parts[1], 0);
  var oldCurrent = toNumberOr(parts[2], 0);
  var oldNext = toNumberOr(parts[3], 0);
  var densapo = parts.length >= 5 ? toNumberOr(parts[4], 0) : 0;

  var obj = {
    name: oldName,
    baseOut: payout,
    unitOut: 0,
    maxStack: 1,
    currentMode: oldCurrent,
    nextMode: oldNext,
    totalMaxOut: payout
  };
  if (densapo) obj.densapo = densapo;
  return obj;
}

function buildMachineJsonById(machineId) {
  var ss = SpreadsheetApp.openById(SS_ID);
  var sheet = ss.getSheets()[0];
  var lastRow = sheet.getLastRow();
  if (lastRow <= 1) return null;

  // B列=機種ID を探索（2行目〜）
  var idValues = sheet.getRange(2, 2, lastRow - 1, 1).getValues(); // [[id],[id],...]
  var rowIndex = -1;
  for (var i = 0; i < idValues.length; i++) {
    if (String(idValues[i][0]).trim() === machineId) { rowIndex = i + 2; break; }
  }
  if (rowIndex === -1) return null;

  // A〜AC（29列）を取得
  var row = sheet.getRange(rowIndex, 1, 1, 29).getValues()[0];

  var introDate = String(row[0] || "").trim();
  var id = String(row[1] || "").trim();
  var name = String(row[2] || "").trim();
  var maker = String(row[3] || "").trim();
  var probability = String(row[4] || "").trim();
  var machineType = String(row[5] || "").trim();
  var specType = String(row[6] || "").trim();
  var tags = String(row[7] || "").trim();
  var status = String(row[8] || "").trim();

  // モード名（J〜Q）
  var modeNames = [];
  for (var m = 0; m < 8; m++) modeNames.push(String(row[9 + m] || "").trim());

  // 当たり（R〜AC）
  var parsedBonuses = [];
  for (var a = 0; a < 12; a++) {
    var parsed = parseAtariCell(row[17 + a]);
    if (parsed) parsedBonuses.push(parsed);
  }

  // モードごとに束ねる
  var modes = [];
  for (var modeId = 0; modeId < 8; modeId++) {
    var bonuses = parsedBonuses
      .filter(function(b) { return b.currentMode === modeId; })
      .map(function(b) {
        return {
          name: b.name,
          baseOut: b.baseOut,
          unitOut: b.unitOut,
          maxStack: b.maxStack,
          next_mode_id: b.nextMode,
          densapo: b.densapo || 0
        };
      });
    modes.push({
      mode_id: modeId,
      name: modeNames[modeId] || ("モード" + modeId),
      bonuses: bonuses
    });
  }

  return {
    machine_id: id,
    name: name,
    introduction_date: introDate,
    manufacturer: maker,
    probability: probability,
    machine_type: machineType,
    spec: specType,
    tags: tags,
    status: status,
    modes: modes
  };
}

/**
 * 解析メイン。HTMLから取得できる項目を29列（A〜AC）の該当列に書き込む。
 * A=導入開始日, B=機種ID, C=機種名, D=メーカー, E=確率, F=機種タイプ, G=スペック, H=特徴タグ, I=ステータス, J〜Q=モード0〜7(空), R〜AC=当たり1〜12(空)
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
      maker = maker.replace(/&amp;/g, "＆");  // HTML実体を全角＆に（例: サンセイR&amp;D → サンセイR＆D）
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
    var isFeather = false; // 羽モノ（羽根モノ）判定
    var iconMatches = specArea.match(/alt="([^"]+)"/g) || [];
    for (var im = 0; im < iconMatches.length; im++) {
      var altText = iconMatches[im].replace(/alt=|\"/g, "").trim();
      if (altText.indexOf("ST機") !== -1) tagSet["ST"] = true;
      else if (altText.match(/\bLT\b|ラッキートリガー/i)) tagSet["LT"] = true;
      if (altText.indexOf("遊タイム") !== -1) tagSet["遊タイム"] = true;
      if (altText.indexOf("1種2種") !== -1) isHybrid = true;
      // 例: alt="羽モノ " のように「羽根モノ」と表記揺れがあるため両方拾う
      if (altText.indexOf("羽モノ") !== -1 || altText.indexOf("羽根モノ") !== -1 || altText.indexOf("羽物") !== -1) isFeather = true;
      if (altText.indexOf("設定") !== -1) tagSet["設定付"] = true;
      if (altText.indexOf("コンプリート") !== -1) tagSet["コンプリート"] = true;
    }
    if (name.toLowerCase().indexOf("e") === 0) tagSet["スマパチ"] = true;
    var specTable = specArea.match(/<table[^>]*>([\s\S]*?)<\/table>/i);
    if (specTable && specTable[0] && specTable[0].match(/c時短|突然時短/i)) tagSet["c時短"] = true;
    if (specTable && specTable[0] && specTable[0].match(/転落抽選|転落型/i)) tagSet["転落"] = true;
    var tagKeys = Object.keys(tagSet);
    var tagString = tagKeys.length > 0 ? tagKeys.join("/") : "なし";
    // 機種タイプ（F列）はシート定義どおり「デジパチ/1種2種混合機/羽根モノ」を入れる（st/kakugen は入れない）
    // 羽モノは「アイコンalt」と「本文（羽根モノ/羽モノ/羽物）」の両方で判定して取りこぼしを防ぐ
    if (!isFeather && (parseTarget.indexOf("羽根モノ") !== -1 || parseTarget.indexOf("羽モノ") !== -1 || parseTarget.indexOf("羽物") !== -1)) {
      isFeather = true;
    }
    var machineType = isHybrid
      ? "1種2種混合機"
      : ((probability === "-" && isFeather) ? "羽根モノ" : "デジパチ");
    var denom = parseFloat(probability.split("/")[1]) || 0;
    var specType = (machineType === "羽根モノ") ? "羽根モノ" : (denom >= 300 ? "ミドル" : denom >= 150 ? "ライトミドル" : denom >= 50 ? "甘デジ" : "その他");

    // ステータス（I列）は運用上「手動入力」が正とするため、GAS/Collector では自動入力しない。
    // 必須項目の不足判定（incomplete）はログ用途には残すが、シートには書き込まない。
    var incomplete = !mCode || mCode === "-" || !name || name === "不明" || !maker || maker === "不明" || !probability || probability === "-";

    // A〜H（導入開始日〜特徴タグ）
    var aToH = [introDate, mCode, name, maker, probability, machineType, specType, tagString];

    // 既存行があれば、A〜H に空があるときだけ上書き（それ以外の列は触らない）
    var existingRowIndex = findRowIndexByMachineId_(sheet, mCode);
    if (existingRowIndex !== -1) {
      var existingAtoH = sheet.getRange(existingRowIndex, 1, 1, 8).getValues()[0];
      if (hasAnyBlankAtoH_(existingAtoH)) {
        sheet.getRange(existingRowIndex, 1, 1, 8).setValues([aToH]);
        // ステータス（I列）は Collector/GAS の再取得では更新しない（手動運用を優先）
        return "更新: " + name;
      }
      return "スキップ: 既に埋まっています " + name;
    }

    // 新規行: 2行目に追加（A〜Hのみ埋め、I列=ステータスは空、右側も空）
    var newRow = [
      introDate, mCode, name, maker, probability, machineType, specType, tagString, "",
      "", "", "", "", "", "", "", "",
      "", "", "", "", "", "", "", "", "", "", "", ""
    ];
    sheet.insertRowBefore(2);
    sheet.getRange(2, 1, 1, HEADER_ROW.length).setValues([newRow]);
    return "追加: " + name;
  } catch (e) {
    return "解析エラー: " + e.toString();
  }
}

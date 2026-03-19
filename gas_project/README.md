# Google Apps Script（P-stats マスタ連携）

- **`gas.gs`** … スプレッドシート連携・`get_machine_json` 等。`scripts/convert_master_one_sheet.py` と同一のマスタ解釈（mode_0〜7・当たり9項目）。
- **`appsscript.json`** … プロジェクトメタ（タイムゾーン等）

## clasp でアップロード（push）

リポジトリでは **`.clasp.json` をコミットしない**（`.gitignore`）ため、**各マシンで一度だけ**紐付けが必要です。

```bash
npm i -g @google/clasp   # 未導入なら
clasp login

cd gas_project
# 既存の GAS プロジェクトに紐付ける（スクリプト ID は GAS エディタの「プロジェクトの設定」から）
clasp clone <SCRIPT_ID>   # または手元で clasp create 後、コードをこの gas.gs に合わせる

clasp push                # gas.gs を Apps Script に反映
```

Web アプリとしてデプロイしている場合は、push 後に GAS エディタで **デプロイ → 既存のデプロイを管理 → バージョン更新** が必要なことがあります。

## 手動反映

`gas.gs` の内容を Apps Script エディタに貼り付けて保存・デプロイしても同じです。

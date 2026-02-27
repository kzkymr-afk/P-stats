# マスタをWebで管理する手順（無料ではじめる）

## 全体のイメージ

```
[あなた] → Web上でJSONを編集（マスタの正本）
    ↓
[アプリ] → そのURLにアクセスして一覧を取得 → ユーザーが「マイリストに追加」
```

- **マスタの編集** = Web上だけ（アプリには「マスタ管理」画面を出さない）
- **アプリ** = そのURLを「参照しに行く」だけ

---

## まず何をすればいいか（2ステップ）

### ステップ1: 「マスタのJSON」を1枚、Webで公開する

**いちばん手軽な無料方法 = GitHub に JSON ファイルを置く**

1. **GitHub** にアカウントを作る（まだなら [github.com](https://github.com) で無料登録）

2. **新しいリポジトリ** を1つ作る（例: `pstats-master`）。中身は空でOK。

3. そのリポジトリに **1つのファイル** を追加する：
   - ファイル名: 例 `presets.json`
   - 中身: 下の「JSONのひな形」をコピーして貼り付け、機種を1件以上書く

4. **「Raw」のURL** を取得する：
   - GitHub で `presets.json` を開く → 右上の **Raw** をクリック
   - ブラウザのアドレスバーに表示されるURLがそのまま「マスタのURL」になる  
     例: `https://raw.githubusercontent.com/あなたのID/pstats-master/main/presets.json`

このURLを、次のステップでアプリに教えます。

---

### ステップ2: アプリに「そのURL」を教える

1. プロジェクト内の **`PresetServiceConfig.swift`** を開く

2. 今の行：
   ```swift
   static var presetListURL: String { "" }
   ```
   を、次のように **URL を入れた形** に変える：
   ```swift
   static var presetListURL: String { "https://raw.githubusercontent.com/あなたのID/リポジトリ名/main/presets.json" }
   ```
   （ステップ1で取った Raw のURLをそのまま貼る）

3. アプリをビルドして実行する

4. アプリ内で **マイリスト** → **マスタから検索して追加** を開くと、WebのJSONから取得した一覧が表示されます。

---

## JSONのひな形（presets.json）

`presets.json` には「機種の配列」を書きます。最低限は次の形です。

```json
[
  {
    "name": "北斗の拳 修羅の国編",
    "machineTypeRaw": "kakugen",
    "supportLimit": 100,
    "defaultPrize": 1500,
    "probability": "1/319.5",
    "border": "16.0",
    "prizeEntries": [
      { "label": "10R（1500玉）", "rounds": 10, "balls": 1500 }
    ]
  }
]
```

- **name** … 機種名（必須）
- **machineTypeRaw** … `"st"` または `"kakugen"`
- **supportLimit** … 電サポ回数（数字）
- **defaultPrize** … デフォルト出玉（数字）
- **probability** … 確率表示用（例: `"1/319.5"`)
- **border** … ボーダー表示用（例: `"16.0"`)
- **prizeEntries** … 当たり種類の配列。各要素は `rounds` と `balls` を数字で

2台目以降は、同じ形のオブジェクトを `,` で区切って追加していけばOKです。

---

## 運用の流れ（まとめ）

| やりたいこと | やること |
|--------------|----------|
| マスタに機種を増やしたい | GitHub の `presets.json` を編集して保存（コミット＆プッシュ） |
| アプリでマスタから選びたい | アプリの「マスタから検索」を開く → 一覧がWebから取得される → 採用でマイリストに追加 |

- マスタの「正本」は **Webの1ファイル** だけ
- アプリは **そのURLを参照しに行くだけ** なので、編集はすべてWeb側で完結します。

---

## ほかの無料案（GitHubが合わない場合）

- **Vercel / Netlify**: リポジトリに `presets.json` を置いてデプロイすると、`https://あなたのプロジェクト.vercel.app/presets.json` のようなURLで配れます。
- **Google Drive**: JSON を置いて「リンクで共有」にすると、直接JSONを返すURLにはしづらいので、まずは **GitHub の Raw URL** がおすすめです。

まずは **ステップ1（GitHubに presets.json を作って Raw URL を取る）** から始めると、全体の流れがわかりやすいです。

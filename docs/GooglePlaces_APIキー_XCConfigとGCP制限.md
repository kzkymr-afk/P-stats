# Google Places API キー（XCConfig・難読化・Google Cloud 制限）

## 1. XCConfig でビルド時だけキーを渡す（推奨）

### 仕組み

- `Config/P-statsProjectOverrides.xcconfig` を **P-stats ターゲットの Base Configuration** に指定している（`project.pbxproj` の `baseConfigurationReference`。未接続だと `$(GOOGLE_PLACES_API_KEY)` がバンドルにそのまま残り、アプリは「キー未設定」になる）。
- その中で `GOOGLE_PLACES_API_KEY` をビルド設定として定義し、`Info.plist` の `$(GOOGLE_PLACES_API_KEY)` がビルド時に置き換わる。
- 実キーは **`Config/P-statsSecrets.xcconfig`** にだけ書く（`.gitignore` 済み）。リポジトリには **`P-statsSecrets.xcconfig.example`** のみコミットする。

### ローカル手順

1. `Config/P-statsSecrets.xcconfig.example` をコピーし、同じ `Config/` フォルダに `P-statsSecrets.xcconfig` として保存する。
2. 中の `YOUR_KEY_HERE` を API キーに置き換える（引用符は付けない）。
3. Xcode で **Product → Clean Build Folder** のあとビルドする。

### CI / コマンドラインビルド

リポジトリに `P-statsSecrets.xcconfig` を置かない場合の例:

```bash
xcodebuild -scheme P-stats \
  GOOGLE_PLACES_API_KEY="あなたのキー" \
  build
```

`#include?` で Secrets が無いときは `P-statsProjectOverrides.xcconfig` 先頭の空の `GOOGLE_PLACES_API_KEY` が効く。環境変数経由で渡す場合は、CI で **ビルド前に** `P-statsSecrets.xcconfig` を生成する方法でもよい。

### 注意

- `Info.plist` にキーを直書きしないこと（履歴に残る）。
- `$(GOOGLE_PLACES_API_KEY)` が置換されずバンドルに残った場合、アプリ側では無効扱いし、難読化フォールバックを試みる（`PlacesAPIKeyResolver`）。

---

## 2. 難読化（Obfuscation）の簡単な例

`P-stats/Utilities/ObfuscatedPlacesAPIKey.swift` を参照。

- API キーを UTF-8 バイト列にし、固定 `xorMask` で XOR した `[UInt8]` をソースに埋める。
- 実行時に XOR で戻して `String` にする。
- **暗号ではなく難読化**のため、バイナリ解析で復元可能。あくまで「誤コミット・簡易スキャン」向け。

キー配列の生成例（Python）:

```bash
python3 -c "k=b'あなたのAPIキー';m=0xA5;print('['+','.join(str(b^m) for b in k)+']')"
```

出力を `encoded` に貼る。`Info.plist` / xcconfig にキーが入っていれば **そちらが優先**され、難読化はフォールバック。

---

## 3. Google Cloud Console での「Bundle ID 制限」手順

Places / Maps 系で **iOS アプリ向けキー**を使う場合の一般的な流れ（コンソールの文言は変更されることがあります）。

### A. API キーを開く

1. [Google Cloud Console](https://console.cloud.google.com/) にログインする。
2. 対象の **プロジェクト** を選択する。
3. メニュー **「API とサービス」→「認証情報」** を開く。
4. 使用している **API キー** をクリックする（または「認証情報を作成」→「API キー」で新規作成）。

### B. アプリケーションの制限（iOS）

1. キー編集画面の **「アプリケーションの制限」** で **「iOS アプリ」** を選ぶ。
2. **「バンドル ID の制限」** に、アプリの Bundle ID を追加する。  
   本プロジェクトの例: `jp.kzkymr.p-stats`（Xcode の *Signing & Capabilities* と一致させる）。
3. 必要に応じて **+ 項目を追加** で開発用・別ターゲットの Bundle ID を追加する。

### C. API の制限

1. 同じキー編集画面の **「API の制限」** で **「キーを制限」** を選ぶ。
2. 実際に使う API だけにチェックを入れる（例: **Places API**、**Geocoding API** など。利用している API に合わせる）。
3. 保存する。

### D. その他の推奨

- キーを **用途別に分ける**（本番用 / 開発用）。
- 漏洩時は **キーをローテーション**し、GCP 側で無効化または削除する。
- **課金アラート**と **クォータ監視**を有効にする。

> **補足**: 「Bundle ID 制限」は **iOS アプリからの利用**向け。サーバー用キーは別の制限（IP など）にする。

---

## 4. トラブルシュート

| 現象 | 確認 |
|------|------|
| アプリで「キー未設定」 | `P-statsSecrets.xcconfig` の有無・`GOOGLE_PLACES_API_KEY` の行・クリーンビルド |
| 403 / REQUEST_DENIED | GCP で該当 API が有効か、キーの API 制限に Places 等が含まれるか |
| iOS 制限で拒否 | Bundle ID が Xcode の `PRODUCT_BUNDLE_IDENTIFIER` と完全一致しているか |

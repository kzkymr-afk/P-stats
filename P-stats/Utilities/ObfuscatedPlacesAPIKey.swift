import Foundation

/// Places API キー用のごく簡単な難読化（バイナリ風バイト列 + XOR）。
/// **実害防止用であり暗号ではない**（リバースで復元可能）。本番の主防衛は GCP のキー制限とローテーション。
///
/// 使い方:
/// 1. 下の `encoded` を空のままにすると無効（Info.plist / xcconfig のキーのみ使用）。
/// 2. キーを埋めたい場合、ターミナルで次を実行し、出力された `[UInt8]` を `encoded` に貼る。
///
/// ```text
/// python3 -c "k=b'あなたのAPIキー';m=0xA5;print('['+','.join(str(b^m) for b in k)+']')"
/// ```
///
/// `PlaceSearchService` は Info.plist のキーが有効ならそちらを優先し、無いときだけここを参照する。
enum ObfuscatedPlacesAPIKey {
    private static let xorMask: UInt8 = 0xA5

    /// 空配列 = 未使用。上記スクリプトで生成したバイト列を入れる。
    private static let encoded: [UInt8] = []

    static var revealedIfConfigured: String? {
        guard !encoded.isEmpty else { return nil }
        let decoded = Data(encoded.map { $0 ^ xorMask })
        return String(data: decoded, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

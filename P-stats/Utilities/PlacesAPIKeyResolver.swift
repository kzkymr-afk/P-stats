import Foundation

/// Google Places API キーの解決（Info.plist のビルド時置換 → 難読化フォールバック）。
enum PlacesAPIKeyResolver {
    /// `$(VAR)` が置換されずバンドルに残った場合は無効扱いにする。
    static func googlePlacesAPIKey() -> String? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "GooglePlacesAPIKey") as? String else {
            return ObfuscatedPlacesAPIKey.revealedIfConfigured
        }
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return ObfuscatedPlacesAPIKey.revealedIfConfigured }
        if t.contains("$(") { return ObfuscatedPlacesAPIKey.revealedIfConfigured }
        return t
    }
}

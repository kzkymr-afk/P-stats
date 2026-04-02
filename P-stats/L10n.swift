import Foundation

/// UI 文言の入口。`Localizable.xcstrings` のキーと対応（一括置換・将来の翻訳用）。
enum L10n {
    enum Places {
        static var errorNetwork: String {
            String(localized: "places.error.network", bundle: .main, comment: "Places API: generic failure")
        }

        static var errorQuota: String {
            String(localized: "places.error.quota", bundle: .main, comment: "Places API: OVER_QUERY_LIMIT")
        }

        static var errorDenied: String {
            String(localized: "places.error.denied", bundle: .main, comment: "Places API: REQUEST_DENIED")
        }

        static var errorInvalid: String {
            String(localized: "places.error.invalid", bundle: .main, comment: "Places API: INVALID_REQUEST")
        }
    }
}

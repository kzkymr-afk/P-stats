import Foundation
import StoreKit

extension Product {
    /// 購入ボタン等の表示用。`displayPrice` は端末のストアフロント・言語設定で英語・米ドルになることがあるため、日本向けアプリでは円・`ja_JP` で整形して統一する。
    var displayPriceJapanese: String {
        price.formatted(
            .currency(code: "JPY")
                .locale(Locale(identifier: "ja_JP"))
        )
    }
}

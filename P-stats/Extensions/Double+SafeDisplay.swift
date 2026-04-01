import Foundation

extension Double {
    /// 画面表示に使ってよい有限値か（NaN / ±Infinity を除外）
    var isValidForNumericDisplay: Bool { isFinite && !isNaN }

    /// `String(format:)` の前に有限性を検証。不正時はプレースホルダ。
    func displayFormat(_ format: String, placeholder: String = "—") -> String {
        guard isValidForNumericDisplay else { return placeholder }
        return String(format: format, self)
    }
}

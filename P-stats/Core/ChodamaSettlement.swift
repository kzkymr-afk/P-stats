import Foundation

/// 実戦終了時の精算（換金 / 貯玉）
enum SessionSettlementMode: String, CaseIterable {
    case exchange
    case chodama

    var displayName: String {
        switch self {
        case .exchange: return "換金"
        case .chodama: return "貯玉"
        }
    }
}

/// 換金時の内訳（払出係数＝pt/玉 を換金レートとして使用）
struct ChodamaExchangeBreakdown: Equatable {
    /// 回収玉の pt 換算（四捨五入）
    let totalRecoveryPt: Int
    /// 500pt 単位に切り捨てた換金額
    let cashProceedsPt: Int
    /// 換金しなかった pt（端数）
    let remainderPt: Int
    /// 端数を玉に戻したときの玉数（四捨五入）
    let remainderBalls: Int
}

enum ChodamaSettlement {
    static let cashIncrementPt: Int = PersistedDataSemantics.cashInvestmentStepPt

    static func exchangeBreakdown(balls: Int, yenPerBall: Double) -> ChodamaExchangeBreakdown {
        let b = max(0, balls)
        let totalPt = Int((Double(b) * yenPerBall).rounded())
        let safeTotal = max(0, totalPt)
        let cash = (safeTotal / cashIncrementPt) * cashIncrementPt
        let remPt = max(0, safeTotal - cash)
        let remBalls: Int
        if yenPerBall > 0 {
            remBalls = max(0, Int((Double(remPt) / yenPerBall).rounded()))
        } else {
            remBalls = 0
        }
        return ChodamaExchangeBreakdown(
            totalRecoveryPt: safeTotal,
            cashProceedsPt: cash,
            remainderPt: remPt,
            remainderBalls: remBalls
        )
    }
}

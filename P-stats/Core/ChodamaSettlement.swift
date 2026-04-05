import Foundation

/// 実戦終了時の精算（履歴 `settlementModeRaw` に保存する識別子）
enum SessionSettlementMode: String, CaseIterable {
    /// 旧版：今回の出玉を換金（端数は貯玉対応店のみ貯玉へ）
    case exchange
    /// 旧版：今回の出玉をすべて貯玉へ
    case chodama
    /// 今回の獲得出玉をすべて貯玉へ（新式の記録）
    case winningDepositChodama
    /// 今回の獲得出玉を換金し、端数 pt を貯玉へ戻す
    case winningExchangeRemainderChodama
    /// 今回の獲得出玉を換金し、端数は貯玉に入れない（放棄扱い）
    case winningExchangeRemainderAbandon
    /// 今回の出玉を貯玉に預けたあと、貯玉の一部を換金
    case chodamaPartialExchange
    /// 今回の出玉を含めた貯玉をすべて換金
    case chodamaFullExchange

    var displayName: String {
        switch self {
        case .exchange: return "換金（旧）"
        case .chodama: return "貯玉（旧）"
        case .winningDepositChodama: return "今回の獲得出玉を貯玉へ"
        case .winningExchangeRemainderChodama: return "今回の出玉を換金（端数→貯玉）"
        case .winningExchangeRemainderAbandon: return "今回の出玉を換金（端数なし）"
        case .chodamaPartialExchange: return "貯玉の一部換金"
        case .chodamaFullExchange: return "貯玉の全額換金"
        }
    }
}

/// 精算シート確定時に `saveCurrentSession` へ渡すペイロード（店の貯玉・換金 pt を確定）
struct SessionSettlementOutcome: Equatable {
    var mode: SessionSettlementMode
    var exchangeCashProceedsPt: Int
    /// `shop.chodamaBalanceBalls` への増減（この保存処理内で加算）
    var chodamaBalanceDeltaBalls: Int
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

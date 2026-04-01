import Foundation

// MARK: - Share payload snapshot (永続/ライブどちらでも使える)

struct SessionShareSnapshot: Equatable, Hashable {
    var date: Date
    var machineName: String
    var shopName: String

    /// 総投資（pt換算）
    var totalInvestmentPt: Int
    /// 回収出玉（玉）
    var totalRecoveryBalls: Int
    /// 収支（pt）
    var profitPt: Int

    /// 総回転数（通常）
    var normalRotations: Int

    /// 大当たり回数
    var rushWinCount: Int
    var normalWinCount: Int

    /// 平均初あたり確率（通常回転 ÷ 当選合計）を「1/N」の N として扱う。出せない場合は nil。
    var averageFirstHitOdds: Double?

    /// 実質回転率（回/1k）
    var realRatePer1k: Double?
    /// 実質ボーダー（回/1k）
    var effectiveBorderPer1k: Double?

    var borderDiffPer1k: Double? {
        guard let r = realRatePer1k, let b = effectiveBorderPer1k, r > 0, b > 0 else { return nil }
        let d = r - b
        return d.isFinite ? d : nil
    }

    var totalWinCount: Int { max(0, rushWinCount) + max(0, normalWinCount) }

    static func from(session: GameSession) -> SessionShareSnapshot {
        let investmentPt = Int(max(0, session.totalRealCost).rounded())
        let recoveryBalls = max(0, session.totalHoldings)
        let realRate = session.displayRealRotationRatePer1k
        let border = session.displayEffectiveBorderPer1kAtSave
        let rush = max(0, session.rushWinCount)
        let normal = max(0, session.normalWinCount)
        let totalWins = rush + normal
        let avgOdds: Double? = (totalWins > 0 && session.normalRotations > 0)
            ? (Double(session.normalRotations) / Double(totalWins))
            : nil
        return SessionShareSnapshot(
            date: session.date,
            machineName: session.machineName,
            shopName: session.shopName,
            totalInvestmentPt: investmentPt,
            totalRecoveryBalls: recoveryBalls,
            profitPt: session.performance,
            normalRotations: max(0, session.normalRotations),
            rushWinCount: rush,
            normalWinCount: normal,
            averageFirstHitOdds: avgOdds,
            realRatePer1k: realRate,
            effectiveBorderPer1k: border
        )
    }

    static func from(log: GameLog) -> SessionShareSnapshot {
        // ライブは店補正ボーダーと実質回転率が取れる場合のみ表示、無理なら nil
        let rr = log.realRate > 0 ? log.realRate : nil
        let db = log.dynamicBorder > 0 ? log.dynamicBorder : nil
        let rush = max(0, log.rushWinCount)
        let normal = max(0, log.normalWinCount)
        let totalWins = rush + normal
        let avgOdds: Double? = (totalWins > 0 && log.normalRotations > 0)
            ? (Double(log.normalRotations) / Double(totalWins))
            : nil
        return SessionShareSnapshot(
            date: Date(),
            machineName: log.selectedMachine.name,
            shopName: log.selectedShop.name,
            totalInvestmentPt: Int(max(0, log.totalRealCost).rounded()),
            totalRecoveryBalls: max(0, log.totalHoldings),
            profitPt: log.balancePt,
            normalRotations: max(0, log.normalRotations),
            rushWinCount: rush,
            normalWinCount: normal,
            averageFirstHitOdds: avgOdds,
            realRatePer1k: rr,
            effectiveBorderPer1k: db
        )
    }
}


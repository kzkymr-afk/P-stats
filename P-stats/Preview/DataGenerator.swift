import Foundation
import SwiftData

/// DEBUG 用：履歴・分析のプレビュー向けに、それっぽい `GameSession` を一括生成する。
enum DataGenerator {

    private static let payoutCoefficient: Double = PersistedDataSemantics.defaultPayoutCoefficientPtPerBall
    private static let ballsPer500Pt: Int = PersistedDataSemantics.defaultBallsPer500Pt

    /// デモ用の人気機種プール（そのうち 5〜6 種を使用）
    private static let machinePool: [(name: String, manufacturer: String, formulaBorder: Double, probability: String, avgNetPerRound: Double)] = [
        ("新世紀エヴァンゲリオン〜未来への咆哮〜", "ビスティ", 18.4, "1/319.6", 142),
        ("P Re:ゼロから始める異世界生活 鬼がかりver.", "サミー", 17.8, "1/229.1", 148),
        ("Pフィーバー機動戦士ガンダムSEED", "サンセイ", 19.2, "1/349.8", 138),
        ("P真・花の慶次3", "KYORAKU", 18.0, "1/319.0", 145),
        ("eジャパンストリートファイターⅡ", "タイヨー", 20.5, "1/399.2", 128),
        ("Pスマート闘神2 神々の飛騨", "大一商会", 17.2, "1/199.8", 155),
        ("Pからくりサーカス 夢幻のレザレクヨ", "藤商事", 18.8, "1/349.5", 140),
        ("P地獄少女 闇", "京楽", 19.0, "1/359.7", 136),
    ]

    private static let demoShopNames = [
        "デモホール北口店",
        "サンプルパチンコ南町",
        "プレビューアミューズ",
    ]

    /// トータル収支の目安（pt）。交換率 4pt/玉 ならおおよそ「+20万玉」相当。
    private static let targetTotalPerformancePt: Int = 800_000

    /// 「大勝ち」1 セッションの成績下限（pt）。約 5万玉 × 4pt。
    private static let bigWinPerformanceThresholdPt: Int = 200_000

    static func deleteAllSessions(context: ModelContext) {
        do {
            let descriptor = FetchDescriptor<GameSession>()
            let sessions = try context.fetch(descriptor)
            for s in sessions {
                context.delete(s)
            }
        } catch {
            // DEBUG 用途のため黙って失敗してよい
        }
    }

    static func generateDummyData(context: ModelContext) {
        var rng = SystemRandomNumberGenerator()
        let machineCount = Int.random(in: 5...6, using: &rng)
        var shuffled = machinePool.shuffled(using: &rng)
        if shuffled.count > machineCount {
            shuffled = Array(shuffled.prefix(machineCount))
        }
        let machines = shuffled

        let sessionCount = Int.random(in: 52...72, using: &rng)
        let targetPerformances = buildTargetPerformances(sessionCount: sessionCount, rng: &rng)

        let calendar = Calendar.current
        let now = Date()

        for perf in targetPerformances {
            let spec = machines.randomElement(using: &rng)!
            let shopName = demoShopNames.randomElement(using: &rng)!

            let inputCash = (Int.random(in: 6...85, using: &rng)) * 500
            let recoveryPt = perf + inputCash
            let totalHoldings = max(0, Int((Double(recoveryPt) / payoutCoefficient).rounded()))

            let totalUsedBalls = max(
                0,
                Int((Double(inputCash) / 1000.0 * PersistedDataSemantics.ballsPer1000Pt(fromBallsPer500Pt: ballsPer500Pt)).rounded())
            )

            let economicRealRate: Double
            let normalRotations: Int
            if inputCash > 0 {
                let ratePer1k = Double.random(in: 14.0...22.5, using: &rng)
                normalRotations = max(120, Int((Double(inputCash) / 1000.0 * ratePer1k).rounded()))
                economicRealRate = Double(normalRotations) / (Double(inputCash) / 1000.0)
            } else {
                normalRotations = 0
                economicRealRate = 0
            }

            let dynamicBorder = Self.dynamicBorder(
                formula: spec.formulaBorder,
                effective1RNet: spec.avgNetPerRound,
                probabilityDenominator: probabilityDenominator(from: spec.probability),
                ballsPer500: ballsPer500Pt,
                rate: payoutCoefficient
            )

            let cashToBalls = Double(inputCash) / 500.0 * Double(ballsPer500Pt)
            let effectiveUnitsForBorder = cashToBalls / 250.0
            let expectationRatio: Double
            if dynamicBorder > 0, effectiveUnitsForBorder > 0, economicRealRate > 0 {
                expectationRatio = economicRealRate / dynamicBorder
            } else {
                expectationRatio = 1.0
            }

            let totalRealCost = Double(inputCash)
            let rWin = max(0, normalRotations / Int.random(in: 140...260, using: &rng))
            let nWin = max(0, normalRotations / Int.random(in: 280...520, using: &rng))

            let dayOffset = Int.random(in: 0..<90, using: &rng)
            guard let dayStart = calendar.date(byAdding: .day, value: -dayOffset, to: calendar.startOfDay(for: now)) else { continue }
            let startHour = Int.random(in: 9...20, using: &rng)
            let startMinute = Int.random(in: 0..<60, using: &rng)
            guard let startedAt = calendar.date(bySettingHour: startHour, minute: startMinute, second: 0, of: dayStart) else { continue }
            let playMinutes = Int.random(in: 75...400, using: &rng)
            let endedAt = startedAt.addingTimeInterval(Double(playMinutes * 60))

            let session = GameSession(
                machineName: spec.name,
                shopName: shopName,
                manufacturerName: spec.manufacturer,
                inputCash: inputCash,
                totalHoldings: totalHoldings,
                normalRotations: normalRotations,
                totalUsedBalls: totalUsedBalls,
                payoutCoefficient: payoutCoefficient,
                totalRealCost: totalRealCost,
                expectationRatioAtSave: expectationRatio,
                rushWinCount: rWin,
                normalWinCount: nWin,
                formulaBorderPer1k: spec.formulaBorder
            )
            session.date = endedAt
            session.startedAt = startedAt
            session.endedAt = endedAt
            session.effectiveBorderPer1kAtSave = dynamicBorder
            session.realRotationRateAtSave = economicRealRate
            session.theoreticalValue = PStatsCalculator.theoreticalValuePt(
                totalRealCostPt: totalRealCost,
                expectationRatio: expectationRatio
            )
            session.isCashflowOnlyRecord = false
            context.insert(session)
        }
    }

    // MARK: - 収支プロファイル

    /// 大勝ち数回＋負け・小勝ちを混ぜ、合計が `targetTotalPerformancePt`（約 +20万玉相当）になるよう配分する。
    private static func buildTargetPerformances(sessionCount: Int, rng: inout SystemRandomNumberGenerator) -> [Int] {
        var out: [Int] = []
        out.reserveCapacity(sessionCount)
        let bigWinCount = Int.random(in: 3...5, using: &rng)
        let bigWins = (0..<bigWinCount).map { _ in
            Int.random(in: bigWinPerformanceThresholdPt...(bigWinPerformanceThresholdPt + 220_000), using: &rng)
        }
        let restCount = sessionCount - bigWinCount
        var rest: [Int] = []
        rest.reserveCapacity(restCount)
        for _ in 0..<restCount {
            let roll = Int.random(in: 0..<100, using: &rng)
            if roll < 48 {
                rest.append(-Int.random(in: 2_000...35_000, using: &rng))
            } else if roll < 82 {
                rest.append(Int.random(in: 300...16_000, using: &rng))
            } else {
                rest.append(Int.random(in: -10_000...24_000, using: &rng))
            }
        }
        let sumBig = bigWins.reduce(0, +)
        let sumRest = rest.reduce(0, +)
        let delta = targetTotalPerformancePt - sumBig - sumRest
        if !rest.isEmpty {
            let idx = Int.random(in: 0..<rest.count, using: &rng)
            rest[idx] += delta
        } else if let last = bigWins.indices.last {
            var bw = bigWins
            bw[last] += delta
            out.append(contentsOf: bw)
            return out
        }
        out.append(contentsOf: bigWins)
        out.append(contentsOf: rest)
        out.shuffle(using: &rng)
        return out
    }

    // MARK: - ボーダー（`GameSessionEditView.expectationMetricsForSimpleSave` と同趣旨）

    private static func dynamicBorder(
        formula: Double,
        effective1RNet: Double,
        probabilityDenominator: Double,
        ballsPer500: Int,
        rate: Double
    ) -> Double {
        let ballsPer1000 = PersistedDataSemantics.ballsPer1000Pt(fromBallsPer500Pt: ballsPer500)
        let loanCorrection = ballsPer1000 > 0 ? 250.0 / ballsPer1000 : 1.0
        let exchangeCorrection = rate > 0 ? 4.0 / rate : 1.0

        if formula > 0 {
            return formula * loanCorrection * exchangeCorrection
        }
        if effective1RNet > 0, probabilityDenominator > 0, rate > 0, ballsPer1000 > 0 {
            return probabilityDenominator * 250.0 / effective1RNet * loanCorrection * exchangeCorrection
        }
        if effective1RNet > 0, rate > 0 {
            return 1000.0 / (effective1RNet * rate)
        }
        return 0
    }

    private static func probabilityDenominator(from probability: String) -> Double {
        let s = probability.trimmingCharacters(in: .whitespaces)
        guard let slash = s.firstIndex(of: "/") else { return 0 }
        let after = s[s.index(after: slash)...].trimmingCharacters(in: .whitespaces)
        return Double(after) ?? 0
    }
}

import Charts
import SwiftUI

extension EarningsPeriod {
    var homeBalanceTitle: String {
        switch self {
        case .month: return "今月の収支"
        case .year: return "今年の収支"
        case .week: return "今週の収支"
        case .day: return "今日の収支"
        }
    }

    var homeTheoreticalTitle: String {
        switch self {
        case .month: return "今月の理論値の積み上げ"
        case .year: return "今年の理論値の積み上げ"
        case .week: return "今週の理論値の積み上げ"
        case .day: return "今日の理論値の積み上げ"
        }
    }

    var homeFirstHitTitle: String {
        switch self {
        case .month: return "今月の初当たりまでの平均投資"
        case .year: return "今年の初当たりまでの平均投資"
        case .week: return "今週の初当たりまでの平均投資"
        case .day: return "今日の初当たりまでの平均投資"
        }
    }
}

/// ホーム上部の統合情報パネル（グラスカード＋任意で横長広告スロット）
struct HomeIntegratedInfoPanel: View {
    let sessions: [GameSession]
    @Binding var statsPeriod: EarningsPeriod
    let orderedSectionIDs: [Int]
    let hiddenSectionIDs: Set<Int>
    let lookbackDays: Int
    /// 非課金でバナー表示時は true（設定パネルの①②のみ。バナーはドック直上に統一）
    let freeTierWithAds: Bool
    let cardPadding: CGFloat

    private var cyan: Color { AppGlassStyle.accent }
    private var lossPink: Color { Color(red: 0.95, green: 0.3, blue: 0.5) }

    private var visibleSectionIDs: [Int] {
        if freeTierWithAds {
            return orderedSectionIDs.filter { $0 == 1 || $0 == 2 }
        }
        return orderedSectionIDs.filter { !hiddenSectionIDs.contains($0) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(visibleSectionIDs.enumerated()), id: \.offset) { index, sid in
                if index > 0 {
                    Divider()
                        .background(Color.white.opacity(0.12))
                        .padding(.vertical, 8)
                }
                sectionBlock(sid)
            }
        }
        .padding(cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppGlassStyle.cardBackground, in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(AppGlassStyle.strokeGradient, lineWidth: 1)
        )
    }

    @ViewBuilder
    private func sectionBlock(_ sid: Int) -> some View {
        switch sid {
        case 1: balanceBlock
        case 2: theoreticalBlock
        case 3: firstHitBlock
        case 4: streakBlock
        case 5: miniTrendBlock
        case 6: affinityBlock
        case 7: rotationBlock
        default: EmptyView()
        }
    }

    private func cyclePeriod() {
        HapticUtil.impact(.light)
        withAnimation(.easeInOut(duration: 0.2)) {
            let all = EarningsPeriod.allCases
            let idx = all.firstIndex(of: statsPeriod).map { ($0 + 1) % all.count } ?? 0
            statsPeriod = all[idx]
        }
    }

    // MARK: - ① 収支

    private var balanceBlock: some View {
        Button(action: cyclePeriod) {
            VStack(alignment: .leading, spacing: 6) {
                Text(statsPeriod.homeBalanceTitle)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.92))
                let p = HomeInsightMetrics.periodProfit(in: statsPeriod, sessions: sessions)
                Text("\(p >= 0 ? "+" : "")\(p.formattedPtWithUnit)")
                    .font(.system(size: 17, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(p >= 0 ? cyan : lossPink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                let ds = HomeInsightMetrics.periodDeficitSurplus(in: statsPeriod, sessions: sessions)
                HStack {
                    Spacer(minLength: 0)
                    Text(ds >= 0 ? "余剰 +\(ds.formattedPtWithUnit)" : "欠損 \(ds.formattedPtWithUnit)")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundColor(ds >= 0 ? Color(red: 0.35, green: 0.92, blue: 0.55) : Color.orange.opacity(0.95))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - ② 理論値積み上げ

    private var theoreticalBlock: some View {
        Button(action: cyclePeriod) {
            VStack(alignment: .leading, spacing: 6) {
                Text(statsPeriod.homeTheoreticalTitle)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.92))
                let t = HomeInsightMetrics.periodTheoreticalSum(in: statsPeriod, sessions: sessions)
                Text("\(t >= 0 ? "+" : "")\(t.formattedPtWithUnit)")
                    .font(.system(size: 17, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(t >= 0 ? cyan : lossPink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("※理論値＝基準値比に基づく期待損益の合算です。")
                    .font(.system(size: 10, weight: .regular, design: .rounded))
                    .foregroundColor(.white.opacity(0.55))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - ③ 初当たり平均投資

    private var firstHitBlock: some View {
        Button(action: cyclePeriod) {
            VStack(alignment: .leading, spacing: 6) {
                Text(statsPeriod.homeFirstHitTitle)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.92))
                if let avg = HomeInsightMetrics.averageFirstHitInvestment(in: statsPeriod, sessions: sessions) {
                    Text("\(Int(avg.rounded()).formattedPtWithUnit)")
                        .font(.system(size: 17, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.95))
                } else {
                    Text("—")
                        .font(.system(size: 17, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundColor(.white.opacity(0.55))
                }
                Text("実戦保存分のみ内部記録。手入力・旧データは平均に含みません。")
                    .font(.system(size: 10, weight: .regular, design: .rounded))
                    .foregroundColor(.white.opacity(0.55))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - ④ 直近7実戦

    private var streakBlock: some View {
        let ordered = HomeInsightMetrics.lastUpToSevenSessions(newestFirst: sessions)
            .sorted { $0.date < $1.date }
        return VStack(alignment: .leading, spacing: 8) {
            Text("直近\(ordered.count)実戦の星取り")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(0.92))
            HStack(spacing: 4) {
                ForEach(ordered, id: \.id) { s in
                    VStack(spacing: 2) {
                        Text(s.performance >= 0 ? "○" : "●")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundColor(s.performance >= 0 ? cyan : lossPink)
                        Text(s.performance.formattedPtCompactK)
                            .font(.system(size: 9, weight: .medium, design: .rounded).monospacedDigit())
                            .foregroundColor(.white.opacity(0.72))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .frame(maxWidth: .infinity)
                }
                if ordered.isEmpty {
                    Text("実戦データがありません")
                        .font(.system(size: 12, weight: .regular, design: .rounded))
                        .foregroundColor(.white.opacity(0.5))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - ⑤ ミニチャート

    private var miniTrendBlock: some View {
        let steps = HomeInsightMetrics.cumulativePerformanceSteps(in: statsPeriod, sessions: sessions)
        let indexed = steps.enumerated().map { ($0.offset, $0.element) }
        let up = steps.count >= 2 && (steps.last! > steps.first!)
        let down = steps.count >= 2 && (steps.last! < steps.first!)

        return VStack(alignment: .leading, spacing: 8) {
            Text("累積収支の推移（ミニ）")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(0.92))
            if steps.count >= 2 {
                Chart {
                    ForEach(Array(indexed), id: \.0) { pair in
                        LineMark(
                            x: .value("n", pair.0),
                            y: .value("累計", pair.1)
                        )
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(
                            LinearGradient(
                                colors: [cyan.opacity(0.95), cyan.opacity(0.35)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .lineStyle(StrokeStyle(lineWidth: 1.8))
                    }
                }
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
                .frame(height: 44)
                .padding(.vertical, 2)

                if up {
                    Text("推移は右肩上がりです。")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundColor(Color(red: 0.35, green: 0.92, blue: 0.55).opacity(0.9))
                } else if down {
                    Text("推移は右肩下がり。今日は慎重に。")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundColor(Color.orange.opacity(0.92))
                }
            } else {
                Text("2ステップ以上の実戦が集まると折れ線が表示されます。")
                    .font(.system(size: 11, weight: .regular, design: .rounded))
                    .foregroundColor(.white.opacity(0.55))
                    .frame(height: 40, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - ⑥ 相性 Top3

    private var affinityBlock: some View {
        let window = HomeInsightMetrics.sessions(inLastDays: lookbackDays, from: sessions)
        let top = HomeInsightMetrics.affinityTop3(sessionsInWindow: window)
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("相性の良い台 Top3")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.92))
                Spacer(minLength: 0)
                Text("直近\(lookbackDays)日")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.5))
            }
            if top.isEmpty {
                Text("対象期間にデータがありません")
                    .font(.system(size: 11, weight: .regular, design: .rounded))
                    .foregroundColor(.white.opacity(0.55))
            } else {
                ForEach(Array(top.enumerated()), id: \.offset) { i, row in
                    HStack(alignment: .firstTextBaseline) {
                        Text("\(i + 1). \(row.name)")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundColor(.white.opacity(0.88))
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        Text(row.deficitSurplus >= 0 ? "+\(row.deficitSurplus.formattedPtWithUnit)" : row.deficitSurplus.formattedPtWithUnit)
                            .font(.system(size: 11, weight: .semibold, design: .rounded).monospacedDigit())
                            .foregroundColor(row.deficitSurplus >= 0 ? cyan : lossPink)
                    }
                }
            }
            Text("並び：理論値に対する余剰が大きい順（理論より上振れしている度合いの目安）。")
                .font(.system(size: 9, weight: .regular, design: .rounded))
                .foregroundColor(.white.opacity(0.48))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - ⑦ 回転率リーダー

    private var rotationBlock: some View {
        let window = HomeInsightMetrics.sessions(inLastDays: lookbackDays, from: sessions)
        let leaders = HomeInsightMetrics.rotationLeadersTop3(sessionsInWindow: window)
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("主力機種の回転率")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.92))
                Spacer(minLength: 0)
                Text("直近\(lookbackDays)日")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.5))
            }
            if leaders.isEmpty {
                Text("対象期間にデータがありません")
                    .font(.system(size: 11, weight: .regular, design: .rounded))
                    .foregroundColor(.white.opacity(0.55))
            } else {
                ForEach(leaders) { row in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(row.name)
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundColor(.white.opacity(0.88))
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        Text(String(format: "%.1f 回/k", row.avgRotationPer1k))
                            .font(.system(size: 11, weight: .semibold, design: .rounded).monospacedDigit())
                            .foregroundColor(.white.opacity(0.9))
                        if let d = row.avgDiffFromFormula {
                            Text(String(format: "(%+.1f)", d))
                                .font(.system(size: 10, weight: .semibold, design: .rounded).monospacedDigit())
                                .foregroundColor(d >= 0 ? cyan : lossPink)
                        }
                    }
                }
            }
            Text("並び：通常回転数の合計が多い機種順。括弧は公式基準値との差（回/1k）の平均。")
                .font(.system(size: 9, weight: .regular, design: .rounded))
                .foregroundColor(.white.opacity(0.48))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

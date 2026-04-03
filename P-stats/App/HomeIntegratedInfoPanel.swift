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
        case .month: return "今月の期待値の積み上げ"
        case .year: return "今年の期待値の積み上げ"
        case .week: return "今週の期待値の積み上げ"
        case .day: return "今日の期待値の積み上げ"
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
    @EnvironmentObject private var themeManager: ThemeManager
    // 設定の単位ラベル変更を即時反映させるための更新トリガー
    @AppStorage(UnitDisplaySettings.unitSuffixKey) private var unitDisplaySuffix: String = "pt"

    let sessions: [GameSession]
    @Binding var statsPeriod: EarningsPeriod
    let orderedSectionIDs: [Int]
    let hiddenSectionIDs: Set<Int>
    let lookbackDays: Int
    /// 非課金でバナー表示時は true（設定パネルの①②のみ。バナーはドック直上に統一）
    let freeTierWithAds: Bool
    let cardPadding: CGFloat

    private var accent: Color { themeManager.currentTheme.accentColor }
    private var skin: ApplicationTheme { themeManager.currentTheme }
    private var lossPink: Color { Color(red: 0.95, green: 0.3, blue: 0.5) }

    private var visibleSectionIDs: [Int] {
        if freeTierWithAds {
            return orderedSectionIDs.filter { $0 == 1 || $0 == 2 }
        }
        return orderedSectionIDs.filter { !hiddenSectionIDs.contains($0) }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(visibleSectionIDs.enumerated()), id: \.offset) { index, sid in
                    if index > 0 {
                        Rectangle()
                            .fill(AppGlassStyle.divider)
                            .frame(height: 1)
                            .padding(.vertical, 12)
                    }
                    sectionBlock(sid)
                        .padding(.vertical, 4)
                }
            }
            .padding(cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .pstatsPanelStyle()
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
            VStack(alignment: .leading, spacing: 10) {
                Text(statsPeriod.homeBalanceTitle)
                    .font(skin.themedFont(size: 17, weight: .semibold))
                    .foregroundColor(skin.mainTextColor)
                let p = HomeInsightMetrics.periodProfit(in: statsPeriod, sessions: sessions)
                let ds = HomeInsightMetrics.periodDeficitSurplus(in: statsPeriod, sessions: sessions)
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("\(p >= 0 ? "+" : "")\(p.formattedPtWithUnit)")
                        .font(skin.themedFont(size: 20, weight: .semibold, monospaced: true))
                        .foregroundStyle(p >= 0 ? AppDesignSystem.Palette.win : AppDesignSystem.Palette.loss)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(ds >= 0 ? "余剰 +\(ds.formattedPtWithUnit)" : "欠損 \(ds.formattedPtWithUnit)")
                        .font(skin.themedFont(size: 14, weight: .semibold))
                        .foregroundColor(ds >= 0 ? Color(red: 0.35, green: 0.92, blue: 0.55) : Color.orange.opacity(0.95))
                        .multilineTextAlignment(.trailing)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - ② 期待値積み上げ

    private var theoreticalBlock: some View {
        Button(action: cyclePeriod) {
            VStack(alignment: .leading, spacing: 10) {
                Text(statsPeriod.homeTheoreticalTitle)
                    .font(skin.themedFont(size: 17, weight: .semibold))
                    .foregroundColor(skin.mainTextColor)
                let t = HomeInsightMetrics.periodTheoreticalSum(in: statsPeriod, sessions: sessions)
                Text("\(t >= 0 ? "+" : "")\(t.formattedPtWithUnit)")
                    .font(skin.themedFont(size: 20, weight: .semibold, monospaced: true))
                    .foregroundStyle(t >= 0 ? AppDesignSystem.Palette.expectation : AppDesignSystem.Palette.loss)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("※期待値＝ボーダー比に基づく期待損益の合算です。")
                    .font(skin.themedFont(size: 10, weight: .regular))
                    .foregroundColor(skin.subTextColor)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - ③ 初当たり平均投資

    private var firstHitBlock: some View {
        Button(action: cyclePeriod) {
            VStack(alignment: .leading, spacing: 10) {
                Text(statsPeriod.homeFirstHitTitle)
                    .font(skin.themedFont(size: 17, weight: .semibold))
                    .foregroundColor(skin.mainTextColor)
                if let avg = HomeInsightMetrics.averageFirstHitInvestment(in: statsPeriod, sessions: sessions) {
                    Text("\(Int(avg.rounded()).formattedPtWithUnit)")
                        .font(skin.themedFont(size: 18, weight: .semibold, monospaced: true))
                        .foregroundStyle(skin.mainTextColor)
                } else {
                    Text("—")
                        .font(skin.themedFont(size: 18, weight: .semibold, monospaced: true))
                        .foregroundColor(skin.subTextColor.opacity(0.88))
                }
                Text("実戦保存分のみ内部記録。手入力・旧データは平均に含みません。")
                    .font(skin.themedFont(size: 10, weight: .regular))
                    .foregroundColor(skin.subTextColor)
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
        return VStack(alignment: .leading, spacing: 10) {
            Text("直近\(ordered.count)実戦の星取り")
                .font(skin.themedFont(size: 17, weight: .semibold))
                .foregroundColor(skin.mainTextColor)
            HStack(spacing: 4) {
                ForEach(ordered, id: \.id) { s in
                    VStack(spacing: 2) {
                        Text(s.performance >= 0 ? "○" : "●")
                            .font(skin.themedFont(size: 14, weight: .bold))
                            .foregroundColor(s.performance >= 0 ? accent : lossPink)
                        Text(s.performance.formattedPtCompactK)
                            .font(skin.themedFont(size: 9, weight: .medium, monospaced: true))
                            .foregroundColor(skin.subTextColor)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .frame(maxWidth: .infinity)
                }
                if ordered.isEmpty {
                    Text("実戦データがありません")
                        .font(skin.themedFont(size: 12, weight: .regular))
                        .foregroundColor(skin.subTextColor.opacity(0.88))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - ⑤ ミニチャート

    private var miniTrendBlock: some View {
        let steps = HomeInsightMetrics.cumulativePerformanceSteps(in: statsPeriod, sessions: sessions)
        let indexed = steps.enumerated().map { ($0.offset, $0.element) }
        let up: Bool = {
            guard steps.count >= 2, let f = steps.first, let l = steps.last else { return false }
            return l > f
        }()
        let down: Bool = {
            guard steps.count >= 2, let f = steps.first, let l = steps.last else { return false }
            return l < f
        }()

        return VStack(alignment: .leading, spacing: 10) {
            Text("累積収支の推移（ミニ）")
                .font(skin.themedFont(size: 17, weight: .semibold))
                .foregroundColor(skin.mainTextColor)
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
                                colors: [accent.opacity(0.95), accent.opacity(0.35)],
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
                        .font(skin.themedFont(size: 10, weight: .medium))
                        .foregroundColor(Color(red: 0.35, green: 0.92, blue: 0.55).opacity(0.9))
                } else if down {
                    Text("推移は右肩下がり。今日は慎重に。")
                        .font(skin.themedFont(size: 10, weight: .medium))
                        .foregroundColor(Color.orange.opacity(0.92))
                }
            } else {
                Text("2ステップ以上の実戦が集まると折れ線が表示されます。")
                    .font(skin.themedFont(size: 11, weight: .regular))
                    .foregroundColor(skin.subTextColor)
                    .frame(height: 40, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - ⑥ 相性 Top3

    private var affinityBlock: some View {
        let window = HomeInsightMetrics.sessions(inLastDays: lookbackDays, from: sessions)
        let top = HomeInsightMetrics.affinityTop3(sessionsInWindow: window)
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("相性の良い台 Top3")
                    .font(skin.themedFont(size: 17, weight: .semibold))
                    .foregroundColor(skin.mainTextColor)
                Spacer(minLength: 0)
                Text("直近\(lookbackDays)日")
                    .font(skin.themedFont(size: 10, weight: .medium))
                    .foregroundColor(skin.subTextColor.opacity(0.88))
            }
            if top.isEmpty {
                Text("対象期間にデータがありません")
                    .font(skin.themedFont(size: 11, weight: .regular))
                    .foregroundColor(skin.subTextColor)
            } else {
                ForEach(Array(top.enumerated()), id: \.offset) { i, row in
                    HStack(alignment: .firstTextBaseline) {
                        Text("\(i + 1). \(row.name)")
                            .font(skin.themedFont(size: 12, weight: .medium))
                            .foregroundColor(skin.mainTextColor)
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        Text(row.deficitSurplus >= 0 ? "+\(row.deficitSurplus.formattedPtWithUnit)" : row.deficitSurplus.formattedPtWithUnit)
                            .font(skin.themedFont(size: 11, weight: .semibold, monospaced: true))
                            .foregroundColor(row.deficitSurplus >= 0 ? accent : lossPink)
                    }
                }
            }
            Text("並び：期待値に対する余剰が大きい順（期待値より上振れしている度合いの目安）。")
                .font(skin.themedFont(size: 9, weight: .regular))
                .foregroundColor(skin.subTextColor.opacity(0.88))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - ⑦ 回転率リーダー

    private var rotationBlock: some View {
        let window = HomeInsightMetrics.sessions(inLastDays: lookbackDays, from: sessions)
        let leaders = HomeInsightMetrics.rotationLeadersTop3(sessionsInWindow: window)
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("主力機種の回転率")
                    .font(skin.themedFont(size: 17, weight: .semibold))
                    .foregroundColor(skin.mainTextColor)
                Spacer(minLength: 0)
                Text("直近\(lookbackDays)日")
                    .font(skin.themedFont(size: 10, weight: .medium))
                    .foregroundColor(skin.subTextColor.opacity(0.88))
            }
            if leaders.isEmpty {
                Text("対象期間にデータがありません")
                    .font(skin.themedFont(size: 11, weight: .regular))
                    .foregroundColor(skin.subTextColor)
            } else {
                ForEach(leaders) { row in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(row.name)
                            .font(skin.themedFont(size: 12, weight: .medium))
                            .foregroundColor(skin.mainTextColor)
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        Text(row.avgRotationPer1k.displayFormat("%.1f 回/k"))
                            .font(skin.themedFont(size: 11, weight: .semibold, monospaced: true))
                            .foregroundColor(skin.mainTextColor)
                        if let d = row.avgBorderDiffPer1k, d.isValidForNumericDisplay {
                            Text(d.displayFormat("(%+.1f)"))
                                .font(skin.themedFont(size: 10, weight: .semibold, monospaced: true))
                                .foregroundColor(d >= 0 ? accent : lossPink)
                        }
                    }
                }
            }
            Text("並び：通常回転数の合計が多い機種順。括弧はボーダーとの差（回/1k・各実戦の通常回転数で加重）。")
                .font(skin.themedFont(size: 9, weight: .regular))
                .foregroundColor(skin.subTextColor.opacity(0.88))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

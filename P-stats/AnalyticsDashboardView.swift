import SwiftUI
import SwiftData

/// 分析軸（場所＝釘・相性、時間＝いつが強いか）
enum AnalyticsSegment: String, CaseIterable {
    case shop = "店舗"
    case machine = "機種"
    case manufacturer = "メーカー"
    case month = "月別"
    case year = "年別"
    case weekday = "曜日別"

    var isTimeBased: Bool { self == .month || self == .year || self == .weekday }
}

/// ボトム・セグメント（表示順: ホーム・全般・店舗・機種・メーカー・期間）。期間はタブ切り替えではなくピッカー表示
enum AnalyticsBottomSegment: String, CaseIterable {
    case overview = "全般"
    case shop = "店舗"
    case machine = "機種"
    case manufacturer = "メーカー"
    case period = "期間"
}

/// 期間フィルタ（ドックの「期間」タップで下からシート選択）
enum AnalyticsPeriodFilter: String, CaseIterable {
    case all = "通算"
    case year = "年別"
    case month = "月別"
    case week = "週別"
    case last30 = "直近30日"
    case last7 = "直近7日"

    var label: String { rawValue }

    func filter(_ sessions: [GameSession]) -> [GameSession] {
        let cal = Calendar.current
        let now = Date()
        switch self {
        case .all: return sessions
        case .year: return sessions.filter { cal.isDate($0.date, equalTo: now, toGranularity: .year) }
        case .month: return sessions.filter { cal.isDate($0.date, equalTo: now, toGranularity: .month) }
        case .week: return sessions.filter { cal.isDate($0.date, equalTo: now, toGranularity: .weekOfYear) }
        case .last30:
            guard let from = cal.date(byAdding: .day, value: -30, to: now) else { return sessions }
            return sessions.filter { $0.date >= from }
        case .last7:
            guard let from = cal.date(byAdding: .day, value: -7, to: now) else { return sessions }
            return sessions.filter { $0.date >= from }
        }
    }
}

/// 全体・機種・メーカー一覧用：通常日・7のつく日・ゾロ目だけ（7分割の左3、右4は空白）。同一ファイル内の他 struct から参照するため internal
enum AnalyticsFixedSpecificDayLabels {
    static let list: [String] = ["通常日", "7のつく日", "ゾロ目"]
}

// MARK: - 分析フッター（ドック。ホーム・全般・店舗・機種・メーカー・期間）
private struct AnalyticsBottomBarView: View {
    @Binding var bottomSegment: AnalyticsBottomSegment
    @Binding var selectedFilterLabel: String?
    @Binding var periodFilter: AnalyticsPeriodFilter
    @Binding var showPeriodSheet: Bool
    /// 子ページにいる時にタブを押したら分析トップへ戻る（dismiss 用）
    var onSegmentTap: (() -> Void)? = nil
    /// ホームタップでアプリのホーム（分析外）へ戻る
    var onHomeTap: (() -> Void)? = nil

    private var cyan: Color { AppGlassStyle.accent }
    private var mutedGray: Color { Color.white.opacity(0.6) }
    private let iconSize: CGFloat = 18
    private let fontSize: CGFloat = 9

    var body: some View {
        HStack(spacing: 0) {
            Button {
                HapticUtil.impact(.light)
                onHomeTap?()
            } label: {
                VStack(spacing: 3) {
                    Image(systemName: "house.fill")
                        .font(.system(size: iconSize, weight: .medium))
                    Text("ホーム")
                        .font(.system(size: fontSize, weight: .medium, design: .rounded))
                }
                .foregroundColor(mutedGray)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .padding(.horizontal, 4)
            }
            .buttonStyle(.plain)
            .contentShape(Rectangle())
            ForEach([AnalyticsBottomSegment.overview, .shop, .machine, .manufacturer], id: \.self) { seg in
                Button {
                    HapticUtil.impact(.light)
                    withAnimation(.easeInOut(duration: 0.28)) {
                        bottomSegment = seg
                        selectedFilterLabel = nil
                    }
                    onSegmentTap?()
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: seg.icon)
                            .font(.system(size: iconSize, weight: .medium))
                        Text(seg.rawValue)
                            .font(.system(size: fontSize, weight: .medium, design: .rounded))
                    }
                    .foregroundColor(seg == bottomSegment ? .white : mutedGray)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 4)
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
            }
            Button {
                HapticUtil.impact(.light)
                showPeriodSheet = true
            } label: {
                VStack(spacing: 3) {
                    Image(systemName: AnalyticsBottomSegment.period.icon)
                        .font(.system(size: iconSize, weight: .medium))
                    Text(periodFilter.label)
                        .font(.system(size: fontSize, weight: .medium, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .foregroundColor(.white.opacity(0.9))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .padding(.horizontal, 4)
            }
            .buttonStyle(.plain)
            .contentShape(Rectangle())
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 5)
        .background(
            TranslucentBlurView(style: .systemUltraThinMaterialDark, alpha: 1.0)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 28))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 28)
                .stroke(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.35),
                            Color.white.opacity(0.1),
                            Color.white.opacity(0.05)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.8
                )
        )
        .padding(.horizontal, 16)
    }
}

private extension AnalyticsBottomSegment {
    var icon: String {
        switch self {
        case .overview: return "chart.bar.doc.horizontal"
        case .shop: return "mappin.circle.fill"
        case .machine: return "cpu"
        case .manufacturer: return "building.2"
        case .period: return "calendar"
        }
    }
}

/// 分析ダッシュボード（モダン・コンソール／片手操作最適化）
struct AnalyticsDashboardView: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \GameSession.date, order: .reverse) private var sessions: [GameSession]
    @Query private var shops: [Shop]
    @State private var bottomSegment: AnalyticsBottomSegment = .shop
    @State private var periodFilter: AnalyticsPeriodFilter = .all
    @State private var selectedFilterLabel: String?
    @State private var showPeriodSheet: Bool = false

    /// 期間フィルタをかけたセッション（店舗・機種・メーカー共通）
    private var filteredSessions: [GameSession] { periodFilter.filter(sessions) }

    private var effectiveSegment: AnalyticsSegment {
        switch bottomSegment {
        case .overview: return .shop
        case .shop: return .shop
        case .machine: return .machine
        case .manufacturer: return .manufacturer
        case .period: return .month
        }
    }

    private var allGroups: [AnalyticsGroup] {
        switch bottomSegment {
        case .overview: return [AnalyticsEngine.overviewGroup(filteredSessions)]
        case .shop: return AnalyticsEngine.byShop(filteredSessions)
        case .machine: return AnalyticsEngine.byMachine(filteredSessions)
        case .manufacturer: return AnalyticsEngine.byManufacturer(filteredSessions)
        case .period: return []
        }
    }

    private var groups: [AnalyticsGroup] {
        guard let label = selectedFilterLabel else { return allGroups }
        return allGroups.filter { $0.label == label }
    }

    /// 店舗名 → 特定日ルール（分析で優先して使用）
    private var rulesByShopName: [String: SpecificDayRules] {
        Dictionary(uniqueKeysWithValues: shops.map { shop in
            (shop.name, SpecificDayRules.from(dayOfMonthString: shop.specificDayOfMonthStorage, lastDigitsString: shop.specificLastDigitsStorage, rulesStorage: shop.specificDayRulesStorage))
        })
    }

    /// 現在のフィルタで見ているセッション（通算・期待値対比の対象）
    private var sessionsForSummary: [GameSession] {
        guard let label = selectedFilterLabel else { return filteredSessions }
        switch bottomSegment {
        case .overview: return filteredSessions
        case .shop: return filteredSessions.filter { ($0.shopName.isEmpty ? "未設定" : $0.shopName) == label }
        case .machine: return filteredSessions.filter { ($0.machineName.isEmpty ? "未設定" : $0.machineName) == label }
        case .manufacturer: return filteredSessions.filter { (($0.manufacturerName.trimmingCharacters(in: .whitespaces).isEmpty) ? "未設定" : $0.manufacturerName) == label }
        case .period: return filteredSessions
        }
    }

    /// 通算実収支（現在の対象セッションの合計実収支）
    private var totalProfit: Int { sessionsForSummary.reduce(0) { $0 + $1.profit } }
    /// 通算実践回転率（加重平均）＝ 総回転数 ÷ (総実質投資/1000)
    private var weightedAvgRotationPer1k: Double {
        let list = sessionsForSummary
        let totalRotations = list.reduce(0) { $0 + $1.normalRotations }
        let totalCost = list.reduce(0.0) { $0 + $1.totalRealCost }
        guard totalCost > 0 else { return 0 }
        return Double(totalRotations) / (totalCost / 1000.0)
    }
    /// 公式ボーダーとの差の平均（回/千円）。公式未設定のセッションは除外して平均
    private var avgDiffFromFormulaBorder: Double? {
        let list = sessionsForSummary.filter { $0.formulaBorderPer1k > 0 }
        guard !list.isEmpty else { return nil }
        let sum = list.reduce(0.0) { acc, s in
            let cost = s.totalRealCost
            let rate = cost > 0 ? (Double(s.normalRotations) / cost) * 1000.0 : 0
            return acc + (rate - s.formulaBorderPer1k)
        }
        return sum / Double(list.count)
    }

    private var displaySummary: (total: Int, rate: Double) {
        if let label = selectedFilterLabel, let g = allGroups.first(where: { $0.label == label }) {
            return (g.totalDeficitSurplus, g.deficitSurplusRate)
        }
        let totalTheoretical = sessions.reduce(0) { $0 + $1.theoreticalProfit }
        let totalDS = sessions.reduce(0) { $0 + $1.deficitSurplus }
        let rate = totalTheoretical != 0 ? Double(totalDS) / Double(abs(totalTheoretical)) : 0
        return (totalDS, rate)
    }

    private var cyan: Color { AppGlassStyle.accent }
    private var cardBackground: Color { AppGlassStyle.cardBackground }
    private var mutedGray: Color { Color.white.opacity(0.4) }
    private var barBackground: Color { Color.black.opacity(0.4) }

    var body: some View {
        ZStack {
            StaticHomeBackgroundView()
            VStack(spacing: 0) {
                if !sessions.isEmpty {
                    totalSummaryCard
                }
                if groups.isEmpty {
                    emptyState
                } else {
                    listContent
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                bottomSegmentBar
                    .frame(height: 88)
                    .frame(maxHeight: 88)
            }
        }
        .sheet(isPresented: $showPeriodSheet) {
            AnalyticsPeriodPickerSheet(selected: $periodFilter)
        }
        .navigationTitle("分析")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .preferredColorScheme(.dark)
    }

    /// 通算サマリ用の1パネル（キャプション + 値、期待値対比と同じフォント）
    private func summaryPanel(title: String, value: String, valueColor: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(mutedGray)
            Text(value)
                .font(.subheadline.monospacedDigit().weight(.semibold))
                .foregroundColor(valueColor)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(AppGlassStyle.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(AppGlassStyle.strokeGradient, lineWidth: 1)
        )
    }

    /// 一番上：通算実収支・通算実践回転率・ボーダー差・期待値対比の4パネル（独立カード・フォント統一）
    private var totalSummaryCard: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                summaryPanel(
                    title: "通算実収支",
                    value: sessionsForSummary.isEmpty ? "—" : "\(totalProfit >= 0 ? "+" : "")\(totalProfit) 円",
                    valueColor: totalProfit >= 0 ? .green : .red
                )
                summaryPanel(
                    title: "通算実践回転率",
                    value: sessionsForSummary.isEmpty || weightedAvgRotationPer1k <= 0 ? "—" : String(format: "%.1f 回/千円", weightedAvgRotationPer1k),
                    valueColor: .white
                )
            }
            HStack(spacing: 8) {
                summaryPanel(
                    title: "公式ボーダーとの差の平均",
                    value: avgDiffFromFormulaBorder.map { String(format: "%+.1f 回/千円", $0) } ?? "—",
                    valueColor: (avgDiffFromFormulaBorder ?? 0) >= 0 ? cyan : Color.orange
                )
                summaryPanel(
                    title: "期待値対比",
                    value: {
                        let (total, rate) = displaySummary
                        var s = (total >= 0 ? "+" : "") + "\(total) 円"
                        if abs(rate) >= 0.01 { s += " (\(rate >= 0 ? "+" : "")\(Int(round(rate * 100)))%)" }
                        return s
                    }(),
                    valueColor: displaySummary.total >= 0 ? cyan : Color.orange
                )
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 4)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "chart.bar.doc.horizontal")
                .font(.system(size: 48))
                .foregroundColor(cyan.opacity(0.5))
            Text("データがありません")
                .font(.headline)
                .foregroundColor(.white)
            Text("実戦を保存するとここに集計が表示されます")
                .font(.subheadline)
                .foregroundColor(mutedGray)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// 全般・店舗・機種・メーカー一覧では曜日・特定日傾向は出さない。個別店舗/機種/メーカー詳細に入ったときだけ表示する。
    private var listContent: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(spacing: 12) {
                ForEach(groups) { g in
                    Group {
                        if bottomSegment == .overview {
                            NavigationLink(destination: AnalyticsSessionListView(segment: .shop, groupLabel: "全体", sessions: filteredSessions, bottomSegment: $bottomSegment, selectedFilterLabel: $selectedFilterLabel, periodFilter: $periodFilter, showPeriodSheet: $showPeriodSheet)) {
                                AnalyticsGroupCard(group: g, accent: cyan)
                            }
                        } else if bottomSegment == .shop {
                            NavigationLink(destination: AnalyticsShopDetailView(
                                shopName: g.label,
                                sessions: filteredSessions,
                                rulesByShopName: rulesByShopName,
                                orderedSpecificDayLabels: shops.first(where: { $0.name == g.label }).map { SpecificDayRules.orderedLabels(rulesStorage: $0.specificDayRulesStorage, dayOfMonthFallback: $0.specificDayOfMonthStorage, lastDigitsFallback: $0.specificLastDigitsStorage) } ?? [],
                                bottomSegment: $bottomSegment,
                                selectedFilterLabel: $selectedFilterLabel,
                                periodFilter: $periodFilter,
                                showPeriodSheet: $showPeriodSheet
                            )) {
                                AnalyticsGroupCard(group: g, accent: cyan, isShopSegment: true)
                            }
                        } else if bottomSegment == .machine {
                            NavigationLink(destination: AnalyticsMachineDetailView(machineName: g.label, sessions: filteredSessions, rulesByShopName: rulesByShopName, bottomSegment: $bottomSegment, selectedFilterLabel: $selectedFilterLabel, periodFilter: $periodFilter, showPeriodSheet: $showPeriodSheet)) {
                                AnalyticsGroupCard(group: g, accent: cyan)
                            }
                        } else {
                            NavigationLink(destination: AnalyticsManufacturerDetailView(manufacturerName: g.label, sessions: filteredSessions, rulesByShopName: rulesByShopName, bottomSegment: $bottomSegment, selectedFilterLabel: $selectedFilterLabel, periodFilter: $periodFilter, showPeriodSheet: $showPeriodSheet)) {
                                AnalyticsGroupCard(group: g, accent: cyan)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 120)
        }
    }

    private var bottomSegmentBar: some View {
        AnalyticsBottomBarView(
            bottomSegment: $bottomSegment,
            selectedFilterLabel: $selectedFilterLabel,
            periodFilter: $periodFilter,
            showPeriodSheet: $showPeriodSheet,
            onSegmentTap: nil,
            onHomeTap: { dismiss() }
        )
    }
}

// MARK: - 期間ピッカー（下からにゅっと）
private struct AnalyticsPeriodPickerSheet: View {
    @Binding var selected: AnalyticsPeriodFilter
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(AnalyticsPeriodFilter.allCases, id: \.rawValue) { option in
                Button {
                    selected = option
                    dismiss()
                } label: {
                    HStack {
                        Text(option.label)
                            .foregroundColor(.white)
                        if option == selected {
                            Spacer()
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(AppGlassStyle.accent)
                        }
                    }
                }
                .listRowBackground(AppGlassStyle.cardBackground)
            }
            .navigationTitle("期間")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .preferredColorScheme(.dark)
        }
    }
}

/// 大きな数値を k（千）・M（百万）で省略表示（改行防止）
private func compactIntegerLabel(_ n: Int) -> String {
    let sign = n >= 0 ? "+" : ""
    let a = abs(n)
    if a >= 1_000_000 { return "\(sign)\(String(format: "%.1f", Double(a) / 1_000_000))M" }
    if a >= 1000 { return "\(sign)\(String(format: "%.1f", Double(a) / 1000))k" }
    return "\(sign)\(n)"
}

// MARK: - 曜日傾向（ゼロ中央：実収支・欠損余剰は正=上・負=下、回転率は0〜max）
private struct WeekdayTendencySection: View {
    let groups: [AnalyticsGroup]
    let accent: Color

    private let barMaxHeight: CGFloat = 56
    private let labelHeight: CGFloat = 28

    private var maxAbsProfit: Int { max(1, groups.map { abs($0.totalProfit) }.max() ?? 1) }
    private var maxRate: Double { groups.map(\.avgRotationRate).max() ?? 1 }
    private var maxAbsDS: Int { max(1, groups.map { abs($0.totalDeficitSurplus) }.max() ?? 1) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("曜日傾向")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.white.opacity(0.8))
                .padding(.horizontal, 4)
            VStack(alignment: .leading, spacing: 12) {
                rowZeroCentered(title: "実収支", groups: groups, maxAbs: maxAbsProfit) { g in (g.totalProfit, g.totalProfit >= 0 ? Color.green : Color.orange, compactIntegerLabel(g.totalProfit)) }
                row(title: "回転率（回/千円）", groups: groups) { g in (maxRate > 0 ? g.avgRotationRate / maxRate : 0, accent, String(format: "%.1f", g.avgRotationRate)) }
                rowZeroCentered(title: "欠損・余剰", groups: groups, maxAbs: maxAbsDS) { g in (g.totalDeficitSurplus, g.totalDeficitSurplus >= 0 ? Color.cyan : Color.orange, compactIntegerLabel(g.totalDeficitSurplus)) }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppGlassStyle.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(AppGlassStyle.strokeGradient, lineWidth: 1))
        }
    }

    private func row(title: String, groups: [AnalyticsGroup], value: @escaping (AnalyticsGroup) -> (scale: CGFloat, color: Color, text: String)) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundColor(.white.opacity(0.7))
            HStack(alignment: .bottom, spacing: 0) {
                ForEach(groups) { g in
                    let v = value(g)
                    barGroup(label: g.label, scale: v.scale, color: v.color, valueText: v.text)
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(height: barMaxHeight + labelHeight)
        }
    }

    private func rowZeroCentered(title: String, groups: [AnalyticsGroup], maxAbs: Int, value: @escaping (AnalyticsGroup) -> (value: Int, color: Color, text: String)) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundColor(.white.opacity(0.7))
            HStack(alignment: .center, spacing: 0) {
                ForEach(groups) { g in
                    let v = value(g)
                    barGroupZeroCentered(label: g.label, value: v.value, maxAbs: maxAbs, color: v.color, valueText: v.text)
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(height: barMaxHeight + labelHeight)
        }
    }

    private func barGroup(label: String, scale: CGFloat, color: Color, valueText: String) -> some View {
        let height = min(barMaxHeight, max(2, scale * barMaxHeight))
        return VStack(spacing: 4) {
            Spacer(minLength: 0)
            GeometryReader { geo in
                HStack(spacing: 0) {
                    Spacer(minLength: 0)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(color.opacity(0.9))
                        .frame(width: max(4, geo.size.width * 0.4), height: height)
                    Spacer(minLength: 0)
                }
            }
            .frame(height: barMaxHeight)
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(.white.opacity(0.8))
                .lineLimit(1)
            Text(valueText)
                .font(.system(size: 8, weight: .medium, design: .monospaced))
                .foregroundColor(color)
                .lineLimit(1)
        }
    }

    private func barGroupZeroCentered(label: String, value: Int, maxAbs: Int, color: Color, valueText: String) -> some View {
        let half = barMaxHeight / 2
        let barLen = maxAbs > 0 ? min(half, max(2, CGFloat(abs(value)) / CGFloat(maxAbs) * half)) : 0
        return VStack(spacing: 4) {
            GeometryReader { geo in
                let center = geo.size.height / 2
                let w = max(4, geo.size.width * 0.4)
                ZStack(alignment: .top) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.white.opacity(0.15))
                        .frame(width: w, height: 1)
                        .position(x: geo.size.width / 2, y: center)
                    if value != 0 {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(color.opacity(0.9))
                            .frame(width: w, height: barLen)
                            .position(x: geo.size.width / 2, y: value >= 0 ? center - barLen / 2 : center + barLen / 2)
                    }
                }
            }
            .frame(height: barMaxHeight)
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(.white.opacity(0.8))
                .lineLimit(1)
            Text(valueText)
                .font(.system(size: 8, weight: .medium, design: .monospaced))
                .foregroundColor(color)
                .lineLimit(1)
        }
    }
}

// MARK: - 特定日傾向（ゼロ中央：実収支・欠損余剰は正=上・負=下。_pad は空白セル）
private struct SpecificDayBarChartSection: View {
    let groups: [AnalyticsGroup]
    let accent: Color
    /// 指定時はこの数で幅を等分（全体ページで7、右側を空白に）
    var fixedSegmentCount: Int? = nil

    private let barMaxHeight: CGFloat = 72
    private let labelHeight: CGFloat = 32

    private var displayGroups: [AnalyticsGroup] {
        guard let n = fixedSegmentCount, groups.count < n else { return groups }
        return groups + (1...(n - groups.count)).map { AnalyticsEngine.emptyGroup(label: "_pad\($0)") }
    }

    private var dataGroups: [AnalyticsGroup] { groups.filter { !$0.label.hasPrefix("_pad") } }
    private var maxAbsProfit: Int { max(1, dataGroups.map { abs($0.totalProfit) }.max() ?? 1) }
    private var maxRate: Double { dataGroups.map(\.avgRotationRate).max() ?? 1 }
    private var maxAbsDS: Int { max(1, dataGroups.map { abs($0.totalDeficitSurplus) }.max() ?? 1) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("特定日傾向")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.white.opacity(0.8))
                .padding(.horizontal, 4)
            VStack(alignment: .leading, spacing: 14) {
                rowZeroCentered(title: "実収支", groups: displayGroups, maxAbs: maxAbsProfit) { g in (g.totalProfit, g.totalProfit >= 0 ? Color.green : Color.orange, compactIntegerLabel(g.totalProfit)) }
                row(title: "回転率（回/千円）", groups: displayGroups) { g in (maxRate > 0 ? g.avgRotationRate / maxRate : 0, accent, String(format: "%.1f", g.avgRotationRate)) }
                rowZeroCentered(title: "欠損・余剰", groups: displayGroups, maxAbs: maxAbsDS) { g in (g.totalDeficitSurplus, g.totalDeficitSurplus >= 0 ? Color.cyan : Color.orange, compactIntegerLabel(g.totalDeficitSurplus)) }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppGlassStyle.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(AppGlassStyle.strokeGradient, lineWidth: 1))
        }
    }

    private func row(title: String, groups: [AnalyticsGroup], value: @escaping (AnalyticsGroup) -> (scale: CGFloat, color: Color, text: String)) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundColor(.white.opacity(0.7))
            HStack(alignment: .bottom, spacing: 0) {
                ForEach(groups) { g in
                    let v = value(g)
                    barGroup(label: g.label, scale: v.scale, color: v.color, valueText: v.text)
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(height: barMaxHeight + labelHeight)
        }
    }

    private func rowZeroCentered(title: String, groups: [AnalyticsGroup], maxAbs: Int, value: @escaping (AnalyticsGroup) -> (value: Int, color: Color, text: String)) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundColor(.white.opacity(0.7))
            HStack(alignment: .center, spacing: 0) {
                ForEach(groups) { g in
                    let v = value(g)
                    barGroupZeroCentered(label: g.label, value: v.value, maxAbs: maxAbs, color: v.color, valueText: v.text)
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(height: barMaxHeight + labelHeight)
        }
    }

    private func barGroup(label: String, scale: CGFloat, color: Color, valueText: String) -> some View {
        let isPad = label.hasPrefix("_pad")
        let height = isPad ? 0 : min(barMaxHeight, max(2, scale * barMaxHeight))
        return VStack(spacing: 4) {
            Spacer(minLength: 0)
            if !isPad {
                GeometryReader { geo in
                    HStack(spacing: 0) {
                        Spacer(minLength: 0)
                        RoundedRectangle(cornerRadius: 3)
                            .fill(color.opacity(0.9))
                            .frame(width: max(4, geo.size.width * 0.4), height: height)
                        Spacer(minLength: 0)
                    }
                }
                .frame(height: barMaxHeight)
            } else {
                Color.clear.frame(height: barMaxHeight)
            }
            Text(isPad ? "" : label)
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(.white.opacity(0.8))
                .lineLimit(1)
            Text(isPad ? "" : valueText)
                .font(.system(size: 8, weight: .medium, design: .monospaced))
                .foregroundColor(color)
                .lineLimit(1)
        }
    }

    private func barGroupZeroCentered(label: String, value: Int, maxAbs: Int, color: Color, valueText: String) -> some View {
        let isPad = label.hasPrefix("_pad")
        let half = barMaxHeight / 2
        let barLen = isPad ? 0 : (maxAbs > 0 ? min(half, max(2, CGFloat(abs(value)) / CGFloat(maxAbs) * half)) : 0)
        return VStack(spacing: 4) {
            GeometryReader { geo in
                let center = geo.size.height / 2
                let w = max(4, geo.size.width * 0.4)
                ZStack(alignment: .top) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.white.opacity(0.15))
                        .frame(width: w, height: 1)
                        .position(x: geo.size.width / 2, y: center)
                    if !isPad && value != 0 {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(color.opacity(0.9))
                            .frame(width: w, height: barLen)
                            .position(x: geo.size.width / 2, y: value >= 0 ? center - barLen / 2 : center + barLen / 2)
                    }
                }
            }
            .frame(height: barMaxHeight)
            Text(isPad ? "" : label)
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(.white.opacity(0.8))
                .lineLimit(1)
            Text(isPad ? "" : valueText)
                .font(.system(size: 8, weight: .medium, design: .monospaced))
                .foregroundColor(color)
                .lineLimit(1)
        }
    }
}

/// 分析用セッションカード（実戦履歴カードと同じレイアウト・同一ファイル内で参照）
private struct AnalyticsSessionCardView: View {
    let session: GameSession
    private var rotationPer1k: Double {
        guard session.totalRealCost > 0 else { return 0 }
        return (Double(session.normalRotations) / session.totalRealCost) * 1000
    }
    /// 実践回転率の表示文字列（公式ボーダーとの差を括弧内に表示）
    private var rotationRateDisplay: String {
        if rotationPer1k <= 0 { return "—" }
        var s = String(format: "%.1f 回/千円", rotationPer1k)
        if session.formulaBorderPer1k > 0 {
            let diff = rotationPer1k - session.formulaBorderPer1k
            s += " (\(diff >= 0 ? "+" : "")\(String(format: "%.1f", diff)))"
        }
        return s
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(session.machineName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white)
                Spacer()
                Text(session.shopName)
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.8))
            }
            HStack(spacing: 16) {
                Text("実収支 \(session.profit >= 0 ? "+" : "")\(session.profit) 円")
                    .font(.subheadline.monospacedDigit().weight(.medium))
                    .foregroundColor(session.profit >= 0 ? .green : .red)
                Text("大当たり RUSH:\(session.rushWinCount) 通常:\(session.normalWinCount)")
                    .font(.subheadline.monospacedDigit())
                    .foregroundColor(.white.opacity(0.85))
            }
            HStack(spacing: 12) {
                labelVal("総回転", "\(session.normalRotations)")
                Text("・").foregroundColor(.white.opacity(0.5))
                labelVal("投資", "\(session.investmentCash)円")
                Text("・").foregroundColor(.white.opacity(0.5))
                labelVal("回収玉", "\(session.totalHoldings)")
            }
            .font(.caption)
            .foregroundColor(.white.opacity(0.85))
            HStack(alignment: .top, spacing: 16) {
                miniblock("実践回転率", value: rotationRateDisplay, valueColor: .white)
                miniblock("理論期待値", value: "\(session.theoreticalProfit >= 0 ? "+" : "")\(session.theoreticalProfit)円", valueColor: .white.opacity(0.9))
                deficitSurplusBlock
            }
            .font(.caption)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppGlassStyle.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(AppGlassStyle.strokeGradient, lineWidth: 1)
        )
    }
    private var deficitSurplusBlock: some View {
        Group {
            if session.deficitSurplus > 0 {
                miniblock("余剰", value: "+\(session.deficitSurplus)円", valueColor: .green.opacity(0.9))
            } else if session.deficitSurplus < 0 {
                miniblock("欠損", value: "\(session.deficitSurplus)円", valueColor: .red.opacity(0.9))
            } else {
                miniblock("余剰・欠損", value: "0円", valueColor: .white.opacity(0.8))
            }
        }
    }
    private func miniblock(_ label: String, value: String, valueColor: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .foregroundColor(.white.opacity(0.65))
            Text(value)
                .font(.caption.monospacedDigit().weight(.medium))
                .foregroundColor(valueColor)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
    }
    private func labelVal(_ label: String, _ value: String) -> some View {
        HStack(spacing: 4) {
            Text(label + ":").foregroundColor(.white.opacity(0.65))
            Text(value).foregroundColor(.white)
        }
    }
}

/// 分析用セッション詳細（同一ファイル内で参照・実戦履歴詳細と同じ内容）
private struct AnalyticsSessionDetailView: View {
    let session: GameSession
    let sessions: [GameSession]
    @Binding var bottomSegment: AnalyticsBottomSegment
    @Binding var selectedFilterLabel: String?
    @Binding var periodFilter: AnalyticsPeriodFilter
    @Binding var showPeriodSheet: Bool
    /// 親（一覧 or 店舗詳細）の dismiss。タブ押下で分析トップへ戻るため
    var onDismissToRoot: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss

    private var recoveryYen: Int { Int(Double(session.totalHoldings) * session.exchangeRate) }
    private var rotationPer1k: Double {
        guard session.investmentCash > 0 else { return 0 }
        return Double(session.normalRotations) / (Double(session.investmentCash) / 1000.0)
    }
    var body: some View {
        List {
            Section("記録日時") {
                Text(session.date, style: .date).listRowBackground(AppGlassStyle.rowBackground)
                Text(session.date, style: .time).listRowBackground(AppGlassStyle.rowBackground)
            }
            Section("機種・店舗") {
                LabeledContent("機種", value: session.machineName).listRowBackground(AppGlassStyle.rowBackground)
                LabeledContent("店舗", value: session.shopName).listRowBackground(AppGlassStyle.rowBackground)
            }
            Section("数値サマリ") {
                LabeledContent("総回転数", value: "\(session.normalRotations)").listRowBackground(AppGlassStyle.rowBackground)
                LabeledContent("大当たり", value: "RUSH: \(session.rushWinCount) / 通常: \(session.normalWinCount)").listRowBackground(AppGlassStyle.rowBackground)
                LabeledContent("総投資額（現金）", value: "\(session.investmentCash) 円").listRowBackground(AppGlassStyle.rowBackground)
                LabeledContent("回収出球", value: "\(session.totalHoldings) 玉").listRowBackground(AppGlassStyle.rowBackground)
                LabeledContent("回収額（円換算）", value: "\(recoveryYen) 円").listRowBackground(AppGlassStyle.rowBackground)
                LabeledContent("理論期待値", value: "\(session.theoreticalProfit >= 0 ? "+" : "")\(session.theoreticalProfit) 円").listRowBackground(AppGlassStyle.rowBackground)
                LabeledContent("欠損・余剰", value: "\(session.deficitSurplus >= 0 ? "+" : "")\(session.deficitSurplus) 円").listRowBackground(AppGlassStyle.rowBackground)
                LabeledContent("実収支", value: "\(session.profit >= 0 ? "+" : "")\(session.profit) 円")
                    .font(.body.weight(.semibold))
                    .foregroundColor(session.profit >= 0 ? .green : .red)
                    .listRowBackground(AppGlassStyle.rowBackground)
            }
            Section("分析") {
                LabeledContent("期待値比（保存時）", value: session.expectationRatioAtSave > 0 ? String(format: "%.2f", session.expectationRatioAtSave) : "—").listRowBackground(AppGlassStyle.rowBackground)
                LabeledContent("実質回転率", value: String(format: "%.1f 回/千円", rotationPer1k)).listRowBackground(AppGlassStyle.rowBackground)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(AppGlassStyle.background)
        .navigationTitle("履歴詳細")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .preferredColorScheme(.dark)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            AnalyticsBottomBarView(bottomSegment: $bottomSegment, selectedFilterLabel: $selectedFilterLabel, periodFilter: $periodFilter, showPeriodSheet: $showPeriodSheet, onSegmentTap: {
                dismiss()
                DispatchQueue.main.async { onDismissToRoot?() }
            })
                .frame(height: 88)
                .frame(maxHeight: 88)
        }
    }
}

/// 分析対象の遊戯履歴一覧（新しい順）。期間タブ削除によりメインからは使わず、必要時用
struct AnalyticsSessionListView: View {
    let segment: AnalyticsSegment
    let groupLabel: String
    let sessions: [GameSession]
    @Binding var bottomSegment: AnalyticsBottomSegment
    @Binding var selectedFilterLabel: String?
    @Binding var periodFilter: AnalyticsPeriodFilter
    @Binding var showPeriodSheet: Bool

    @Environment(\.dismiss) private var dismiss

    private var filteredSessions: [GameSession] {
        if groupLabel == "全体" {
            return sessions.sorted { $0.date > $1.date }
        }
        let list: [GameSession]
        switch segment {
        case .shop:
            list = sessions.filter { ($0.shopName.isEmpty ? "未設定" : $0.shopName) == groupLabel }
        case .machine:
            list = sessions.filter { ($0.machineName.isEmpty ? "未設定" : $0.machineName) == groupLabel }
        case .manufacturer:
            list = sessions.filter { (($0.manufacturerName.trimmingCharacters(in: .whitespaces).isEmpty) ? "未設定" : $0.manufacturerName) == groupLabel }
        case .month:
            list = sessions.filter { AnalyticsEngine.monthKey(from: $0.date) == groupLabel }
        case .year:
            list = sessions.filter { AnalyticsEngine.yearLabel(from: $0.date) == groupLabel }
        case .weekday:
            list = sessions.filter { AnalyticsEngine.weekdayLabel(from: $0.date) == groupLabel }
        }
        return list.sorted { $0.date > $1.date }
    }

    var body: some View {
        ZStack {
            StaticHomeBackgroundView()
            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 12) {
                    ForEach(filteredSessions) { session in
                        NavigationLink(destination: AnalyticsSessionDetailView(session: session, sessions: sessions, bottomSegment: $bottomSegment, selectedFilterLabel: $selectedFilterLabel, periodFilter: $periodFilter, showPeriodSheet: $showPeriodSheet, onDismissToRoot: { DispatchQueue.main.async { dismiss() } })) {
                            AnalyticsSessionCardView(session: session)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 120)
            }
        }
        .navigationTitle(groupLabel)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .preferredColorScheme(.dark)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            AnalyticsBottomBarView(bottomSegment: $bottomSegment, selectedFilterLabel: $selectedFilterLabel, periodFilter: $periodFilter, showPeriodSheet: $showPeriodSheet, onSegmentTap: { dismiss() })
                .frame(height: 88)
                .frame(maxHeight: 88)
        }
    }
}

/// 店舗別分析ページ（通算サマリ＋曜日・特定日傾向＋履歴パネル）
private struct AnalyticsShopDetailView: View {
    let shopName: String
    let sessions: [GameSession]
    let rulesByShopName: [String: SpecificDayRules]
    /// この店舗で設定した特定日ラベル（追加順、最大4つ）。例: ["毎月13日", "5のつく日"]
    let orderedSpecificDayLabels: [String]
    @Binding var bottomSegment: AnalyticsBottomSegment
    @Binding var selectedFilterLabel: String?
    @Binding var periodFilter: AnalyticsPeriodFilter
    @Binding var showPeriodSheet: Bool

    @Environment(\.dismiss) private var dismiss

    private var shopSessions: [GameSession] {
        sessions.filter { ($0.shopName.isEmpty ? "未設定" : $0.shopName) == shopName }
            .sorted { $0.date > $1.date }
    }

    private var weekdayGroups: [AnalyticsGroup] {
        let byWeekday = AnalyticsEngine.byWeekday(shopSessions)
        let order = ["日曜", "月曜", "火曜", "水曜", "木曜", "金曜", "土曜"]
        return order.map { day in byWeekday.first(where: { $0.label == day }) ?? AnalyticsEngine.emptyGroup(label: day) }
    }

    /// 個別店舗用：通常日 + 設定した特定日（最大4つ）+ ゾロ目。7分割表示
    private var specificDayGroups: [AnalyticsGroup] {
        let fromAttr = AnalyticsEngine.bySpecificDayAttribute(shopSessions, rulesByShopName: rulesByShopName)
        let byLabel = Dictionary(uniqueKeysWithValues: fromAttr.map { ($0.label, $0) })
        let labels = ["通常日"] + orderedSpecificDayLabels.prefix(4) + ["ゾロ目"]
        return labels.map { byLabel[$0] ?? AnalyticsEngine.emptyGroup(label: $0) }
    }

    private var totalProfit: Int { shopSessions.reduce(0) { $0 + $1.profit } }
    private var weightedAvgRotationPer1k: Double {
        let totalRotations = shopSessions.reduce(0) { $0 + $1.normalRotations }
        let totalCost = shopSessions.reduce(0.0) { $0 + $1.totalRealCost }
        guard totalCost > 0 else { return 0 }
        return Double(totalRotations) / (totalCost / 1000.0)
    }
    private var avgDiffFromFormulaBorder: Double? {
        let list = shopSessions.filter { $0.formulaBorderPer1k > 0 }
        guard !list.isEmpty else { return nil }
        let sum = list.reduce(0.0) { acc, s in
            let rate = s.totalRealCost > 0 ? (Double(s.normalRotations) / s.totalRealCost) * 1000.0 : 0
            return acc + (rate - s.formulaBorderPer1k)
        }
        return sum / Double(list.count)
    }
    private var displaySummary: (total: Int, rate: Double) {
        let g = AnalyticsEngine.byShop(sessions).first { $0.label == shopName }
        guard let g = g else {
            let totalTheoretical = shopSessions.reduce(0) { $0 + $1.theoreticalProfit }
            let totalDS = shopSessions.reduce(0) { $0 + $1.deficitSurplus }
            let rate = totalTheoretical != 0 ? Double(totalDS) / Double(abs(totalTheoretical)) : 0
            return (totalDS, rate)
        }
        return (g.totalDeficitSurplus, g.deficitSurplusRate)
    }

    private var cyan: Color { AppGlassStyle.accent }
    private var mutedGray: Color { Color.white.opacity(0.4) }

    private func summaryPanel(title: String, value: String, valueColor: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(mutedGray)
            Text(value)
                .font(.subheadline.monospacedDigit().weight(.semibold))
                .foregroundColor(valueColor)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(AppGlassStyle.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(AppGlassStyle.strokeGradient, lineWidth: 1)
        )
    }

    var body: some View {
        ZStack {
            StaticHomeBackgroundView()
            ScrollView(showsIndicators: false) {
                VStack(spacing: 12) {
                    VStack(spacing: 8) {
                        HStack(spacing: 8) {
                            summaryPanel(
                                title: "通算実収支",
                                value: shopSessions.isEmpty ? "—" : "\(totalProfit >= 0 ? "+" : "")\(totalProfit) 円",
                                valueColor: totalProfit >= 0 ? .green : .red
                            )
                            summaryPanel(
                                title: "通算実践回転率",
                                value: shopSessions.isEmpty || weightedAvgRotationPer1k <= 0 ? "—" : String(format: "%.1f 回/千円", weightedAvgRotationPer1k),
                                valueColor: .white
                            )
                        }
                        HStack(spacing: 8) {
                            summaryPanel(
                                title: "公式ボーダーとの差の平均",
                                value: avgDiffFromFormulaBorder.map { String(format: "%+.1f 回/千円", $0) } ?? "—",
                                valueColor: (avgDiffFromFormulaBorder ?? 0) >= 0 ? cyan : Color.orange
                            )
                            summaryPanel(
                                title: "期待値対比",
                                value: shopSessions.isEmpty ? "—" : {
                                    let (total, rate) = displaySummary
                                    var s = (total >= 0 ? "+" : "") + "\(total) 円"
                                    if abs(rate) >= 0.01 { s += " (\(rate >= 0 ? "+" : "")\(Int(round(rate * 100)))%)" }
                                    return s
                                }(),
                                valueColor: displaySummary.total >= 0 ? cyan : Color.orange
                            )
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)

                    if !shopSessions.isEmpty {
                        VStack(alignment: .leading, spacing: 20) {
                            WeekdayTendencySection(groups: weekdayGroups, accent: cyan)
                            SpecificDayBarChartSection(groups: specificDayGroups, accent: cyan, fixedSegmentCount: 7)
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 4)
                        .padding(.bottom, 8)
                    }

                    Text("この店舗の履歴")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.white.opacity(0.8))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20)
                        .padding(.top, 8)

                    LazyVStack(spacing: 12) {
                        ForEach(shopSessions) { session in
                            NavigationLink(destination: AnalyticsSessionDetailView(session: session, sessions: sessions, bottomSegment: $bottomSegment, selectedFilterLabel: $selectedFilterLabel, periodFilter: $periodFilter, showPeriodSheet: $showPeriodSheet, onDismissToRoot: { DispatchQueue.main.async { dismiss() } })) {
                                AnalyticsSessionCardView(session: session)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 120)
                }
            }
        }
        .navigationTitle(shopName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .preferredColorScheme(.dark)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            AnalyticsBottomBarView(bottomSegment: $bottomSegment, selectedFilterLabel: $selectedFilterLabel, periodFilter: $periodFilter, showPeriodSheet: $showPeriodSheet, onSegmentTap: { dismiss() })
                .frame(height: 88)
                .frame(maxHeight: 88)
        }
    }
}

/// 機種別分析ページ（店舗詳細と同様に上部サマリ＋曜日・特定日傾向＋履歴）
private struct AnalyticsMachineDetailView: View {
    let machineName: String
    let sessions: [GameSession]
    let rulesByShopName: [String: SpecificDayRules]
    @Binding var bottomSegment: AnalyticsBottomSegment
    @Binding var selectedFilterLabel: String?
    @Binding var periodFilter: AnalyticsPeriodFilter
    @Binding var showPeriodSheet: Bool
    @Environment(\.dismiss) private var dismiss

    private var machineSessions: [GameSession] {
        sessions.filter { ($0.machineName.isEmpty ? "未設定" : $0.machineName) == machineName }
            .sorted { $0.date > $1.date }
    }

    private var weekdayGroups: [AnalyticsGroup] {
        let byWeekday = AnalyticsEngine.byWeekday(machineSessions)
        let order = ["日曜", "月曜", "火曜", "水曜", "木曜", "金曜", "土曜"]
        return order.map { day in byWeekday.first(where: { $0.label == day }) ?? AnalyticsEngine.emptyGroup(label: day) }
    }

    /// 機種全体では通常日・7のつく日・ゾロ目の3つのみ、7分割
    private var specificDayGroups: [AnalyticsGroup] {
        let fromAttr = AnalyticsEngine.bySpecificDayAttribute(machineSessions, rulesByShopName: rulesByShopName)
        let byLabel = Dictionary(uniqueKeysWithValues: fromAttr.map { ($0.label, $0) })
        return AnalyticsFixedSpecificDayLabels.list.map { byLabel[$0] ?? AnalyticsEngine.emptyGroup(label: $0) }
    }
    private var totalProfit: Int { machineSessions.reduce(0) { $0 + $1.profit } }
    private var weightedAvgRotationPer1k: Double {
        let totalRotations = machineSessions.reduce(0) { $0 + $1.normalRotations }
        let totalCost = machineSessions.reduce(0.0) { $0 + $1.totalRealCost }
        guard totalCost > 0 else { return 0 }
        return Double(totalRotations) / (totalCost / 1000.0)
    }
    private var avgDiffFromFormulaBorder: Double? {
        let list = machineSessions.filter { $0.formulaBorderPer1k > 0 }
        guard !list.isEmpty else { return nil }
        return list.reduce(0.0) { acc, s in
            let rate = s.totalRealCost > 0 ? (Double(s.normalRotations) / s.totalRealCost) * 1000.0 : 0
            return acc + (rate - s.formulaBorderPer1k)
        } / Double(list.count)
    }
    private var displaySummary: (total: Int, rate: Double) {
        let g = AnalyticsEngine.byMachine(sessions).first { $0.label == machineName }
        guard let g = g else {
            let totalTheoretical = machineSessions.reduce(0) { $0 + $1.theoreticalProfit }
            let totalDS = machineSessions.reduce(0) { $0 + $1.deficitSurplus }
            let rate = totalTheoretical != 0 ? Double(totalDS) / Double(abs(totalTheoretical)) : 0
            return (totalDS, rate)
        }
        return (g.totalDeficitSurplus, g.deficitSurplusRate)
    }
    private var cyan: Color { AppGlassStyle.accent }
    private var mutedGray: Color { Color.white.opacity(0.4) }
    private func summaryPanel(title: String, value: String, valueColor: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(mutedGray)
            Text(value).font(.subheadline.monospacedDigit().weight(.semibold)).foregroundColor(valueColor)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(AppGlassStyle.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(AppGlassStyle.strokeGradient, lineWidth: 1))
    }

    var body: some View {
        ZStack {
            StaticHomeBackgroundView()
            ScrollView(showsIndicators: false) {
                VStack(spacing: 12) {
                    VStack(spacing: 8) {
                        HStack(spacing: 8) {
                            summaryPanel(title: "通算実収支", value: machineSessions.isEmpty ? "—" : "\(totalProfit >= 0 ? "+" : "")\(totalProfit) 円", valueColor: totalProfit >= 0 ? .green : .red)
                            summaryPanel(title: "通算実践回転率", value: machineSessions.isEmpty || weightedAvgRotationPer1k <= 0 ? "—" : String(format: "%.1f 回/千円", weightedAvgRotationPer1k), valueColor: .white)
                        }
                        HStack(spacing: 8) {
                            summaryPanel(title: "公式ボーダーとの差の平均", value: avgDiffFromFormulaBorder.map { String(format: "%+.1f 回/千円", $0) } ?? "—", valueColor: (avgDiffFromFormulaBorder ?? 0) >= 0 ? cyan : Color.orange)
                            summaryPanel(title: "期待値対比", value: machineSessions.isEmpty ? "—" : { let (total, rate) = displaySummary; var s = (total >= 0 ? "+" : "") + "\(total) 円"; if abs(rate) >= 0.01 { s += " (\(rate >= 0 ? "+" : "")\(Int(round(rate * 100)))%)" }; return s }(), valueColor: displaySummary.total >= 0 ? cyan : Color.orange)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    if !machineSessions.isEmpty {
                        VStack(alignment: .leading, spacing: 20) {
                            WeekdayTendencySection(groups: weekdayGroups, accent: cyan)
                            SpecificDayBarChartSection(groups: specificDayGroups, accent: cyan, fixedSegmentCount: 7)
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 4)
                        .padding(.bottom, 8)
                    }
                    Text("この機種の履歴")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.white.opacity(0.8))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                    LazyVStack(spacing: 12) {
                        ForEach(machineSessions) { session in
                            NavigationLink(destination: AnalyticsSessionDetailView(session: session, sessions: sessions, bottomSegment: $bottomSegment, selectedFilterLabel: $selectedFilterLabel, periodFilter: $periodFilter, showPeriodSheet: $showPeriodSheet, onDismissToRoot: { DispatchQueue.main.async { dismiss() } })) {
                                AnalyticsSessionCardView(session: session)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 120)
                }
            }
        }
        .navigationTitle(machineName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .preferredColorScheme(.dark)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            AnalyticsBottomBarView(bottomSegment: $bottomSegment, selectedFilterLabel: $selectedFilterLabel, periodFilter: $periodFilter, showPeriodSheet: $showPeriodSheet, onSegmentTap: { dismiss() })
                .frame(height: 88)
                .frame(maxHeight: 88)
        }
    }
}

/// メーカー別分析ページ（店舗・機種と同様に上部サマリ＋曜日・特定日傾向＋履歴）
private struct AnalyticsManufacturerDetailView: View {
    let manufacturerName: String
    let sessions: [GameSession]
    let rulesByShopName: [String: SpecificDayRules]
    @Binding var bottomSegment: AnalyticsBottomSegment
    @Binding var selectedFilterLabel: String?
    @Binding var periodFilter: AnalyticsPeriodFilter
    @Binding var showPeriodSheet: Bool
    @Environment(\.dismiss) private var dismiss

    private var manufacturerSessions: [GameSession] {
        let key = manufacturerName.trimmingCharacters(in: .whitespaces).isEmpty ? "未設定" : manufacturerName
        return sessions.filter { ($0.manufacturerName.trimmingCharacters(in: .whitespaces).isEmpty ? "未設定" : $0.manufacturerName) == key }
            .sorted { $0.date > $1.date }
    }

    private var weekdayGroups: [AnalyticsGroup] {
        let byWeekday = AnalyticsEngine.byWeekday(manufacturerSessions)
        let order = ["日曜", "月曜", "火曜", "水曜", "木曜", "金曜", "土曜"]
        return order.map { day in byWeekday.first(where: { $0.label == day }) ?? AnalyticsEngine.emptyGroup(label: day) }
    }

    /// メーカー全体では通常日・7のつく日・ゾロ目の3つのみ、7分割
    private var specificDayGroups: [AnalyticsGroup] {
        let fromAttr = AnalyticsEngine.bySpecificDayAttribute(manufacturerSessions, rulesByShopName: rulesByShopName)
        let byLabel = Dictionary(uniqueKeysWithValues: fromAttr.map { ($0.label, $0) })
        return AnalyticsFixedSpecificDayLabels.list.map { byLabel[$0] ?? AnalyticsEngine.emptyGroup(label: $0) }
    }
    private var totalProfit: Int { manufacturerSessions.reduce(0) { $0 + $1.profit } }
    private var weightedAvgRotationPer1k: Double {
        let totalRotations = manufacturerSessions.reduce(0) { $0 + $1.normalRotations }
        let totalCost = manufacturerSessions.reduce(0.0) { $0 + $1.totalRealCost }
        guard totalCost > 0 else { return 0 }
        return Double(totalRotations) / (totalCost / 1000.0)
    }
    private var avgDiffFromFormulaBorder: Double? {
        let list = manufacturerSessions.filter { $0.formulaBorderPer1k > 0 }
        guard !list.isEmpty else { return nil }
        return list.reduce(0.0) { acc, s in
            let rate = s.totalRealCost > 0 ? (Double(s.normalRotations) / s.totalRealCost) * 1000.0 : 0
            return acc + (rate - s.formulaBorderPer1k)
        } / Double(list.count)
    }
    private var displaySummary: (total: Int, rate: Double) {
        let g = AnalyticsEngine.byManufacturer(sessions).first { $0.label == manufacturerName }
        guard let g = g else {
            let totalTheoretical = manufacturerSessions.reduce(0) { $0 + $1.theoreticalProfit }
            let totalDS = manufacturerSessions.reduce(0) { $0 + $1.deficitSurplus }
            let rate = totalTheoretical != 0 ? Double(totalDS) / Double(abs(totalTheoretical)) : 0
            return (totalDS, rate)
        }
        return (g.totalDeficitSurplus, g.deficitSurplusRate)
    }
    private var cyan: Color { AppGlassStyle.accent }
    private var mutedGray: Color { Color.white.opacity(0.4) }
    private func summaryPanel(title: String, value: String, valueColor: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(mutedGray)
            Text(value).font(.subheadline.monospacedDigit().weight(.semibold)).foregroundColor(valueColor)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(AppGlassStyle.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(AppGlassStyle.strokeGradient, lineWidth: 1))
    }

    var body: some View {
        ZStack {
            StaticHomeBackgroundView()
            ScrollView(showsIndicators: false) {
                VStack(spacing: 12) {
                    VStack(spacing: 8) {
                        HStack(spacing: 8) {
                            summaryPanel(title: "通算実収支", value: manufacturerSessions.isEmpty ? "—" : "\(totalProfit >= 0 ? "+" : "")\(totalProfit) 円", valueColor: totalProfit >= 0 ? .green : .red)
                            summaryPanel(title: "通算実践回転率", value: manufacturerSessions.isEmpty || weightedAvgRotationPer1k <= 0 ? "—" : String(format: "%.1f 回/千円", weightedAvgRotationPer1k), valueColor: .white)
                        }
                        HStack(spacing: 8) {
                            summaryPanel(title: "公式ボーダーとの差の平均", value: avgDiffFromFormulaBorder.map { String(format: "%+.1f 回/千円", $0) } ?? "—", valueColor: (avgDiffFromFormulaBorder ?? 0) >= 0 ? cyan : Color.orange)
                            summaryPanel(title: "期待値対比", value: manufacturerSessions.isEmpty ? "—" : { let (total, rate) = displaySummary; var s = (total >= 0 ? "+" : "") + "\(total) 円"; if abs(rate) >= 0.01 { s += " (\(rate >= 0 ? "+" : "")\(Int(round(rate * 100)))%)" }; return s }(), valueColor: displaySummary.total >= 0 ? cyan : Color.orange)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    if !manufacturerSessions.isEmpty {
                        VStack(alignment: .leading, spacing: 20) {
                            WeekdayTendencySection(groups: weekdayGroups, accent: cyan)
                            SpecificDayBarChartSection(groups: specificDayGroups, accent: cyan, fixedSegmentCount: 7)
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 4)
                        .padding(.bottom, 8)
                    }
                    Text("このメーカーの履歴")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.white.opacity(0.8))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                    LazyVStack(spacing: 12) {
                        ForEach(manufacturerSessions) { session in
                            NavigationLink(destination: AnalyticsSessionDetailView(session: session, sessions: sessions, bottomSegment: $bottomSegment, selectedFilterLabel: $selectedFilterLabel, periodFilter: $periodFilter, showPeriodSheet: $showPeriodSheet, onDismissToRoot: { DispatchQueue.main.async { dismiss() } })) {
                                AnalyticsSessionCardView(session: session)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 120)
                }
            }
        }
        .navigationTitle(manufacturerName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .preferredColorScheme(.dark)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            AnalyticsBottomBarView(bottomSegment: $bottomSegment, selectedFilterLabel: $selectedFilterLabel, periodFilter: $periodFilter, showPeriodSheet: $showPeriodSheet, onSegmentTap: { dismiss() })
                .frame(height: 88)
                .frame(maxHeight: 88)
        }
    }
}

/// 分析1行をグラスカードでラップ（実戦履歴UIと統一）
/// 店舗分析時はパネル全体を実収支に応じてシアン〜マゼンタのグラデーションで tint（透明度維持）
struct AnalyticsGroupCard: View {
    let group: AnalyticsGroup
    let accent: Color
    /// 店舗タブ時のみ true。パネルをシアン〜マゼンタのグラデーションで着色
    var isShopSegment: Bool = false

    private static let magenta = Color(red: 1, green: 0, blue: 0.55)

    /// 店舗分析用：パネルオーバー用グラデーション（実収支プラス＝シアン寄り、マイナス＝マゼンタ寄り）。透明度は弱めに維持
    private var panelGradient: LinearGradient? {
        guard isShopSegment else { return nil }
        let ratio: Double
        if group.totalInvestment > 0 {
            ratio = Double(group.totalProfit) / Double(group.totalInvestment)
        } else {
            ratio = group.totalProfit > 0 ? 0.2 : (group.totalProfit < 0 ? -0.2 : 0)
        }
        let intensity = min(1.0, abs(ratio) * 3)
        let cyanOp = 0.06 + (ratio > 0 ? intensity * 0.18 : 0.04)
        let magOp = 0.06 + (ratio < 0 ? intensity * 0.18 : 0.04)
        return LinearGradient(
            colors: [accent.opacity(cyanOp), Self.magenta.opacity(magOp)],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    /// 数値用：プラスはアクセント、マイナスは店舗時マゼンタ／それ以外オレンジ
    private var shopAccentColor: (positive: Color, negative: Color) {
        guard isShopSegment else { return (accent, Color.orange) }
        if group.totalInvestment > 0 {
            let ratio = Double(group.totalProfit) / Double(group.totalInvestment)
            let intensity = min(1.0, abs(ratio) * 4)
            if ratio > 0 {
                return (accent.opacity(0.6 + 0.4 * intensity), Self.magenta.opacity(0.6 + 0.4 * intensity))
            } else if ratio < 0 {
                return (accent, Self.magenta.opacity(0.6 + 0.4 * intensity))
            } else {
                let n = Color.white.opacity(0.85)
                return (n, n)
            }
        }
        return (accent, Self.magenta.opacity(0.85))
    }

    private var effectiveAccent: Color { shopAccentColor.positive }
    private var effectiveLossColor: Color { shopAccentColor.negative }

    /// 二行目：実践回転率・回数・公式ボーダーとの差（あれば）
    private var secondLineText: String {
        var s = "実践回転率 \(String(format: "%.1f", group.avgRotationRate))/1k円 · \(group.sessionCount)回"
        if let diff = group.avgDiffFromFormulaBorder {
            s += " （公式ボーダーとの差: \(String(format: "%+.1f 回/千円", diff))"
        }
        return s
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(group.label)
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.white)
                        Text("（遊技回数：\(group.sessionCount)回）")
                            .font(.caption2)
                            .foregroundColor(.white.opacity(0.65))
                    }
                    Text(secondLineText)
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.65))
                }
                Spacer()
            }
            HStack(alignment: .bottom, spacing: 12) {
                // 実収支を最前面に（強調）
                VStack(alignment: .leading, spacing: 2) {
                    Text("実収支")
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.65))
                    Text("\(group.totalProfit >= 0 ? "+" : "")\(group.totalProfit)")
                        .font(.subheadline.monospacedDigit().weight(.semibold))
                        .foregroundColor(group.totalProfit >= 0 ? effectiveAccent : effectiveLossColor)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("理論")
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.65))
                    Text("\(group.totalTheoreticalProfit >= 0 ? "+" : "")\(group.totalTheoreticalProfit)")
                        .font(.caption.monospacedDigit())
                        .foregroundColor(.white.opacity(0.85))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("期待比")
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.65))
                    Text("\(group.totalDeficitSurplus >= 0 ? "+" : "")\(group.totalDeficitSurplus)")
                        .font(.caption.monospacedDigit().weight(.semibold))
                        .foregroundColor(group.totalDeficitSurplus >= 0 ? effectiveAccent : effectiveLossColor)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("理論との差")
                        .font(.system(size: 9))
                        .foregroundColor(.white.opacity(0.5))
                    DeficitSurplusBarView(
                        deficitSurplus: group.totalDeficitSurplus,
                        accent: effectiveAccent,
                        lossColor: effectiveLossColor,
                        barColorByActualProfit: isShopSegment ? group.totalProfit : nil
                    )
                    .frame(height: 20)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppGlassStyle.cardBackground)
        .overlay(
            Group {
                if let g = panelGradient {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(g)
                        .allowsHitTesting(false)
                }
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(AppGlassStyle.strokeGradient, lineWidth: 1)
        )
    }
}

// MARK: - 理論との差（余剰・欠損）をゼロ中心の1本バーで表示
// 代替案メモ:
// - 旧: 理論・実収支の2本並び → 長さの意味が伝わりにくい
// - 案A: 共通ゼロ軸で理論・実収支を左右に同じスケールで描く（情報量多め）
// - 案B: 理論を100%とする達成率バー（理論0や負のときは要工夫）
// 採用: 差だけ表示＝「理論よりどれだけ出た/損したか」がひと目で分かる
struct DeficitSurplusBarView: View {
    let deficitSurplus: Int
    let accent: Color
    var lossColor: Color = Color.orange
    /// 店舗分析時のみ指定。実収支がマイナスなら右伸びの棒も lossColor に（「理論よりマシだが実収支は赤字」と分かる）
    var barColorByActualProfit: Int? = nil

    /// 右方向の棒（理論との差プラス）の色。実収支マイナスならマゼンタ
    private var rightBarColor: Color {
        if let actual = barColorByActualProfit, actual < 0 { return lossColor }
        return accent
    }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let half = w / 2
            let absVal = max(abs(deficitSurplus), 1)
            let scale = half / CGFloat(absVal)
            let barW = min(CGFloat(abs(deficitSurplus)) * scale, half - 2)
            ZStack(alignment: .center) {
                // 中央のゼロ線
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color.white.opacity(0.35))
                    .frame(width: 2)
                if deficitSurplus > 0 {
                    // 余剰: 中央から右へ（実収支マイナスならマゼンタで「理論よりマシだがまだ赤字」）
                    RoundedRectangle(cornerRadius: 3)
                        .fill(rightBarColor.opacity(0.9))
                        .frame(width: max(4, barW), height: 14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.leading, half)
                } else if deficitSurplus < 0 {
                    // 欠損: 中央から左へ
                    RoundedRectangle(cornerRadius: 3)
                        .fill(lossColor.opacity(0.9))
                        .frame(width: max(4, barW), height: 14)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .padding(.trailing, half)
                }
            }
        }
    }
}

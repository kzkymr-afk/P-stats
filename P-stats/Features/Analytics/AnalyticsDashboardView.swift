import SwiftUI
import SwiftData
import Charts

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

/// 期間フィルタ（ドックの「期間」タップで下からシート選択）。年別・月別・日別はドック上のドラムで参照日を指定
enum AnalyticsPeriodFilter: String, CaseIterable {
    case all = "通算"
    case year = "年別"
    case month = "月別"
    case day = "日別"
    case last30 = "直近30日"
    case last7 = "直近7日"

    var label: String { rawValue }

    /// referenceDate: 年別・月別・日別で使う基準日（ドラムで選択）。それ以外は無視
    func filter(_ sessions: [GameSession], referenceDate: Date = Date()) -> [GameSession] {
        let cal = Calendar.current
        let now = Date()
        switch self {
        case .all: return sessions
        case .year: return sessions.filter { cal.isDate($0.date, equalTo: referenceDate, toGranularity: .year) }
        case .month: return sessions.filter { cal.isDate($0.date, equalTo: referenceDate, toGranularity: .month) }
        case .day: return sessions.filter { cal.isDate($0.date, equalTo: referenceDate, toGranularity: .day) }
        case .last30:
            guard let from = cal.date(byAdding: .day, value: -30, to: now) else { return sessions }
            return sessions.filter { $0.date >= from }
        case .last7:
            guard let from = cal.date(byAdding: .day, value: -7, to: now) else { return sessions }
            return sessions.filter { $0.date >= from }
        }
    }

    /// ドック上に日付ドラムを表示するか（年別・月別・日別）
    var showsPeriodDrum: Bool {
        self == .year || self == .month || self == .day
    }
}

/// 全体・機種・メーカー一覧用：通常日・7のつく日・ゾロ目だけ（7分割の左3、右4は空白）。同一ファイル内の他 struct から参照するため internal
enum AnalyticsFixedSpecificDayLabels {
    static let list: [String] = ["通常日", "7のつく日", "ゾロ目"]
}

/// データ分析内パネル用スタイル（不透明度を15%上げて背景との重なりで文字が見にくくなるのを軽減）
private enum AnalyticsPanelStyle {
    static let panelBackground = Color.black.opacity(0.90)
    static let rowBackground = Color.black.opacity(0.85)
}

// MARK: - 分析フッター（ドック。YouTube風フローティングピル）
private struct AnalyticsBottomBarView: View {
    @Binding var bottomSegment: AnalyticsBottomSegment
    @Binding var selectedFilterLabel: String?
    @Binding var periodFilter: AnalyticsPeriodFilter
    @Binding var showPeriodSheet: Bool
    /// 子ページにいる時にタブを押したら分析トップへ戻る（dismiss 用）
    var onSegmentTap: (() -> Void)? = nil
    /// 戻るタップで一つ前の画面へ（分析ルートではアプリホームへ）
    var onHomeTap: (() -> Void)? = nil

    private var cyan: Color { AppGlassStyle.accent }
    private var mutedGray: Color { Color.white.opacity(0.6) }
    private let iconSize: CGFloat = 20
    private let fontSize: CGFloat = 10

    var body: some View {
        HStack(spacing: 0) {
            Button {
                HapticUtil.impact(.light)
                onHomeTap?()
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: iconSize, weight: .medium))
                    Text("戻る")
                        .font(.system(size: fontSize, weight: .medium, design: .rounded))
                }
                .foregroundColor(mutedGray)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .padding(.horizontal, 2)
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
                    VStack(spacing: 4) {
                        Image(systemName: seg.icon)
                            .font(.system(size: iconSize, weight: .medium))
                        Text(seg.rawValue)
                            .font(.system(size: fontSize, weight: .medium, design: .rounded))
                    }
                    .foregroundColor(seg == bottomSegment ? .white : mutedGray)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .padding(.horizontal, 2)
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
            }
            Button {
                HapticUtil.impact(.light)
                showPeriodSheet = true
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: AnalyticsBottomSegment.period.icon)
                        .font(.system(size: iconSize, weight: .medium))
                    Text(periodFilter.label)
                        .font(.system(size: fontSize, weight: .medium, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .foregroundColor(.white.opacity(0.9))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .padding(.horizontal, 2)
            }
            .buttonStyle(.plain)
            .contentShape(Rectangle())
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
        .background(
            TranslucentBlurView(style: .systemUltraThinMaterialDark, alpha: 0.92)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipShape(Capsule())
        )
        .overlay(
            Capsule()
                .stroke(Color.white.opacity(0.18), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.25), radius: 12, x: 0, y: 4)
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
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
    @Query(sort: \GameSession.date, order: .reverse) private var sessionsQuery: [GameSession]
    @Query private var shops: [Shop]
    @State private var bottomSegment: AnalyticsBottomSegment = .overview
    @State private var periodFilter: AnalyticsPeriodFilter = .all
    @State private var selectedFilterLabel: String?
    @State private var showPeriodSheet: Bool = false
    @State private var showGameSessionEdit: Bool = false
    /// ヒートマップのセルタップで遷移する日（navigationDestination で使用）
    @State private var heatmapSelectedDay: Date? = nil
    /// 年別・月別・日別で使う基準日（ドック上のドラムで変更）
    @State private var selectedPeriodDate: Date = Date()

    @State private var cachedFilteredSessions: [GameSession] = []
    @State private var cachedAllGroups: [AnalyticsGroup] = []

    /// 期間フィルタをかけたセッション（店舗・機種・メーカー共通）
    private var filteredSessions: [GameSession] { cachedFilteredSessions }

    private var effectiveSegment: AnalyticsSegment {
        switch bottomSegment {
        case .overview: return .shop
        case .shop: return .shop
        case .machine: return .machine
        case .manufacturer: return .manufacturer
        case .period: return .month
        }
    }

    private var allGroups: [AnalyticsGroup] { cachedAllGroups }

    private var groups: [AnalyticsGroup] {
        guard let label = selectedFilterLabel else { return allGroups }
        return allGroups.filter { $0.label == label }
    }

    private func updateCaches() {
        let f = periodFilter.filter(sessionsQuery, referenceDate: selectedPeriodDate)
        cachedFilteredSessions = f
        switch bottomSegment {
        case .overview: cachedAllGroups = [AnalyticsEngine.overviewGroup(f)]
        case .shop: cachedAllGroups = AnalyticsEngine.byShop(f)
        case .machine: cachedAllGroups = AnalyticsEngine.byMachine(f)
        case .manufacturer: cachedAllGroups = AnalyticsEngine.byManufacturer(f)
        case .period: cachedAllGroups = []
        }
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

    /// 通算実成績（現在の対象セッションの合計実成績）
    private var totalProfit: Int { sessionsForSummary.reduce(0) { $0 + $1.performance } }
    /// 通算実践回転率（加重平均）＝ 総回転数 ÷ (総実質投資/1000)
    private var weightedAvgRotationPer1k: Double {
        let list = sessionsForSummary
        let totalRotations = list.reduce(0) { $0 + $1.normalRotations }
        let totalCost = list.reduce(0.0) { $0 + $1.totalRealCost }
        guard totalCost > 0 else { return 0 }
        return Double(totalRotations) / (totalCost / 1000.0)
    }
    /// 公式基準値との差の平均（回/1k）。公式未設定のセッションは除外して平均
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
        let totalTheoretical = sessionsQuery.reduce(0) { $0 + $1.theoreticalValue }
        let totalDS = sessionsQuery.reduce(0) { $0 + $1.deficitSurplus }
        let rate = totalTheoretical != 0 ? Double(totalDS) / Double(abs(totalTheoretical)) : 0
        return (totalDS, rate)
    }

    private var cyan: Color { AppGlassStyle.accent }
    private var cardBackground: Color { AnalyticsPanelStyle.panelBackground }
    private var mutedGray: Color { Color.white.opacity(0.4) }
    private var barBackground: Color { Color.black.opacity(0.4) }

    var body: some View {
        ZStack {
            StaticHomeBackgroundView()
            VStack(spacing: 0) {
                if !sessionsQuery.isEmpty {
                    totalSummaryCard
                }
                if groups.isEmpty {
                    emptyState
                } else {
                    listContent
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(spacing: 0) {
                    if periodFilter.showsPeriodDrum {
                        periodDrumView
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(TranslucentBlurView(style: .systemUltraThinMaterialDark, alpha: 0.95))
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                            .padding(.horizontal, 20)
                            .padding(.bottom, 8)
                    }
                    bottomSegmentBar
                        .frame(height: 88)
                        .frame(maxHeight: 88)
                }
            }
        }
        .onAppear {
            updateCaches()
        }
        .onChange(of: sessionsQuery) { _, _ in updateCaches() }
        .onChange(of: periodFilter) { _, _ in updateCaches() }
        .onChange(of: selectedPeriodDate) { _, _ in updateCaches() }
        .onChange(of: bottomSegment) { _, _ in updateCaches() }
        .sheet(isPresented: $showPeriodSheet) {
            AnalyticsPeriodPickerSheet(selected: $periodFilter)
        }
        .navigationDestination(isPresented: Binding(
            get: { heatmapSelectedDay != nil },
            set: { if !$0 { heatmapSelectedDay = nil } }
        )) {
            if let d = heatmapSelectedDay {
                AnalyticsDayDetailView(day: d, sessions: filteredSessions, bottomSegment: $bottomSegment, selectedFilterLabel: $selectedFilterLabel, periodFilter: $periodFilter, showPeriodSheet: $showPeriodSheet)
            } else {
                EmptyView()
            }
        }
        .navigationTitle("分析")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .preferredColorScheme(.dark)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: {
                    showGameSessionEdit = true
                }) {
                    Image(systemName: "plus")
                        .foregroundColor(cyan)
                }
            }
        }
        .sheet(isPresented: $showGameSessionEdit) {
            GameSessionEditView()
        }
    }

    /// 通算サマリ用の1行（ラベル左・値右）。1パネル内の行として使用
    private func summaryRow(title: String, value: String, valueColor: Color, explanation: String? = nil) -> some View {
        HStack {
            HStack(spacing: 2) {
                Text(title)
                    .font(AppTypography.bodyRounded)
                    .foregroundStyle(mutedGray)
                if let exp = explanation {
                    InfoIconView(explanation: exp, tint: mutedGray)
                }
            }
            Spacer(minLength: 4)
            Text(value)
                .font(.system(size: 15, weight: .semibold, design: .monospaced))
                .foregroundColor(valueColor)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
    }

    /// 一番上：1パネルに集約。左＝収支・期待値、右＝回転率。高さを抑えたレイアウト
    private var totalSummaryCard: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                summaryRow(
                    title: "通算実成績",
                    value: sessionsForSummary.isEmpty ? "—" : "\(totalProfit >= 0 ? "+" : "")\(totalProfit.formattedPtWithUnit)",
                    valueColor: totalProfit >= 0 ? .green : .red
                )
                summaryRow(
                    title: "理論上成績",
                    value: sessionsForSummary.isEmpty ? "—" : {
                        let totalTheoretical = sessionsForSummary.reduce(0) { $0 + $1.theoreticalValue }
                        return "\(totalTheoretical >= 0 ? "+" : "")\(totalTheoretical.formattedPtWithUnit)"
                    }(),
                    valueColor: .white.opacity(0.9)
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .leading, spacing: 8) {
                summaryRow(
                    title: "通算実践回転率",
                    value: sessionsForSummary.isEmpty || weightedAvgRotationPer1k <= 0 ? "—" : String(format: "%.1f 回/1k", weightedAvgRotationPer1k),
                    valueColor: .white,
                    explanation: "総回転数（通常のみ）÷実質投入千pt単位。"
                )
                summaryRow(
                    title: "平均基準値差",
                    value: avgDiffFromFormulaBorder.map { String(format: "%+.1f 回/1k", $0) } ?? "—",
                    valueColor: (avgDiffFromFormulaBorder ?? 0) >= 0 ? cyan : Color.orange,
                    explanation: "実践回転率−公式基準値。プラスでボーダー上回り。"
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(AnalyticsPanelStyle.panelBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(AppGlassStyle.strokeGradient, lineWidth: 1)
        )
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "chart.bar.doc.horizontal")
                .font(.system(size: 48))
                .foregroundColor(cyan.opacity(0.5))
            Text("データがありません")
                .font(AppTypography.panelHeading)
                .foregroundColor(.white)
            Text("実戦を保存するとここに集計が表示されます")
                .font(AppTypography.bodyRounded)
                .foregroundColor(.white.opacity(0.75))
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 28)
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity)
        .background(AnalyticsPanelStyle.panelBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(AppGlassStyle.strokeGradient, lineWidth: 1)
        )
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// 全般・店舗・機種・メーカー一覧では曜日・特定日傾向は出さない。個別店舗/機種/メーカー詳細に入ったときだけ表示する。
    private var listContent: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(spacing: 12) {
                if bottomSegment == .overview && !filteredSessions.isEmpty {
                    MonthlyTrendChartSection(sessions: filteredSessions, cyan: cyan)
                        .padding(.horizontal, 16)
                    CalendarHeatmapSection(sessions: filteredSessions, cyan: cyan, selectedDay: $heatmapSelectedDay, bottomSegment: $bottomSegment, selectedFilterLabel: $selectedFilterLabel, periodFilter: $periodFilter, showPeriodSheet: $showPeriodSheet)
                        .padding(.horizontal, 16)
                }
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

    /// 年別・月別・日別のときドック直上に表示する日付選択ドラム
    private var periodDrumView: some View {
        DatePicker(selection: $selectedPeriodDate, displayedComponents: .date) {
            Text(periodFilter.label)
                .font(.caption)
                .foregroundColor(.white.opacity(0.8))
        }
        .datePickerStyle(.wheel)
        .labelsHidden()
        .colorScheme(.dark)
        .frame(height: 140)
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
                .listRowBackground(AnalyticsPanelStyle.rowBackground)
            }
            .navigationTitle("期間")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .preferredColorScheme(.dark)
        }
    }
}

/// セッションを日付（カレンダー日）でグループ化。日付は降順、同日内も新しい順。同じ日付のパネル間隔を詰めるために使用
private func sessionsGroupedByDay(_ sessions: [GameSession]) -> [(day: Date, sessions: [GameSession])] {
    let cal = Calendar.current
    let grouped = Dictionary(grouping: sessions) { cal.startOfDay(for: $0.date) }
    return grouped
        .map { (day: $0.key, sessions: $0.value.sorted { $0.date > $1.date }) }
        .sorted { $0.day > $1.day }
}

/// 大きな数値を k（千）・M（百万）で省略表示（改行防止）
/// 金額表示用：符号付きでカンマ区切り（例: 12345 → "+12,345", -1500 → "-1,500"）
private func compactIntegerLabel(_ n: Int) -> String {
    let sign = n >= 0 ? "+" : "-"
    return "\(sign)\(abs(n).formattedPtWithUnit)"
}

// MARK: - 曜日傾向（SwiftCharts: ゼロ中央・回転率0〜max、自動スケール・アニメーション）
private struct WeekdayTendencySection: View {
    let groups: [AnalyticsGroup]
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("曜日傾向")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.white.opacity(0.95))
                .shadow(color: .black.opacity(0.7), radius: 2, x: 0, y: 1)
                .padding(.horizontal, 4)
            VStack(alignment: .leading, spacing: 14) {
                chartRow(title: "実成績") {
                    Chart {
                        RuleMark(y: .value("ゼロ", 0))
                            .foregroundStyle(Color.white.opacity(0.4))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        ForEach(groups) { g in
                            BarMark(
                                x: .value("曜日", g.label),
                                y: .value("pt", g.totalProfit)
                            )
                            .foregroundStyle(g.totalProfit >= 0 ? Color.green : Color.orange)
                        }
                    }
                    .chartYAxis {
                        AxisMarks(position: .leading, values: .automatic(desiredCount: 5)) { value in
                            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(Color.white.opacity(0.2))
                            AxisValueLabel { if let v = value.as(Int.self) { Text("\(v / 10000)万") } }
                                .foregroundStyle(Color.white.opacity(0.7))
                        }
                    }
                    .chartXAxis {
                        AxisMarks { _ in
                            AxisValueLabel().foregroundStyle(Color.white.opacity(0.8))
                        }
                    }
                }
                chartRow(title: "回転率（回/1k）") {
                    Chart(groups) { g in
                        BarMark(
                            x: .value("曜日", g.label),
                            y: .value("回/1k", g.avgRotationRate)
                        )
                        .foregroundStyle(accent)
                    }
                    .chartYAxis {
                        AxisMarks(position: .leading, values: .automatic(desiredCount: 5)) { value in
                            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(Color.white.opacity(0.2))
                            AxisValueLabel().foregroundStyle(Color.white.opacity(0.7))
                        }
                    }
                    .chartXAxis {
                        AxisMarks { _ in
                            AxisValueLabel().foregroundStyle(Color.white.opacity(0.8))
                        }
                    }
                }
                chartRow(title: "欠損・余剰") {
                    Chart {
                        RuleMark(y: .value("ゼロ", 0))
                            .foregroundStyle(Color.white.opacity(0.4))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        ForEach(groups) { g in
                            BarMark(
                                x: .value("曜日", g.label),
                                y: .value("pt", g.totalDeficitSurplus)
                            )
                            .foregroundStyle(g.totalDeficitSurplus >= 0 ? Color.cyan : Color.orange)
                        }
                    }
                    .chartYAxis {
                        AxisMarks(position: .leading, values: .automatic(desiredCount: 5)) { value in
                            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(Color.white.opacity(0.2))
                            AxisValueLabel { if let v = value.as(Int.self) { Text("\(v / 10000)万") } }
                                .foregroundStyle(Color.white.opacity(0.7))
                        }
                    }
                    .chartXAxis {
                        AxisMarks { _ in
                            AxisValueLabel().foregroundStyle(Color.white.opacity(0.8))
                        }
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AnalyticsPanelStyle.panelBackground)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(AppGlassStyle.strokeGradient, lineWidth: 1))
        }
    }

    private func chartRow<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundColor(.white.opacity(0.7))
            content()
                .frame(height: 120)
                .chartLegend(.hidden)
        }
    }
}

// MARK: - 特定日傾向（SwiftCharts: ゼロ中央・回転率0〜max。_pad は値0で表示し軸のみ維持）
private struct SpecificDayBarChartSection: View {
    let groups: [AnalyticsGroup]
    let accent: Color
    var fixedSegmentCount: Int? = nil

    private var displayGroups: [AnalyticsGroup] {
        guard let n = fixedSegmentCount, groups.count < n else { return groups }
        return groups + (1...(n - groups.count)).map { AnalyticsEngine.emptyGroup(label: "_pad\($0)") }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("特定日傾向")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.white.opacity(0.95))
                .shadow(color: .black.opacity(0.7), radius: 2, x: 0, y: 1)
                .padding(.horizontal, 4)
            VStack(alignment: .leading, spacing: 14) {
                chartRow(title: "実成績") {
                    Chart {
                        RuleMark(y: .value("ゼロ", 0))
                            .foregroundStyle(Color.white.opacity(0.4))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        ForEach(displayGroups) { g in
                            BarMark(
                                x: .value("区分", g.label),
                                y: .value("pt", g.label.hasPrefix("_pad") ? 0 : g.totalProfit)
                            )
                            .foregroundStyle(g.label.hasPrefix("_pad") ? Color.clear : (g.totalProfit >= 0 ? Color.green : Color.orange))
                        }
                    }
                    .chartYAxis { AxisMarks(position: .leading, values: .automatic(desiredCount: 5)) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(Color.white.opacity(0.2))
                        AxisValueLabel { if let v = value.as(Int.self) { Text("\(v / 10000)万") } }.foregroundStyle(Color.white.opacity(0.7))
                    } }
                    .chartXAxis { AxisMarks(preset: .aligned) { value in
                        AxisValueLabel { if let s = value.as(String.self), !s.hasPrefix("_pad") { Text(s).foregroundStyle(Color.white.opacity(0.8)) } }
                    } }
                }
                chartRow(title: "回転率（回/1k）") {
                    Chart(displayGroups) { g in
                        BarMark(
                            x: .value("区分", g.label),
                            y: .value("回/1k", g.label.hasPrefix("_pad") ? 0 : g.avgRotationRate)
                        )
                        .foregroundStyle(g.label.hasPrefix("_pad") ? Color.clear : accent)
                    }
                    .chartYAxis { AxisMarks(position: .leading, values: .automatic(desiredCount: 5)) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(Color.white.opacity(0.2))
                        AxisValueLabel().foregroundStyle(Color.white.opacity(0.7))
                    } }
                    .chartXAxis { AxisMarks(preset: .aligned) { value in
                        AxisValueLabel { if let s = value.as(String.self), !s.hasPrefix("_pad") { Text(s).foregroundStyle(Color.white.opacity(0.8)) } }
                    } }
                }
                chartRow(title: "欠損・余剰") {
                    Chart {
                        RuleMark(y: .value("ゼロ", 0))
                            .foregroundStyle(Color.white.opacity(0.4))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        ForEach(displayGroups) { g in
                            BarMark(
                                x: .value("区分", g.label),
                                y: .value("pt", g.label.hasPrefix("_pad") ? 0 : g.totalDeficitSurplus)
                            )
                            .foregroundStyle(g.label.hasPrefix("_pad") ? Color.clear : (g.totalDeficitSurplus >= 0 ? Color.cyan : Color.orange))
                        }
                    }
                    .chartYAxis { AxisMarks(position: .leading, values: .automatic(desiredCount: 5)) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(Color.white.opacity(0.2))
                        AxisValueLabel { if let v = value.as(Int.self) { Text("\(v / 10000)万") } }.foregroundStyle(Color.white.opacity(0.7))
                    } }
                    .chartXAxis { AxisMarks(preset: .aligned) { value in
                        AxisValueLabel { if let s = value.as(String.self), !s.hasPrefix("_pad") { Text(s).foregroundStyle(Color.white.opacity(0.8)) } }
                    } }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AnalyticsPanelStyle.panelBackground)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(AppGlassStyle.strokeGradient, lineWidth: 1))
        }
    }

    private func chartRow<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption).foregroundColor(.white.opacity(0.7))
            content().frame(height: 72).chartLegend(.hidden)
        }
    }
}

// MARK: - 月間収支トレンド（累計実成績・累計理論期待値の折れ線＋エリア）
private struct MonthlyTrendChartSection: View {
    let sessions: [GameSession]
    let cyan: Color

    private var trendData: [(month: String, cumulativeProfit: Int, cumulativeTheoretical: Int)] {
        AnalyticsEngine.monthlyCumulativeTrend(sessions)
    }

    var body: some View {
        Group {
            if trendData.isEmpty {
                EmptyView()
            } else {
                VStack(alignment: .leading, spacing: 12) {
                Text("月間収支トレンド")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white.opacity(0.95))
                    .shadow(color: .black.opacity(0.7), radius: 2, x: 0, y: 1)
                Chart(trendData, id: \.month) { d in
                    AreaMark(
                        x: .value("月", d.month),
                        y: .value("実成績", d.cumulativeProfit)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [cyan.opacity(0.4), cyan.opacity(0.05)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    LineMark(
                        x: .value("月", d.month),
                        y: .value("実成績", d.cumulativeProfit)
                    )
                    .foregroundStyle(cyan)
                    .lineStyle(StrokeStyle(lineWidth: 2))
                    .symbol(.circle)
                    LineMark(
                        x: .value("月", d.month),
                        y: .value("理論値", d.cumulativeTheoretical)
                    )
                    .foregroundStyle(Color.white.opacity(0.85))
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                    .symbol(.square)
                }
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 6)) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(Color.white.opacity(0.2))
                        AxisValueLabel { if let v = value.as(Int.self) { Text("\(v / 10000)万") } }.foregroundStyle(Color.white.opacity(0.7))
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: 1)) { value in
                        AxisValueLabel().foregroundStyle(Color.white.opacity(0.8))
                    }
                }
                .frame(height: 180)
                .chartLegend(.hidden)
                HStack(spacing: 16) {
                    legendDot(cyan, label: "累計実成績")
                    legendDot(Color.white.opacity(0.85), label: "累計理論値", dashed: true)
                }
                .font(.caption)
                .foregroundColor(.white.opacity(0.8))
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AnalyticsPanelStyle.panelBackground)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(AppGlassStyle.strokeGradient, lineWidth: 1))
            }
        }
    }

    private func legendDot(_ color: Color, label: String, dashed: Bool = false) -> some View {
        HStack(spacing: 6) {
            if dashed {
                Rectangle()
                    .stroke(color, style: StrokeStyle(lineWidth: 2, dash: [4, 3]))
                    .frame(width: 20, height: 2)
            } else {
                Circle().fill(color).frame(width: 8, height: 8)
            }
            Text(label)
        }
    }
}

// MARK: - カレンダーヒートマップ（稼働日・勝敗の濃淡・縦並び・タップで日別履歴へ）
private struct CalendarHeatmapSection: View {
    let sessions: [GameSession]
    let cyan: Color
    @Binding var selectedDay: Date?
    @Binding var bottomSegment: AnalyticsBottomSegment
    @Binding var selectedFilterLabel: String?
    @Binding var periodFilter: AnalyticsPeriodFilter
    @Binding var showPeriodSheet: Bool

    private let magenta = Color(red: 0.9, green: 0.2, blue: 0.5)
    private let cal = Calendar.current
    private let cellSize: CGFloat = 40
    private let cellSpacing: CGFloat = 3
    private var columns: [GridItem] { Array(repeating: GridItem(.fixed(cellSize), spacing: cellSpacing), count: 7) }
    @State private var showFullCalendar = false
    @State private var sheetSelectedDay: Date? = nil

    private var profitByDay: [Date: Int] {
        let grouped = Dictionary(grouping: sessions) { cal.startOfDay(for: $0.date) }
        return Dictionary(uniqueKeysWithValues: grouped.map { day, list in
            (day, list.reduce(0) { $0 + $1.performance })
        })
    }

    /// デフォルト表示: 当月のみ
    private var defaultMonths: [Date] {
        guard let startOfMonth = cal.date(from: cal.dateComponents([.year, .month], from: Date())) else { return [] }
        return [startOfMonth]
    }

    /// 全期間: セッションが存在する月のみ、古い月→新しい月の順（無制限に遡らない）
    private var allMonthsAscending: [Date] {
        guard !sessions.isEmpty else {
            return defaultMonths
        }
        let days = sessions.map { cal.startOfDay(for: $0.date) }
        guard let first = days.min(), let last = days.max() else { return defaultMonths }
        guard let startMonth = cal.date(from: cal.dateComponents([.year, .month], from: first)),
              let endMonth = cal.date(from: cal.dateComponents([.year, .month], from: last)) else { return defaultMonths }
        var list: [Date] = []
        var cursor = startMonth
        while cursor <= endMonth {
            list.append(cursor)
            guard let next = cal.date(byAdding: .month, value: 1, to: cursor) else { break }
            cursor = next
        }
        return list
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 4) {
                Text("稼働ヒートマップ")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white.opacity(0.95))
                    .shadow(color: .black.opacity(0.7), radius: 2, x: 0, y: 1)
                InfoIconView(explanation: "濃いほど収支の絶対値が大きい（青=プラス・赤=マイナス）。タップでその日の履歴へ。", tint: .white.opacity(0.6))
            }

            VStack(spacing: 20) {
                ForEach(defaultMonths, id: \.timeIntervalSince1970) { monthStart in
                    monthBlock(monthStart: monthStart, selectedDay: $selectedDay)
                }
            }

            Button {
                showFullCalendar = true
            } label: {
                HStack {
                    Spacer()
                    Text("全て表示（全期間）")
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(cyan)
                    Spacer()
                }
                .padding(.vertical, 12)
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AnalyticsPanelStyle.panelBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(AppGlassStyle.strokeGradient, lineWidth: 1))
        .sheet(isPresented: $showFullCalendar) {
            NavigationStack {
                fullCalendarSheetContent
            }
        }
    }

    private var fullCalendarSheetContent: some View {
        ZStack {
            StaticHomeBackgroundView()
            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 24) {
                    ForEach(allMonthsAscending, id: \.timeIntervalSince1970) { monthStart in
                        monthBlock(monthStart: monthStart, selectedDay: $sheetSelectedDay)
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(AnalyticsPanelStyle.panelBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                            .overlay(RoundedRectangle(cornerRadius: 14).stroke(AppGlassStyle.strokeGradient, lineWidth: 1))
                    }
                }
                .padding(16)
                .padding(.bottom, 40)
            }
        }
        .navigationTitle("稼働ヒートマップ（全期間）")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .preferredColorScheme(.dark)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("閉じる") { showFullCalendar = false }
                    .foregroundColor(cyan)
            }
        }
        .navigationDestination(isPresented: Binding(
            get: { sheetSelectedDay != nil },
            set: { if !$0 { sheetSelectedDay = nil } }
        )) {
            if let d = sheetSelectedDay {
                AnalyticsDayDetailView(day: d, sessions: sessions, bottomSegment: $bottomSegment, selectedFilterLabel: $selectedFilterLabel, periodFilter: $periodFilter, showPeriodSheet: $showPeriodSheet)
            } else {
                EmptyView()
            }
        }
    }

    private func monthBlock(monthStart: Date, selectedDay: Binding<Date?>) -> some View {
        let daysInMonth = cal.range(of: .day, in: .month, for: monthStart).map { $0.count } ?? 30
        let firstDay = cal.date(from: cal.dateComponents([.year, .month], from: monthStart))!
        let firstWeekday = cal.component(.weekday, from: firstDay) - 1
        let leadingBlanks = firstWeekday
        let rows = (leadingBlanks + daysInMonth + 6) / 7
        let maxAbs = max(1, profitByDay.values.map(abs).max() ?? 1)

        return VStack(alignment: .leading, spacing: 8) {
            Text(monthHeaderLabel(monthStart))
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.white.opacity(0.9))

            LazyVGrid(columns: columns, spacing: cellSpacing) {
                ForEach(weekdayHeaderIndices(), id: \.self) { i in
                    Text(weekdayLabel(i))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.white.opacity(0.5))
                        .frame(width: cellSize, height: 22)
                }
                ForEach(0..<(rows * 7), id: \.self) { i in
                    if i < leadingBlanks {
                        Color.clear
                            .frame(width: cellSize, height: cellSize)
                    } else {
                        let day = i - leadingBlanks + 1
                        if day <= daysInMonth,
                           let date = cal.date(byAdding: .day, value: day - 1, to: firstDay) {
                            let profit = profitByDay[cal.startOfDay(for: date)] ?? Int.min
                            cellView(profit: profit, maxAbs: maxAbs, date: date, day: day, selectedDay: selectedDay)
                        } else {
                            Color.clear
                                .frame(width: cellSize, height: cellSize)
                        }
                    }
                }
            }
        }
    }

    private func weekdayHeaderIndices() -> [Int] {
        (0..<7).map { $0 }
    }

    private func weekdayLabel(_ index: Int) -> String {
        let symbols = ["日", "月", "火", "水", "木", "金", "土"]
        return symbols[index]
    }

    private func monthHeaderLabel(_ monthStart: Date) -> String {
        JapaneseDateFormatters.yearMonth.string(from: monthStart)
    }

    private func cellView(profit: Int, maxAbs: Int, date: Date, day: Int, selectedDay: Binding<Date?>) -> some View {
        let isEmpty = profit == Int.min
        let alpha = isEmpty ? 0.0 : min(1.0, 0.3 + 0.7 * Double(abs(profit)) / Double(maxAbs))
        let fillColor: Color = isEmpty ? Color.white.opacity(0.1) : (profit >= 0 ? cyan : magenta)
        let textColor: Color = isEmpty ? .white.opacity(0.6) : (alpha > 0.5 ? .white : .white.opacity(0.9))

        return Button {
            selectedDay.wrappedValue = date
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 4)
                    .fill(fillColor.opacity(isEmpty ? 1 : alpha))
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color.white.opacity(0.15), lineWidth: 0.8)
                Text("\(day)")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundColor(textColor)
            }
            .frame(width: cellSize, height: cellSize)
        }
        .buttonStyle(.plain)
    }
}

/// 分析用セッションカード（実戦履歴カードと同じレイアウト・同一ファイル内で参照）
private struct AnalyticsSessionCardView: View {
    let session: GameSession
    private var rotationPer1k: Double {
        guard session.totalRealCost > 0 else { return 0 }
        return (Double(session.normalRotations) / session.totalRealCost) * 1000
    }
    /// 実践回転率の表示文字列（公式基準値との差を括弧内に表示）
    private var rotationRateDisplay: String {
        if rotationPer1k <= 0 { return "—" }
        var s = String(format: "%.1f 回/1k", rotationPer1k)
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
                Text("実成績 \(session.performance >= 0 ? "+" : "")\(session.performance.formattedPtWithUnit)")
                    .font(.subheadline.monospacedDigit().weight(.medium))
                    .foregroundColor(session.performance >= 0 ? .green : .red)
                Text("当選 RUSH:\(session.rushWinCount) 通常:\(session.normalWinCount) LT:\(session.ltWinCount)")
                    .font(.subheadline.monospacedDigit())
                    .foregroundColor(.white.opacity(0.85))
            }
            HStack(spacing: 12) {
                labelVal("総回転", "\(session.normalRotations)")
                Text("・").foregroundColor(.white.opacity(0.5))
                labelVal("投入", session.inputCash.formattedPtWithUnit)
                Text("・").foregroundColor(.white.opacity(0.5))
                labelVal("回収玉", "\(session.totalHoldings)")
            }
            .font(.caption)
            .foregroundColor(.white.opacity(0.85))
            HStack(alignment: .top, spacing: 16) {
                miniblock("実践回転率", value: rotationRateDisplay, valueColor: .white)
                miniblock("理論値", value: "\(session.theoreticalValue >= 0 ? "+" : "")\(session.theoreticalValue.formattedPtWithUnit)", valueColor: .white.opacity(0.9))
                deficitSurplusBlock
            }
            .font(.caption)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AnalyticsPanelStyle.panelBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(AppGlassStyle.strokeGradient, lineWidth: 1)
        )
    }
    private var deficitSurplusBlock: some View {
        Group {
            if session.deficitSurplus > 0 {
                miniblock("余剰", value: "+\(session.deficitSurplus.formattedPtWithUnit)", valueColor: .green.opacity(0.9))
            } else if session.deficitSurplus < 0 {
                miniblock("欠損", value: session.deficitSurplus.formattedPtWithUnit, valueColor: .red.opacity(0.9))
            } else {
                miniblock("余剰・欠損", value: "0 pt", valueColor: .white.opacity(0.8))
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

    private var recoveryPt: Int { Int(Double(session.totalHoldings) * session.payoutCoefficient) }
    private var rotationPer1k: Double {
        guard session.inputCash > 0 else { return 0 }
        return Double(session.normalRotations) / (Double(session.inputCash) / 1000.0)
    }
    @State private var showEditSheet = false
    var body: some View {
        List {
            Section("記録日時") {
                Text(JapaneseDateFormatters.yearMonthDay.string(from: session.date))
                    .foregroundColor(.white.opacity(0.95))
                    .shadow(color: .black.opacity(0.7), radius: 2, x: 0, y: 1)
                    .listRowBackground(AnalyticsPanelStyle.rowBackground)
            }
            Section("機種・店舗") {
                LabeledContent("機種", value: session.machineName).listRowBackground(AnalyticsPanelStyle.rowBackground)
                LabeledContent("店舗", value: session.shopName).listRowBackground(AnalyticsPanelStyle.rowBackground)
            }
            Section("数値サマリ") {
                LabeledContent("総回転数", value: "\(session.normalRotations)").listRowBackground(AnalyticsPanelStyle.rowBackground)
                LabeledContent("当選", value: "RUSH: \(session.rushWinCount) / 通常: \(session.normalWinCount) / LT: \(session.ltWinCount)").listRowBackground(AnalyticsPanelStyle.rowBackground)
                LabeledContent("総投入額（現金）", value: "\(session.inputCash.formattedPtWithUnit)").listRowBackground(AnalyticsPanelStyle.rowBackground)
                LabeledContent("回収出球", value: "\(session.totalHoldings) 玉").listRowBackground(AnalyticsPanelStyle.rowBackground)
                LabeledContent("回収額（pt換算）", value: "\(recoveryPt.formattedPtWithUnit)").listRowBackground(AnalyticsPanelStyle.rowBackground)
                LabeledContent("理論値", value: "\(session.theoreticalValue >= 0 ? "+" : "")\(session.theoreticalValue.formattedPtWithUnit)").listRowBackground(AnalyticsPanelStyle.rowBackground)
                LabeledContent("欠損・余剰", value: "\(session.deficitSurplus >= 0 ? "+" : "")\(session.deficitSurplus.formattedPtWithUnit)").listRowBackground(AnalyticsPanelStyle.rowBackground)
                LabeledContent("実成績", value: "\(session.performance >= 0 ? "+" : "")\(session.performance.formattedPtWithUnit)")
                    .font(.body.weight(.semibold))
                    .foregroundColor(session.performance >= 0 ? .green : .red)
                    .listRowBackground(AnalyticsPanelStyle.rowBackground)
            }
            Section("分析") {
                LabeledContent("理論値比（保存時）", value: session.expectationRatioAtSave > 0 ? String(format: "%.2f%%", session.expectationRatioAtSave * 100) : "—").listRowBackground(AnalyticsPanelStyle.rowBackground)
                LabeledContent("実質回転率", value: String(format: "%.1f 回/1k", rotationPer1k)).listRowBackground(AnalyticsPanelStyle.rowBackground)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(AppGlassStyle.background)
        .navigationTitle("履歴詳細")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .preferredColorScheme(.dark)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("編集") {
                    showEditSheet = true
                }
                .foregroundColor(AppGlassStyle.accent)
            }
        }
        .sheet(isPresented: $showEditSheet) {
            GameSessionEditView(sessionToEdit: session)
        }
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

/// 指定日の遊戯履歴のみ表示（ヒートマップのセルタップ先）
private struct AnalyticsDayDetailView: View {
    let day: Date
    let sessions: [GameSession]
    @Binding var bottomSegment: AnalyticsBottomSegment
    @Binding var selectedFilterLabel: String?
    @Binding var periodFilter: AnalyticsPeriodFilter
    @Binding var showPeriodSheet: Bool
    @Environment(\.dismiss) private var dismiss

    private static let cal = Calendar.current
    private var daySessions: [GameSession] {
        sessions.filter { Self.cal.isDate($0.date, inSameDayAs: day) }
            .sorted { $0.date > $1.date }
    }

    private var dayTitle: String {
        JapaneseDateFormatters.yearMonthDay.string(from: day)
    }

    var body: some View {
        ZStack {
            StaticHomeBackgroundView()
            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 12) {
                    ForEach(daySessions) { session in
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
        .navigationTitle(dayTitle)
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

/// 分析対象の遊戯履歴一覧（新しい順）。店舗/機種/メーカー別のセッション一覧（NavigationLink）用。メインの期間タブでは使用しない。
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
                    ForEach(sessionsGroupedByDay(filteredSessions), id: \.day.timeIntervalSince1970) { group in
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(group.sessions) { session in
                                NavigationLink(destination: AnalyticsSessionDetailView(session: session, sessions: sessions, bottomSegment: $bottomSegment, selectedFilterLabel: $selectedFilterLabel, periodFilter: $periodFilter, showPeriodSheet: $showPeriodSheet, onDismissToRoot: { DispatchQueue.main.async { dismiss() } })) {
                                    AnalyticsSessionCardView(session: session)
                                }
                                .buttonStyle(.plain)
                            }
                        }
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

    private var totalProfit: Int { shopSessions.reduce(0) { $0 + $1.performance } }
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
            let totalTheoretical = shopSessions.reduce(0) { $0 + $1.theoreticalValue }
            let totalDS = shopSessions.reduce(0) { $0 + $1.deficitSurplus }
            let rate = totalTheoretical != 0 ? Double(totalDS) / Double(abs(totalTheoretical)) : 0
            return (totalDS, rate)
        }
        return (g.totalDeficitSurplus, g.deficitSurplusRate)
    }

    private var cyan: Color { AppGlassStyle.accent }
    private var mutedGray: Color { Color.white.opacity(0.4) }

    /// 通算サマリ用の1行（ラベル左・値右）。1パネル内の行として使用
    private func summaryRow(title: String, value: String, valueColor: Color) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 10))
                .foregroundStyle(mutedGray)
            Spacer(minLength: 4)
            Text(value)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundColor(valueColor)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
    }

    var body: some View {
        ZStack {
            StaticHomeBackgroundView()
            ScrollView(showsIndicators: false) {
                VStack(spacing: 12) {
                    HStack(alignment: .top, spacing: 16) {
                        VStack(alignment: .leading, spacing: 8) {
                            summaryRow(
                                title: "通算実成績",
                                value: shopSessions.isEmpty ? "—" : "\(totalProfit >= 0 ? "+" : "")\(totalProfit.formattedPtWithUnit)",
                                valueColor: totalProfit >= 0 ? .green : .red
                            )
                            summaryRow(
                                title: "理論上成績",
                                value: shopSessions.isEmpty ? "—" : {
                                    let totalTheoretical = shopSessions.reduce(0) { $0 + $1.theoreticalValue }
                                    return "\(totalTheoretical >= 0 ? "+" : "")\(totalTheoretical.formattedPtWithUnit)"
                                }(),
                                valueColor: .white.opacity(0.9)
                            )
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        VStack(alignment: .leading, spacing: 8) {
                            summaryRow(
                                title: "通算実践回転率",
                                value: shopSessions.isEmpty || weightedAvgRotationPer1k <= 0 ? "—" : String(format: "%.1f 回/1k", weightedAvgRotationPer1k),
                                valueColor: .white
                            )
                            summaryRow(
                                title: "平均基準値差",
                                value: avgDiffFromFormulaBorder.map { String(format: "%+.1f 回/1k", $0) } ?? "—",
                                valueColor: (avgDiffFromFormulaBorder ?? 0) >= 0 ? cyan : Color.orange
                            )
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(AnalyticsPanelStyle.panelBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(AppGlassStyle.strokeGradient, lineWidth: 1)
                    )
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 4)

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
                        .foregroundColor(.white.opacity(0.95))
                        .shadow(color: .black.opacity(0.7), radius: 2, x: 0, y: 1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20)
                        .padding(.top, 8)

                    LazyVStack(spacing: 12) {
                        ForEach(sessionsGroupedByDay(shopSessions), id: \.day.timeIntervalSince1970) { group in
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(group.sessions) { session in
                                    NavigationLink(destination: AnalyticsSessionDetailView(session: session, sessions: sessions, bottomSegment: $bottomSegment, selectedFilterLabel: $selectedFilterLabel, periodFilter: $periodFilter, showPeriodSheet: $showPeriodSheet, onDismissToRoot: { DispatchQueue.main.async { dismiss() } })) {
                                        AnalyticsSessionCardView(session: session)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
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
    private var totalProfit: Int { machineSessions.reduce(0) { $0 + $1.performance } }
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
            let totalTheoretical = machineSessions.reduce(0) { $0 + $1.theoreticalValue }
            let totalDS = machineSessions.reduce(0) { $0 + $1.deficitSurplus }
            let rate = totalTheoretical != 0 ? Double(totalDS) / Double(abs(totalTheoretical)) : 0
            return (totalDS, rate)
        }
        return (g.totalDeficitSurplus, g.deficitSurplusRate)
    }
    private var cyan: Color { AppGlassStyle.accent }
    private var mutedGray: Color { Color.white.opacity(0.4) }
    /// 通算サマリ用の1行（ラベル左・値右）。1パネル内の行として使用
    private func summaryRow(title: String, value: String, valueColor: Color) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 10))
                .foregroundStyle(mutedGray)
            Spacer(minLength: 4)
            Text(value)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundColor(valueColor)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
    }

    /// 上部サマリパネル（全般タブ等と共通のデザイン）
    private var totalSummaryCard: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                summaryRow(
                    title: "通算実成績",
                    value: machineSessions.isEmpty ? "—" : "\(totalProfit >= 0 ? "+" : "")\(totalProfit.formattedPtWithUnit)",
                    valueColor: totalProfit >= 0 ? .green : .red
                )
                summaryRow(
                    title: "理論上成績",
                    value: machineSessions.isEmpty ? "—" : {
                        let totalTheoretical = machineSessions.reduce(0) { $0 + $1.theoreticalValue }
                        return "\(totalTheoretical >= 0 ? "+" : "")\(totalTheoretical.formattedPtWithUnit)"
                    }(),
                    valueColor: .white.opacity(0.9)
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .leading, spacing: 8) {
                summaryRow(
                    title: "通算実践回転率",
                    value: machineSessions.isEmpty || weightedAvgRotationPer1k <= 0 ? "—" : String(format: "%.1f 回/1k", weightedAvgRotationPer1k),
                    valueColor: .white
                )
                summaryRow(
                    title: "平均基準値差",
                    value: avgDiffFromFormulaBorder.map { String(format: "%+.1f 回/1k", $0) } ?? "—",
                    valueColor: (avgDiffFromFormulaBorder ?? 0) >= 0 ? cyan : Color.orange
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(AnalyticsPanelStyle.panelBackground)
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
                    totalSummaryCard
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
                        .foregroundColor(.white.opacity(0.95))
                        .shadow(color: .black.opacity(0.7), radius: 2, x: 0, y: 1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                    LazyVStack(spacing: 12) {
                        ForEach(sessionsGroupedByDay(machineSessions), id: \.day.timeIntervalSince1970) { group in
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(group.sessions) { session in
                                    NavigationLink(destination: AnalyticsSessionDetailView(session: session, sessions: sessions, bottomSegment: $bottomSegment, selectedFilterLabel: $selectedFilterLabel, periodFilter: $periodFilter, showPeriodSheet: $showPeriodSheet, onDismissToRoot: { DispatchQueue.main.async { dismiss() } })) {
                                        AnalyticsSessionCardView(session: session)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
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
    private var totalProfit: Int { manufacturerSessions.reduce(0) { $0 + $1.performance } }
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
            let totalTheoretical = manufacturerSessions.reduce(0) { $0 + $1.theoreticalValue }
            let totalDS = manufacturerSessions.reduce(0) { $0 + $1.deficitSurplus }
            let rate = totalTheoretical != 0 ? Double(totalDS) / Double(abs(totalTheoretical)) : 0
            return (totalDS, rate)
        }
        return (g.totalDeficitSurplus, g.deficitSurplusRate)
    }
    private var cyan: Color { AppGlassStyle.accent }
    private var mutedGray: Color { Color.white.opacity(0.4) }
    /// 通算サマリ用の1行（ラベル左・値右）。1パネル内の行として使用
    private func summaryRow(title: String, value: String, valueColor: Color) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 10))
                .foregroundStyle(mutedGray)
            Spacer(minLength: 4)
            Text(value)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundColor(valueColor)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
    }

    /// 上部サマリパネル（全般タブ等と共通のデザイン）
    private var totalSummaryCard: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                summaryRow(
                    title: "通算実成績",
                    value: manufacturerSessions.isEmpty ? "—" : "\(totalProfit >= 0 ? "+" : "")\(totalProfit.formattedPtWithUnit)",
                    valueColor: totalProfit >= 0 ? .green : .red
                )
                summaryRow(
                    title: "理論上成績",
                    value: manufacturerSessions.isEmpty ? "—" : {
                        let totalTheoretical = manufacturerSessions.reduce(0) { $0 + $1.theoreticalValue }
                        return "\(totalTheoretical >= 0 ? "+" : "")\(totalTheoretical.formattedPtWithUnit)"
                    }(),
                    valueColor: .white.opacity(0.9)
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .leading, spacing: 8) {
                summaryRow(
                    title: "通算実践回転率",
                    value: manufacturerSessions.isEmpty || weightedAvgRotationPer1k <= 0 ? "—" : String(format: "%.1f 回/1k", weightedAvgRotationPer1k),
                    valueColor: .white
                )
                summaryRow(
                    title: "平均基準値差",
                    value: avgDiffFromFormulaBorder.map { String(format: "%+.1f 回/1k", $0) } ?? "—",
                    valueColor: (avgDiffFromFormulaBorder ?? 0) >= 0 ? cyan : Color.orange
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(AnalyticsPanelStyle.panelBackground)
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
                    totalSummaryCard
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
                        .foregroundColor(.white.opacity(0.95))
                        .shadow(color: .black.opacity(0.7), radius: 2, x: 0, y: 1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                    LazyVStack(spacing: 12) {
                        ForEach(sessionsGroupedByDay(manufacturerSessions), id: \.day.timeIntervalSince1970) { group in
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(group.sessions) { session in
                                    NavigationLink(destination: AnalyticsSessionDetailView(session: session, sessions: sessions, bottomSegment: $bottomSegment, selectedFilterLabel: $selectedFilterLabel, periodFilter: $periodFilter, showPeriodSheet: $showPeriodSheet, onDismissToRoot: { DispatchQueue.main.async { dismiss() } })) {
                                        AnalyticsSessionCardView(session: session)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
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
/// 店舗分析時はパネル全体を実成績に応じてシアン〜マゼンタのグラデーションで tint（透明度維持）
struct AnalyticsGroupCard: View {
    let group: AnalyticsGroup
    let accent: Color
    /// 店舗タブ時のみ true。パネルをシアン〜マゼンタのグラデーションで着色
    var isShopSegment: Bool = false

    private static let magenta = Color(red: 1, green: 0, blue: 0.55)

    /// 店舗分析用：パネルオーバー用グラデーション（実成績プラス＝シアン寄り、マイナス＝マゼンタ寄り）。透明度は弱めに維持
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

    /// 二行目：実践回転率・回数・公式基準値との差（あれば）
    private var secondLineText: String {
        var s = "実践回転率 \(String(format: "%.1f", group.avgRotationRate))/1kpt · \(group.sessionCount)回"
        if let diff = group.avgDiffFromFormulaBorder {
            s += " （公式基準値との差: \(String(format: "%+.1f 回/1k", diff))"
        }
        return s
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(group.label)
                            .font(AppTypography.panelHeading)
                            .foregroundColor(.white)
                        Text("（遊技回数：\(group.sessionCount)回）")
                            .font(.caption2)
                            .foregroundColor(.white.opacity(0.65))
                    }
                    Text(secondLineText)
                        .font(AppTypography.bodyRounded)
                        .foregroundColor(.white.opacity(0.7))
                }
                Spacer()
            }
            HStack(alignment: .bottom, spacing: 12) {
                // 実成績を最前面に（強調）
                VStack(alignment: .leading, spacing: 2) {
                    Text("実成績")
                        .font(AppTypography.sectionSubheading)
                        .foregroundColor(.white.opacity(0.8))
                    Text("\(group.totalProfit >= 0 ? "+" : "")\(group.totalProfit.formattedPtWithUnit)")
                        .font(AppTypography.bodyMonoSemibold)
                        .monospacedDigit()
                        .foregroundColor(group.totalProfit >= 0 ? effectiveAccent : effectiveLossColor)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("理論")
                        .font(AppTypography.sectionSubheading)
                        .foregroundColor(.white.opacity(0.8))
                    Text("\(group.totalTheoreticalProfit >= 0 ? "+" : "")\(group.totalTheoreticalProfit)")
                        .font(AppTypography.bodyMonoSemibold)
                        .monospacedDigit()
                        .foregroundColor(.white.opacity(0.85))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("期待比")
                        .font(AppTypography.sectionSubheading)
                        .foregroundColor(.white.opacity(0.8))
                    Text("\(group.totalDeficitSurplus >= 0 ? "+" : "")\(group.totalDeficitSurplus.formattedPtWithUnit)")
                        .font(AppTypography.bodyMonoSemibold)
                        .monospacedDigit()
                        .foregroundColor(group.totalDeficitSurplus >= 0 ? effectiveAccent : effectiveLossColor)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("理論との差")
                        .font(AppTypography.bodyRounded)
                        .foregroundColor(.white.opacity(0.55))
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
        .background(AnalyticsPanelStyle.panelBackground)
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
// - 旧: 理論・実成績の2本並び → 長さの意味が伝わりにくい
// - 案A: 共通ゼロ軸で理論・実成績を左右に同じスケールで描く（情報量多め）
// - 案B: 理論を100%とする達成率バー（理論0や負のときは要工夫）
// 採用: 差だけ表示＝「理論よりどれだけ出た/損したか」がひと目で分かる
struct DeficitSurplusBarView: View {
    let deficitSurplus: Int
    let accent: Color
    var lossColor: Color = Color.orange
    /// 店舗分析時のみ指定。実成績がマイナスなら右伸びの棒も lossColor に（「理論よりマシだが実成績は赤字」と分かる）
    var barColorByActualProfit: Int? = nil

    /// 右方向の棒（理論との差プラス）の色。実成績マイナスならマゼンタ
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
                    // 余剰: 中央から右へ（実成績マイナスならマゼンタで「理論よりマシだがまだ赤字」）
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

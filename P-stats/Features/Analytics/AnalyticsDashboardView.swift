import SwiftUI
import SwiftData
import Charts
import Combine

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

    /// クロス分析パネル用：現在の期間フィルタの説明（下部ドックの設定と一致）
    func crossAnalysisPeriodCaption(referenceDate: Date) -> String {
        let cal = Calendar.current
        switch self {
        case .all:
            return "対象: 通算（全期間）— 期間は下部ドックで変更できます"
        case .last7:
            return "対象: 直近7日"
        case .last30:
            return "対象: 直近30日"
        case .year:
            let y = cal.component(.year, from: referenceDate)
            return "対象: \(y)年"
        case .month:
            return "対象: \(JapaneseDateFormatters.yearMonth.string(from: referenceDate))"
        case .day:
            return "対象: \(JapaneseDateFormatters.yearMonthDay.string(from: referenceDate))"
        }
    }
}

/// 全体・機種・メーカー一覧用：通常日・7のつく日・ゾロ目だけ（7分割の左3、右4は空白）。同一ファイル内の他 struct から参照するため internal
enum AnalyticsFixedSpecificDayLabels {
    static let list: [String] = ["通常日", "7のつく日", "ゾロ目"]
}

/// 分析スタック内の遷移先（下部ドックを画面外に固定するため `NavigationPath` と併用）
enum AnalyticsNavRoute: Hashable {
    case dayDetail(dayStart: TimeInterval)
    case shopDetail(name: String)
    case machineDetail(name: String)
    case manufacturerDetail(name: String)
    case sessionList(segment: AnalyticsSegment, groupLabel: String)
    case sessionDetail(id: UUID)
    /// 下部ドックはそのまま。全般内のクロス分析を専用画面へ（ドックにタブは増やさない）
    case crossAnalysis
}

/// 分析ドック・内部ナビ・一覧キャッシュをホームの下部インセットと画面本体で共有する
final class AnalyticsDashboardSharedModel: ObservableObject {
    @Published var bottomSegment: AnalyticsBottomSegment = .overview
    @Published var periodFilter: AnalyticsPeriodFilter = .all
    @Published var selectedFilterLabel: String?
    @Published var showPeriodSheet = false
    @Published var showGameSessionEdit = false
    @Published var heatmapSelectedDay: Date?
    @Published var analyticsNavPath: [AnalyticsNavRoute] = []
    @Published var selectedPeriodDate = Date()
    /// 全般タブのクロス分析：店×メーカー / 店×機種
    @Published var crossAnalysisDimension: CrossAnalysisDimension = .manufacturer
    /// 全般タブのクロス分析の並び順
    @Published var crossAnalysisSortAxis: CrossAnalysisSortAxis = .sessionsDesc
    @Published private(set) var cachedFilteredSessions: [GameSession] = []
    @Published private(set) var cachedAllGroups: [AnalyticsGroup] = []

    func updateCaches(sessionsQuery: [GameSession]) {
        let f = periodFilter.filter(sessionsQuery, referenceDate: selectedPeriodDate)
        cachedFilteredSessions = f
        switch bottomSegment {
        case .overview: cachedAllGroups = [AnalyticsEngine.overviewGroup(f)]
        case .shop: cachedAllGroups = AnalyticsEngine.byShop(f)
        case .machine: cachedAllGroups = AnalyticsEngine.byMachine(f)
        case .manufacturer: cachedAllGroups = AnalyticsEngine.byManufacturer(f)
        case .period:
            switch periodFilter {
            case .all, .year, .last30, .last7:
                cachedAllGroups = AnalyticsEngine.byMonth(f)
            case .month:
                cachedAllGroups = AnalyticsEngine.byCalendarDay(f)
            case .day:
                cachedAllGroups = f.isEmpty ? [] : [AnalyticsEngine.overviewGroup(f)]
            }
        }
    }
}

/// 分析スタック内のナビバー：背景をほぼ不透明にして視認性を確保
private struct AnalyticsNavigationBarChrome: ViewModifier {
    func body(content: Content) -> some View {
        content
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarBackground(Color.black.opacity(0.94), for: .navigationBar)
    }
}

private extension View {
    func analyticsNavigationBarChrome() -> some View {
        modifier(AnalyticsNavigationBarChrome())
    }
}

/// 左端から右へスワイプして戻る（`analyticsNavPath` が空ならホームへ閉じる／単体表示なら `dismiss`）。ドックの「戻る」と同じ動き。
private struct AnalyticsInteractiveEdgeSwipeBack: ViewModifier {
    @ObservedObject var model: AnalyticsDashboardSharedModel
    var onDismissEmbeddedToHome: (() -> Void)?
    @Environment(\.dismiss) private var dismiss

    func body(content: Content) -> some View {
        content.simultaneousGesture(
            DragGesture(minimumDistance: 24, coordinateSpace: .local)
                .onEnded { value in
                    let edgeWidth: CGFloat = 26
                    guard value.startLocation.x <= edgeWidth else { return }
                    guard value.translation.width >= 72 else { return }
                    guard value.translation.width > abs(value.translation.height) * 1.08 else { return }
                    HapticUtil.impact(.light)
                    if model.analyticsNavPath.isEmpty {
                        if let onDismissEmbeddedToHome {
                            onDismissEmbeddedToHome()
                        } else {
                            dismiss()
                        }
                    } else {
                        model.analyticsNavPath.removeLast()
                    }
                }
        )
    }
}

private extension View {
    func analyticsInteractiveEdgeSwipeBack(
        model: AnalyticsDashboardSharedModel,
        onDismissEmbeddedToHome: (() -> Void)?
    ) -> some View {
        modifier(AnalyticsInteractiveEdgeSwipeBack(
            model: model,
            onDismissEmbeddedToHome: onDismissEmbeddedToHome
        ))
    }
}

/// データ分析内パネル用スタイル（不透明度を15%上げて背景との重なりで文字が見にくくなるのを軽減）
private enum AnalyticsPanelStyle {
    static let panelBackground = Color.black.opacity(0.90)
    static let rowBackground = Color.black.opacity(0.85)
}

// MARK: - 分析フッター（ドック。ホーム下部タブバーと同一の黒パネル・下寄せ）
private struct AnalyticsBottomBarView: View {
    @ObservedObject private var entitlements = EntitlementsStore.shared
    @Binding var bottomSegment: AnalyticsBottomSegment
    @Binding var selectedFilterLabel: String?
    @Binding var periodFilter: AnalyticsPeriodFilter
    @Binding var showPeriodSheet: Bool
    @Binding var analyticsNavPath: [AnalyticsNavRoute]
    /// 内側スタックがルートのときにホームへ戻す（`dismiss`）
    var onDismissAnalyticsToHome: () -> Void

    private let dockTabCount = 6

    /// 均等6列のうちスポットライト列（戻る=0）
    private var dockSpotlightIndex: Int? {
        switch bottomSegment {
        case .overview: return 1
        case .shop: return 2
        case .machine: return 3
        case .manufacturer: return 4
        case .period: return 5
        }
    }

    var body: some View {
        AppGlassStyle.MainTabDockChrome(selectedTabIndex: dockSpotlightIndex, tabCount: dockTabCount) {
            HStack(alignment: .center, spacing: 0) {
                Button {
                    HapticUtil.impact(.light)
                    if analyticsNavPath.isEmpty {
                        onDismissAnalyticsToHome()
                    } else {
                        analyticsNavPath.removeLast()
                    }
                } label: {
                    VStack(spacing: AppGlassStyle.MainTabDock.tabIconLabelSpacing) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: AppGlassStyle.MainTabDock.iconPointSize, weight: .light))
                        Text("戻る")
                            .font(.system(size: AppGlassStyle.MainTabDock.labelPointSize, weight: .regular, design: .default))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .foregroundColor(AppGlassStyle.MainTabDock.inactiveTint)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: AppGlassStyle.MainTabDock.tabRowHeight, alignment: .center)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                ForEach([AnalyticsBottomSegment.overview, .shop, .machine, .manufacturer], id: \.self) { seg in
                    let on = seg == bottomSegment
                    Button {
                        HapticUtil.impact(.light)
                        if !entitlements.analyticsUnlocked && seg != .overview {
                            entitlements.showAnalyticsUpsellHalfSheet = true
                            return
                        }
                        withAnimation(.easeInOut(duration: 0.28)) {
                            bottomSegment = seg
                            selectedFilterLabel = nil
                        }
                        if !analyticsNavPath.isEmpty {
                            analyticsNavPath.removeAll()
                        }
                    } label: {
                        ZStack(alignment: .topTrailing) {
                            VStack(spacing: AppGlassStyle.MainTabDock.tabIconLabelSpacing) {
                                Image(systemName: seg.iconName(isSelected: on))
                                    .font(.system(
                                        size: AppGlassStyle.MainTabDock.iconPointSize,
                                        weight: on ? .semibold : .light
                                    ))
                                Text(seg.rawValue)
                                    .font(.system(
                                        size: AppGlassStyle.MainTabDock.labelPointSize,
                                        weight: on ? .semibold : .regular,
                                        design: .default
                                    ))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.75)
                            }
                            if !entitlements.analyticsUnlocked && seg != .overview {
                                Image(systemName: "lock.fill")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(AppGlassStyle.accent)
                                    .offset(x: 8, y: -6)
                                    .accessibilityHidden(true)
                            }
                        }
                        .foregroundColor(on ? Color.white : AppGlassStyle.MainTabDock.inactiveTint)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: AppGlassStyle.MainTabDock.tabRowHeight, alignment: .center)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                Button {
                    HapticUtil.impact(.light)
                    if !entitlements.analyticsUnlocked {
                        entitlements.showAnalyticsUpsellHalfSheet = true
                        return
                    }
                    if bottomSegment == .period {
                        showPeriodSheet = true
                    } else {
                        withAnimation(.easeInOut(duration: 0.28)) {
                            bottomSegment = .period
                            selectedFilterLabel = nil
                        }
                        if !analyticsNavPath.isEmpty {
                            analyticsNavPath.removeAll()
                        }
                    }
                } label: {
                    let periodOn = bottomSegment == .period
                    ZStack(alignment: .topTrailing) {
                        VStack(spacing: AppGlassStyle.MainTabDock.tabIconLabelSpacing) {
                            Image(systemName: AnalyticsBottomSegment.period.iconName(isSelected: periodOn))
                                .font(.system(
                                    size: AppGlassStyle.MainTabDock.iconPointSize,
                                    weight: periodOn ? .semibold : .light
                                ))
                            Text(periodFilter.label)
                                .font(.system(
                                    size: AppGlassStyle.MainTabDock.labelPointSize,
                                    weight: periodOn ? .semibold : .regular,
                                    design: .default
                                ))
                                .lineLimit(1)
                                .minimumScaleFactor(0.65)
                        }
                        if !entitlements.analyticsUnlocked {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(AppGlassStyle.accent)
                                .offset(x: 8, y: -6)
                                .accessibilityHidden(true)
                        }
                    }
                    .foregroundColor(periodOn ? Color.white : AppGlassStyle.MainTabDock.inactiveTint)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: AppGlassStyle.MainTabDock.tabRowHeight, alignment: .center)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .frame(maxWidth: .infinity)
        }
    }
}

// MARK: - 分析ドック一式（`AnalyticsDashboardView` 内の `NavigationStack` と同一階層の `safeAreaInset` に載せる）
struct AnalyticsDashboardBottomChrome: View {
    @ObservedObject var model: AnalyticsDashboardSharedModel
    @ObservedObject private var adVisibility = AdVisibilityManager.shared
    var onDismissToHome: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            if adVisibility.shouldShowBanner {
                AdaptiveBannerSlot(adUnitID: AdMobConfig.bannerUnitID)
                    .frame(maxWidth: .infinity)
                    .background(Color.black)
            }
            if model.periodFilter.showsPeriodDrum {
                DatePicker(selection: $model.selectedPeriodDate, displayedComponents: .date) {
                    Text(model.periodFilter.label)
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.8))
                }
                .datePickerStyle(.wheel)
                .labelsHidden()
                .colorScheme(.dark)
                .frame(height: 140)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(TranslucentBlurView(style: .systemUltraThinMaterialDark, alpha: 0.95))
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .padding(.horizontal, 20)
                .padding(.bottom, 8)
            }
            AnalyticsBottomBarView(
                bottomSegment: $model.bottomSegment,
                selectedFilterLabel: $model.selectedFilterLabel,
                periodFilter: $model.periodFilter,
                showPeriodSheet: $model.showPeriodSheet,
                analyticsNavPath: $model.analyticsNavPath,
                onDismissAnalyticsToHome: onDismissToHome
            )
        }
    }
}

private extension AnalyticsBottomSegment {
    /// Prime 風：非選択はアウトライン、選択はフィル
    func iconName(isSelected: Bool) -> String {
        switch self {
        case .overview:
            return isSelected ? "chart.bar.doc.horizontal.fill" : "chart.bar.doc.horizontal"
        case .shop:
            return isSelected ? "mappin.circle.fill" : "mappin.circle"
        case .machine:
            return isSelected ? "cpu.fill" : "cpu"
        case .manufacturer:
            return isSelected ? "building.2.fill" : "building.2"
        case .period:
            return isSelected ? "calendar.circle.fill" : "calendar"
        }
    }
}

/// 分析ダッシュボード（モダン・コンソール／片手操作最適化）
struct AnalyticsDashboardView: View {
    @ObservedObject var model: AnalyticsDashboardSharedModel
    /// false のとき下部ドックを出さない（実戦からのモーダル表示など）。ドックは必ずこのビュー内の `NavigationStack` の `safeAreaInset` に載せ、外側スタックに載せない（ヒットテストが内側に奪われるのを防ぐ）。
    var embedBottomChrome: Bool = true
    /// ホームの `NavigationStack` に埋め込んでいるとき、分析ルートで「戻る」した際に外側のパスを閉じる。nil のときは `dismiss()`（単体プレゼン用）。
    var onDismissEmbeddedToHome: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var entitlements = EntitlementsStore.shared
    @ObservedObject private var adVisibility = AdVisibilityManager.shared
    @Query(sort: \GameSession.date, order: .reverse) private var sessionsQuery: [GameSession]
    @Query private var shops: [Shop]
    @Query private var machines: [Machine]

    /// 期間フィルタをかけたセッション（店舗・機種・メーカー共通）
    private var filteredSessions: [GameSession] { model.cachedFilteredSessions }

    /// 機種名（トリム）→ マシン。同名は先勝ち。
    private var machinesByName: [String: Machine] {
        var d: [String: Machine] = [:]
        for m in machines {
            let k = m.name.trimmingCharacters(in: .whitespacesAndNewlines)
            if d[k] == nil { d[k] = m }
        }
        return d
    }

    private var overviewTotalSummary: AnalyticsOverviewTotalSummary {
        AnalyticsOverviewTotalSummary.compute(sessions: filteredSessions, machinesByName: machinesByName)
    }

    private var effectiveSegment: AnalyticsSegment {
        switch model.bottomSegment {
        case .overview: return .shop
        case .shop: return .shop
        case .machine: return .machine
        case .manufacturer: return .manufacturer
        case .period: return .month
        }
    }

    private var allGroups: [AnalyticsGroup] { model.cachedAllGroups }

    private var groups: [AnalyticsGroup] {
        guard let label = model.selectedFilterLabel else { return allGroups }
        return allGroups.filter { $0.label == label }
    }

    private func updateCaches() {
        model.updateCaches(sessionsQuery: sessionsQuery)
    }

    /// 店舗名 → 特定日ルール（分析で優先して使用）
    private var rulesByShopName: [String: SpecificDayRules] {
        Dictionary(uniqueKeysWithValues: shops.map { shop in
            (shop.name, SpecificDayRules.from(dayOfMonthString: shop.specificDayOfMonthStorage, lastDigitsString: shop.specificLastDigitsStorage, rulesStorage: shop.specificDayRulesStorage))
        })
    }

    private var cyan: Color { AppGlassStyle.accent }

    var body: some View {
        NavigationStack(path: $model.analyticsNavPath) {
            analyticsDashboardRoot
                .navigationDestination(for: AnalyticsNavRoute.self) { route in
                    analyticsDestinationContent(for: route)
                        .navigationBarBackButtonHidden(embedBottomChrome)
                        .analyticsNavigationBarChrome()
                }
        }
        .analyticsInteractiveEdgeSwipeBack(model: model, onDismissEmbeddedToHome: onDismissEmbeddedToHome)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if embedBottomChrome {
                analyticsBottomChrome
            }
        }
        .onAppear {
            if !entitlements.analyticsUnlocked, model.bottomSegment != .overview {
                model.bottomSegment = .overview
            }
            updateCaches()
        }
        .onChange(of: model.heatmapSelectedDay, initial: false) { _, newValue in
            guard let d = newValue else { return }
            let start = Calendar.current.startOfDay(for: d).timeIntervalSince1970
            model.analyticsNavPath.append(.dayDetail(dayStart: start))
            model.heatmapSelectedDay = nil
        }
        .sheet(isPresented: $entitlements.showAnalyticsUpsellHalfSheet) {
            AnalyticsUpgradeHalfSheet()
                .presentationDetents([.medium])
        }
        .onChange(of: sessionsQuery) { _, _ in updateCaches() }
        .onChange(of: model.periodFilter) { _, _ in updateCaches() }
        .onChange(of: model.selectedPeriodDate) { _, _ in updateCaches() }
        .onChange(of: model.bottomSegment) { _, _ in updateCaches() }
        .sheet(isPresented: $model.showPeriodSheet) {
            AnalyticsPeriodPickerSheet(selected: $model.periodFilter)
        }
        .sheet(isPresented: $model.showGameSessionEdit) {
            GameSessionEditView()
        }
    }

    /// ドックの全般・店舗・機種・メーカーに対応するルートのナビタイトル
    private var analyticsRootNavigationTitle: String {
        switch model.bottomSegment {
        case .overview: return "全般分析"
        case .shop: return "店舗分析"
        case .machine: return "機種分析"
        case .manufacturer: return "メーカー分析"
        case .period: return "期間分析"
        }
    }

    private var analyticsDashboardRoot: some View {
        ZStack {
            StaticHomeBackgroundView()
            VStack(spacing: 0) {
                if filteredSessions.isEmpty {
                    emptyState
                } else {
                    listContent
                }
            }
        }
        .navigationTitle(analyticsRootNavigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .analyticsNavigationBarChrome()
        .preferredColorScheme(.dark)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: {
                    model.showGameSessionEdit = true
                }) {
                    Image(systemName: "plus")
                        .foregroundColor(cyan)
                }
            }
        }
    }

    private var analyticsBottomChrome: some View {
        AnalyticsDashboardBottomChrome(model: model, onDismissToHome: {
            if let onDismissEmbeddedToHome {
                onDismissEmbeddedToHome()
            } else {
                dismiss()
            }
        })
    }

    private func appendAnalyticsRoute(_ route: AnalyticsNavRoute) {
        model.analyticsNavPath.append(route)
    }

    /// 期間タブ一覧からの遷移（フィルタに応じて日詳細または月キー単位のセッション一覧）
    private func openPeriodAnalyticsGroup(_ g: AnalyticsGroup) {
        switch model.periodFilter {
        case .day:
            let t = Calendar.current.startOfDay(for: model.selectedPeriodDate).timeIntervalSince1970
            appendAnalyticsRoute(.dayDetail(dayStart: t))
        case .month:
            if let t = TimeInterval(g.id) {
                appendAnalyticsRoute(.dayDetail(dayStart: t))
            }
        case .all, .year, .last30, .last7:
            appendAnalyticsRoute(.sessionList(segment: .month, groupLabel: g.label))
        }
    }

    /// 同一スタック・単一の `navigationDestination(for: AnalyticsNavRoute.self)` のみにする（再帰登録は `AnyNavigationPath` の比較エラー誘因になりうる）。
    @ViewBuilder
    private func analyticsDestinationContent(for route: AnalyticsNavRoute) -> some View {
        switch route {
        case .dayDetail(let t):
            let day = Date(timeIntervalSince1970: t)
            AnalyticsDayDetailView(
                day: day,
                sessions: filteredSessions,
                bottomSegment: $model.bottomSegment,
                selectedFilterLabel: $model.selectedFilterLabel,
                periodFilter: $model.periodFilter,
                showPeriodSheet: $model.showPeriodSheet,
                scrollBottomInset: 120,
                onSessionTap: { appendAnalyticsRoute(.sessionDetail(id: $0)) }
            )
        case .sessionDetail(let id):
            if let s = filteredSessions.first(where: { $0.id == id }) {
                AnalyticsSessionDetailView(
                    session: s,
                    sessions: filteredSessions,
                    bottomSegment: $model.bottomSegment,
                    selectedFilterLabel: $model.selectedFilterLabel,
                    periodFilter: $model.periodFilter,
                    showPeriodSheet: $model.showPeriodSheet
                )
            } else {
                Text("データが見つかりません")
                    .foregroundStyle(.white)
            }
        case .shopDetail(let name):
            AnalyticsShopDetailView(
                shopName: name,
                sessions: filteredSessions,
                machinesByName: machinesByName,
                rulesByShopName: rulesByShopName,
                orderedSpecificDayLabels: shops.first(where: { $0.name == name }).map { SpecificDayRules.orderedLabels(rulesStorage: $0.specificDayRulesStorage, dayOfMonthFallback: $0.specificDayOfMonthStorage, lastDigitsFallback: $0.specificLastDigitsStorage) } ?? [],
                bottomSegment: $model.bottomSegment,
                selectedFilterLabel: $model.selectedFilterLabel,
                periodFilter: $model.periodFilter,
                showPeriodSheet: $model.showPeriodSheet,
                onSessionTap: { appendAnalyticsRoute(.sessionDetail(id: $0)) }
            )
        case .machineDetail(let name):
            AnalyticsMachineDetailView(
                machineName: name,
                sessions: filteredSessions,
                machinesByName: machinesByName,
                rulesByShopName: rulesByShopName,
                bottomSegment: $model.bottomSegment,
                selectedFilterLabel: $model.selectedFilterLabel,
                periodFilter: $model.periodFilter,
                showPeriodSheet: $model.showPeriodSheet,
                onSessionTap: { appendAnalyticsRoute(.sessionDetail(id: $0)) }
            )
        case .manufacturerDetail(let name):
            AnalyticsManufacturerDetailView(
                manufacturerName: name,
                sessions: filteredSessions,
                machinesByName: machinesByName,
                rulesByShopName: rulesByShopName,
                bottomSegment: $model.bottomSegment,
                selectedFilterLabel: $model.selectedFilterLabel,
                periodFilter: $model.periodFilter,
                showPeriodSheet: $model.showPeriodSheet,
                onSessionTap: { appendAnalyticsRoute(.sessionDetail(id: $0)) }
            )
        case .sessionList(let segment, let groupLabel):
            AnalyticsSessionListView(
                segment: segment,
                groupLabel: groupLabel,
                sessions: filteredSessions,
                bottomSegment: $model.bottomSegment,
                selectedFilterLabel: $model.selectedFilterLabel,
                periodFilter: $model.periodFilter,
                showPeriodSheet: $model.showPeriodSheet,
                onSessionTap: { appendAnalyticsRoute(.sessionDetail(id: $0)) }
            )
        case .crossAnalysis:
            CrossAnalysisFullScreenView(
                sessions: filteredSessions,
                periodFilter: model.periodFilter,
                selectedPeriodDate: model.selectedPeriodDate,
                dimension: $model.crossAnalysisDimension,
                sortAxis: $model.crossAnalysisSortAxis,
                cyan: cyan
            )
        }
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
                if model.bottomSegment == .overview && !filteredSessions.isEmpty {
                    OverviewTotalSummaryPanel(metrics: overviewTotalSummary, accent: cyan)
                    CumulativeProfitTrendSection(sessions: filteredSessions, cyan: cyan)
                    CalendarHeatmapSection(sessions: filteredSessions, cyan: cyan, selectedDay: $model.heatmapSelectedDay, bottomSegment: $model.bottomSegment, selectedFilterLabel: $model.selectedFilterLabel, periodFilter: $model.periodFilter, showPeriodSheet: $model.showPeriodSheet)
                    if entitlements.analyticsUnlocked {
                        CrossAnalysisOverviewSection(
                            sessions: filteredSessions,
                            periodFilter: model.periodFilter,
                            selectedPeriodDate: model.selectedPeriodDate,
                            dimension: $model.crossAnalysisDimension,
                            sortAxis: $model.crossAnalysisSortAxis,
                            cyan: cyan,
                            onRequestFullScreen: { appendAnalyticsRoute(.crossAnalysis) }
                        )
                    }
                    Button {
                        HapticUtil.impact(.light)
                        appendAnalyticsRoute(.sessionList(segment: .shop, groupLabel: "全体"))
                    } label: {
                        Text("実戦履歴")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(AnalyticsPanelStyle.panelBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .stroke(AppGlassStyle.strokeGradient, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
                if model.bottomSegment != .overview {
                    ForEach(groups) { g in
                        Group {
                            if model.bottomSegment == .shop {
                                Button {
                                    appendAnalyticsRoute(.shopDetail(name: g.label))
                                } label: {
                                    AnalyticsGroupCard(
                                        group: g,
                                        accent: cyan,
                                        compactListSessions: filteredSessions.filter { ($0.shopName.isEmpty ? "未設定" : $0.shopName) == g.label },
                                        machinesByNameForCompact: machinesByName
                                    )
                                }
                            } else if model.bottomSegment == .machine {
                                Button {
                                    appendAnalyticsRoute(.machineDetail(name: g.label))
                                } label: {
                                    AnalyticsGroupCard(
                                        group: g,
                                        accent: cyan,
                                        compactListSessions: filteredSessions.filter { ($0.machineName.isEmpty ? "未設定" : $0.machineName) == g.label },
                                        machinesByNameForCompact: machinesByName
                                    )
                                }
                            } else if model.bottomSegment == .period {
                                Button {
                                    openPeriodAnalyticsGroup(g)
                                } label: {
                                    AnalyticsGroupCard(group: g, accent: cyan)
                                }
                            } else {
                                Button {
                                    appendAnalyticsRoute(.manufacturerDetail(name: g.label))
                                } label: {
                                    AnalyticsGroupCard(
                                        group: g,
                                        accent: cyan,
                                        compactListSessions: filteredSessions.filter {
                                            let row = $0.manufacturerName.trimmingCharacters(in: .whitespaces).isEmpty ? "未設定" : $0.manufacturerName
                                            let card = g.label.trimmingCharacters(in: .whitespaces).isEmpty ? "未設定" : g.label
                                            return row == card
                                        },
                                        machinesByNameForCompact: machinesByName
                                    )
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 120)
        }
    }

}

/// 全般タブ最上段：タップで遷移しない「通算サマリー」
private struct OverviewTotalSummaryPanel: View {
    let metrics: AnalyticsOverviewTotalSummary
    let accent: Color
    /// 店舗詳細などで同じブロックを使うときの見出し（デフォルトは通算サマリー）
    var panelTitle: String = "通算サマリー"

    private var lossColor: Color { Color.orange }
    private var neutral: Color { Color.white.opacity(0.92) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(panelTitle)
                .font(AppTypography.panelHeading)
                .foregroundColor(.white)
                .padding(.bottom, 10)

            summaryPairRow(
                "通算成績", signedPt(metrics.totalPerformance), metrics.totalPerformance >= 0 ? accent : lossColor,
                "通算遊技回数", "\(metrics.sessionCount)回", neutral
            )
            summaryDivider()
            summaryPairRow(
                "総投資額", "\(metrics.totalInputCash.formattedPtWithUnit)", neutral,
                "総回収額", "\(metrics.totalRecoveryPt.formattedPtWithUnit)", neutral
            )
            summaryDivider()
            summaryPairRow(
                "勝利回数", "\(metrics.winCount)回", neutral,
                "敗北回数", "\(metrics.loseCount)回", neutral
            )
            summaryDivider()
            summaryPairRow(
                "勝率", metrics.winRatePercent.map { String(format: "%.1f%%", $0) } ?? "—", neutral,
                "平均初当たり確率", metrics.avgFirstHitProbabilityText ?? "—", neutral
            )
            summaryDivider()
            summaryPairRow(
                "通算期待値", signedPt(metrics.totalTheoretical), metrics.totalTheoretical >= 0 ? accent : lossColor,
                "期待値との差", signedPt(metrics.totalExpectationDiff), metrics.totalExpectationDiff >= 0 ? accent : lossColor
            )
            summaryDivider()
            summaryPairRow(
                "平均回転率", metrics.avgRotationPer1k.map { String(format: "%.1f 回/1k", $0) } ?? "—", neutral,
                "公式ボーダーとの差",
                metrics.avgBorderDiffPer1k.map { String(format: "%+.1f 回/1k", $0) } ?? "—",
                {
                    guard let d = metrics.avgBorderDiffPer1k else { return neutral }
                    return d >= 0 ? accent : lossColor
                }()
            )
            summaryDivider()
            summaryPairRow(
                "1日の最大投資額", "\(metrics.maxDailyInput.formattedPtWithUnit)", neutral,
                "1日の最高回収額", "\(metrics.maxDailyRecovery.formattedPtWithUnit)", neutral
            )
            summaryDivider()
            summaryPairRow(
                "1日の最高収支額", signedPt(metrics.maxDailyPerformance), metrics.maxDailyPerformance >= 0 ? accent : lossColor,
                "平均収支",
                metrics.avgPerformancePerSession.map { String(format: "%+.1f pt", $0) } ?? "—",
                metrics.avgPerformancePerSession.map { $0 >= 0 ? accent : lossColor } ?? neutral
            )
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AnalyticsPanelStyle.panelBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(AppGlassStyle.strokeGradient, lineWidth: 1)
        )
        .allowsHitTesting(false)
    }

    private func signedPt(_ n: Int) -> String {
        "\(n >= 0 ? "+" : "")\(n.formattedPtWithUnit)"
    }

    private func summaryDivider() -> some View {
        Rectangle()
            .fill(Color.white.opacity(0.12))
            .frame(height: 1)
            .padding(.vertical, 8)
    }

    private func summaryPairRow(
        _ leftTitle: String, _ leftValue: String, _ leftColor: Color,
        _ rightTitle: String, _ rightValue: String, _ rightColor: Color
    ) -> some View {
        twoCol(leftTitle, leftValue, leftColor, rightTitle, rightValue, rightColor)
    }

    private func oneCol(_ title: String, _ value: String, _ valueColor: Color) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(AppTypography.bodyRounded)
                .foregroundStyle(Color.white.opacity(0.55))
            Spacer(minLength: 8)
            Text(value)
                .font(AppTypography.bodyMonoSemibold)
                .monospacedDigit()
                .foregroundColor(valueColor)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }

    private func twoCol(
        _ leftTitle: String, _ leftValue: String, _ leftColor: Color,
        _ rightTitle: String, _ rightValue: String, _ rightColor: Color
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(leftTitle)
                    .font(AppTypography.bodyRounded)
                    .foregroundStyle(Color.white.opacity(0.55))
                Text(leftValue)
                    .font(AppTypography.bodyMonoSemibold)
                    .monospacedDigit()
                    .foregroundColor(leftColor)
                    .lineLimit(2)
                    .minimumScaleFactor(0.75)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .leading, spacing: 4) {
                Text(rightTitle)
                    .font(AppTypography.bodyRounded)
                    .foregroundStyle(Color.white.opacity(0.55))
                Text(rightValue)
                    .font(AppTypography.bodyMonoSemibold)
                    .monospacedDigit()
                    .foregroundColor(rightColor)
                    .lineLimit(2)
                    .minimumScaleFactor(0.75)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// 実戦画面などホーム外から開く分析（独立した `ObservableObject` を保持）。下部ドックは出さずナビゲーションの戻るで階層移動する。
struct StandaloneAnalyticsDashboardView: View {
    @StateObject private var model = AnalyticsDashboardSharedModel()

    var body: some View {
        AnalyticsDashboardView(model: model, embedBottomChrome: false)
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

// MARK: - クロス分析（全般タブ：店×メーカー／店×機種・期間連動・並び替え）

/// パネル内外で共有する中身（外枠のグラスパネルは呼び出し側）
private struct CrossAnalysisPanelCore: View {
    let sessions: [GameSession]
    let periodFilter: AnalyticsPeriodFilter
    let selectedPeriodDate: Date
    @Binding var dimension: CrossAnalysisDimension
    @Binding var sortAxis: CrossAnalysisSortAxis
    let cyan: Color
    var onRequestFullScreen: (() -> Void)? = nil

    private var periodCaption: String {
        periodFilter.crossAnalysisPeriodCaption(referenceDate: selectedPeriodDate)
    }

    private var manufacturerRows: [ShopManufacturerCrossRow] {
        AnalyticsEngine.shopManufacturerCrossRows(sessions, sortBy: sortAxis)
    }

    private var machineRows: [ShopMachineCrossRow] {
        AnalyticsEngine.shopMachineCrossRows(sessions, sortBy: sortAxis)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Text("クロス分析")
                    .font(AppTypography.panelHeading)
                    .foregroundColor(.white)
                InfoIconView(
                    explanation: "店舗とメーカー、または店舗と機種の組み合わせごとに集計します。同一組み合わせの実戦が2件以上あるときだけ表示します。下部ドックの「期間」（通算・直近・年月日）に連動します。並び替えで回りやすさ・収支の振れを見つけやすくできます。",
                    tint: .white.opacity(0.6)
                )
            }

            if let openFull = onRequestFullScreen {
                Button(action: openFull) {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.caption.weight(.semibold))
                        Text("全画面で開く")
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                    }
                    .foregroundColor(cyan)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(AnalyticsPanelStyle.rowBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(AppGlassStyle.strokeGradient.opacity(0.75), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }

            Text(periodCaption)
                .font(.caption)
                .foregroundColor(.white.opacity(0.62))
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 10) {
                Picker("軸", selection: $dimension) {
                    ForEach(CrossAnalysisDimension.allCases) { d in
                        Text(d.rawValue).tag(d)
                    }
                }
                .pickerStyle(.segmented)

                Menu {
                    Picker("並び替え", selection: $sortAxis) {
                        ForEach(CrossAnalysisSortAxis.allCases) { axis in
                            Text(axis.menuLabel).tag(axis)
                        }
                    }
                } label: {
                    HStack {
                        Text("並び替え: \(sortAxis.menuLabel)")
                            .font(.subheadline.weight(.medium))
                            .foregroundColor(.white.opacity(0.92))
                        Spacer()
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(cyan.opacity(0.9))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(AnalyticsPanelStyle.rowBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.white.opacity(0.12), lineWidth: 1)
                    )
                }
            }

            Group {
                switch dimension {
                case .manufacturer:
                    if manufacturerRows.isEmpty {
                        emptyHint(isMachine: false)
                    } else {
                        VStack(spacing: 10) {
                            ForEach(manufacturerRows) { row in
                                CrossAnalysisPairRowCard(
                                    shop: row.shop,
                                    counterpart: row.manufacturer,
                                    sessionCount: row.sessionCount,
                                    avgRotationPer1k: row.avgRotationPer1k,
                                    totalProfit: row.totalProfit,
                                    avgDiffFromFormulaBorder: row.avgDiffFromFormulaBorder,
                                    cyan: cyan
                                )
                            }
                        }
                    }
                case .machine:
                    if machineRows.isEmpty {
                        emptyHint(isMachine: true)
                    } else {
                        VStack(spacing: 10) {
                            ForEach(machineRows) { row in
                                CrossAnalysisPairRowCard(
                                    shop: row.shop,
                                    counterpart: row.machine,
                                    sessionCount: row.sessionCount,
                                    avgRotationPer1k: row.avgRotationPer1k,
                                    totalProfit: row.totalProfit,
                                    avgDiffFromFormulaBorder: row.avgDiffFromFormulaBorder,
                                    cyan: cyan
                                )
                            }
                        }
                    }
                }
            }
        }
    }

    private func emptyHint(isMachine: Bool) -> some View {
        Text(
            isMachine
                ? "表示できる組み合わせがありません（同一店・同一機種の実戦を2件以上蓄えると表示されます）"
                : "表示できる組み合わせがありません（同一店・同一メーカー分類の実戦を2件以上蓄えると表示されます）"
        )
        .font(.caption)
        .foregroundColor(.white.opacity(0.65))
    }
}

/// 全般タブ一覧内：ヒートマップ等と同じ外周パネル
private struct CrossAnalysisOverviewSection: View {
    let sessions: [GameSession]
    let periodFilter: AnalyticsPeriodFilter
    let selectedPeriodDate: Date
    @Binding var dimension: CrossAnalysisDimension
    @Binding var sortAxis: CrossAnalysisSortAxis
    let cyan: Color
    var onRequestFullScreen: (() -> Void)?

    var body: some View {
        CrossAnalysisPanelCore(
            sessions: sessions,
            periodFilter: periodFilter,
            selectedPeriodDate: selectedPeriodDate,
            dimension: $dimension,
            sortAxis: $sortAxis,
            cyan: cyan,
            onRequestFullScreen: onRequestFullScreen
        )
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AnalyticsPanelStyle.panelBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(AppGlassStyle.strokeGradient, lineWidth: 1)
        )
    }
}

/// ドックは増やさずナビで専用画面（同一モデルのバインディングを共有）
private struct CrossAnalysisFullScreenView: View {
    let sessions: [GameSession]
    let periodFilter: AnalyticsPeriodFilter
    let selectedPeriodDate: Date
    @Binding var dimension: CrossAnalysisDimension
    @Binding var sortAxis: CrossAnalysisSortAxis
    let cyan: Color

    var body: some View {
        ZStack {
            StaticHomeBackgroundView()
            ScrollView(showsIndicators: false) {
                CrossAnalysisPanelCore(
                    sessions: sessions,
                    periodFilter: periodFilter,
                    selectedPeriodDate: selectedPeriodDate,
                    dimension: $dimension,
                    sortAxis: $sortAxis,
                    cyan: cyan,
                    onRequestFullScreen: nil
                )
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AnalyticsPanelStyle.panelBackground)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(AppGlassStyle.strokeGradient, lineWidth: 1)
                )
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 120)
            }
        }
        .navigationTitle("クロス分析")
        .navigationBarTitleDisplayMode(.inline)
        .analyticsNavigationBarChrome()
        .preferredColorScheme(.dark)
    }
}

private struct CrossAnalysisPairRowCard: View {
    let shop: String
    let counterpart: String
    let sessionCount: Int
    let avgRotationPer1k: Double
    let totalProfit: Int
    let avgDiffFromFormulaBorder: Double?
    let cyan: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(shop)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white)
                Image(systemName: "multiply")
                    .font(.caption.weight(.light))
                    .foregroundColor(.white.opacity(0.45))
                Text(counterpart)
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(cyan.opacity(0.95))
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                Spacer()
                Text("実戦 \(sessionCount)件")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.55))
            }
            HStack(spacing: 14) {
                crossAnalysisMetric(title: "回転率", value: avgRotationPer1k > 0 ? String(format: "%.1f/1k", avgRotationPer1k) : "—")
                crossAnalysisMetric(
                    title: "ボーダー差",
                    value: avgDiffFromFormulaBorder.map { String(format: "%+.1f", $0) } ?? "—",
                    valueColor: (avgDiffFromFormulaBorder ?? 0) >= 0 ? cyan : Color.orange
                )
                crossAnalysisMetric(
                    title: "実成績",
                    value: "\(totalProfit >= 0 ? "+" : "")\(totalProfit.formattedPtWithUnit)",
                    valueColor: totalProfit >= 0 ? .green : .red
                )
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(AnalyticsPanelStyle.rowBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
    }

    private func crossAnalysisMetric(title: String, value: String, valueColor: Color = .white.opacity(0.92)) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 10))
                .foregroundColor(.white.opacity(0.42))
            Text(value)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundColor(valueColor)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
        VStack(alignment: .leading, spacing: 14) {
            Text("曜日傾向")
                .font(AppTypography.panelHeading)
                .foregroundColor(.white)
            chartRow(title: "実成績") {
                    Chart {
                        RuleMark(y: .value("ゼロ", 0))
                            .foregroundStyle(Color.white.opacity(0.4))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        ForEach(groups) { g in
                            BarMark(
                                x: .value("曜日", g.label),
                                y: .value("pt", g.totalProfit),
                                width: .ratio(0.8)
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
                            y: .value("回/1k", g.avgRotationRate),
                            width: .ratio(0.8)
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
                chartRow(title: "期待値との差（欠損・余剰）") {
                    Chart {
                        RuleMark(y: .value("ゼロ", 0))
                            .foregroundStyle(Color.white.opacity(0.4))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        ForEach(groups) { g in
                            BarMark(
                                x: .value("曜日", g.label),
                                y: .value("pt", g.totalDeficitSurplus),
                                width: .ratio(0.8)
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
        VStack(alignment: .leading, spacing: 14) {
            Text("特定日傾向")
                .font(AppTypography.panelHeading)
                .foregroundColor(.white)
            chartRow(title: "実成績") {
                    Chart {
                        RuleMark(y: .value("ゼロ", 0))
                            .foregroundStyle(Color.white.opacity(0.4))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        ForEach(displayGroups) { g in
                            BarMark(
                                x: .value("区分", g.label),
                                y: .value("pt", g.label.hasPrefix("_pad") ? 0 : g.totalProfit),
                                width: .ratio(0.8)
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
                            y: .value("回/1k", g.label.hasPrefix("_pad") ? 0 : g.avgRotationRate),
                            width: .ratio(0.8)
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
                chartRow(title: "期待値との差（欠損・余剰）") {
                    Chart {
                        RuleMark(y: .value("ゼロ", 0))
                            .foregroundStyle(Color.white.opacity(0.4))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        ForEach(displayGroups) { g in
                            BarMark(
                                x: .value("区分", g.label),
                                y: .value("pt", g.label.hasPrefix("_pad") ? 0 : g.totalDeficitSurplus),
                                width: .ratio(0.8)
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

    private func chartRow<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption).foregroundColor(.white.opacity(0.7))
            content().frame(height: 72).chartLegend(.hidden)
        }
    }
}

// MARK: - 月間／週間 収支トレンド（累計実成績・累計期待値＋差の棒。タップで切替）
private struct CumulativeProfitTrendSection: View {
    let sessions: [GameSession]
    let cyan: Color

    @State private var showsWeekly = false

    private var underperformRed: Color {
        Color(
            red: DesignTokens.Color.edgeGlowRedR,
            green: DesignTokens.Color.edgeGlowRedG,
            blue: DesignTokens.Color.edgeGlowRedB
        )
    }

    private var monthlyRows: [(periodKey: String, axisLabel: String, cumulativeProfit: Int, cumulativeTheoretical: Int)] {
        AnalyticsEngine.monthlyCumulativeTrend(sessions).map { m in
            (periodKey: m.month, axisLabel: "", cumulativeProfit: m.cumulativeProfit, cumulativeTheoretical: m.cumulativeTheoretical)
        }
    }

    private var weeklyRows: [(periodKey: String, axisLabel: String, cumulativeProfit: Int, cumulativeTheoretical: Int)] {
        AnalyticsEngine.weeklyCumulativeTrend(sessions, maxWeeks: 12).map { w in
            (periodKey: w.weekId, axisLabel: w.weekLabel, cumulativeProfit: w.cumulativeProfit, cumulativeTheoretical: w.cumulativeTheoretical)
        }
    }

    private var trendData: [(periodKey: String, axisLabel: String, cumulativeProfit: Int, cumulativeTheoretical: Int)] {
        showsWeekly ? weeklyRows : monthlyRows
    }

    private struct TrendDiffBar: Identifiable {
        let id: String
        let diff: Int
    }

    private var trendDiffBars: [TrendDiffBar] {
        trendData.map {
            TrendDiffBar(id: $0.periodKey, diff: $0.cumulativeProfit - $0.cumulativeTheoretical)
        }
    }

    private static let chartExplanationMonthly =
        "上段の折れ線は、各月末時点の累計実成績（実線・●）と累計期待値（破線・□）です。下段の棒は同じ時点での「累計実成績 − 累計期待値」。棒がゼロより上ならその時点では期待値より上振れ、下なら下振れです。"

    private static let chartExplanationWeekly =
        "上段は、各週の週頭日までの累計実成績と累計期待値（週の並びはカレンダー週・直近12週）。下段の棒は累計の差（実−期待値）。横軸の週は「M/d〜」表記です。"

    private var chartExplanation: String {
        showsWeekly ? Self.chartExplanationWeekly : Self.chartExplanationMonthly
    }

    /// 目盛用：データが複数年にまたがるときだけ年を付ける（月間のみ）
    private var chartYears: Set<String> {
        Set(monthlyRows.compactMap { key in
            key.periodKey.split(separator: "/").first.map(String.init)
        })
    }

    private func monthAxisLabel(for yyyyMm: String) -> String {
        let p = yyyyMm.split(separator: "/").map(String.init)
        guard p.count == 2, let y = Int(p[0]), let m = Int(p[1]) else { return yyyyMm }
        if chartYears.count <= 1 { return "\(m)月" }
        return "\(y)年\(m)月"
    }

    private func axisLabel(for periodKey: String) -> String {
        if showsWeekly {
            return trendData.first(where: { $0.periodKey == periodKey })?.axisLabel ?? periodKey
        }
        return monthAxisLabel(for: periodKey)
    }

    /// 横に詰まりすぎるとき間引く（目盛キーのみ）
    private var xAxisPeriodKeys: [String] {
        let keys = trendData.map(\.periodKey)
        if showsWeekly {
            guard keys.count > 8 else { return keys }
            let step = max(1, (keys.count + 7) / 8)
            return Swift.stride(from: 0, to: keys.count, by: step).map { keys[$0] }
        }
        guard keys.count > 14 else { return keys }
        let step = max(1, (keys.count + 11) / 12)
        return Swift.stride(from: 0, to: keys.count, by: step).map { keys[$0] }
    }

    var body: some View {
        Group {
            if trendData.isEmpty {
                EmptyView()
            } else {
                VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center, spacing: 6) {
                    Button {
                        showsWeekly.toggle()
                    } label: {
                        HStack(spacing: 6) {
                            Text(showsWeekly ? "週間収支トレンド" : "月間収支トレンド")
                                .font(AppTypography.panelHeading)
                                .foregroundColor(.white)
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.white.opacity(0.55))
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("タップで月間と週間を切り替え")
                    InfoIconView(explanation: chartExplanation, tint: .white.opacity(0.6))
                }
                Text("折れ線は累計の推移。棒はその時点の累計「実成績−期待値」。")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.58))
                    .fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: 10) {
                    cumulativeTrendLinesChart
                    cumulativeDiffBarsChart
                }
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 14) {
                        legendDot(cyan, label: "累計実成績", symbolCircle: true)
                        legendDot(Color.white.opacity(0.88), label: "累計期待値", dashed: true, symbolSquare: true)
                    }
                    HStack(spacing: 14) {
                        legendDot(cyan, label: "差＋（上振れ）", bar: true)
                        legendDot(underperformRed, label: "差−（下振れ）", bar: true)
                    }
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

    private var cumulativeTrendLinesChart: some View {
        Chart {
            ForEach(trendData, id: \.periodKey) { d in
                LineMark(
                    x: .value("期間", d.periodKey),
                    y: .value("pt", d.cumulativeProfit)
                )
                .interpolationMethod(.monotone)
                .foregroundStyle(cyan)
                .lineStyle(StrokeStyle(lineWidth: 2.25))
                .symbol(.circle)
                .symbolSize(36)
            }
            ForEach(trendData, id: \.periodKey) { d in
                LineMark(
                    x: .value("期間", d.periodKey),
                    y: .value("pt", d.cumulativeTheoretical)
                )
                .interpolationMethod(.monotone)
                .foregroundStyle(Color.white.opacity(0.88))
                .lineStyle(StrokeStyle(lineWidth: 1.6, dash: [6, 4]))
                .symbol(.square)
                .symbolSize(28)
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 6)) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(Color.white.opacity(0.2))
                AxisValueLabel { if let v = value.as(Int.self) { Text("\(v / 10000)万") } }.foregroundStyle(Color.white.opacity(0.7))
            }
        }
        .chartXAxis { trendXAxisMarks(showLabels: false) }
        .frame(height: 168)
        .chartLegend(.hidden)
    }

    private var cumulativeDiffBarsChart: some View {
        Chart {
            RuleMark(y: .value("同点", 0))
                .foregroundStyle(Color.white.opacity(0.38))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
            ForEach(trendDiffBars) { row in
                BarMark(
                    x: .value("期間", row.id),
                    y: .value("差", row.diff),
                    width: .ratio(0.62)
                )
                .foregroundStyle(row.diff >= 0 ? cyan : underperformRed)
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(Color.white.opacity(0.15))
                AxisValueLabel { if let v = value.as(Int.self) { Text("\(v / 10000)万") } }.foregroundStyle(Color.white.opacity(0.65))
            }
        }
        .chartXAxis { trendXAxisMarks(showLabels: true) }
        .frame(height: 96)
        .chartLegend(.hidden)
    }

    @AxisContentBuilder
    private func trendXAxisMarks(showLabels: Bool) -> some AxisContent {
        AxisMarks(values: xAxisPeriodKeys) { value in
            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(Color.white.opacity(showLabels ? 0.12 : 0.07))
            if showLabels {
                AxisTick(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(Color.white.opacity(0.35))
                AxisValueLabel(centered: true) {
                    if let s = value.as(String.self) {
                        Text(axisLabel(for: s))
                            .font(.system(size: 9, weight: .medium, design: .rounded))
                            .foregroundStyle(Color.white.opacity(0.78))
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                }
            }
        }
    }

    private func legendDot(
        _ color: Color,
        label: String,
        dashed: Bool = false,
        symbolCircle: Bool = false,
        symbolSquare: Bool = false,
        bar: Bool = false
    ) -> some View {
        HStack(spacing: 6) {
            if bar {
                RoundedRectangle(cornerRadius: 2)
                    .fill(color)
                    .frame(width: 14, height: 8)
            } else if dashed {
                HStack(spacing: 2) {
                    Image(systemName: "square.fill")
                        .font(.system(size: 6))
                        .foregroundStyle(color.opacity(0.9))
                    Rectangle()
                        .stroke(color, style: StrokeStyle(lineWidth: 2, dash: [4, 3]))
                        .frame(width: 14, height: 2)
                }
            } else if symbolCircle {
                Image(systemName: "circle.fill")
                    .font(.system(size: 7))
                    .foregroundStyle(color)
            } else if symbolSquare {
                Image(systemName: "square.fill")
                    .font(.system(size: 7))
                    .foregroundStyle(color)
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
                    .font(AppTypography.panelHeading)
                    .foregroundColor(.white)
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
                AnalyticsDayDetailView(day: d, sessions: sessions, bottomSegment: $bottomSegment, selectedFilterLabel: $selectedFilterLabel, periodFilter: $periodFilter, showPeriodSheet: $showPeriodSheet, scrollBottomInset: 40, onSessionTap: nil)
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
    /// 実戦回転率の表示文字列（公式ボーダーとの差を括弧内に表示）
    private var rotationRateDisplay: String {
        if session.excludesFromRotationExpectationAnalytics { return "—（帳簿）" }
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
                miniblock("実戦回転率", value: rotationRateDisplay, valueColor: .white)
                miniblock("期待値", value: "\(session.theoreticalValue >= 0 ? "+" : "")\(session.theoreticalValue.formattedPtWithUnit)", valueColor: .white.opacity(0.9))
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

    private var recoveryPt: Int { Int(Double(session.totalHoldings) * session.payoutCoefficient) }
    private var rotationPer1k: Double {
        guard session.inputCash > 0 else { return 0 }
        return Double(session.normalRotations) / (Double(session.inputCash) / 1000.0)
    }
    @State private var showEditSheet = false

    var body: some View {
        ZStack {
            StaticHomeBackgroundView()
            ScrollView(showsIndicators: false) {
                VStack(spacing: 12) {
                    sessionDetailPanel(title: "実戦日") {
                        Text(JapaneseDateFormatters.yearMonthDay.string(from: session.date))
                            .font(AppTypography.bodyMonoSemibold)
                            .foregroundColor(.white.opacity(0.95))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    sessionDetailPanel(title: "機種・店舗") {
                        sessionDetailLabeledRow("機種", session.machineName)
                        sessionDetailDivider()
                        sessionDetailLabeledRow("店舗", session.shopName)
                    }
                    sessionDetailPanel(title: "数値サマリ") {
                        sessionDetailLabeledRow("総回転数", "\(session.normalRotations)")
                        sessionDetailDivider()
                        sessionDetailLabeledRow("当選", "RUSH: \(session.rushWinCount) / 通常: \(session.normalWinCount) / LT: \(session.ltWinCount)")
                        sessionDetailDivider()
                        sessionDetailLabeledRow("総投入額（現金）", session.inputCash.formattedPtWithUnit)
                        sessionDetailDivider()
                        sessionDetailLabeledRow("回収出球", "\(session.totalHoldings) 玉")
                        sessionDetailDivider()
                        sessionDetailLabeledRow("回収額（pt換算）", recoveryPt.formattedPtWithUnit)
                        sessionDetailDivider()
                        sessionDetailLabeledRow("期待値", "\(session.theoreticalValue >= 0 ? "+" : "")\(session.theoreticalValue.formattedPtWithUnit)")
                        sessionDetailDivider()
                        sessionDetailLabeledRow("欠損・余剰", "\(session.deficitSurplus >= 0 ? "+" : "")\(session.deficitSurplus.formattedPtWithUnit)")
                        sessionDetailDivider()
                        HStack(alignment: .firstTextBaseline) {
                            Text("実成績")
                                .font(AppTypography.bodyRounded)
                                .foregroundStyle(Color.white.opacity(0.55))
                            Spacer(minLength: 8)
                            Text("\(session.performance >= 0 ? "+" : "")\(session.performance.formattedPtWithUnit)")
                                .font(AppTypography.bodyMonoSemibold)
                                .foregroundColor(session.performance >= 0 ? .green : .red)
                                .multilineTextAlignment(.trailing)
                        }
                    }
                    sessionDetailPanel(title: "分析") {
                        sessionDetailLabeledRow(
                            "期待値比（保存時）",
                            session.expectationRatioAtSave > 0 ? String(format: "%.2f%%", session.expectationRatioAtSave * 100) : "—"
                        )
                        sessionDetailDivider()
                        sessionDetailLabeledRow("実質回転率", String(format: "%.1f 回/1k", rotationPer1k))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 180)
            }
        }
        .navigationTitle("履歴詳細")
        .navigationBarTitleDisplayMode(.inline)
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
    }

    private func sessionDetailPanel<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(AppTypography.panelHeading)
                .foregroundColor(.white)
            content()
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

    private func sessionDetailLabeledRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(AppTypography.bodyRounded)
                .foregroundStyle(Color.white.opacity(0.55))
            Spacer(minLength: 8)
            Text(value)
                .font(AppTypography.bodyMonoSemibold)
                .foregroundColor(.white.opacity(0.95))
                .multilineTextAlignment(.trailing)
        }
    }

    private func sessionDetailDivider() -> some View {
        Rectangle()
            .fill(Color.white.opacity(0.12))
            .frame(height: 1)
            .padding(.vertical, 8)
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
    /// メイン分析パスではドック分の余白。シート内は小さめでよい。
    var scrollBottomInset: CGFloat = 120
    /// メイン分析の `NavigationPath` から open するとき指定。nil のときは `NavigationLink`（ヒートマップ全期間シート用）
    var onSessionTap: ((UUID) -> Void)? = nil

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
                    ForEach(NativeAdListInterleaving.rowsForSessionGroup(daySessions: daySessions, placementPrefix: "aday-\(day.timeIntervalSince1970)"), id: \.id) { row in
                        switch row {
                        case .session(let session):
                            if let onSessionTap {
                                Button {
                                    onSessionTap(session.id)
                                } label: {
                                    AnalyticsSessionCardView(session: session)
                                }
                                .buttonStyle(.plain)
                            } else {
                                NavigationLink(destination: AnalyticsSessionDetailView(session: session, sessions: sessions, bottomSegment: $bottomSegment, selectedFilterLabel: $selectedFilterLabel, periodFilter: $periodFilter, showPeriodSheet: $showPeriodSheet)) {
                                    AnalyticsSessionCardView(session: session)
                                }
                                .buttonStyle(.plain)
                            }
                        case .native(let placementKey):
                            OptionalNativeAdCardSlot(placementID: placementKey)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, scrollBottomInset)
            }
        }
        .navigationTitle("日別分析（\(dayTitle)）")
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(.dark)
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
    let onSessionTap: (UUID) -> Void

    private var listNavigationTitle: String {
        if groupLabel == "全体" { return "全般の遊技履歴" }
        switch segment {
        case .shop: return "店舗別（\(groupLabel)）"
        case .machine: return "機種別（\(groupLabel)）"
        case .manufacturer: return "メーカー別（\(groupLabel)）"
        case .month, .year, .weekday: return groupLabel
        }
    }

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
                            ForEach(NativeAdListInterleaving.rowsForSessionGroup(daySessions: group.sessions, placementPrefix: "alist-\(groupLabel)-\(group.day.timeIntervalSince1970)"), id: \.id) { row in
                                switch row {
                                case .session(let session):
                                    Button {
                                        onSessionTap(session.id)
                                    } label: {
                                        AnalyticsSessionCardView(session: session)
                                    }
                                    .buttonStyle(.plain)
                                case .native(let placementKey):
                                    OptionalNativeAdCardSlot(placementID: placementKey)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 120)
            }
        }
        .navigationTitle(listNavigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(.dark)
    }
}

/// 店舗別分析ページ（曜日・特定日傾向＋履歴パネル）
private struct AnalyticsShopDetailView: View {
    let shopName: String
    let sessions: [GameSession]
    let machinesByName: [String: Machine]
    let rulesByShopName: [String: SpecificDayRules]
    /// この店舗で設定した特定日ラベル（追加順、最大4つ）。例: ["毎月13日", "5のつく日"]
    let orderedSpecificDayLabels: [String]
    @Binding var bottomSegment: AnalyticsBottomSegment
    @Binding var selectedFilterLabel: String?
    @Binding var periodFilter: AnalyticsPeriodFilter
    @Binding var showPeriodSheet: Bool
    let onSessionTap: (UUID) -> Void

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

    private var cyan: Color { AppGlassStyle.accent }

    private var shopScopeOverview: AnalyticsOverviewTotalSummary {
        AnalyticsOverviewTotalSummary.compute(sessions: shopSessions, machinesByName: machinesByName)
    }

    var body: some View {
        ZStack {
            StaticHomeBackgroundView()
            ScrollView(showsIndicators: false) {
                VStack(spacing: 12) {
                    if !shopSessions.isEmpty {
                        OverviewTotalSummaryPanel(metrics: shopScopeOverview, accent: cyan)
                            .padding(.horizontal, 16)
                        VStack(alignment: .leading, spacing: 20) {
                            WeekdayTendencySection(groups: weekdayGroups, accent: cyan)
                            SpecificDayBarChartSection(groups: specificDayGroups, accent: cyan, fixedSegmentCount: 7)
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 4)
                        .padding(.bottom, 8)
                    }

                    Text("この店舗の履歴")
                        .font(AppTypography.panelHeading)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20)
                        .padding(.top, 8)

                    LazyVStack(spacing: 12) {
                        ForEach(sessionsGroupedByDay(shopSessions), id: \.day.timeIntervalSince1970) { group in
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(NativeAdListInterleaving.rowsForSessionGroup(daySessions: group.sessions, placementPrefix: "shop-\(shopName)-\(group.day.timeIntervalSince1970)"), id: \.id) { row in
                                    switch row {
                                    case .session(let session):
                                        VStack(spacing: 0) {
                                            Button {
                                                onSessionTap(session.id)
                                            } label: {
                                                AnalyticsSessionCardView(session: session)
                                            }
                                            .buttonStyle(.plain)
                                            Rectangle()
                                                .fill(Color.white.opacity(0.12))
                                                .frame(height: 1)
                                        }
                                    case .native(let placementKey):
                                        OptionalNativeAdCardSlot(placementID: placementKey)
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 120)
                }
                .padding(.top, 8)
            }
        }
        .navigationTitle("個別店舗分析（\(shopName)）")
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(.dark)
    }
}

/// 機種別分析ページ（店舗詳細と同様に曜日・特定日傾向＋履歴）
private struct AnalyticsMachineDetailView: View {
    let machineName: String
    let sessions: [GameSession]
    let machinesByName: [String: Machine]
    let rulesByShopName: [String: SpecificDayRules]
    @Binding var bottomSegment: AnalyticsBottomSegment
    @Binding var selectedFilterLabel: String?
    @Binding var periodFilter: AnalyticsPeriodFilter
    @Binding var showPeriodSheet: Bool
    let onSessionTap: (UUID) -> Void

    private var machineSessions: [GameSession] {
        sessions.filter { ($0.machineName.isEmpty ? "未設定" : $0.machineName) == machineName }
            .sorted { $0.date > $1.date }
    }

    private var machineScopeOverview: AnalyticsOverviewTotalSummary {
        AnalyticsOverviewTotalSummary.compute(sessions: machineSessions, machinesByName: machinesByName)
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
    private var cyan: Color { AppGlassStyle.accent }

    var body: some View {
        ZStack {
            StaticHomeBackgroundView()
            ScrollView(showsIndicators: false) {
                VStack(spacing: 12) {
                    if !machineSessions.isEmpty {
                        OverviewTotalSummaryPanel(metrics: machineScopeOverview, accent: cyan)
                            .padding(.horizontal, 16)
                        VStack(alignment: .leading, spacing: 20) {
                            WeekdayTendencySection(groups: weekdayGroups, accent: cyan)
                            SpecificDayBarChartSection(groups: specificDayGroups, accent: cyan, fixedSegmentCount: 7)
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 4)
                        .padding(.bottom, 8)
                    }
                    Text("この機種の履歴")
                        .font(AppTypography.panelHeading)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                    LazyVStack(spacing: 12) {
                        ForEach(sessionsGroupedByDay(machineSessions), id: \.day.timeIntervalSince1970) { group in
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(NativeAdListInterleaving.rowsForSessionGroup(daySessions: group.sessions, placementPrefix: "mach-\(machineName)-\(group.day.timeIntervalSince1970)"), id: \.id) { row in
                                    switch row {
                                    case .session(let session):
                                        VStack(spacing: 0) {
                                            Button {
                                                onSessionTap(session.id)
                                            } label: {
                                                AnalyticsSessionCardView(session: session)
                                            }
                                            .buttonStyle(.plain)
                                            Rectangle()
                                                .fill(Color.white.opacity(0.12))
                                                .frame(height: 1)
                                        }
                                    case .native(let placementKey):
                                        OptionalNativeAdCardSlot(placementID: placementKey)
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 120)
                }
                .padding(.top, 8)
            }
        }
        .navigationTitle("個別機種分析（\(machineName)）")
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(.dark)
    }
}

/// メーカー別分析ページ（店舗・機種と同様に曜日・特定日傾向＋履歴）
private struct AnalyticsManufacturerDetailView: View {
    let manufacturerName: String
    let sessions: [GameSession]
    let machinesByName: [String: Machine]
    let rulesByShopName: [String: SpecificDayRules]
    @Binding var bottomSegment: AnalyticsBottomSegment
    @Binding var selectedFilterLabel: String?
    @Binding var periodFilter: AnalyticsPeriodFilter
    @Binding var showPeriodSheet: Bool
    let onSessionTap: (UUID) -> Void

    private var manufacturerSessions: [GameSession] {
        let key = manufacturerName.trimmingCharacters(in: .whitespaces).isEmpty ? "未設定" : manufacturerName
        return sessions.filter { ($0.manufacturerName.trimmingCharacters(in: .whitespaces).isEmpty ? "未設定" : $0.manufacturerName) == key }
            .sorted { $0.date > $1.date }
    }

    private var manufacturerScopeOverview: AnalyticsOverviewTotalSummary {
        AnalyticsOverviewTotalSummary.compute(sessions: manufacturerSessions, machinesByName: machinesByName)
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
    private var cyan: Color { AppGlassStyle.accent }

    var body: some View {
        ZStack {
            StaticHomeBackgroundView()
            ScrollView(showsIndicators: false) {
                VStack(spacing: 12) {
                    if !manufacturerSessions.isEmpty {
                        OverviewTotalSummaryPanel(metrics: manufacturerScopeOverview, accent: cyan)
                            .padding(.horizontal, 16)
                        VStack(alignment: .leading, spacing: 20) {
                            WeekdayTendencySection(groups: weekdayGroups, accent: cyan)
                            SpecificDayBarChartSection(groups: specificDayGroups, accent: cyan, fixedSegmentCount: 7)
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 4)
                        .padding(.bottom, 8)
                    }
                    Text("このメーカーの履歴")
                        .font(AppTypography.panelHeading)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                    LazyVStack(spacing: 12) {
                        ForEach(sessionsGroupedByDay(manufacturerSessions), id: \.day.timeIntervalSince1970) { group in
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(NativeAdListInterleaving.rowsForSessionGroup(daySessions: group.sessions, placementPrefix: "mfr-\(manufacturerName)-\(group.day.timeIntervalSince1970)"), id: \.id) { row in
                                    switch row {
                                    case .session(let session):
                                        VStack(spacing: 0) {
                                            Button {
                                                onSessionTap(session.id)
                                            } label: {
                                                AnalyticsSessionCardView(session: session)
                                            }
                                            .buttonStyle(.plain)
                                            Rectangle()
                                                .fill(Color.white.opacity(0.12))
                                                .frame(height: 1)
                                        }
                                    case .native(let placementKey):
                                        OptionalNativeAdCardSlot(placementID: placementKey)
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 120)
                }
                .padding(.top, 8)
            }
        }
        .navigationTitle("個別メーカー分析（\(manufacturerName)）")
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(.dark)
    }
}

/// 分析1行をグラスカードでラップ（実戦履歴UIと統一）
struct AnalyticsGroupCard: View {
    let group: AnalyticsGroup
    let accent: Color
    /// 店舗・機種・メーカー一覧のコンパクト行：このグループに属するセッション（nil なら従来の詳細レイアウト）
    var compactListSessions: [GameSession]? = nil
    var machinesByNameForCompact: [String: Machine]? = nil

    private var lossColor: Color { Color.orange }
    private var neutralLabel: Color { Color.white.opacity(0.92) }

    /// 店舗一覧以外：プラスはアクセント、マイナスはオレンジ
    private var effectiveAccent: Color { accent }
    private var effectiveLossColor: Color { Color.orange }

    private var useCompactLayout: Bool { compactListSessions != nil }

    /// 二行目：実戦回転率・回数・公式ボーダーとの差（あれば）
    private var secondLineText: String {
        var s = "実戦回転率 \(String(format: "%.1f", group.avgRotationRate))/1kpt · \(group.sessionCount)回"
        if let diff = group.avgDiffFromFormulaBorder {
            s += " （公式ボーダーとの差: \(String(format: "%+.1f 回/1k", diff))"
        }
        return s
    }

    private var compactScopeMetrics: AnalyticsOverviewTotalSummary {
        AnalyticsOverviewTotalSummary.compute(
            sessions: compactListSessions ?? [],
            machinesByName: machinesByNameForCompact ?? [:]
        )
    }

    private func signedPt(_ n: Int) -> String {
        "\(n >= 0 ? "+" : "")\(n.formattedPtWithUnit)"
    }

    private func shopMetricColumn(title: String, value: String, valueColor: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(AppTypography.bodyRounded)
                .foregroundStyle(Color.white.opacity(0.55))
            Text(value)
                .font(AppTypography.bodyMonoSemibold)
                .monospacedDigit()
                .foregroundColor(valueColor)
                .lineLimit(2)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var compactListBody: some View {
        let m = compactScopeMetrics
        return VStack(alignment: .leading, spacing: 0) {
            Text(group.label)
                .font(AppTypography.panelHeading)
                .foregroundColor(.white)
                .padding(.bottom, 10)
            compactRowDivider()
            HStack(alignment: .top, spacing: 12) {
                shopMetricColumn(title: "通算成績", value: signedPt(m.totalPerformance), valueColor: m.totalPerformance >= 0 ? accent : lossColor)
                shopMetricColumn(title: "通算遊技回数", value: "\(m.sessionCount)回", valueColor: neutralLabel)
            }
            .padding(.vertical, 8)
            compactRowDivider()
            HStack(alignment: .top, spacing: 12) {
                shopMetricColumn(title: "勝率", value: m.winRatePercent.map { String(format: "%.1f%%", $0) } ?? "—", valueColor: neutralLabel)
                shopMetricColumn(title: "平均初当たり確率", value: m.avgFirstHitProbabilityText ?? "—", valueColor: neutralLabel)
            }
            .padding(.vertical, 8)
            compactRowDivider()
            HStack(alignment: .top, spacing: 12) {
                shopMetricColumn(title: "平均回転率", value: m.avgRotationPer1k.map { String(format: "%.1f 回/1k", $0) } ?? "—", valueColor: neutralLabel)
                shopMetricColumn(
                    title: "公式ボーダーとの差",
                    value: m.avgBorderDiffPer1k.map { String(format: "%+.1f 回/1k", $0) } ?? "—",
                    valueColor: {
                        guard let d = m.avgBorderDiffPer1k else { return neutralLabel }
                        return d >= 0 ? accent : lossColor
                    }()
                )
            }
            .padding(.vertical, 8)
        }
    }

    private func compactRowDivider() -> some View {
        Rectangle()
            .fill(Color.white.opacity(0.12))
            .frame(height: 1)
    }

    private var defaultListBody: some View {
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
                    Text("期待値")
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
                    Text("期待値との差")
                        .font(AppTypography.bodyRounded)
                        .foregroundColor(.white.opacity(0.55))
                    DeficitSurplusBarView(
                        deficitSurplus: group.totalDeficitSurplus,
                        accent: effectiveAccent,
                        lossColor: effectiveLossColor,
                        barColorByActualProfit: nil
                    )
                    .frame(height: 20)
                }
            }
        }
    }

    var body: some View {
        Group {
            if useCompactLayout {
                compactListBody
            } else {
                defaultListBody
            }
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
}

// MARK: - 期待値との差（余剰・欠損）をゼロ中心の1本バーで表示
// 代替案メモ:
// - 旧: 期待値・実成績の2本並び → 長さの意味が伝わりにくい
// - 案A: 共通ゼロ軸で期待値・実成績を左右に同じスケールで描く（情報量多め）
// - 案B: 期待値を100%とする達成率バー（期待値0や負のときは要工夫）
// 採用: 差だけ表示＝「期待値よりどれだけ出た/損したか」がひと目で分かる
struct DeficitSurplusBarView: View {
    let deficitSurplus: Int
    let accent: Color
    var lossColor: Color = Color.orange
    /// 店舗分析時のみ指定。実成績がマイナスなら右伸びの棒も lossColor に（「期待値よりマシだが実成績は赤字」と分かる）
    var barColorByActualProfit: Int? = nil

    /// 右方向の棒（期待値との差プラス）の色。実成績マイナスならマゼンタ
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
                    // 余剰: 中央から右へ（実成績マイナスならマゼンタで「期待値よりマシだがまだ赤字」）
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

import SwiftUI
import SwiftData
import UIKit

// MARK: - 収支表示期間（タップで切り替え）
enum EarningsPeriod: String, CaseIterable {
    case month = "今月の成績"
    case year = "今年の成績"
    case week = "今週の成績"
    case day = "今日の成績"

    var calendarComponent: Calendar.Component {
        switch self {
        case .month: return .month
        case .year: return .year
        case .week: return .weekOfYear
        case .day: return .day
        }
    }

    /// ボーダー差パネル用ラベル（期間ごとの数字）
    var borderDiffTitle: String {
        switch self {
        case .month: return "今月の基準値差"
        case .year: return "今年の基準値差"
        case .week: return "今週の基準値差"
        case .day: return "今日の基準値差"
        }
    }
}

// MARK: - ホームから遷移する画面（遅延構築用）
private enum HomeRoute: String, Hashable {
    case history
    case analytics
}

// MARK: - ホーム画面タブ
enum HomeTab: String, CaseIterable {
    case home = "ホーム"
    case machines = "機種管理"
    case shops = "店舗管理"
    case settings = "Settings"

    var icon: String {
        switch self {
        case .home: return "house.fill"
        case .machines: return "cpu"
        case .shops: return "mappin.circle"
        case .settings: return "gearshape"
        }
    }
}

// MARK: - グラスモーフィズム・ホーム画面
struct HomeView: View {
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("homeBackgroundStyle") private var homeBackgroundStyle = HomeBackgroundStore.defaultStyle
    @AppStorage("homeBackgroundImagePath") private var homeBackgroundImagePath = ""

    @State private var log = GameLog()
    @State private var theme = AppTheme.cyber
    @State private var isPlaying = false
    @State private var showMachineShopGate = false
    @State private var showContinueSelection = false
    @State private var continueRestoreFailed = false
    @State private var showGameSessionEdit = false
    @Query(sort: \Machine.name) private var machines: [Machine]
    @Query(sort: \Shop.name) private var shops: [Shop]
    @State private var selectedTab: HomeTab = .home
    @State private var homeNavigationPath: [HomeRoute] = []
    @State private var appeared = false
    @State private var orbPhase: CGFloat = 0
    @State private var geoAngle: Double = 0
    @State private var earningsPeriod: EarningsPeriod = .month
    @State private var borderDiffPeriod: EarningsPeriod = .month
    @State private var loadedBackgroundImage: UIImage?

    @Query(sort: \GameSession.date, order: .reverse) private var allSessions: [GameSession]

    /// 通常モードでのバッテリー節約：アニメーションはホームタブ・フォアグラウンド・低電力でない時のみ
    private var shouldRunBackgroundAnimation: Bool {
        selectedTab == .home && scenePhase == .active && !ProcessInfo.processInfo.isLowPowerModeEnabled
    }

    private let cyan = AppGlassStyle.accent
    private let purple = Color(red: 0.5, green: 0.2, blue: 0.9)
    private let magenta = Color(red: 0.9, green: 0.2, blue: 0.5)

    /// 画面幅の約5.5%（最小20・最大32）。ドックなどで使用
    private func contentHorizontalPadding(_ width: CGFloat) -> CGFloat { min(32, max(20, width * 0.055)) }

    private var periodProfit: Int {
        let cal = Calendar.current
        return allSessions
            .filter { cal.isDate($0.date, equalTo: Date(), toGranularity: earningsPeriod.calendarComponent) }
            .reduce(0) { $0 + $1.performance }
    }

    private var periodDeficitSurplus: Int {
        let cal = Calendar.current
        return allSessions
            .filter { cal.isDate($0.date, equalTo: Date(), toGranularity: earningsPeriod.calendarComponent) }
            .reduce(0) { $0 + $1.deficitSurplus }
    }

    /// 期間内の公式基準値との差の平均（回/1k）。実質回転率 − 公式基準値。nil は対象なし
    private var periodBorderDiff: Double? {
        let cal = Calendar.current
        let list = allSessions
            .filter { cal.isDate($0.date, equalTo: Date(), toGranularity: borderDiffPeriod.calendarComponent) }
            .filter { $0.formulaBorderPer1k > 0 && $0.totalRealCost > 0 }
        guard !list.isEmpty else { return nil }
        let sumDiff = list.reduce(0.0) { acc, s in
            let rate = (Double(s.normalRotations) / s.totalRealCost) * 1000.0
            return acc + (rate - s.formulaBorderPer1k)
        }
        return sumDiff / Double(list.count)
    }

    /// 抜本対策：タブ切り替えでビューを破棄しない。4タブ分を常に保持し表示だけ切り替える。
    var body: some View {
        ZStack {
            // ホーム（背景＋コンテンツを同一レイヤーにして背景が確実に表示される）
            NavigationStack(path: $homeNavigationPath) {
                ZStack {
                    backgroundLayer
                    mainContent
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .navigationDestination(for: HomeRoute.self) { route in
                    switch route {
                    case .history: HistoryListView()
                    case .analytics: AnalyticsDashboardView()
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationBarHidden(homeNavigationPath.isEmpty)
            .opacity(selectedTab == .home ? 1 : 0)
            .allowsHitTesting(selectedTab == .home)
            .zIndex(selectedTab == .home ? 1 : 0)

            // 機種管理
            NavigationStack {
                MachineManagementView()
                    .navigationTitle(HomeTab.machines.rawValue)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbarColorScheme(.dark, for: .navigationBar)
                    .preferredColorScheme(.dark)
            }
            .opacity(selectedTab == .machines ? 1 : 0)
            .allowsHitTesting(selectedTab == .machines)
            .zIndex(selectedTab == .machines ? 1 : 0)

            // 店舗管理
            NavigationStack {
                ShopManagementView()
                    .navigationTitle(HomeTab.shops.rawValue)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbarColorScheme(.dark, for: .navigationBar)
                    .preferredColorScheme(.dark)
            }
            .opacity(selectedTab == .shops ? 1 : 0)
            .allowsHitTesting(selectedTab == .shops)
            .zIndex(selectedTab == .shops ? 1 : 0)

            // 設定
            NavigationStack {
                SettingsTabView(theme: $theme)
                    .navigationTitle(HomeTab.settings.rawValue)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbarColorScheme(.dark, for: .navigationBar)
                    .preferredColorScheme(.dark)
            }
            .opacity(selectedTab == .settings ? 1 : 0)
            .allowsHitTesting(selectedTab == .settings)
            .zIndex(selectedTab == .settings ? 1 : 0)

            // ドックは分析画面のときのみ非表示（分析は分析用ドックのみ）。履歴表示時は表示し、ホームタップでトップに戻る
            if selectedTab != .home || homeNavigationPath != [.analytics] {
                footerTabBar
                    .zIndex(10)
            }
        }
        .onChange(of: selectedTab) { _, new in
            if new != .home {
                homeNavigationPath = []
            }
        }
        .fullScreenCover(isPresented: $showMachineShopGate) {
            MachineShopSelectionView(log: log, gateMode: true, onGateStart: { showMachineShopGate = false; isPlaying = true }, onGateCancel: { showMachineShopGate = false })
        }
        .onChange(of: scenePhase) { _, newPhase in
            // inactive: 電源・Appスイッチャー・着信等で先に呼ばれる。background 待ちだと保存が間に合わないことがある
            if newPhase == .inactive || newPhase == .background {
                ResumableStateStore.autosave(from: log, force: true)
            }
        }
        .fullScreenCover(isPresented: $showContinueSelection) {
            ContinuePlaySelectionView(log: log, restoreFailed: continueRestoreFailed) {
                showContinueSelection = false
                continueRestoreFailed = false
                isPlaying = true
            } onCancel: {
                showContinueSelection = false
                continueRestoreFailed = false
            }
        }
        .fullScreenCover(isPresented: $isPlaying) {
            PlayView(log: log, theme: $theme, onOpenSettingsTab: {
                isPlaying = false
                selectedTab = .settings
            })
        }
        .sheet(isPresented: $showGameSessionEdit) {
            GameSessionEditView()
        }
    }

    private var backgroundLayer: some View {
        GeometryReader { geo in
            ZStack {
                if homeBackgroundStyle == "custom", let uiImage = loadedBackgroundImage {
                    Image(uiImage: uiImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                        .position(x: geo.size.width / 2, y: geo.size.height / 2)
                } else if shouldRunBackgroundAnimation {
                    AppGlassStyle.background
                    orbView(color: cyan, x: 0.2, y: 0.15)
                    orbView(color: purple, x: 0.75, y: 0.3)
                    orbView(color: magenta, x: 0.5, y: 0.75)
                    geometricBackground
                        .onAppear {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                                withAnimation(.easeInOut(duration: 4).repeatForever(autoreverses: true)) { orbPhase = 1 }
                                withAnimation(.linear(duration: 12).repeatForever(autoreverses: false)) { geoAngle = 360 }
                            }
                        }
                } else {
                    AppGlassStyle.background
                    staticOrbView(color: cyan, x: 0.2, y: 0.15)
                    staticOrbView(color: purple, x: 0.75, y: 0.3)
                    staticOrbView(color: magenta, x: 0.5, y: 0.75)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .onAppear {
            if homeBackgroundStyle == "custom", !homeBackgroundImagePath.isEmpty {
                let path = homeBackgroundImagePath
                Task.detached(priority: .userInitiated) { @Sendable () async in
                    let img = HomeBackgroundStore.loadCustomImage(fileName: path)
                    await MainActor.run { loadedBackgroundImage = img }
                }
            }
        }
        .onChange(of: homeBackgroundStyle) { _, new in
            if new == "custom", !homeBackgroundImagePath.isEmpty {
                let path = homeBackgroundImagePath
                Task.detached(priority: .userInitiated) { @Sendable () async in
                    let img = HomeBackgroundStore.loadCustomImage(fileName: path)
                    await MainActor.run { loadedBackgroundImage = img }
                }
            } else {
                loadedBackgroundImage = nil
            }
        }
        .onChange(of: homeBackgroundImagePath) { _, new in
            if homeBackgroundStyle == "custom", !new.isEmpty {
                Task.detached(priority: .userInitiated) { @Sendable () async in
                    let img = HomeBackgroundStore.loadCustomImage(fileName: new)
                    await MainActor.run { loadedBackgroundImage = img }
                }
            } else {
                loadedBackgroundImage = nil
            }
        }
    }

    private var geometricBackground: some View {
        GeometryReader { geo in
            ZStack {
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [.clear, cyan.opacity(0.04), .clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: geo.size.width, height: 2)
                    .offset(y: (geoAngle / 360) * geo.size.height - geo.size.height / 2)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .allowsHitTesting(false)
    }

    private func orbView(color: Color, x: CGFloat, y: CGFloat) -> some View {
        GeometryReader { geo in
            let size = geo.size.width * 0.6
            Circle()
                .fill(color.opacity(0.25))
                .frame(width: size, height: size)
                .blur(radius: 80)
                .offset(x: (x - 0.5) * geo.size.width + sin(orbPhase * .pi * 2) * 20,
                       y: (y - 0.5) * geo.size.height + cos(orbPhase * .pi * 2) * 15)
        }
        .allowsHitTesting(false)
    }

    /// バッテリー節約用：アニメーションなしの固定オーブ（他タブ・バックグラウンド・低電力時）
    private func staticOrbView(color: Color, x: CGFloat, y: CGFloat) -> some View {
        GeometryReader { geo in
            let size = geo.size.width * 0.6
            Circle()
                .fill(color.opacity(0.25))
                .frame(width: size, height: size)
                .blur(radius: 80)
                .offset(x: (x - 0.5) * geo.size.width, y: (y - 0.5) * geo.size.height)
        }
        .allowsHitTesting(false)
    }

    private var mainContent: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let contentPad = contentHorizontalPadding(w)
            let verticalSpacing = min(44, max(28, h * 0.032))
            let gridSpacing = min(18, max(12, w * 0.04))
            let gridSide = max(120, min(220, (w - contentPad * 2 - gridSpacing) / 2))
            let topPad = max(20, min(36, h * 0.028))
            let bottomPad = max(80, min(140, h * 0.12))
            let cardPad = min(24, max(14, w * 0.04))
            VStack(spacing: 0) {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: verticalSpacing) {
                        earningsCard(padding: cardPad)
                            .padding(.horizontal, contentPad)
                        borderDiffCard(padding: cardPad)
                            .padding(.horizontal, contentPad)
                        mainActionsGrid(side: gridSide, gridSpacing: gridSpacing)
                            .padding(.horizontal, contentPad)
                    }
                    .padding(.top, topPad)
                    .padding(.bottom, bottomPad)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // opacity 0 だと起動直後〜アニメ中にタップが効かないケースがあるため、不透明度は維持しオフセットのみ演出する
        .offset(y: appeared ? 0 : 14)
        .onAppear {
            withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) { appeared = true }
        }
    }

    private func earningsCard(padding cardPad: CGFloat = 16) -> some View {
        Button {
            HapticUtil.impact(.light)
            withAnimation(.easeInOut(duration: 0.2)) {
                let all = EarningsPeriod.allCases
                let idx = all.firstIndex(of: earningsPeriod).map { ($0 + 1) % all.count } ?? 0
                earningsPeriod = all[idx]
            }
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                Text(earningsPeriod.rawValue)
                    .font(AppTypography.panelHeading)
                    .foregroundColor(.white.opacity(0.95))
                Text("\(periodProfit >= 0 ? "+" : "")\(periodProfit.formattedPtWithUnit)")
                    .font(.system(size: 28, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(periodProfit >= 0 ? cyan : Color(red: 0.95, green: 0.3, blue: 0.5))
                    .frame(maxWidth: .infinity)
                HStack {
                    Spacer(minLength: 0)
                    Text(periodDeficitSurplus >= 0 ? "余剰 +\(periodDeficitSurplus.formattedPtWithUnit)" : "欠損 \(periodDeficitSurplus.formattedPtWithUnit)")
                        .font(AppTypography.bodyRounded)
                        .fontWeight(.semibold)
                        .monospacedDigit()
                        .foregroundColor(periodDeficitSurplus >= 0 ? Color(red: 0.3, green: 0.95, blue: 0.5) : Color.orange)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(cardPad)
            .background(Color.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.38),
                                Color.white.opacity(0.12),
                                Color.white.opacity(0.06)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
    }

    /// 公式基準値と実質回転率の差分パネル（成績パネルと同じ大きさ・フォント。タップで期間切替）
    private func borderDiffCard(padding cardPad: CGFloat = 16) -> some View {
        Button {
            HapticUtil.impact(.light)
            withAnimation(.easeInOut(duration: 0.2)) {
                let all = EarningsPeriod.allCases
                let idx = all.firstIndex(of: borderDiffPeriod).map { ($0 + 1) % all.count } ?? 0
                borderDiffPeriod = all[idx]
            }
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                Text(borderDiffPeriod.borderDiffTitle)
                    .font(AppTypography.panelHeading)
                    .foregroundColor(.white.opacity(0.95))
                if let diff = periodBorderDiff {
                    Text(String(format: "%+.1f 回/1k", diff))
                        .font(.system(size: 28, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(diff >= 0 ? cyan : Color(red: 0.95, green: 0.3, blue: 0.5))
                        .frame(maxWidth: .infinity)
                } else {
                    Text("—")
                        .font(.system(size: 28, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundColor(.white.opacity(0.6))
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(cardPad)
            .background(Color.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.38),
                                Color.white.opacity(0.12),
                                Color.white.opacity(0.06)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private func mainActionsGrid(side: CGFloat, gridSpacing: CGFloat) -> some View {
        let leftColumnTotalHeight = 2 * side + gridSpacing

        return HStack(alignment: .top, spacing: gridSpacing) {
            VStack(spacing: gridSpacing) {
                HomeGridButton(title: "新規スタート", icon: "plus.circle", cyan: cyan, size: side) {
                    HapticUtil.impact(.medium)
                    log.reset()
                    ResumableStateStore.clear()
                    showMachineShopGate = true
                }
                HomeGridButton(title: "シンプル入力", icon: "square.and.pencil", cyan: cyan, size: side) {
                    HapticUtil.impact(.medium)
                    showGameSessionEdit = true
                }
            }
            .frame(width: side)

            GeometryReader { geo in
                let rowH = max(48, (geo.size.height - 2 * gridSpacing) / 3)
                VStack(spacing: gridSpacing) {
                    Button {
                        HapticUtil.impact(.medium)
                        if let state = ResumableStateStore.load(),
                           let machine = machines.first(where: { $0.name == state.machineName }),
                           let shop = shops.first(where: { $0.name == state.shopName }) {
                            log.applyResumableState(state, machine: machine, shop: shop)
                            isPlaying = true
                        } else {
                            continueRestoreFailed = ResumableStateStore.load() != nil
                            showContinueSelection = true
                        }
                    } label: {
                        HomeGridButtonLabelSplit(
                            title: "続きから",
                            icon: "play.circle",
                            cyan: cyan,
                            width: side,
                            height: rowH
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    Button {
                        HapticUtil.impact(.medium)
                        homeNavigationPath = [.history]
                    } label: {
                        HomeGridButtonLabelSplit(
                            title: "実践履歴",
                            icon: "calendar",
                            cyan: cyan,
                            width: side,
                            height: rowH
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    Button {
                        HapticUtil.impact(.medium)
                        homeNavigationPath = [.analytics]
                    } label: {
                        HomeGridButtonLabelSplit(
                            title: "データ分析",
                            icon: "chart.bar",
                            cyan: cyan,
                            width: side,
                            height: rowH
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .frame(width: side, height: geo.size.height, alignment: .top)
            }
            .frame(width: side, height: leftColumnTotalHeight)
        }
    }

    // MARK: - ホーム右列など（高さ可変ラベル）
    private struct HomeGridButtonLabelSplit: View {
        let title: String
        let icon: String
        var cyan: Color = AppGlassStyle.accent
        let width: CGFloat
        let height: CGFloat

        private var cornerRadius: CGFloat { min(20, max(14, height * 0.22)) }
        private var minDim: CGFloat { min(width, height) }
        private var iconSize: CGFloat { min(32, max(18, minDim * 0.18)) }
        private var titleSize: CGFloat { min(14, max(10, minDim * 0.075)) }
        private var innerSpacing: CGFloat { max(4, minDim * 0.06) }

        var body: some View {
            VStack(spacing: innerSpacing) {
                Image(systemName: icon)
                    .font(.system(size: iconSize, weight: .medium))
                Text(title)
                    .font(.system(size: titleSize, weight: .medium, design: .rounded))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .foregroundColor(.white.opacity(0.95))
            .frame(width: width, height: height)
            .background(Color.black.opacity(0.75), in: RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.4),
                                cyan.opacity(0.25),
                                Color.white.opacity(0.08)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
        }
    }

    private var footerTabBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                Color.clear
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .allowsHitTesting(false)
                HStack(spacing: 0) {
                    ForEach(HomeTab.allCases, id: \.self) { tab in
                        Button {
                            HapticUtil.impact(.light)
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                selectedTab = tab
                                if tab == .home {
                                    homeNavigationPath = []
                                }
                            }
                        } label: {
                            VStack(spacing: 4) {
                                Image(systemName: tab.icon)
                                    .font(.system(size: 22, weight: .medium))
                                Text(tab.rawValue)
                                    .font(.system(size: 10, weight: .medium, design: .rounded))
                            }
                            .foregroundColor(selectedTab == tab ? .white : .white.opacity(0.6))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .padding(.horizontal, 20)
                        }
                        .buttonStyle(.plain)
                        .contentShape(Rectangle())
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(
                    Color.black
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
                .padding(.horizontal, contentHorizontalPadding(geo.size.width))
                .padding(.bottom, 0)
            }
        }
    }
}

// MARK: - ホーム用 2x2 四角グリッドボタン（ウィジェットサイズ・押下で沈み込み＋Haptics）
struct HomeGridButton: View {
    let title: String
    let icon: String
    var cyan: Color = AppGlassStyle.accent
    var size: CGFloat = 160
    let action: () -> Void
    @State private var isPressed = false

    private var iconSize: CGFloat { min(32, max(24, size * 0.175)) }
    private var titleSize: CGFloat { min(14, max(11, size * 0.075)) }

    var body: some View {
        Button(action: action) {
            VStack(spacing: max(6, size * 0.06)) {
                Image(systemName: icon)
                    .font(.system(size: iconSize, weight: .medium))
                Text(title)
                    .font(.system(size: titleSize, weight: .medium, design: .rounded))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .foregroundColor(.white.opacity(0.95))
            .frame(width: size, height: size)
            .background(Color.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 20))
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.4),
                                cyan.opacity(0.25),
                                Color.white.opacity(0.08)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .scaleEffect(isPressed ? 0.96 : 1)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    withAnimation(.easeInOut(duration: 0.15)) { isPressed = true }
                }
                .onEnded { _ in
                    withAnimation(.easeInOut(duration: 0.2)) { isPressed = false }
                }
        )
    }
}

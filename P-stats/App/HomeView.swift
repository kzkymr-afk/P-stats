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
        case .month: return "今月のボーダー差"
        case .year: return "今年のボーダー差"
        case .week: return "今週のボーダー差"
        case .day: return "今日のボーダー差"
        }
    }
}

// MARK: - ホームから遷移する画面（遅延構築用）
/// 分析は `NavigationStack` へ push しない（内側スタックとの二重化でパス不整合・ドック消失を起こすため）。`isHomeAnalyticsPresented` でオーバーレイ表示する。
private enum HomeRoute: String, Hashable {
    case history
}

// MARK: - ホーム画面タブ
enum HomeTab: String, CaseIterable {
    case home = "ホーム"
    case machines = "機種管理"
    case shops = "店舗管理"
    case settings = "設定"

    /// Prime 風：非選択はアウトライン、選択はフィル
    func symbolName(isSelected: Bool) -> String {
        switch self {
        case .home: return isSelected ? "house.fill" : "house"
        case .machines: return isSelected ? "cpu.fill" : "cpu"
        case .shops: return isSelected ? "mappin.circle.fill" : "mappin.circle"
        case .settings: return isSelected ? "gearshape.fill" : "gearshape"
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
    @StateObject private var homeAnalyticsModel = AnalyticsDashboardSharedModel()
    /// 実戦中にドロワーから設定へ来たとき「実戦に戻る」を出す
    @State private var showReturnToPlayFromSettings = false
    @State private var homeNavigationPath: [HomeRoute] = []
    /// データ分析をホーム上にフルスクリーンオーバーレイ（単一 `NavigationStack` は履歴専用）
    @State private var isHomeAnalyticsPresented = false
    @State private var appeared = false
    @State private var orbPhase: CGFloat = 0
    @State private var geoAngle: Double = 0
    /// ホーム統合パネル①〜③の共通期間（タップでローテーション）
    @State private var statsPeriod: EarningsPeriod = .month
    @State private var loadedBackgroundImage: UIImage?

    @AppStorage("homeInfoPanelOrder") private var homeInfoPanelOrderRaw = HomeInfoPanelSettings.defaultOrderCSV
    @AppStorage("homeInfoPanelHidden") private var homeInfoPanelHiddenRaw = ""
    @AppStorage("homeStatsLookbackDays") private var homeStatsLookbackDays = 30

    @ObservedObject private var entitlements = EntitlementsStore.shared
    @ObservedObject private var adVisibility = AdVisibilityManager.shared

    @Query(sort: \GameSession.date, order: .reverse) private var allSessions: [GameSession]

    private var homeInfoPanelOrderParsed: [Int] {
        HomeInfoPanelSettings.normalizedOrder(from: homeInfoPanelOrderRaw)
    }

    private var homeInfoPanelHiddenParsed: Set<Int> {
        HomeInfoPanelSettings.hiddenSet(from: homeInfoPanelHiddenRaw)
    }

    private var homeLookbackClamped: Int {
        min(365, max(7, homeStatsLookbackDays))
    }

    /// 通常モードでのバッテリー節約：アニメーションはホームタブ・フォアグラウンド・低電力でない時のみ
    private var shouldRunBackgroundAnimation: Bool {
        selectedTab == .home && scenePhase == .active && !ProcessInfo.processInfo.isLowPowerModeEnabled
    }

    private let cyan = AppGlassStyle.accent
    private let purple = Color(red: 0.5, green: 0.2, blue: 0.9)
    private let magenta = Color(red: 0.9, green: 0.2, blue: 0.5)

    /// 画面幅の約5.5%（最小20・最大32）。ドックなどで使用
    private func contentHorizontalPadding(_ width: CGFloat) -> CGFloat { min(32, max(20, width * 0.055)) }

    /// `GeometryReader` 初期レイアウト等で非有限・0 以下になり得る値をガードする
    private static func clampLayoutDimension(_ value: CGFloat, minimum: CGFloat = 1) -> CGFloat {
        guard value.isFinite else { return minimum }
        return Swift.max(minimum, value)
    }

    /// ホーム「パネル下端〜広告上端＝ボタン帯」を **一続きの式** で決める。
    /// - Note: 親は `VStack { メイン領域 ; 広告＋ドック }` とし、`GeometryReader` には **広告上端より上の残り高さだけ**が提案される（`NavigationStack`＋`safeAreaInset` の組み合わせでは提案がフル画面になりボタンが広告裏に回り込むことがあったため）。
    private struct HomeMainColumnLayout {
        let width: CGFloat
        /// `GeometryReader` が受け取る高さ（広告・ドックの上からナビ／画面上端まで）
        let heightAboveAdTop: CGFloat
        let contentPad: CGFloat
        let topPad: CGFloat
        /// ボタン列の下と広告上端のあいだの余白（メイン列の内側の下端パディング）
        let bottomVisualGap: CGFloat
        let verticalSpacing: CGFloat
        let actionGridSpacing: CGFloat
        let innerW: CGFloat
        let columnW: CGFloat
        let cellW: CGFloat
        let cardPad: CGFloat
        /// パネル＋ボタン列を置く縦幅（上下パディングを除いたメイン列の確定高）
        let contentBodyH: CGFloat
        let panelSlotH: CGFloat
        let buttonColumnH: CGFloat
        let rowUnit: CGFloat

        /// ルート `safeAreaInset` に載せている下端クロームと同じ積算（自己文書化・将来の寸法変更時に `AdaptiveBannerSlot` / `MainTabDockChrome` と数を揃える）
        static func bottomChromeHeightForInset(width: CGFloat, showBanner: Bool, safeAreaBottomForHomeIndicator: CGFloat) -> CGFloat {
            let bannerH = showBanner ? AdaptiveBannerLayout.slotHeight(forWidth: width) : 0
            let dockH = max(
                AppGlassStyle.MainTabDock.selectedGlowSlotHeight,
                AppGlassStyle.MainTabDock.paddingTopBelowGlare
                    + AppGlassStyle.MainTabDock.tabRowHeight
                    + safeAreaBottomForHomeIndicator
                    + AppGlassStyle.MainTabDock.paddingBottomInterior
            )
            return bannerH + dockH
        }

        static func make(
            geo: GeometryProxy,
            hasBanner: Bool,
            contentHorizontalPadding: (CGFloat) -> CGFloat,
            panelSlotHeight: (CGFloat, Bool) -> CGFloat
        ) -> HomeMainColumnLayout {
            let w = geo.size.width
            let hRaw = geo.size.height
            let h = max(1, hRaw.isFinite ? hRaw : 1)
            let contentPad = contentHorizontalPadding(w)
            let verticalSpacing = min(22, max(10, h * 0.018))
            let actionGridSpacing = min(10, max(5, w * 0.026))
            let innerW = HomeView.clampLayoutDimension(w - contentPad * 2)
            let topPad = max(10, min(24, h * 0.02))
            let cardPad = min(20, max(12, w * 0.036))
            let bottomVisualGap = max(8, verticalSpacing * 0.55)
            let columnW = (innerW - actionGridSpacing) / 2
            let cellW = max(52, columnW)
            let contentBodyH = max(1, h - topPad - bottomVisualGap)
            let minReserveForButtons: CGFloat = 148
            let panelCap = panelSlotHeight(contentBodyH, hasBanner)
            let panelSlotH = min(
                panelCap,
                max(96, contentBodyH - verticalSpacing - minReserveForButtons)
            )
            let buttonColumnH = max(0, contentBodyH - panelSlotH - verticalSpacing)
            let spacingTotal = actionGridSpacing * 2
            let rowAlloc = max(0, buttonColumnH - spacingTotal)
            let rowUnit = rowAlloc > 0 ? rowAlloc / 5 : 0
            return HomeMainColumnLayout(
                width: w,
                heightAboveAdTop: h,
                contentPad: contentPad,
                topPad: topPad,
                bottomVisualGap: bottomVisualGap,
                verticalSpacing: verticalSpacing,
                actionGridSpacing: actionGridSpacing,
                innerW: innerW,
                columnW: columnW,
                cellW: cellW,
                cardPad: cardPad,
                contentBodyH: contentBodyH,
                panelSlotH: panelSlotH,
                buttonColumnH: buttonColumnH,
                rowUnit: rowUnit
            )
        }
    }

    /// 抜本対策：タブ切り替えでビューを破棄しない。4タブ分を常に保持し表示だけ切り替える。
    /// 下端の広告＋ドックは `safeAreaInset` ではなく **`VStack` 下部に固定**し、上段メインに残り高さだけを渡す（ボタンが広告・ドックの下に回り込まないようにする）。
    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                // ホーム（背景＋コンテンツを同一レイヤーにして背景が確実に表示される）
                ZStack {
                    NavigationStack(path: $homeNavigationPath) {
                        ZStack {
                            backgroundLayer
                            mainContent
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .navigationDestination(for: HomeRoute.self) { route in
                            switch route {
                            case .history: HistoryListView()
                            }
                        }
                    }
                    if isHomeAnalyticsPresented {
                        AnalyticsDashboardView(
                            model: homeAnalyticsModel,
                            embedBottomChrome: true,
                            onDismissEmbeddedToHome: { isHomeAnalyticsPresented = false }
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .transition(.opacity)
                        .zIndex(1)
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
                        .toolbar {
                            if showReturnToPlayFromSettings {
                                ToolbarItem(placement: .confirmationAction) {
                                    Button("実戦に戻る") {
                                        showReturnToPlayFromSettings = false
                                        isPlaying = true
                                    }
                                    .fontWeight(.semibold)
                                    .foregroundColor(AppGlassStyle.accent)
                                }
                            }
                        }
                }
                .opacity(selectedTab == .settings ? 1 : 0)
                .allowsHitTesting(selectedTab == .settings)
                .zIndex(selectedTab == .settings ? 1 : 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if !(selectedTab == .home && isHomeAnalyticsPresented) {
                VStack(spacing: 0) {
                    if adVisibility.shouldShowBanner {
                        AdaptiveBannerSlot(adUnitID: AdMobConfig.bannerUnitID)
                            .frame(maxWidth: .infinity)
                            .background(Color.black)
                    }
                    footerTabBar
                }
            }
        }
        .onChange(of: homeNavigationPath) { _, newPath in
            if newPath == [.history] {
                isHomeAnalyticsPresented = false
            }
        }
        .onChange(of: isHomeAnalyticsPresented) { _, on in
            if on {
                homeAnalyticsModel.analyticsNavPath = []
                homeAnalyticsModel.selectedFilterLabel = nil
            }
        }
        .onChange(of: selectedTab) { _, new in
            if new != .home {
                homeNavigationPath = []
                isHomeAnalyticsPresented = false
            }
            if new != .settings {
                showReturnToPlayFromSettings = false
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
                showReturnToPlayFromSettings = true
                isPlaying = false
                selectedTab = .settings
            })
        }
        .onAppear {
            syncAdPresentationGateForAppOpen()
        }
        .onChange(of: isPlaying) { _, _ in
            syncAdPresentationGateForAppOpen()
        }
        .onChange(of: showReturnToPlayFromSettings) { _, _ in
            syncAdPresentationGateForAppOpen()
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

    /// 情報パネル用の**固定スロット高**（表示セクションが変わってもレイアウト高はここで一定。溢れはパネル内スクロールのみ。ホーム全体はスクロールしない）。
    private func homePanelSlotHeight(containerHeight h: CGFloat, hasBanner: Bool) -> CGFloat {
        if hasBanner {
            return min(278, max(196, h * 0.26))
        }
        return min(400, max(232, h * 0.42))
    }

    private var mainContent: some View {
        GeometryReader { geo in
            let hasBanner = adVisibility.shouldShowBanner
            let m = HomeMainColumnLayout.make(
                geo: geo,
                hasBanner: hasBanner,
                contentHorizontalPadding: contentHorizontalPadding,
                panelSlotHeight: { homePanelSlotHeight(containerHeight: $0, hasBanner: $1) }
            )

            VStack(spacing: m.verticalSpacing) {
                ScrollView(showsIndicators: false) {
                    HomeIntegratedInfoPanel(
                        sessions: allSessions,
                        statsPeriod: $statsPeriod,
                        orderedSectionIDs: homeInfoPanelOrderParsed,
                        hiddenSectionIDs: homeInfoPanelHiddenParsed,
                        lookbackDays: homeLookbackClamped,
                        freeTierWithAds: hasBanner,
                        cardPadding: m.cardPad
                    )
                }
                .frame(height: m.panelSlotH, alignment: .top)

                mainActionsGridContent(
                    iw: m.innerW,
                    gs: m.actionGridSpacing,
                    cellW: m.cellW,
                    newStartHeight: m.rowUnit * 3,
                    secondaryHeight: m.rowUnit * 1,
                    gridSpacing: m.actionGridSpacing
                )
                .frame(maxWidth: .infinity)
                .frame(height: m.buttonColumnH, alignment: .top)
            }
            /// メイン列の縦をここで一回だけ確定し、`maxHeight: .infinity` 由来の二段階レイアウト・下端クリップを防ぐ
            .frame(height: m.contentBodyH, alignment: .top)
            .padding(.horizontal, m.contentPad)
            .padding(.top, m.topPad)
            .padding(.bottom, m.bottomVisualGap)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // opacity 0 だと起動直後〜アニメ中にタップが効かないケースがあるため、不透明度は維持しオフセットのみ演出する
        .offset(y: appeared ? 0 : 14)
        .onAppear {
            withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) { appeared = true }
        }
    }

    @ViewBuilder
    private func mainActionsGridContent(
        iw: CGFloat,
        gs: CGFloat,
        cellW: CGFloat,
        newStartHeight: CGFloat,
        secondaryHeight: CGFloat,
        gridSpacing: CGFloat
    ) -> some View {
        VStack(spacing: gridSpacing) {
            Button {
                HapticUtil.impact(.medium)
                log.reset()
                ResumableStateStore.clear()
                showMachineShopGate = true
            } label: {
                HomeGridButtonLabelSplit(
                    title: "新規スタート",
                    icon: "plus.circle",
                    width: iw,
                    height: newStartHeight
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(HomeStyleGridButtonPressStyle())

            HStack(spacing: gridSpacing) {
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
                        width: cellW,
                        height: secondaryHeight
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(HomeStyleGridButtonPressStyle())

                Button {
                    HapticUtil.impact(.medium)
                    homeNavigationPath = [.history]
                } label: {
                    HomeGridButtonLabelSplit(
                        title: "実戦履歴",
                        icon: "calendar",
                        width: cellW,
                        height: secondaryHeight
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(HomeStyleGridButtonPressStyle())
            }

            HStack(spacing: gridSpacing) {
                Button {
                    HapticUtil.impact(.medium)
                    showGameSessionEdit = true
                } label: {
                    HomeGridButtonLabelSplit(
                        title: "シンプル入力",
                        icon: "square.and.pencil",
                        width: cellW,
                        height: secondaryHeight
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(HomeStyleGridButtonPressStyle())

                Button {
                    HapticUtil.impact(.medium)
                    homeNavigationPath = []
                    isHomeAnalyticsPresented = true
                } label: {
                    HomeGridButtonLabelSplit(
                        title: "データ分析",
                        icon: "chart.bar",
                        width: cellW,
                        height: secondaryHeight
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(HomeStyleGridButtonPressStyle())
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - ホーム右列など（高さ可変ラベル）
    private struct HomeGridButtonLabelSplit: View {
        let title: String
        let icon: String
        let width: CGFloat
        let height: CGFloat

        private var safeW: CGFloat {
            guard width.isFinite, width > 0 else { return 1 }
            return width
        }
        private var safeH: CGFloat {
            guard height.isFinite, height > 0 else { return 1 }
            return height
        }

        private var cornerRadius: CGFloat { min(20, max(14, safeH * 0.22)) }
        private var minDim: CGFloat { min(safeW, safeH) }
        private var iconSize: CGFloat { min(36, max(20, minDim * 0.205)) }
        private var titleSize: CGFloat { min(16, max(11, minDim * 0.088)) }
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
            .frame(width: safeW, height: safeH)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(AppGlassStyle.cardBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(Color.white.opacity(0.14), lineWidth: 1)
            )
            .compositingGroup()
        }
    }

    private func syncAdPresentationGateForAppOpen() {
        AdPresentationGate.shared.setPlaySessionBlockingAppOpen(isPlaying || showReturnToPlayFromSettings)
    }

    /// 下部タブバー（黒帯・グレー非選択／白選択・選択直上の細ラインのみ）
    private var footerTabBar: some View {
        AppGlassStyle.MainTabDockChrome(
            selectedTabIndex: HomeTab.allCases.firstIndex(of: selectedTab),
            tabCount: HomeTab.allCases.count
        ) {
            HStack(alignment: .center, spacing: 0) {
                ForEach(HomeTab.allCases, id: \.self) { tab in
                    let on = selectedTab == tab
                    Button {
                        HapticUtil.impact(.light)
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            selectedTab = tab
                            if tab == .home {
                                homeNavigationPath = []
                                isHomeAnalyticsPresented = false
                            }
                        }
                    } label: {
                        VStack(spacing: AppGlassStyle.MainTabDock.tabIconLabelSpacing) {
                            Image(systemName: tab.symbolName(isSelected: on))
                                .font(.system(
                                    size: AppGlassStyle.MainTabDock.iconPointSize,
                                    weight: on ? .semibold : .light
                                ))
                            Text(tab.rawValue)
                                .font(.system(
                                    size: AppGlassStyle.MainTabDock.labelPointSize,
                                    weight: on ? .semibold : .regular,
                                    design: .default
                                ))
                                .lineLimit(1)
                                .minimumScaleFactor(0.85)
                        }
                        .foregroundColor(on ? Color.white : AppGlassStyle.MainTabDock.inactiveTint)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: AppGlassStyle.MainTabDock.tabRowHeight, alignment: .center)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }
}

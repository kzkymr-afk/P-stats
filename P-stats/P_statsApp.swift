import SwiftUI
import SwiftData
import PhotosUI
import LocalAuthentication
import Security
import Combine

// MARK: - ポイント表示（統計シミュレーション用・カンマ区切り + pt）
extension Int {
    /// 表示用：数値をカンマ区切りで返す（例: 12345 → "12,345"）
    var formattedPt: String { formatted(.number) }
    /// 表示用：数値 + " pt" 単位（例: 12345 → "12,345 pt"）
    var formattedPtWithUnit: String { formatted(.number) + " pt" }
}

// MARK: - キーボード・テンキー用：テンキー枠内右上にチェックマークで閉じる（全画面で統一）
extension View {
    func keyboardDismissToolbar() -> some View {
        self.toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer(minLength: 0)
                Button {
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                } label: {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(AppGlassStyle.accent)
                }
            }
        }
    }
}

// MARK: - リスト選択のマイクロインタラクション（押下で沈む・選択時触感・選択中は発光）
struct ListSelectionStyleModifier: ViewModifier {
    var isSelected: Bool

    @State private var isPressed = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(isPressed ? 0.95 : 1.0)
            .shadow(color: isSelected ? AppGlassStyle.accent.opacity(0.3) : .clear, radius: 10)
            .animation(.spring(response: 0.35, dampingFraction: 0.7), value: isPressed)
            .animation(.easeOut(duration: 0.2), value: isSelected)
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        if !isPressed {
                            UISelectionFeedbackGenerator().selectionChanged()
                            withAnimation(.easeInOut(duration: 0.12)) { isPressed = true }
                        }
                    }
                    .onEnded { _ in
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) { isPressed = false }
                        HapticUtil.impact(.medium)
                    }
            )
    }
}
extension View {
    func listSelectionStyle(isSelected: Bool = false) -> some View {
        modifier(ListSelectionStyleModifier(isSelected: isSelected))
    }
}

// MARK: - バイブ（触覚フィードバック）ユーティリティ
enum HapticUtil {
    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: "hapticEnabled") as? Bool ?? true
    }
    static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .light) {
        guard isEnabled else { return }
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }
    static func notification(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        guard isEnabled else { return }
        UINotificationFeedbackGenerator().notificationOccurred(type)
    }
}

// MARK: - 旧アプリパスコード用Keychain（本体認証移行済み。removePasscode 時のみ削除に使用）
private enum KeychainPasscode {
    static let service = "P-stats.app.lock"

    static func delete() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service
        ]
        SecItemDelete(query as CFDictionary)
    }
}

// MARK: - アプリロック状態
final class AppLockState: ObservableObject {
    static let shared = AppLockState()

    @Published var isUnlocked = false
    @AppStorage("appLockEnabled") var lockEnabled = false
    @AppStorage("appLockUseBiometric") var useBiometric = true

    /// 生体認証の可否・種類は body のたびに LAContext を作ると重いため、ロック表示時に1回だけ評価してキャッシュする
    private var cachedBiometric: (canUse: Bool, name: String)?

    var canUseBiometric: Bool {
        if let c = cachedBiometric { return c.canUse }
        let context = LAContext()
        var error: NSError?
        let canUse = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
        let name = biometricTypeName(with: context, canUse: canUse)
        cachedBiometric = (canUse, name)
        return canUse
    }
    var biometricTypeName: String {
        if let c = cachedBiometric { return c.name }
        let context = LAContext()
        var error: NSError?
        let canUse = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
        let name = biometricTypeName(with: context, canUse: canUse)
        cachedBiometric = (canUse, name)
        return name
    }
    private func biometricTypeName(with context: LAContext, canUse: Bool) -> String {
        guard canUse else { return "生体認証" }
        switch context.biometryType {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        default: return "生体認証"
        }
    }

    func removePasscode() {
        KeychainPasscode.delete()
    }

    /// 生体認証のみ（指紋 or Face ID）
    func authenticateWithBiometric() async -> Bool {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else { return false }
        do {
            return try await context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: "アプリのロックを解除")
        } catch {
            return false
        }
    }

    /// iPhone本体のパスコード or 生体認証で解除（共通）
    func authenticateWithDevice() async -> Bool {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else { return false }
        do {
            return try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "アプリのロックを解除")
        } catch {
            return false
        }
    }

    func lock() {
        isUnlocked = false
        cachedBiometric = nil
    }

    func unlock() {
        isUnlocked = true
    }
}

// MARK: - ロック画面（iPhone本体パスコード＋生体認証で解除）
/// 初回描画で LAContext を呼ばないよう、生体認証の表示文言は onAppear で遅延取得する
struct AppLockScreenView: View {
    @ObservedObject var lockState: AppLockState
    @State private var errorMessage: String?
    @State private var biometricLabel: String = "パスコードで解除"
    @State private var biometricCaption: String = "生体認証"
    @State private var biometricIcon: String = "lock.open"

    private var cyan: Color { AppGlassStyle.accent }

    var body: some View {
        ZStack {
            AppGlassStyle.background
                .ignoresSafeArea()
            VStack(spacing: 28) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 48))
                    .foregroundColor(cyan.opacity(0.9))
                Text("アプリがロックされています")
                    .font(.headline)
                    .foregroundColor(.white)
                Text("本体のパスコードまたは\(biometricCaption)で解除")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                if let msg = errorMessage {
                    Text(msg)
                        .font(.caption)
                        .foregroundColor(.red)
                        .padding(.top, 4)
                }
                Button {
                    Task {
                        if await lockState.authenticateWithDevice() {
                            await MainActor.run {
                                lockState.unlock()
                                errorMessage = nil
                                HapticUtil.notification(.success)
                            }
                        } else {
                            await MainActor.run {
                                errorMessage = "認証に失敗しました"
                            }
                        }
                    }
                } label: {
                    Label(biometricLabel, systemImage: biometricIcon)
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(cyan)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 14)
                }
                .padding(.top, 24)
            }
            .padding(40)
        }
        .onAppear {
            // 初回描画後に LAContext を参照（メインスレッドブロックで固まらないよう遅延）
            DispatchQueue.main.async {
                let name = lockState.biometricTypeName
                let canUse = lockState.canUseBiometric
                biometricCaption = name
                biometricLabel = canUse ? (name + " / パスコードで解除") : "パスコードで解除"
                biometricIcon = name == "Face ID" ? "faceid" : (name == "Touch ID" ? "touchid" : "lock.open")
            }
            if lockState.useBiometric {
                Task {
                    try? await Task.sleep(nanoseconds: 400_000_000)
                    if lockState.canUseBiometric, await lockState.authenticateWithDevice() {
                        await MainActor.run { lockState.unlock(); errorMessage = nil; HapticUtil.notification(.success) }
                    }
                }
            }
        }
    }
}

// MARK: - 起動直後の固まり防止（実機で Launch Screen のまま固まる対策）
/// 最初の 1 フレーム用。SwiftData / Models / AppLockState を一切参照しない（参照すると実機でメインスレッドがブロックされる）
private struct BootstrapLoadingView: View {
    var body: some View {
        ZStack {
            Color(red: 28/255, green: 28/255, blue: 30/255)
                .ignoresSafeArea()
            ProgressView()
                .progressViewStyle(.circular)
                .tint(.white)
                .scaleEffect(1.2)
        }
    }
}

// MARK: - ModelContainer 準備後にのみ本編を表示。ローディング中は AppLockState を参照しない
private struct AppBootstrapView: View {
    @State private var modelContainer: ModelContainer?

    var body: some View {
        Group {
            if let container = modelContainer {
                MainContentWithContainer(container: container)
            } else {
                BootstrapLoadingView()
            }
        }
        .task {
            guard modelContainer == nil else { return }
            try? await Task.sleep(nanoseconds: 300_000_000)
            let container = await Task.detached(priority: .userInitiated) {
                try? ModelContainer(
                    for: Machine.self, Shop.self, GameSession.self, PrizeSet.self,
                    MachinePrize.self, PresetMachine.self, PresetMachinePrize.self, MyMachinePreset.self
                )
            }.value
            await MainActor.run {
                modelContainer = container
            }
            // 次フレームまで譲り、SwiftUI が最初の本編レイアウトを先に進められるようにする（起動直後のタップ劣化対策）
            await Task.yield()
        }
    }
}

// MARK: - ここから先で初めて AppLockState / LaunchAppearance / HomeView を参照する
private struct MainContentWithContainer: View {
    let container: ModelContainer
    @State private var launchFinished = false
    @StateObject private var appLock = AppLockState.shared
    @Environment(\.scenePhase) private var scenePhase

    private var showLockScreen: Bool {
        launchFinished && appLock.lockEnabled && !appLock.isUnlocked
    }

    var body: some View {
        ZStack {
            LaunchAppearance.iconBackgroundColor
                .ignoresSafeArea()

            if !launchFinished {
                LaunchView(onFinish: { launchFinished = true })
            } else {
                HomeView()
                    .opacity(showLockScreen ? 0 : 1)
                    .allowsHitTesting(!showLockScreen)
            }

            if showLockScreen {
                AppGlassStyle.background
                    .ignoresSafeArea()
                    .allowsHitTesting(true)
                AppLockScreenView(lockState: appLock)
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        .environment(\.modelContext, container.mainContext)
        .animation(.easeInOut(duration: 0.25), value: showLockScreen)
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background, appLock.lockEnabled {
                appLock.lock()
            }
        }
    }
}

@main
struct P_statsApp: App {
    var body: some Scene {
        WindowGroup {
            AppBootstrapView()
        }
    }
}

// MARK: - 共通背景（実戦履歴・分析で使用。トップと同じビジュアルだが静止）
struct StaticHomeBackgroundView: View {
    @AppStorage("homeBackgroundStyle") private var homeBackgroundStyle = HomeBackgroundStore.defaultStyle
    @AppStorage("homeBackgroundImagePath") private var homeBackgroundImagePath = ""
    @State private var loadedBackgroundImage: UIImage?

    private let cyan = AppGlassStyle.accent
    private let purple = Color(red: 0.5, green: 0.2, blue: 0.9)
    private let magenta = Color(red: 0.9, green: 0.2, blue: 0.5)

    var body: some View {
        GeometryReader { geo in
            ZStack {
                if homeBackgroundStyle == "custom", let uiImage = loadedBackgroundImage {
                    Image(uiImage: uiImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                } else {
                    AppGlassStyle.background
                    orbViewStatic(color: cyan, x: 0.2, y: 0.15, geo: geo)
                    orbViewStatic(color: purple, x: 0.75, y: 0.3, geo: geo)
                    orbViewStatic(color: magenta, x: 0.5, y: 0.75, geo: geo)
                    geometricLineStatic(geo: geo)
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
            } else { loadedBackgroundImage = nil }
        }
        .onChange(of: homeBackgroundImagePath) { _, new in
            if homeBackgroundStyle == "custom", !new.isEmpty {
                Task.detached(priority: .userInitiated) { @Sendable () async in
                    let img = HomeBackgroundStore.loadCustomImage(fileName: new)
                    await MainActor.run { loadedBackgroundImage = img }
                }
            } else { loadedBackgroundImage = nil }
        }
    }

    private func orbViewStatic(color: Color, x: CGFloat, y: CGFloat, geo: GeometryProxy) -> some View {
        let size = geo.size.width * 0.6
        return Circle()
            .fill(color.opacity(0.25))
            .frame(width: size, height: size)
            .blur(radius: 80)
            .offset(x: (x - 0.5) * geo.size.width, y: (y - 0.5) * geo.size.height)
    }

    private func geometricLineStatic(geo: GeometryProxy) -> some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [.clear, cyan.opacity(0.04), .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .frame(width: geo.size.width, height: 2)
            .position(x: geo.size.width / 2, y: geo.size.height / 2)
    }
}

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
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.92))
                Text("\(periodProfit >= 0 ? "+" : "")\(periodProfit.formattedPtWithUnit)")
                    .font(.system(size: 28, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(periodProfit >= 0 ? cyan : Color(red: 0.95, green: 0.3, blue: 0.5))
                    .frame(maxWidth: .infinity)
                HStack {
                    Spacer(minLength: 0)
                    Text(periodDeficitSurplus >= 0 ? "余剰 +\(periodDeficitSurplus.formattedPtWithUnit)" : "欠損 \(periodDeficitSurplus.formattedPtWithUnit)")
                        .font(.system(size: 14, weight: .semibold, design: .rounded).monospacedDigit())
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
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.92))
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
        // 左: 新規スタート・シンプル入力を各々 side×side（従来の新規スタートと同サイズ）
        // 右: 続きから・実践履歴・データ分析を縦3等分（左列の総高さと一致）
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
                .padding(.horizontal, contentHorizontalPadding(geo.size.width))
                .padding(.bottom, 10) // 本物のiPhoneドックに近い位置（ホームインジケータ直上）
            }
        }
    }
}

// MARK: - ホーム用グリッドボタンラベル（NavigationLink用・Buttonを使わずタップで遷移）
struct HomeGridButtonLabel: View {
    let title: String
    let icon: String
    var cyan: Color = AppGlassStyle.accent
    var size: CGFloat = 160

    private var iconSize: CGFloat { min(32, max(24, size * 0.175)) }
    private var titleSize: CGFloat { min(14, max(11, size * 0.075)) }

    var body: some View {
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

// MARK: - 機種管理（スワイプで編集・削除、並べ替え、右下FABで新規登録）
private let machineOrderKey = "machineDisplayOrder"
private let shopOrderKey = "shopDisplayOrder"

struct MachineManagementView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Machine.name) private var machines: [Machine]
    @Query(sort: \GameSession.date, order: .reverse) private var recentSessions: [GameSession]
    @AppStorage(machineOrderKey) private var machineOrderStr = ""
    @State private var machineToEdit: Machine?
    @State private var showNewMachine = false
    @State private var isReorderMode = false

    private var cyan: Color { AppGlassStyle.accent }

    /// 実戦履歴ベース：新しい順（未使用の機種は後ろへ）
    private var recencyOrderedMachines: [Machine] {
        let order = recentSessions.reduce(into: [String]()) { acc, s in
            let n = s.machineName.isEmpty ? "未設定" : s.machineName
            if !acc.contains(n) { acc.append(n) }
        }
        return machines.sorted { m1, m2 in
            let i1 = order.firstIndex(of: m1.name) ?? Int.max
            let i2 = order.firstIndex(of: m2.name) ?? Int.max
            if i1 != i2 { return i1 < i2 }
            return m1.name < m2.name
        }
    }

    private var orderedMachines: [Machine] {
        let order = machineOrderStr.split(separator: "|").map(String.init)
        return machines.sorted { m1, m2 in
            let i1 = order.firstIndex(of: m1.name) ?? Int.max
            let i2 = order.firstIndex(of: m2.name) ?? Int.max
            if i1 != i2 { return i1 < i2 }
            return m1.name < m2.name
        }
    }

    // 通常表示は最新遊技順。並べ替えモード時のみ手動順を反映。
    private var machinesForList: [Machine] {
        isReorderMode ? orderedMachines : recencyOrderedMachines
    }

    private func saveMachineOrder(_ list: [Machine]) {
        machineOrderStr = list.map(\.name).joined(separator: "|")
    }

    var body: some View {
        // bottomTrailing: フル画面の List がスクロール・スワイプを受け取る。FAB はドック直上の右下。
        // 行に listSelectionStyle() を付けない（DragGesture minimumDistance:0 が List の縦スクロール・swipeActions と競合するため）
        ZStack(alignment: .bottomTrailing) {
            StaticHomeBackgroundView()
            List {
                ForEach(machinesForList) { m in
                    HStack {
                        Text(m.name)
                            .foregroundColor(.white)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .padding(.vertical, 12)
                    .listRowBackground(AppGlassStyle.rowBackground)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button {
                            machineToEdit = m
                        } label: { Label("編集", systemImage: "pencil") }
                        .tint(cyan)
                        Button(role: .destructive) {
                            modelContext.delete(m)
                            let arr = orderedMachines.filter { $0.persistentModelID != m.persistentModelID }
                            saveMachineOrder(arr)
                        } label: { Label("削除", systemImage: "trash") }
                    }
                    .moveDisabled(!isReorderMode)
                }
                .onMove { from, to in
                    guard isReorderMode else { return }
                    var arr = orderedMachines
                    arr.move(fromOffsets: from, toOffset: to)
                    saveMachineOrder(arr)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .contentMargins(.bottom, 76, for: .scrollContent)
            .environment(\.editMode, .constant(isReorderMode ? .active : .inactive))

            Button {
                showNewMachine = true
            } label: {
                Label("新規機種を登録", systemImage: "plus.circle.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 14)
                    .background(cyan, in: Capsule())
            }
            .buttonStyle(.plain)
            .padding(.trailing, 20)
            .padding(.bottom, 12)
        }
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .preferredColorScheme(.dark)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(isReorderMode ? "完了" : "並べ替え") {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        if !isReorderMode {
                            saveMachineOrder(machinesForList)
                        }
                        isReorderMode.toggle()
                    }
                }
                .foregroundColor(cyan)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { Color.clear.frame(height: 84) }
        .sheet(isPresented: Binding(
            get: { machineToEdit != nil },
            set: { if !$0 { machineToEdit = nil } }
            )) {
            if let m = machineToEdit {
                MachineEditView(editing: m)
                    .equatable()
                    .presentationDetents([.large])
            }
        }
        .sheet(isPresented: $showNewMachine) {
            MachineEditView(editing: nil)
                .equatable()
                .presentationDetents([.large])
        }
    }
}

// MARK: - 店舗管理（スワイプで編集・削除、右上並べ替え、右下FABで新規登録）
struct ShopManagementView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Shop.name) private var shops: [Shop]
    @AppStorage(shopOrderKey) private var shopOrderStr = ""
    @State private var shopToEdit: Shop?
    @State private var showNewShop = false
    @State private var isReorderMode = false

    private var cyan: Color { AppGlassStyle.accent }
    private var orderedShops: [Shop] {
        let order = shopOrderStr.split(separator: "|").map(String.init)
        return shops.sorted { s1, s2 in
            let i1 = order.firstIndex(of: s1.name) ?? Int.max
            let i2 = order.firstIndex(of: s2.name) ?? Int.max
            if i1 != i2 { return i1 < i2 }
            return s1.name < s2.name
        }
    }
    private func saveShopOrder(_ list: [Shop]) {
        shopOrderStr = list.map(\.name).joined(separator: "|")
    }

    var body: some View {
        // 行に listSelectionStyle() を付けない（機種管理と同様、List のスクロール・swipeActions と競合するため）
        ZStack(alignment: .bottomTrailing) {
            StaticHomeBackgroundView()
            List {
                ForEach(orderedShops) { s in
                    Button {
                        guard !isReorderMode else { return }
                        shopToEdit = s
                    } label: {
                        HStack {
                            Text(s.name)
                                .foregroundColor(.white)
                            Spacer()
                            if isReorderMode {
                                Image(systemName: "line.3.horizontal")
                                    .font(.subheadline)
                                    .foregroundColor(cyan.opacity(0.8))
                            } else {
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundColor(cyan.opacity(0.8))
                            }
                        }
                        .padding(.vertical, 12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .listRowBackground(AppGlassStyle.rowBackground)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            modelContext.delete(s)
                            let arr = orderedShops.filter { $0.persistentModelID != s.persistentModelID }
                            saveShopOrder(arr)
                        } label: { Label("削除", systemImage: "trash") }
                        Button {
                            shopToEdit = s
                        } label: { Label("編集", systemImage: "pencil") }
                        .tint(cyan)
                    }
                    .moveDisabled(!isReorderMode)
                }
                .onMove { from, to in
                    guard isReorderMode else { return }
                    var arr = orderedShops
                    arr.move(fromOffsets: from, toOffset: to)
                    saveShopOrder(arr)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .contentMargins(.bottom, 76, for: .scrollContent)
            .environment(\.editMode, .constant(isReorderMode ? .active : .inactive))

            Button {
                showNewShop = true
            } label: {
                Label("新規店舗を登録", systemImage: "plus.circle.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 14)
                    .background(cyan, in: Capsule())
            }
            .buttonStyle(.plain)
            .padding(.trailing, 20)
            .padding(.bottom, 12)
        }
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .preferredColorScheme(.dark)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(isReorderMode ? "完了" : "並べ替え") {
                    withAnimation(.easeInOut(duration: 0.25)) { isReorderMode.toggle() }
                }
                .foregroundColor(cyan)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { Color.clear.frame(height: 84) }
        .sheet(isPresented: Binding(
            get: { shopToEdit != nil },
            set: { if !$0 { shopToEdit = nil } }
            )) {
            if let s = shopToEdit {
                ShopEditView(shop: s) { shopToEdit = nil }
                    .presentationDetents([.medium, .large])
            }
        }
        .sheet(isPresented: $showNewShop) {
            ShopEditView(shop: nil) { showNewShop = false }
                .presentationDetents([.medium, .large])
        }
    }
}

// MARK: - Settings（タブコンテンツ・グラスモーフィズム）
struct SettingsTabView: View {
    @Binding var theme: AppTheme
    @ObservedObject private var appLock = AppLockState.shared
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Machine.name) private var machines: [Machine]
    @Query(sort: \Shop.name) private var shops: [Shop]

    @AppStorage("homeBackgroundStyle") private var homeBackgroundStyle = HomeBackgroundStore.defaultStyle
    @AppStorage("homeBackgroundImagePath") private var homeBackgroundImagePath = ""
    @AppStorage("playViewBackgroundStyle") private var playViewBackgroundStyle = "sameAsHome"
    @AppStorage("playViewBackgroundImagePath") private var playViewBackgroundImagePath = ""
    @AppStorage("playViewStartWithPowerSaving") private var playViewStartWithPowerSaving = false
    @AppStorage("startWithZeroHoldings") private var startWithZeroHoldings = false
    @AppStorage("hapticEnabled") private var hapticEnabled = true
    @AppStorage("defaultExchangeRate") private var defaultExchangeRateStr = "4.0"  // 払出係数（pt/玉）文字列
    @AppStorage("defaultBallsPerCash") private var defaultBallsPerCashStr = "125"
    @AppStorage("defaultMachineName") private var defaultMachineName = ""
    @AppStorage("defaultShopName") private var defaultShopName = ""
    @AppStorage("alwaysShowBothInvestmentButtons") private var alwaysShowBothInvestmentButtons = true
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var selectedPlayPhotoItem: PhotosPickerItem?
    @State private var isSavingPhoto = false
    @State private var isSavingPlayPhoto = false

    private var cyan: Color { AppGlassStyle.accent }
    private var defaultExchangeRate: Double { Double(defaultExchangeRateStr) ?? 4.0 }
    private var defaultBallsPerCash: Int { Int(defaultBallsPerCashStr) ?? 125 }

    var body: some View {
        ZStack {
            StaticHomeBackgroundView()
            ScrollView(showsIndicators: false) {
                    VStack(spacing: 16) {
                    // 1. アプリロック
                    settingsCard(title: "アプリロック", icon: "lock.fill") {
                        VStack(alignment: .leading, spacing: 14) {
                            Toggle(isOn: bindingLockEnabled) {
                                Text("ロックを有効にする")
                                    .foregroundColor(.white.opacity(0.9))
                            }
                            .tint(cyan)
                            if appLock.lockEnabled {
                                if appLock.canUseBiometric {
                                    Toggle(isOn: $appLock.useBiometric) {
                                        Text(appLock.biometricTypeName + "を使用")
                                            .foregroundColor(.white.opacity(0.9))
                                    }
                                    .tint(cyan)
                                }
                            }
                        }
                    }

                    // 2. デフォルト設定（機種・店舗・持ち玉0・投資ボタン表示）
                    settingsCard(title: "デフォルト設定", icon: "play.circle.fill") {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("機種")
                                    .foregroundColor(.white.opacity(0.85))
                                Spacer()
                                Picker("", selection: $defaultMachineName) {
                                    Text("— 指定なし").tag("")
                                    ForEach(machines) { m in
                                        Text(m.name).tag(m.name)
                                    }
                                }
                                .labelsHidden()
                                .tint(cyan)
                            }
                            HStack {
                                Text("店舗")
                                    .foregroundColor(.white.opacity(0.85))
                                Spacer()
                                Picker("", selection: $defaultShopName) {
                                    Text("— 指定なし").tag("")
                                    ForEach(shops) { s in
                                        Text(s.name).tag(s.name)
                                    }
                                }
                                .labelsHidden()
                                .tint(cyan)
                            }
                            Toggle(isOn: $startWithZeroHoldings) {
                                Text("新規遊技時の持ち玉数を常に０で始める")
                                    .foregroundColor(.white.opacity(0.9))
                            }
                            .tint(cyan)
                            Text("オンにすると、新規遊技開始時の必須入力「開始時の持ち玉（貯玉）」に０が入力された状態になります。")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.7))
                            Toggle(isOn: $alwaysShowBothInvestmentButtons) {
                                Text("常に現金投入・持ち玉投入両方を表示")
                                    .foregroundColor(.white.opacity(0.9))
                            }
                            .tint(cyan)
                            Text("オフの場合、持ち玉0のときは現金投入のみ、持ち玉があるときは持ち玉投入のみを表示します（ボタンは2つ分の大きさ）。")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.7))
                        }
                    }

                    // 3. 遊技開始時の初期画面
                    settingsCard(title: "遊戯開始時の初期画面", icon: "leaf.fill") {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("遊戯開始後、最初に表示する画面を選べます。")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.7))
                            Picker("", selection: $playViewStartWithPowerSaving) {
                                Text("通常モード").tag(false)
                                Text("省エネモード").tag(true)
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                        }
                    }

                    // 店舗選択なしの場合のデフォルト交換率
                    settingsCard(title: "店舗選択なしの場合のデフォルト払出係数", icon: "yensign.circle.fill") {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("払出係数（pt/玉）")
                                    .foregroundColor(.white.opacity(0.85))
                                Spacer()
                                TextField("4.0", text: $defaultExchangeRateStr)
                                    .keyboardType(.decimalPad)
                                    .multilineTextAlignment(.trailing)
                                    .foregroundColor(.white)
                                    .frame(width: 64)
                                    .padding(.vertical, 6)
                                    .padding(.horizontal, 10)
                                    .background(Color.white.opacity(0.12))
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                            HStack {
                                Text("貸玉料金（500ptあたりの玉数）")
                                    .foregroundColor(.white.opacity(0.85))
                                Spacer()
                                TextField("125", text: $defaultBallsPerCashStr)
                                    .keyboardType(.numberPad)
                                    .multilineTextAlignment(.trailing)
                                    .foregroundColor(.white)
                                    .frame(width: 64)
                                    .padding(.vertical, 6)
                                    .padding(.horizontal, 10)
                                    .background(Color.white.opacity(0.12))
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                        }
                    }

                    // 6. バイブ
                    settingsCard(title: "バイブ（触覚フィードバック）", icon: "iphone.radiowaves.left.and.right") {
                        Toggle(isOn: $hapticEnabled) {
                            Text("オン")
                                .foregroundColor(.white.opacity(0.9))
                        }
                        .tint(cyan)
                    }

                    // 7. テーマ
                    settingsCard(title: "テーマ", icon: "paintbrush.fill") {
                        Picker("", selection: $theme) {
                            ForEach(AppTheme.allCases, id: \.self) { t in
                                Text(t.rawValue).tag(t)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                    }

                    // 8. 背景設定（ホーム上・実戦下）
                    settingsCard(title: "背景設定", icon: "photo.fill") {
                        VStack(alignment: .leading, spacing: 16) {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("ホーム")
                                    .font(.subheadline.weight(.medium))
                                    .foregroundColor(.white.opacity(0.9))
                                Picker("", selection: $homeBackgroundStyle) {
                                    Text("デフォルト").tag(HomeBackgroundStore.defaultStyle)
                                    Text("カスタム画像").tag("custom")
                                }
                                .pickerStyle(.segmented)
                                .labelsHidden()
                                if homeBackgroundStyle == "custom" {
                                    PhotosPicker(
                                        selection: $selectedPhotoItem,
                                        matching: .images,
                                        photoLibrary: .shared()
                                    ) {
                                        HStack {
                                            Image(systemName: "photo.on.rectangle.angled")
                                                .foregroundColor(cyan)
                                            Text(homeBackgroundImagePath.isEmpty ? "写真を選択" : "写真を変更")
                                                .foregroundColor(.white)
                                            if homeBackgroundImagePath.isEmpty {
                                                Text("壁紙として設定")
                                                    .font(.caption)
                                                    .foregroundColor(.white.opacity(0.6))
                                            }
                                        }
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 10)
                                    }
                                    .onChange(of: selectedPhotoItem) { _, newItem in
                                        Task { await saveSelectedPhoto(newItem) }
                                    }
                                    if isSavingPhoto {
                                        HStack {
                                            ProgressView()
                                                .tint(.white)
                                            Text("保存中…")
                                                .font(.caption)
                                                .foregroundColor(.white.opacity(0.7))
                                        }
                                        .frame(maxWidth: .infinity)
                                    }
                                }
                            }
                            VStack(alignment: .leading, spacing: 12) {
                                Text("実戦画面")
                                    .font(.subheadline.weight(.medium))
                                    .foregroundColor(.white.opacity(0.9))
                                Picker("", selection: $playViewBackgroundStyle) {
                                    Text("ホームと同じ").tag("sameAsHome")
                                    Text("別の画像").tag("custom")
                                }
                                .pickerStyle(.segmented)
                                .labelsHidden()
                                if playViewBackgroundStyle == "custom" {
                                    PhotosPicker(
                                        selection: $selectedPlayPhotoItem,
                                        matching: .images,
                                        photoLibrary: .shared()
                                    ) {
                                        HStack {
                                            Image(systemName: "photo.on.rectangle.angled")
                                                .foregroundColor(cyan)
                                            Text(playViewBackgroundImagePath.isEmpty ? "写真を選択" : "写真を変更")
                                                .foregroundColor(.white)
                                        }
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 10)
                                    }
                                    .onChange(of: selectedPlayPhotoItem) { _, newItem in
                                        Task { await saveSelectedPlayPhoto(newItem) }
                                    }
                                    if isSavingPlayPhoto {
                                        HStack {
                                            ProgressView().tint(.white)
                                            Text("保存中…").font(.caption).foregroundColor(.white.opacity(0.7))
                                        }
                                        .frame(maxWidth: .infinity)
                                    }
                                }
                            }
                        }
                    }

                    // 9. このアプリの情報
                    settingsCard(title: "このアプリの情報", icon: "info.circle.fill") {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("バージョン")
                                    .foregroundColor(.white.opacity(0.85))
                                Spacer()
                                Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—")
                                    .foregroundColor(.white)
                            }
                            HStack {
                                Text("ビルド")
                                    .foregroundColor(.white.opacity(0.85))
                                Spacer()
                                Text(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—")
                                    .foregroundColor(.white.opacity(0.9))
                            }
                            if let mailURL = URL(string: "mailto:?subject=P-stats%20要望・お問い合わせ") {
                                Link(destination: mailURL) {
                                    HStack {
                                        Image(systemName: "envelope.fill")
                                            .foregroundColor(cyan)
                                        Text("要望を管理人に送る")
                                            .foregroundColor(cyan)
                                    }
                                    .font(.subheadline)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 120)
                }
        }
        .keyboardDismissToolbar()
        .toolbarColorScheme(.dark, for: .navigationBar)
        .preferredColorScheme(.dark)
        .safeAreaInset(edge: .bottom, spacing: 0) { Color.clear.frame(height: 84) }
    }

    private var bindingLockEnabled: Binding<Bool> {
        Binding(
            get: { appLock.lockEnabled },
            set: { new in
                if new {
                    appLock.lockEnabled = true
                } else {
                    Task {
                        if await appLock.authenticateWithDevice() {
                            await MainActor.run {
                                appLock.removePasscode()
                                appLock.lockEnabled = false
                                appLock.unlock()
                            }
                        }
                    }
                }
            }
        )
    }

    private func settingsCard<Content: View>(title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundColor(cyan)
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white.opacity(0.95))
            }
            content()
                .foregroundColor(.white.opacity(0.9))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(AppGlassStyle.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(AppGlassStyle.strokeGradient, lineWidth: 1)
        )
    }

    private func saveSelectedPhoto(_ item: PhotosPickerItem?) async {
        guard let item = item else { return }
        isSavingPhoto = true
        defer { isSavingPhoto = false }
        if let data = try? await item.loadTransferable(type: Data.self),
           let image = UIImage(data: data),
           let _ = HomeBackgroundStore.saveCustomImage(image) {
            homeBackgroundImagePath = HomeBackgroundStore.customImageFileName
            homeBackgroundStyle = "custom"
        }
    }

    private func saveSelectedPlayPhoto(_ item: PhotosPickerItem?) async {
        guard let item = item else { return }
        isSavingPlayPhoto = true
        defer { isSavingPlayPhoto = false }
        if let data = try? await item.loadTransferable(type: Data.self),
           let image = UIImage(data: data),
           let _ = PlayBackgroundStore.saveCustomImage(image) {
            playViewBackgroundImagePath = PlayBackgroundStore.imageFileName
            playViewBackgroundStyle = "custom"
        }
    }
}


// MARK: - 続きから：直近5件の履歴から選んで同じ機種・店舗で再開（復元不可時）
struct ContinuePlaySelectionView: View {
    @Bindable var log: GameLog
    var restoreFailed: Bool = false
    var onStart: () -> Void
    var onCancel: () -> Void

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \GameSession.date, order: .reverse) private var allSessions: [GameSession]
    @Query(sort: \Machine.name) private var machines: [Machine]
    @Query(sort: \Shop.name) private var shops: [Shop]

    @State private var alertMessage: String?
    @State private var showRestoreFailedAlert = false

    private var recentSessions: [GameSession] { Array(allSessions.prefix(5)) }

    var body: some View {
        NavigationStack {
            ZStack {
                StaticHomeBackgroundView()
                Group {
                    if recentSessions.isEmpty {
                        VStack(spacing: 16) {
                            Image(systemName: "tray")
                                .font(.system(size: 48))
                                .foregroundStyle(.white.opacity(0.5))
                            Text("遊戯履歴がありません")
                                .font(.headline)
                                .foregroundColor(.white)
                            Text("新規遊技スタートで遊戯を開始してください")
                                .font(.subheadline)
                                .foregroundStyle(.white.opacity(0.7))
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        List {
                            Section {
                                Text("再開したい遊戯を選んでください。同じ機種・店舗で遊戯を開始します。")
                                    .font(.caption)
                                    .foregroundStyle(.white.opacity(0.7))
                                    .listRowBackground(AppGlassStyle.rowBackground)
                            }
                            ForEach(recentSessions, id: \.id) { session in
                                Button {
                                    resume(session)
                                } label: {
                                    VStack(alignment: .leading, spacing: 6) {
                                        HStack {
                                            Text(session.machineName)
                                                .font(.body.weight(.semibold))
                                                .foregroundColor(.white)
                                            Spacer()
                                            Text(fullJapaneseDateFormatter.string(from: session.date))
                                                .font(.caption)
                                                .foregroundColor(.white.opacity(0.95))
                                                .shadow(color: .black.opacity(0.7), radius: 2, x: 0, y: 1)
                                        }
                                        Text(session.shopName)
                                            .font(.subheadline)
                                            .foregroundStyle(.white.opacity(0.8))
                                    }
                                    .padding(.vertical, 4)
                                }
                                .listRowBackground(AppGlassStyle.rowBackground)
                                .listSelectionStyle()
                            }
                        }
                        .listStyle(.plain)
                        .scrollContentBackground(.hidden)
                    }
                }
            }
            .navigationTitle("続きから")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .preferredColorScheme(.dark)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { onCancel() }
                }
            }
            .alert("この履歴では再開できません", isPresented: Binding(
                get: { alertMessage != nil },
                set: { if !$0 { alertMessage = nil } }
            )) {
                Button("OK", role: .cancel) { alertMessage = nil }
            } message: {
                if let m = alertMessage { Text(m) }
            }
            .alert("前回の状態から復元できません", isPresented: $showRestoreFailedAlert) {
                Button("OK", role: .cancel) { showRestoreFailedAlert = false }
            } message: {
                Text("前回の機種・店舗がマイリストに登録されていません。履歴から選んで再開してください。")
            }
            .onAppear {
                if restoreFailed { showRestoreFailedAlert = true }
            }
        }
    }

    private func resume(_ session: GameSession) {
        let mach = machines.first { $0.name == session.machineName }
        let shop = shops.first { $0.name == session.shopName }
        if let m = mach, let s = shop {
            log.selectedMachine = m
            log.selectedShop = s
            onStart()
        } else {
            alertMessage = "この履歴の機種・店舗がマイリストに登録されていません。マイリストで同じ機種・店舗を登録してから再度お試しください。"
        }
    }
}

// --- 実戦ログ・期待値収支（日付でグループ化） ---
private let fullJapaneseDateFormatter: DateFormatter = {
    let f = DateFormatter()
    f.locale = Locale(identifier: "ja_JP")
    f.dateFormat = "yyyy年M月d日"
    return f
}()

private let sessionDateFormatter: DateFormatter = {
    let f = DateFormatter()
    f.locale = Locale(identifier: "ja_JP")
    f.dateFormat = "yyyy年M月d日"
    return f
}()

struct HistoryListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \GameSession.date, order: .reverse) var sessions: [GameSession]
    @State private var sessionToEdit: GameSession?

    private var sessionsByDate: [(String, [GameSession])] {
        let grouped = Dictionary(grouping: sessions) { sessionDateFormatter.string(from: $0.date) }
        return grouped.sorted { $0.key > $1.key }.map { ($0.key, $0.value) }
    }

    var body: some View {
        ZStack {
            StaticHomeBackgroundView()
            ScrollView(showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(sessionsByDate, id: \.0) { item in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.0)
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(.white.opacity(0.95))
                                .shadow(color: .black.opacity(0.7), radius: 2, x: 0, y: 1)
                                .padding(.horizontal, 4)
                            ForEach(item.1) { session in
                                NavigationLink(destination: SessionDetailView(session: session)) {
                                    HistorySessionCard(session: session)
                                }
                                .buttonStyle(.plain)
                                .contentShape(Rectangle())
                                .contextMenu {
                                    Button {
                                        sessionToEdit = session
                                    } label: { Label("編集", systemImage: "pencil") }
                                    Button(role: .destructive) {
                                        modelContext.delete(session)
                                    } label: { Label("削除", systemImage: "trash") }
                                }
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    Button(role: .destructive) {
                                        modelContext.delete(session)
                                    } label: { Label("削除", systemImage: "trash") }
                                    Button {
                                        sessionToEdit = session
                                    } label: { Label("編集", systemImage: "pencil") }
                                        .tint(AppGlassStyle.accent)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
        }
        .navigationTitle("実戦履歴")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .preferredColorScheme(.dark)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    dismiss()
                } label: {
                    Label("戻る", systemImage: "chevron.left")
                }
            }
        }
        .sheet(item: $sessionToEdit) { s in
            NavigationStack {
                SessionEditView(session: s)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("閉じる") { sessionToEdit = nil }
                        }
                    }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(AppGlassStyle.background)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .preferredColorScheme(.dark)
        }
    }
}

// MARK: - 履歴詳細（タップで表示）。各パネルは角丸・不透明度85％・ラベル可読性向上
struct SessionDetailView: View {
    let session: GameSession
    @Environment(\.dismiss) private var dismiss
    @State private var showEditSheet = false

    private let panelBg = Color.black.opacity(0.85)
    private let labelColor = Color.white.opacity(0.95)
    private let labelShadow = (color: Color.black.opacity(0.7), radius: CGFloat(2), x: CGFloat(0), y: CGFloat(1))

    /// 回収額（pt換算）
    private var recoveryPt: Int { Int(Double(session.totalHoldings) * session.payoutCoefficient) }
    /// 実質回転率（回転/千pt）
    private var rotationPer1k: Double {
        guard session.inputCash > 0 else { return 0 }
        return Double(session.normalRotations) / (Double(session.inputCash) / 1000.0)
    }

    var body: some View {
        ZStack {
            StaticHomeBackgroundView()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    detailPanel(title: "記録日時") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(fullJapaneseDateFormatter.string(from: session.date))
                                .font(.body)
                                .foregroundColor(labelColor)
                                .shadow(color: labelShadow.color, radius: labelShadow.radius, x: labelShadow.x, y: labelShadow.y)
                        }
                    }

                    detailPanel(title: "機種・店舗") {
                        VStack(alignment: .leading, spacing: 8) {
                            detailRow(label: "機種", value: session.machineName)
                            detailRow(label: "店舗", value: session.shopName)
                            if !session.manufacturerName.isEmpty {
                                detailRow(label: "メーカー", value: session.manufacturerName)
                            }
                        }
                    }

                    detailPanel(title: "成績の推移") {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("投入（現金）")
                                        .font(.caption)
                                        .foregroundColor(labelColor)
                                        .shadow(color: labelShadow.color, radius: labelShadow.radius, x: labelShadow.x, y: labelShadow.y)
                                    Text(session.inputCash.formattedPtWithUnit)
                                        .font(.subheadline.monospacedDigit())
                                        .foregroundColor(.white)
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 4) {
                                    Text("回収（pt換算）")
                                        .font(.caption)
                                        .foregroundColor(labelColor)
                                        .shadow(color: labelShadow.color, radius: labelShadow.radius, x: labelShadow.x, y: labelShadow.y)
                                    Text(recoveryPt.formattedPtWithUnit)
                                        .font(.subheadline.monospacedDigit())
                                        .foregroundColor(.white)
                                }
                            }
                            GeometryReader { geo in
                                let w = geo.size.width
                                let total = max(session.inputCash + recoveryPt, 1)
                                let investW = w * CGFloat(session.inputCash) / CGFloat(total)
                                HStack(spacing: 0) {
                                    Rectangle()
                                        .fill(Color.orange.opacity(0.7))
                                        .frame(width: max(4, investW))
                                    Rectangle()
                                        .fill(Color.green.opacity(0.7))
                                        .frame(width: max(4, w - investW))
                                }
                            }
                            .frame(height: 24)
                        }
                    }

                    detailPanel(title: "数値サマリ") {
                        VStack(alignment: .leading, spacing: 8) {
                            detailRow(label: "総回転数", value: "\(session.normalRotations)")
                            detailRow(label: "総投入額（現金）", value: session.inputCash.formattedPtWithUnit)
                            detailRow(label: "回収出球", value: "\(session.totalHoldings) 玉")
                            detailRow(label: "回収額（pt換算）", value: recoveryPt.formattedPtWithUnit)
                            detailRow(label: "理論値", value: "\(session.theoreticalValue >= 0 ? "+" : "")\(session.theoreticalValue.formattedPtWithUnit)")
                            detailRow(label: "欠損・余剰", value: "\(session.deficitSurplus >= 0 ? "+" : "")\(session.deficitSurplus.formattedPtWithUnit)")
                            HStack {
                                Text("実成績")
                                    .font(.subheadline)
                                    .foregroundColor(labelColor)
                                    .shadow(color: labelShadow.color, radius: labelShadow.radius, x: labelShadow.x, y: labelShadow.y)
                                Spacer()
                                Text("\(session.performance >= 0 ? "+" : "")\(session.performance.formattedPtWithUnit)")
                                    .font(.body.weight(.semibold).monospacedDigit())
                                    .foregroundColor(session.performance >= 0 ? .green : .red)
                            }
                        }
                    }

                    detailPanel(title: "分析（入力データから算出）") {
                        VStack(alignment: .leading, spacing: 8) {
                            detailRow(label: "理論値比（保存時）", value: session.expectationRatioAtSave > 0 ? String(format: "%.2f%%", session.expectationRatioAtSave * 100) : "—")
                            detailRow(label: "実質回転率", value: String(format: "%.1f 回/1k", rotationPer1k))
                            detailRow(label: "RUSH当選", value: "\(session.rushWinCount) 回")
                            detailRow(label: "通常当選", value: "\(session.normalWinCount) 回")
                            detailRow(label: "LT当選", value: "\(session.ltWinCount) 回")
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
        }
        .navigationTitle("履歴詳細")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .preferredColorScheme(.dark)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("編集") { showEditSheet = true }
            }
        }
        .sheet(isPresented: $showEditSheet) {
            NavigationStack {
                SessionEditView(session: session)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("閉じる") { showEditSheet = false }
                        }
                    }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(AppGlassStyle.background)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .preferredColorScheme(.dark)
        }
    }

    private func detailPanel<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(labelColor)
                .shadow(color: labelShadow.color, radius: labelShadow.radius, x: labelShadow.x, y: labelShadow.y)
            content()
                .foregroundColor(.white.opacity(0.9))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(panelBg)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(AppGlassStyle.strokeGradient, lineWidth: 1))
    }

    private func detailRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundColor(labelColor)
                .shadow(color: labelShadow.color, radius: labelShadow.radius, x: labelShadow.x, y: labelShadow.y)
            Spacer()
            Text(value)
                .font(.subheadline.monospacedDigit())
                .foregroundColor(.white)
        }
    }
}

// MARK: - 実戦履歴カード（1記録＝1枚の角丸グラスパネル）
struct HistorySessionCard: View {
    let session: GameSession

    private var rotationPer1k: Double {
        guard session.totalRealCost > 0 else { return 0 }
        return (Double(session.normalRotations) / session.totalRealCost) * 1000
    }
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
                labelValue("総回転", "\(session.normalRotations)")
                Text("・").foregroundColor(.white.opacity(0.5))
                labelValue("投入", session.inputCash.formattedPtWithUnit)
                Text("・").foregroundColor(.white.opacity(0.5))
                labelValue("回収玉", "\(session.totalHoldings)")
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
        .background(Color.black.opacity(0.85))
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

    private func labelValue(_ label: String, _ value: String) -> some View {
        HStack(spacing: 4) {
            Text(label + ":")
                .foregroundColor(.white.opacity(0.65))
            Text(value)
                .foregroundColor(.white)
        }
    }
}

// MARK: - 実戦履歴の編集（マイリスト参照＋一覧にない場合は手入力）
struct SessionEditView: View {
    @Bindable var session: GameSession
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Machine.name) private var machines: [Machine]
    @Query(sort: \Shop.name) private var shops: [Shop]
    @State private var selectedMachine: Machine?
    @State private var selectedShop: Shop?

    var body: some View {
        ZStack {
            StaticHomeBackgroundView()
            List {
                Section("機種（マイリスト）") {
                if !machines.isEmpty {
                    Picker("機種を選択", selection: $selectedMachine) {
                        Text("手入力（一覧にない）").tag(nil as Machine?)
                        ForEach(machines) { m in
                            Text(m.name).tag(Optional(m))
                        }
                    }
                    .onChange(of: selectedMachine) { _, new in
                        if let m = new {
                            session.machineName = m.name
                            session.manufacturerName = m.manufacturer
                        }
                    }
                    .listRowBackground(AppGlassStyle.rowBackground)
                }
                Text("一覧にない場合は下記で入力")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
                    .listRowBackground(AppGlassStyle.rowBackground)
                TextField("機種名（手入力）", text: $session.machineName)
                    .onChange(of: session.machineName) { _, _ in selectedMachine = nil }
                    .listRowBackground(AppGlassStyle.rowBackground)
                TextField("メーカー（分析用）", text: $session.manufacturerName)
                    .listRowBackground(AppGlassStyle.rowBackground)
            }

            Section("店舗（マイリスト）") {
                if !shops.isEmpty {
                    Picker("店舗を選択", selection: $selectedShop) {
                        Text("手入力（一覧にない）").tag(nil as Shop?)
                        ForEach(shops) { s in
                            Text(s.name).tag(Optional(s))
                        }
                    }
                    .onChange(of: selectedShop) { _, new in
                        if let s = new {
                            session.shopName = s.name
                            session.payoutCoefficient = s.payoutCoefficient
                        }
                    }
                    .listRowBackground(AppGlassStyle.rowBackground)
                }
                Text("一覧にない場合は下記で入力")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
                    .listRowBackground(AppGlassStyle.rowBackground)
                TextField("店舗名（手入力）", text: $session.shopName)
                    .onChange(of: session.shopName) { _, _ in selectedShop = nil }
                    .listRowBackground(AppGlassStyle.rowBackground)
            }

            Section("数値") {
                HStack {
                    Text("投入（pt）")
                    Spacer()
                    TextField("0", value: $session.inputCash, format: .number)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                }
                .listRowBackground(AppGlassStyle.rowBackground)
                HStack {
                    Text("回収玉数")
                    Spacer()
                    TextField("0", value: $session.totalHoldings, format: .number)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                }
                .listRowBackground(AppGlassStyle.rowBackground)
                HStack {
                    Text("総回転数")
                    Spacer()
                    TextField("0", value: $session.normalRotations, format: .number)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                }
                .listRowBackground(AppGlassStyle.rowBackground)
                HStack {
                    Text("RUSH当選回数")
                    Spacer()
                    TextField("0", value: $session.rushWinCount, format: .number)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                }
                .listRowBackground(AppGlassStyle.rowBackground)
                HStack {
                    Text("通常当選回数")
                    Spacer()
                    TextField("0", value: $session.normalWinCount, format: .number)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                }
                .listRowBackground(AppGlassStyle.rowBackground)
                HStack {
                    Text("LT当選回数")
                    Spacer()
                    TextField("0", value: $session.ltWinCount, format: .number)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                }
                .listRowBackground(AppGlassStyle.rowBackground)
                HStack {
                    Text("払出係数（pt/玉）")
                    Spacer()
                    TextField("4.0", value: $session.payoutCoefficient, format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                }
                .listRowBackground(AppGlassStyle.rowBackground)
            }

            Section("計算用（変更時は理論値を再計算）") {
                HStack {
                    Text("実質投入（pt）")
                    Spacer()
                    TextField("0", value: $session.totalRealCost, format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                }
                .listRowBackground(AppGlassStyle.rowBackground)
                HStack {
                    Text("基準値比（保存時）")
                    Spacer()
                    TextField("1.0", value: $session.expectationRatioAtSave, format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                }
                .listRowBackground(AppGlassStyle.rowBackground)
                if session.expectationRatioAtSave == 0 || session.totalRealCost == 0 {
                    Text("理論値を出すには「実質投入」と「基準値比」を入力し、「理論値を再計算」をタップしてください。1.0＝基準、1.1＝10%上回り。")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.7))
                        .listRowBackground(AppGlassStyle.rowBackground)
                }
                Button("理論値を再計算") {
                    let ratio = session.expectationRatioAtSave > 0 ? session.expectationRatioAtSave : 1.0
                    let cost = session.totalRealCost > 0 ? session.totalRealCost : Double(session.inputCash)
                    session.theoreticalValue = Int(round(cost * (ratio - 1)))
                    if session.totalRealCost == 0 && session.inputCash > 0 {
                        session.totalRealCost = Double(session.inputCash)
                    }
                }
                .listRowBackground(AppGlassStyle.rowBackground)
            }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("履歴を編集")
        .navigationBarTitleDisplayMode(.inline)
        .keyboardDismissToolbar()
        .toolbarColorScheme(.dark, for: .navigationBar)
        .preferredColorScheme(.dark)
        .onAppear {
            if selectedMachine == nil {
                selectedMachine = machines.first { $0.name == session.machineName }
            }
            if selectedShop == nil {
                selectedShop = shops.first { $0.name == session.shopName }
            }
            // 実質投入が未入力で総投入額がある場合は、現金投入を実質投入として補正（理論値計算のため）
            if session.totalRealCost == 0 && session.inputCash > 0 {
                session.totalRealCost = Double(session.inputCash)
            }
        }
    }
}

import SwiftUI
import SwiftData

// MARK: - ここから先で初めて AppLockState / LaunchAppearance / HomeView を参照する
struct MainContentWithContainer: View {
    let container: ModelContainer
    @State private var launchFinished = false
    @StateObject private var appLock = AppLockState.shared
    @Environment(\.scenePhase) private var scenePhase
    @State private var appOpenColdStartTask: Task<Void, Never>?

    private var showLockScreen: Bool {
        launchFinished && appLock.lockEnabled && !appLock.isUnlocked
    }

    private var homeReadyForAppOpenAd: Bool {
        launchFinished && (!appLock.lockEnabled || appLock.isUnlocked)
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
        .onChange(of: scenePhase) { oldPhase, newPhase in
            if newPhase == .background, appLock.lockEnabled {
                appLock.lock()
            }
            if oldPhase == .background, newPhase == .active {
                AppOpenAdPresenter.tryPresentAfterResumeFromBackgroundIfNeeded()
            }
        }
        .onChange(of: launchFinished) { _, _ in
            scheduleAppOpenColdStartIfNeeded()
        }
        .onChange(of: appLock.isUnlocked) { _, _ in
            scheduleAppOpenColdStartIfNeeded()
        }
        .onChange(of: appLock.lockEnabled) { _, _ in
            scheduleAppOpenColdStartIfNeeded()
        }
    }

    private func scheduleAppOpenColdStartIfNeeded() {
        guard homeReadyForAppOpenAd else { return }
        appOpenColdStartTask?.cancel()
        appOpenColdStartTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 450_000_000)
            guard !Task.isCancelled else { return }
            AppOpenAdPresenter.requestColdStartIfNeeded()
        }
    }
}

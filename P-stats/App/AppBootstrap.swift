import SwiftUI
import SwiftData

// MARK: - 起動直後の固まり防止（実機で Launch Screen のまま固まる対策）
/// 最初の 1 フレーム用。SwiftData / Models / AppLockState を一切参照しない（参照すると実機でメインスレッドがブロックされる）
private struct BootstrapLoadingView: View {
    var body: some View {
        ZStack {
            Color(
                red: DesignTokens.System.rootBackgroundR,
                green: DesignTokens.System.rootBackgroundG,
                blue: DesignTokens.System.rootBackgroundB
            )
            .ignoresSafeArea()
            ProgressView()
                .progressViewStyle(.circular)
                .tint(.white)
                .scaleEffect(1.2)
        }
    }
}

/// `ModelContainer` をプロセス内で1回だけ（同時リクエストは同一 Task に合流）作成する。
/// - `.task` の重なりや detached スレッドでの init は SwiftData が「初期化失敗後の再利用」扱いになり得るため、**必ず MainActor 上で**開く。
private actor AppModelContainerLoader {
    static let shared = AppModelContainerLoader()
    private var container: ModelContainer?
    private var inFlight: Task<ModelContainer, Error>?

    func loadIfNeeded() async throws -> ModelContainer {
        if let container { return container }
        if let inFlight {
            return try await inFlight.value
        }
        let task = Task(priority: .userInitiated) {
            try await MainActor.run {
                let schema = Schema(versionedSchema: PStatsSchemaV1.self)
                return try ModelContainer(
                    for: schema,
                    migrationPlan: PStatsMigrationPlan.self,
                    configurations: ModelConfiguration()
                )
            }
        }
        inFlight = task
        do {
            let c = try await task.value
            container = c
            inFlight = nil
            return c
        } catch {
            inFlight = nil
            throw error
        }
    }
}

private struct BootstrapFailedView: View {
    var message: String

    var body: some View {
        ZStack {
            Color(
                red: DesignTokens.System.rootBackgroundR,
                green: DesignTokens.System.rootBackgroundG,
                blue: DesignTokens.System.rootBackgroundB
            )
            .ignoresSafeArea()
            VStack(spacing: 16) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.largeTitle)
                    .foregroundStyle(.yellow)
                Text("データの準備に失敗しました")
                    .font(.headline)
                    .foregroundStyle(.white)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                Text("アプリを終了して再度開いてください。改善しない場合はアプリを削除して再インストールするとデータストアを初期化できます。")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.65))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
        }
    }
}

// MARK: - ModelContainer 準備後にのみ本編を表示。ローディング中は AppLockState を参照しない
struct AppBootstrapView: View {
    @State private var modelContainer: ModelContainer?
    @State private var bootstrapError: String?

    var body: some View {
        Group {
            if let container = modelContainer {
                MainContentWithContainer(container: container)
            } else if let bootstrapError {
                BootstrapFailedView(message: bootstrapError)
            } else {
                BootstrapLoadingView()
            }
        }
        .task {
            guard modelContainer == nil, bootstrapError == nil else { return }
            try? await Task.sleep(nanoseconds: 300_000_000)
            do {
                let container = try await AppModelContainerLoader.shared.loadIfNeeded()
                await MainActor.run {
                    modelContainer = container
                }
                // 次フレームまで譲り、SwiftUI が最初の本編レイアウトを先に進められるようにする（起動直後のタップ劣化対策）
                await Task.yield()
            } catch {
                await MainActor.run {
                    bootstrapError = "データストアを開けませんでした。アプリを終了して再度お試しください。改善しない場合は再インストールで初期化できます。"
                }
            }
        }
    }
}

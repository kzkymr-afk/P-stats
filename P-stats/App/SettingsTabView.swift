import SwiftUI
import SwiftData
import PhotosUI
import UIKit

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
                                    .font(AppTypography.sectionSubheading)
                                    .foregroundColor(.white.opacity(0.9))
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
                                    .font(AppTypography.sectionSubheading)
                                    .foregroundColor(.white.opacity(0.9))
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
                                    .font(AppTypography.sectionSubheading)
                                    .foregroundColor(.white.opacity(0.9))
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
                                    .font(AppTypography.sectionSubheading)
                                    .foregroundColor(.white.opacity(0.9))
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
                                    .font(AppTypography.sectionSubheading)
                                    .foregroundColor(.white.opacity(0.95))
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
                                    .font(AppTypography.sectionSubheading)
                                    .foregroundColor(.white.opacity(0.95))
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
                                    .font(AppTypography.sectionSubheading)
                                    .foregroundColor(.white.opacity(0.9))
                                Spacer()
                                Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—")
                                    .foregroundColor(.white)
                            }
                            HStack {
                                Text("ビルド")
                                    .font(AppTypography.sectionSubheading)
                                    .foregroundColor(.white.opacity(0.9))
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
                    .font(AppTypography.panelHeading)
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


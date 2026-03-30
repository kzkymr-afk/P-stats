import SwiftUI
import SwiftData
import PhotosUI
import StoreKit
import UIKit

// MARK: - Settings（タブコンテンツ・グラスモーフィズム）
struct SettingsTabView: View {
    @Binding var theme: AppTheme
    @ObservedObject private var appLock = AppLockState.shared
    @ObservedObject private var entitlements = EntitlementsStore.shared
    @ObservedObject private var analyticsTrial = RewardedAnalyticsTrialController.shared
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Machine.name) private var machines: [Machine]
    @Query(sort: \Shop.name) private var shops: [Shop]

    @AppStorage("homeBackgroundStyle") private var homeBackgroundStyle = HomeBackgroundStore.defaultStyle
    @AppStorage("homeBackgroundImagePath") private var homeBackgroundImagePath = ""
    @AppStorage("playViewBackgroundStyle") private var playViewBackgroundStyle = "sameAsHome"
    @AppStorage("playViewBackgroundImagePath") private var playViewBackgroundImagePath = ""
    @AppStorage("playViewStartWithPowerSaving") private var playViewStartWithPowerSaving = false
    /// 実戦画面表示中は自動スリープ（画面オフ）を無効化
    @AppStorage("playDisableIdleTimerDuringPlay") private var playDisableIdleTimerDuringPlay = true
    @AppStorage("startWithZeroHoldings") private var startWithZeroHoldings = false
    @AppStorage("hapticEnabled") private var hapticEnabled = true
    @AppStorage("defaultExchangeRate") private var defaultExchangeRateStr = "4.0"  // 払出係数（pt/玉）文字列
    @AppStorage("defaultBallsPerCash") private var defaultBallsPerCashStr = "125"
    @AppStorage("defaultMachineName") private var defaultMachineName = ""
    @AppStorage("defaultShopName") private var defaultShopName = ""
    @AppStorage("alwaysShowBothInvestmentButtons") private var alwaysShowBothInvestmentButtons = true
    @AppStorage("bigHitSlideRailStyle") private var bigHitSlideRailStyleRaw = BigHitSlideRailStyle.defaultStorageValue
    @AppStorage("bigHitHoldingsEntryDefault") private var bigHitHoldingsEntryDefaultRaw = BigHitHoldingsEntryKind.appStorageDefaultRawValue
    @AppStorage("homeInfoPanelOrder") private var homeInfoPanelOrderRaw = HomeInfoPanelSettings.defaultOrderCSV
    @AppStorage("homeInfoPanelHidden") private var homeInfoPanelHiddenRaw = ""
    @AppStorage("homeStatsLookbackDays") private var homeStatsLookbackDays = 30
    @State private var panelOrderEdit: [Int] = []
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var selectedPlayPhotoItem: PhotosPickerItem?
    @State private var isSavingPhoto = false
    @State private var isSavingPlayPhoto = false
    @State private var showAnalyticsUpgradeSheet = false
    @State private var rewardedBusy = false

    private var cyan: Color { AppGlassStyle.accent }

    private func analyticsTrialEndLabel(_ date: Date) -> String {
        let d = JapaneseDateFormatters.yearMonthDay.string(from: date)
        let t = DateFormatter.localizedString(from: date, dateStyle: .none, timeStyle: .short)
        return "\(d) \(t)"
    }
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
                            Text("省エネは演出・情報の表示を抑え、画面の更新を減らします。バッテリー効果は端末・状況により限定的です。アプリを閉じる・画面を落とす方が効果が大きい場合があります。")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.65))
                            Toggle(isOn: $playDisableIdleTimerDuringPlay) {
                                Text("遊技中はスリープしない")
                                    .foregroundColor(.white.opacity(0.9))
                            }
                            .tint(cyan)
                            Text("オンにすると実戦画面を表示しているあいだ、端末の自動ロックまでの時間が経っても画面が暗くなりにくくなります。ホームや他タブに戻ると通常どおりスリープします。")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.65))
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
                                DecimalPadTextField(
                                    text: $defaultExchangeRateStr,
                                    placeholder: "4.0",
                                    maxIntegerDigits: 4,
                                    maxFractionDigits: 4,
                                    font: .preferredFont(forTextStyle: .body),
                                    textColor: UIColor.white,
                                    accentColor: UIColor(cyan)
                                )
                                    .multilineTextAlignment(.trailing)
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
                                IntegerPadTextField(
                                    text: $defaultBallsPerCashStr,
                                    placeholder: "125",
                                    maxDigits: 4,
                                    font: .preferredFont(forTextStyle: .body),
                                    textColor: UIColor.white,
                                    accentColor: UIColor(cyan)
                                )
                                    .multilineTextAlignment(.trailing)
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

                    settingsCard(title: "大当たり開始スライド", icon: "arrow.left.circle") {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("実戦画面（通常モード）下部の「スライドで大当たり」のデザインを選べます。")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.7))
                            Picker("デザイン", selection: $bigHitSlideRailStyleRaw) {
                                ForEach(BigHitSlideRailStyle.allCases) { s in
                                    Text(s.displayName).tag(s.rawValue)
                                }
                            }
                            .tint(cyan)
                            .labelsHidden()

                            Text("大当たり突入シートの「持ち玉」は入力欄1つです。最初にどちらの意味で入力するかのデフォルトです（シート内の切替でいつでも変更できます）。")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.68))
                                .padding(.top, 4)
                            Picker("持ち玉入力のデフォルト", selection: $bigHitHoldingsEntryDefaultRaw) {
                                ForEach(BigHitHoldingsEntryKind.allCases) { k in
                                    Text(k.settingsLabel).tag(k.rawValue)
                                }
                            }
                            .tint(cyan)
                        }
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

                    settingsCard(title: "ホームの情報パネル", icon: "rectangle.on.rectangle.angled") {
                        VStack(alignment: .leading, spacing: 14) {
                            Text("ホーム上部のガラスパネル表示の並びと出し分けです。広告が表示されているときは「収支」と「理論値の積み上げ」だけがパネルに出ます（バナー枠はパネル内）。広告オフ時はトグルに従い、⑥⑦は直近N日で集計します。")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.68))
                            HStack {
                                Text("直近N日（⑥⑦の集計）")
                                    .font(AppTypography.sectionSubheading)
                                    .foregroundColor(.white.opacity(0.9))
                                Spacer()
                                Picker("", selection: $homeStatsLookbackDays) {
                                    Text("7日").tag(7)
                                    Text("14日").tag(14)
                                    Text("30日").tag(30)
                                    Text("60日").tag(60)
                                    Text("90日").tag(90)
                                }
                                .labelsHidden()
                                .tint(cyan)
                            }
                            Text("表示と並び順")
                                .font(AppTypography.sectionSubheading)
                                .foregroundColor(.white.opacity(0.9))
                            ForEach(Array(panelOrderEdit.enumerated()), id: \.element) { idx, sid in
                                HStack(alignment: .center, spacing: 10) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        if let kind = HomeInfoPanelSectionID(rawValue: sid) {
                                            Text(kind.settingsLabel)
                                                .font(.subheadline)
                                                .foregroundColor(.white.opacity(0.92))
                                        }
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    Toggle(isOn: Binding(
                                        get: { !HomeInfoPanelSettings.hiddenSet(from: homeInfoPanelHiddenRaw).contains(sid) },
                                        set: { on in
                                            var h = HomeInfoPanelSettings.hiddenSet(from: homeInfoPanelHiddenRaw)
                                            if on { h.remove(sid) } else { h.insert(sid) }
                                            homeInfoPanelHiddenRaw = HomeInfoPanelSettings.persistHidden(h)
                                        }
                                    )) {
                                        EmptyView()
                                    }
                                    .labelsHidden()
                                    .tint(cyan)
                                    VStack(spacing: 2) {
                                        Button {
                                            moveHomePanelSection(from: idx, direction: -1)
                                        } label: {
                                            Image(systemName: "chevron.up")
                                                .font(.system(size: 14, weight: .semibold))
                                        }
                                        .buttonStyle(.plain)
                                        .disabled(idx == 0)
                                        Button {
                                            moveHomePanelSection(from: idx, direction: 1)
                                        } label: {
                                            Image(systemName: "chevron.down")
                                                .font(.system(size: 14, weight: .semibold))
                                        }
                                        .buttonStyle(.plain)
                                        .disabled(idx >= panelOrderEdit.count - 1)
                                    }
                                    .foregroundColor(cyan)
                                    .opacity(0.95)
                                }
                                .padding(.vertical, 4)
                            }
                        }
                        .onAppear {
                            panelOrderEdit = HomeInfoPanelSettings.normalizedOrder(from: homeInfoPanelOrderRaw)
                        }
                        .onChange(of: homeInfoPanelOrderRaw) { _, new in
                            panelOrderEdit = HomeInfoPanelSettings.normalizedOrder(from: new)
                        }
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

                    settingsCard(title: "プレミアム", icon: "cart.fill") {
                        VStack(alignment: .leading, spacing: 14) {
                            Text("月額サブスクリプションで、広告の非表示と分析機能のフル利用の両方が有効になります。解約・確認は「サブスクリプションの管理」から App Store で行えます。")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.7))
                            HStack {
                                Text("プレミアム（広告オフ・分析フル）")
                                    .font(AppTypography.sectionSubheading)
                                    .foregroundColor(.white.opacity(0.9))
                                Spacer()
                                if entitlements.hasPurchasedPremium {
                                    Text("利用中")
                                        .font(.caption)
                                        .foregroundColor(cyan)
                                } else if analyticsTrial.isTrialActive {
                                    Text("試用中")
                                        .font(.caption)
                                        .foregroundColor(cyan.opacity(0.9))
                                }
                            }
                            if !entitlements.hasPurchasedPremium {
                                if let product = entitlements.product(for: .premiumMonthly) {
                                    Button {
                                        Task { await entitlements.purchasePremium() }
                                    } label: {
                                        Text("登録する（\(product.displayPrice)）")
                                            .fontWeight(.semibold)
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 12)
                                            .foregroundColor(.black)
                                            .background(cyan)
                                            .clipShape(RoundedRectangle(cornerRadius: 10))
                                    }
                                } else {
                                    ProgressView().tint(cyan)
                                    Text("価格を読み込み中…")
                                        .font(.caption)
                                        .foregroundColor(.white.opacity(0.6))
                                }
                                Button { showAnalyticsUpgradeSheet = true } label: {
                                    Text("詳細・試用について")
                                        .fontWeight(.semibold)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 12)
                                        .foregroundColor(.black)
                                        .background(cyan.opacity(0.85))
                                        .clipShape(RoundedRectangle(cornerRadius: 10))
                                }
                                if analyticsTrial.isTrialActive, let end = analyticsTrial.trialEndDate {
                                    Text("試用期限: \(analyticsTrialEndLabel(end))")
                                        .font(.caption2)
                                        .foregroundColor(.white.opacity(0.65))
                                }
                                if analyticsTrial.canOfferRewardToday() {
                                    Button {
                                        guard !rewardedBusy else { return }
                                        rewardedBusy = true
                                        RewardedAdPresenter.presentForAnalyticsTrialReward { _ in
                                            rewardedBusy = false
                                        }
                                    } label: {
                                        HStack {
                                            if rewardedBusy {
                                                ProgressView().tint(.white)
                                            }
                                            Text("動画で24時間試す残り \(RewardedAnalyticsTrialController.maxRewardsPerCalendarDay - analyticsTrial.rewardsUsedToday) 回")
                                                .fontWeight(.medium)
                                        }
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 10)
                                        .foregroundColor(.white)
                                        .background(Color.white.opacity(0.12))
                                        .clipShape(RoundedRectangle(cornerRadius: 10))
                                    }
                                    .disabled(rewardedBusy)
                                }
                            }
                            Button {
                                Task { await entitlements.restorePurchases() }
                            } label: {
                                Text("購入を復元")
                                    .font(.subheadline)
                                    .foregroundColor(cyan)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            Button {
                                entitlements.openManageSubscriptions()
                            } label: {
                                Text("サブスクリプションの管理（解約・プラン変更）")
                                    .font(.subheadline)
                                    .foregroundColor(cyan)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            if let err = entitlements.purchasesErrorMessage {
                                Text(err)
                                    .font(.caption)
                                    .foregroundColor(.orange)
                            }
                            #if DEBUG
                            VStack(alignment: .leading, spacing: 10) {
                                Divider()
                                    .background(Color.white.opacity(0.18))
                                HStack(spacing: 6) {
                                    Image(systemName: "ladybug.fill")
                                        .foregroundColor(cyan)
                                    Text("開発者向け（デバッグ版でのみ表示）")
                                        .font(.caption.weight(.semibold))
                                        .foregroundColor(cyan.opacity(0.95))
                                }
                                Toggle(isOn: $entitlements.debugFullAccess) {
                                    Text("フルアクセスをシミュレート（広告オフ・分析フル解放）")
                                        .font(.subheadline)
                                        .foregroundColor(.white.opacity(0.9))
                                }
                                .tint(cyan)
                                Text("Xcode で「Debug」構成から実行したアプリだけに出ます。TestFlight や App Store 版には含まれません。")
                                    .font(.caption2)
                                    .foregroundColor(.white.opacity(0.62))
                            }
                            .padding(.top, 4)
                            #endif
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
        .sheet(isPresented: $showAnalyticsUpgradeSheet) {
            AnalyticsUpgradeSheet()
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { Color.clear.frame(height: 84) }
    }

    private func moveHomePanelSection(from index: Int, direction: Int) {
        let j = index + direction
        guard panelOrderEdit.indices.contains(j) else { return }
        panelOrderEdit.swapAt(index, j)
        homeInfoPanelOrderRaw = panelOrderEdit.map(String.init).joined(separator: ",")
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


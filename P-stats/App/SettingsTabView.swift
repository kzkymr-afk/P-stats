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
    #if DEBUG
    @ObservedObject private var devEntitlementDebug = DeveloperEntitlementDebugSettings.shared
    #endif
    @EnvironmentObject private var themeManager: ThemeManager
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Machine.name) private var machines: [Machine]
    @Query(sort: \Shop.name) private var shops: [Shop]
    @Query(sort: \GameSession.date, order: .reverse) private var allSessions: [GameSession]
    @Query(sort: \MyMachinePreset.name) private var myMachinePresets: [MyMachinePreset]
    @Query(sort: \PrizeSet.displayOrder) private var prizeSets: [PrizeSet]

    @AppStorage("homeBackgroundStyle") private var homeBackgroundStyle = HomeBackgroundStore.defaultStyle
    @AppStorage("homeBackgroundImagePath") private var homeBackgroundImagePath = ""
    @AppStorage("playViewBackgroundStyle") private var playViewBackgroundStyle = "sameAsHome"
    @AppStorage("playViewBackgroundImagePath") private var playViewBackgroundImagePath = ""
    // 旧キー（true ならプロモード相当として移行）
    @AppStorage("playViewStartWithPowerSaving") private var playViewStartWithPowerSavingLegacy = false
    /// "normal" / "pro"
    @AppStorage("playStartMode") private var playStartModeRaw: String = "normal"
    /// 実戦画面表示中は自動スリープ（画面オフ）を無効化
    @AppStorage("playDisableIdleTimerDuringPlay") private var playDisableIdleTimerDuringPlay = true
    /// 遊技中の時給の基準（実収支の損益 vs 期待値理論）
    @AppStorage(PlayInfoPanelSettings.hourlyWageBasisKey) private var playHourlyWageBasisRaw: String = PlayHourlyWageBasis.actual.rawValue
    @AppStorage("initialHoldingsGatePolicy") private var initialHoldingsGatePolicyRaw: String = InitialHoldingsGatePolicy.manual.rawValue
    @AppStorage("hapticEnabled") private var hapticEnabled = true
    @AppStorage("defaultExchangeRate") private var defaultExchangeRateStr = "4.0"  // 払出係数（pt/玉）文字列
    @AppStorage(UnitDisplaySettings.unitSuffixKey) private var unitDisplaySuffix: String = "pt"
    @AppStorage("defaultBallsPerCash") private var defaultBallsPerCashStr = "125"
    @AppStorage("defaultMachineName") private var defaultMachineName = ""
    @AppStorage("defaultShopName") private var defaultShopName = ""
    @AppStorage("alwaysShowBothInvestmentButtons") private var alwaysShowBothInvestmentButtons = true
    @AppStorage("bigHitHoldingsEntryDefault") private var bigHitHoldingsEntryDefaultRaw = BigHitHoldingsEntryKind.appStorageDefaultRawValue
    @AppStorage("homeInfoPanelOrder") private var homeInfoPanelOrderRaw = HomeInfoPanelSettings.defaultOrderCSV
    @AppStorage("homeInfoPanelHidden") private var homeInfoPanelHiddenRaw = ""
    @AppStorage("homeStatsLookbackDays") private var homeStatsLookbackDays = 30
    @AppStorage(PlayInfoPanelSettings.orderKey) private var playInfoPanelOrderRaw: String = PlayInfoPanelSettings.defaultOrderCSV
    @AppStorage(PlayInfoPanelSettings.hiddenKey) private var playInfoPanelHiddenRaw: String = ""
    @State private var panelOrderEdit: [Int] = []
    @State private var playInfoOrderEdit: [PlayInfoPanelRowID] = []
    /// 実戦パネルで 6 個目をオンにしようとした行（この直下に赤字メッセージを出す）
    @State private var playInfoPanelLimitErrorRowIndex: Int? = nil
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var selectedPlayPhotoItem: PhotosPickerItem?
    @State private var isSavingPhoto = false
    @State private var isSavingPlayPhoto = false
    @State private var showAnalyticsUpgradeSheet = false
    @State private var rewardedBusy = false
    @State private var csvExportPackage: CsvExportSheetPackage?
    @State private var csvPendingCleanupURLs: [URL]?
    @State private var csvExportErrorMessage: String?
    @State private var showCsvImportSheet = false

    private var cyan: Color { themeManager.currentTheme.accentColor }

    @ViewBuilder
    private func sectionHeader(_ title: String) -> some View {
        let skin = themeManager.currentTheme
        HStack {
            Text(title)
                .font(AppTypography.annotationSemibold)
                .foregroundColor(skin.subTextColor.opacity(0.92))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(skin.surfaceSecondary, in: Capsule())
            Spacer()
        }
        .padding(.top, 6)
    }

    private func analyticsTrialEndLabel(_ date: Date) -> String {
        let d = JapaneseDateFormatters.yearMonthDay.string(from: date)
        let t = DateFormatter.localizedString(from: date, dateStyle: .none, timeStyle: .short)
        return "\(d) \(t)"
    }
    private var defaultExchangeRate: Double { Double(defaultExchangeRateStr) ?? 4.0 }
    private var defaultBallsPerCash: Int { Int(defaultBallsPerCashStr) ?? 125 }

    /// CSV バックアップは課金済みプレミアムのみ（試用・リワード試用は対象外）
    private var canExportCsvBackup: Bool { entitlements.hasPurchasedPremium }
    private var canImportCsvSessions: Bool { entitlements.hasPurchasedPremium }

    var body: some View {
        ZStack {
            StaticHomeBackgroundView()
            ScrollView(showsIndicators: false) {
                    VStack(spacing: 16) {
                    sectionHeader("基本操作")
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
                            Picker("新規遊技開始時の持ち玉の初期表示", selection: $initialHoldingsGatePolicyRaw) {
                                ForEach(InitialHoldingsGatePolicy.allCases) { p in
                                    Text(p.settingsTitle).tag(p.rawValue)
                                }
                            }
                            .tint(cyan)
                            Text("・手入力：毎回空欄から（貯玉を使わない・同日に台移動して持ち玉だけ持ち込む等）\n・常に0：貯玉に頼らず毎回ゼロから\n・貯玉残高に合わせる：店舗マスタの貯玉が1玉以上ならその数を入れる（0なら0）。貯玉サービスで残高をアプリに合わせている場合向け")
                                .font(AppTypography.annotation)
                                .foregroundColor(.white.opacity(0.68))
                                .fixedSize(horizontal: false, vertical: true)
                            Toggle(isOn: $alwaysShowBothInvestmentButtons) {
                                Text("常に現金投資・持ち玉投資両方を表示")
                                    .foregroundColor(.white.opacity(0.9))
                            }
                            .tint(cyan)
                            Text("オフの場合、持ち玉0のときは現金投資のみ、持ち玉があるときは持ち玉投資のみを表示します（ボタンは2つ分の大きさ）。")
                                .font(AppTypography.annotation)
                                .foregroundColor(.white.opacity(0.7))
                        }
                    }

                    sectionHeader("遊技中設定")
                    // 3. 遊技開始時の初期画面（通常／プロ）
                    settingsCard(title: "遊技開始時の初期画面", icon: "speedometer") {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("遊技開始後、最初に表示する画面を選べます。")
                                .font(AppTypography.annotation)
                                .foregroundColor(.white.opacity(0.7))
                            Picker("", selection: $playStartModeRaw) {
                                Text("通常モード").tag("normal")
                                Text("プロモード").tag("pro")
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                            Text("プロモードは「期待値と時給だけ見たい」「片手で最短入力したい」人向けのミニマルUIです。")
                                .font(AppTypography.annotation)
                                .foregroundColor(.white.opacity(0.65))
                            VStack(alignment: .leading, spacing: 8) {
                                Text("遊技中の時給の基準")
                                    .font(AppTypography.sectionSubheading)
                                    .foregroundColor(.white.opacity(0.9))
                                Picker("", selection: $playHourlyWageBasisRaw) {
                                    Text("実収支（現在損益）").tag(PlayHourlyWageBasis.actual.rawValue)
                                    Text("期待値（理論）").tag(PlayHourlyWageBasis.expected.rawValue)
                                }
                                .pickerStyle(.segmented)
                                .labelsHidden()
                                Text("「実収支」は現在損益÷経過時間。「期待値」は実費×(期待値比−1)÷経過時間（ボーダーが取れているときのみ）。")
                                    .font(AppTypography.annotation)
                                    .foregroundColor(.white.opacity(0.65))
                            }
                            Toggle(isOn: $playDisableIdleTimerDuringPlay) {
                                Text("遊技中はスリープしない")
                                    .foregroundColor(.white.opacity(0.9))
                            }
                            .tint(cyan)
                            Text("オンにすると実戦画面を表示しているあいだ、端末の自動ロックまでの時間が経っても画面が暗くなりにくくなります。ホームや他タブに戻ると通常どおりスリープします。")
                                .font(AppTypography.annotation)
                                .foregroundColor(.white.opacity(0.65))
                        }
                        .onAppear {
                            // 初回/旧キーからの移行：未設定や不正値は旧キーを優先
                            if playStartModeRaw != "normal" && playStartModeRaw != "pro" {
                                playStartModeRaw = playViewStartWithPowerSavingLegacy ? "pro" : "normal"
                            }
                        }
                        .onChange(of: playStartModeRaw) { _, newValue in
                            // 旧キーも合わせて更新しておく（互換用）
                            playViewStartWithPowerSavingLegacy = (newValue == "pro")
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
                                    .background(themeManager.currentTheme.inputFieldBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
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
                                    .background(themeManager.currentTheme.inputFieldBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
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

                    settingsCard(title: "大当たり開始（スライド）", icon: "arrow.left.circle") {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("大当たり突入シートの「持ち玉」は入力欄1つです。セグメントの左が「当選時点の残り持ち玉」、右が「当選までの投資（玉）」です。最初にどちらを意味するかのデフォルトを選べます（シート内の切替でいつでも変更できます）。")
                                .font(AppTypography.annotation)
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

                    settingsCard(title: "実戦の情報パネル", icon: "list.bullet.rectangle") {
                        VStack(alignment: .leading, spacing: 14) {
                            Text("実戦画面に出す情報（最大5行）を、表示/並び替えできます。オンにできる項目は5個までです。")
                                .font(AppTypography.annotation)
                                .foregroundColor(.white.opacity(0.68))
                            ForEach(0..<playInfoOrderEdit.count, id: \.self) { idx in
                                let rid = playInfoOrderEdit[idx]
                                if PlayInfoPanelSettings.settingsPrimaryRowIDs.contains(rid) {
                                    playInfoPanelSettingsRow(index: idx, rid: rid)
                                }
                            }

                            Text("ほかに選べる項目")
                                .font(AppTypography.sectionSubheading)
                                .foregroundColor(.white.opacity(0.88))
                                .padding(.top, 4)
                            ForEach(0..<playInfoOrderEdit.count, id: \.self) { idx in
                                let rid = playInfoOrderEdit[idx]
                                if PlayInfoPanelSettings.settingsAlternateRowIDs.contains(rid) {
                                    playInfoPanelSettingsRow(index: idx, rid: rid)
                                }
                            }

                            Text("その他")
                                .font(AppTypography.sectionSubheading)
                                .foregroundColor(.white.opacity(0.88))
                                .padding(.top, 4)
                            ForEach(0..<playInfoOrderEdit.count, id: \.self) { idx in
                                let rid = playInfoOrderEdit[idx]
                                if !PlayInfoPanelSettings.settingsPrimaryRowIDs.contains(rid),
                                   !PlayInfoPanelSettings.settingsAlternateRowIDs.contains(rid) {
                                    playInfoPanelSettingsRow(index: idx, rid: rid)
                                }
                            }

                            Text("※非表示が多い場合でも、実戦画面では上から最大5行まで表示します。")
                                .font(AppTypography.annotationSmall)
                                .foregroundColor(.white.opacity(0.58))
                        }
                        .onAppear {
                            playInfoOrderEdit = PlayInfoPanelSettings.normalizedOrder(from: playInfoPanelOrderRaw)
                            clampPlayInfoPanelVisibleToMaxFive()
                        }
                        .onChange(of: playInfoPanelOrderRaw) { _, new in
                            playInfoOrderEdit = PlayInfoPanelSettings.normalizedOrder(from: new)
                        }
                    }

                    sectionHeader("表示・デザイン")
                    settingsCard(title: "単位の設定", icon: "textformat.123") {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("アプリ内の表示上の「pt」の単位ラベルを変更できます（内部の計算・保存値は変わりません）。")
                                .font(AppTypography.annotation)
                                .foregroundColor(.white.opacity(0.68))
                            HStack(spacing: 10) {
                                Text("単位ラベル")
                                    .font(AppTypography.sectionSubheading)
                                    .foregroundColor(.white.opacity(0.9))
                                Spacer()
                                TextField("pt", text: $unitDisplaySuffix)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                                    .multilineTextAlignment(.trailing)
                                    .foregroundColor(.white.opacity(0.95))
                                    .frame(width: 160)
                            }
                            Text("例: pt / ポイント / p / 単位（空欄で単位なし）")
                                .font(AppTypography.annotationSmall)
                                .foregroundColor(.white.opacity(0.62))
                        }
                    }

                    settingsCard(title: "ホームの情報パネル", icon: "rectangle.on.rectangle.angled") {
                        VStack(alignment: .leading, spacing: 14) {
                            Text("ホーム上部のガラスパネル表示の並びと出し分けです。広告が表示されているときは「収支」と「期待値の積み上げ」だけがパネルに出ます（バナー枠はパネル内）。広告オフ時はトグルに従い、⑥⑦は直近N日で集計します。")
                                .font(AppTypography.annotation)
                                .foregroundColor(.white.opacity(0.68))
                            if !entitlements.hasPurchasedPremium {
                                Text("プレミアム未購入のときは、①収支・②期待値の積み上げ以外は鍵のためトグルと並び替えができません。")
                                    .font(AppTypography.annotation)
                                    .foregroundColor(.white.opacity(0.62))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
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
                                let homeRowLocked = homePanelSectionLocked(sid: sid)
                                HStack(alignment: .center, spacing: 10) {
                                    if homeRowLocked {
                                        Image(systemName: "lock.fill")
                                            .font(.system(size: 14, weight: .semibold))
                                            .foregroundColor(.white.opacity(0.45))
                                            .frame(width: 18)
                                    } else {
                                        Color.clear.frame(width: 18)
                                    }
                                    VStack(alignment: .leading, spacing: 2) {
                                        if let kind = HomeInfoPanelSectionID(rawValue: sid) {
                                            Text(kind.settingsLabel)
                                                .font(.subheadline)
                                                .foregroundColor(.white.opacity(homeRowLocked ? 0.55 : 0.92))
                                        }
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    Toggle(isOn: Binding(
                                        get: { !HomeInfoPanelSettings.hiddenSet(from: homeInfoPanelHiddenRaw).contains(sid) },
                                        set: { on in
                                            guard !homeRowLocked else { return }
                                            var h = HomeInfoPanelSettings.hiddenSet(from: homeInfoPanelHiddenRaw)
                                            if on { h.remove(sid) } else { h.insert(sid) }
                                            homeInfoPanelHiddenRaw = HomeInfoPanelSettings.persistHidden(h)
                                        }
                                    )) {
                                        EmptyView()
                                    }
                                    .labelsHidden()
                                    .tint(cyan)
                                    .disabled(homeRowLocked)
                                    VStack(spacing: 2) {
                                        Button {
                                            moveHomePanelSection(from: idx, direction: -1)
                                        } label: {
                                            Image(systemName: "chevron.up")
                                                .font(.system(size: 14, weight: .semibold))
                                        }
                                        .buttonStyle(.plain)
                                        .disabled(homeRowLocked || idx == 0)
                                        Button {
                                            moveHomePanelSection(from: idx, direction: 1)
                                        } label: {
                                            Image(systemName: "chevron.down")
                                                .font(.system(size: 14, weight: .semibold))
                                        }
                                        .buttonStyle(.plain)
                                        .disabled(homeRowLocked || idx >= panelOrderEdit.count - 1)
                                    }
                                    .foregroundColor(cyan)
                                    .opacity(homeRowLocked ? 0.35 : 0.95)
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
                                                    .font(AppTypography.annotation)
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
                                                .font(AppTypography.annotation)
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
                                            Text("保存中…").font(AppTypography.annotation).foregroundColor(.white.opacity(0.7))
                                        }
                                        .frame(maxWidth: .infinity)
                                    }
                                }
                            }
                        }
                    }

                    sectionHeader("プレミアム")
                    settingsCard(title: "プレミアム", icon: "cart.fill") {
                        VStack(alignment: .leading, spacing: 14) {
                            Text("無料版では、データ分析機能に制限があります。\nプレミアムに登録すると、広告が非表示になり、全ての分析機能が解放されます。")
                                .font(AppTypography.annotation)
                                .foregroundColor(.white.opacity(0.7))
                            HStack {
                                Text("プレミアム（広告オフ・分析フル）")
                                    .font(AppTypography.sectionSubheading)
                                    .foregroundColor(.white.opacity(0.9))
                                Spacer()
                                if entitlements.hasPurchasedPremium {
                                    Text("利用中")
                                        .font(AppTypography.annotation)
                                        .foregroundColor(cyan)
                                } else if entitlements.isRewardTrialActiveForDisplay {
                                    Text("試用中")
                                        .font(AppTypography.annotation)
                                        .foregroundColor(cyan.opacity(0.9))
                                }
                            }
                            if !entitlements.hasPurchasedPremium {
                                if let product = entitlements.product(for: .premiumMonthly) {
                                    Button {
                                        Task { await entitlements.purchasePremium() }
                                    } label: {
                                        Text("登録する（\(product.displayPriceJapanese)）")
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
                                        .font(AppTypography.annotation)
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
                                if entitlements.isRewardTrialActiveForDisplay, let end = entitlements.rewardTrialEndDateForDisplay {
                                    Text("試用期限: \(analyticsTrialEndLabel(end))")
                                        .font(AppTypography.annotationSmall)
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
                                            Text(RewardedAnalyticsTrialController.videoRewardUnlockButtonTitle(remainingToday: analyticsTrial.remainingRewardOffersToday))
                                                .fontWeight(.medium)
                                        }
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 10)
                                        .foregroundColor(.white)
                                        .background(themeManager.currentTheme.panelSecondaryBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
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
                            Text("次に表示される画面は iOS の言語設定により英語になることがあります。解約やプラン変更はその画面で行えます。")
                                .font(AppTypography.annotationSmall)
                                .foregroundColor(.white.opacity(0.55))
                            if let err = entitlements.purchasesErrorMessage {
                                Text(err)
                                    .font(AppTypography.annotation)
                                    .foregroundColor(.orange)
                            }
                            #if DEBUG
                            VStack(alignment: .leading, spacing: 12) {
                                Divider()
                                    .background(themeManager.currentTheme.hairlineDividerColor)
                                HStack(spacing: 6) {
                                    Image(systemName: "ladybug.fill")
                                        .foregroundColor(cyan)
                                    Text("開発者向け（デバッグ版でのみ表示）")
                                        .font(AppTypography.annotationSemibold)
                                        .foregroundColor(cyan.opacity(0.95))
                                }
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("プレミアム（ストアの状態）")
                                        .font(AppTypography.annotationSmall)
                                        .foregroundColor(.white.opacity(0.65))
                                    Picker("", selection: $devEntitlementDebug.premiumMode) {
                                        ForEach(DebugPremiumEntitlementMode.allCases) { mode in
                                            Text(mode.label).tag(mode)
                                        }
                                    }
                                    .pickerStyle(.menu)
                                    .tint(cyan)
                                }
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("リワード試用の表示・権限")
                                        .font(AppTypography.annotationSmall)
                                        .foregroundColor(.white.opacity(0.65))
                                    Picker("", selection: $devEntitlementDebug.rewardTrialMode) {
                                        ForEach(DebugRewardTrialMode.allCases) { mode in
                                            Text(mode.label).tag(mode)
                                        }
                                    }
                                    .pickerStyle(.menu)
                                    .tint(cyan)
                                }
                                Text("Xcode の Debug 構成でのみ表示。TestFlight / App Store 版には含まれません。ストアの実購入とは独立して UI と広告・分析のガードを切り替えられます。")
                                    .font(AppTypography.annotationSmall)
                                    .foregroundColor(.white.opacity(0.62))
                            }
                            .padding(.top, 4)
                            #endif
                        }
                    }

                    sectionHeader("データ")
                    // 8b. データのバックアップ（プレミアム）
                    settingsCard(title: "データのバックアップ", icon: "doc.plaintext") {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("実戦履歴・登録機種・店舗・マイ機種プリセット・ボーナス種ライブラリを UTF-8（BOM 付き）の CSV に分割して書き出します。Numbers や Excel で開けます。")
                                .font(AppTypography.annotation)
                                .foregroundColor(.white.opacity(0.72))
                            if canExportCsvBackup {
                                Text("実戦 \(allSessions.count) 件 ／ 機種 \(machines.count) 件 ／ 店舗 \(shops.count) 件")
                                    .font(AppTypography.annotation)
                                    .foregroundColor(.white.opacity(0.6))
                                Button {
                                    do {
                                        let urls = try CsvBackupExportService.makeExportFileURLs(
                                            sessions: allSessions,
                                            machines: machines,
                                            shops: shops,
                                            myPresets: myMachinePresets,
                                            prizeSets: prizeSets
                                        )
                                        csvPendingCleanupURLs = urls
                                        csvExportPackage = CsvExportSheetPackage(urls: urls)
                                    } catch {
                                        csvExportErrorMessage = error.localizedDescription
                                    }
                                } label: {
                                    Label("CSV を書き出す（共有）", systemImage: "square.and.arrow.up")
                                        .fontWeight(.semibold)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 12)
                                        .foregroundColor(.black)
                                        .background(cyan)
                                        .clipShape(RoundedRectangle(cornerRadius: 10))
                                }
                                .buttonStyle(.plain)
                            } else {
                                Text("この機能はプレミアム（有料登録）のみ利用できます。試用中・動画試用では書き出しできません。")
                                    .font(AppTypography.annotation)
                                    .foregroundColor(.white.opacity(0.68))
                                Button {
                                    showAnalyticsUpgradeSheet = true
                                } label: {
                                    Text("プレミアムについて見る")
                                        .fontWeight(.semibold)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 12)
                                        .foregroundColor(.white)
                                        .background(themeManager.currentTheme.panelSecondaryBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                }
                                .buttonStyle(.plain)
                            }
                            Divider().background(themeManager.currentTheme.hairlineDividerColor)
                            Text("書き出した「sessions」CSV や、指定の列だけ揃えた表から実戦履歴を追加できます。機種・店舗名は表記が違っても、取り込み画面で登録済みの機種・店舗に紐づけられます。列が足りない行は帳簿向け（回転・期待値の集計から外れる保存）になります。")
                                .font(AppTypography.annotation)
                                .foregroundColor(.white.opacity(0.68))
                            if canImportCsvSessions {
                                Button {
                                    showCsvImportSheet = true
                                } label: {
                                    Label("CSV から実戦を取り込む", systemImage: "square.and.arrow.down")
                                        .fontWeight(.semibold)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 12)
                                        .foregroundColor(.black)
                                        .background(cyan.opacity(0.92))
                                        .clipShape(RoundedRectangle(cornerRadius: 10))
                                }
                                .buttonStyle(.plain)
                            } else {
                                Text("取り込みもプレミアム（有料登録）のみです。")
                                    .font(AppTypography.annotationSmall)
                                    .foregroundColor(.white.opacity(0.55))
                            }
                        }
                    }

                    sectionHeader("その他")
                    // 9. このアプリの情報
                    settingsCard(title: "このアプリの情報", icon: "info.circle.fill") {
                        VStack(alignment: .leading, spacing: 12) {
                            NavigationLink {
                                HelpManualView()
                            } label: {
                                HStack {
                                    Image(systemName: "questionmark.circle.fill")
                                        .foregroundColor(cyan)
                                    Text("マニュアル")
                                        .foregroundColor(cyan)
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(AppTypography.annotation)
                                        .foregroundColor(cyan.opacity(0.8))
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                            }
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
        .onAppear {
            InitialHoldingsGatePolicy.migrateFromLegacyIfNeeded()
        }
        .keyboardDismissToolbar()
        .toolbarColorScheme(.dark, for: .navigationBar)
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showAnalyticsUpgradeSheet) {
            AnalyticsUpgradeSheet()
        }
        .sheet(isPresented: $showCsvImportSheet) {
            NavigationStack {
                CsvSessionImportSheetView()
            }
        }
        .sheet(item: $csvExportPackage, onDismiss: {
            if let u = csvPendingCleanupURLs {
                CsvBackupExportService.removeTemporaryFiles(at: u)
                csvPendingCleanupURLs = nil
            }
        }) { pkg in
            CsvBackupShareView(fileURLs: pkg.urls) {
                csvPendingCleanupURLs = nil
                csvExportPackage = nil
            }
        }
        .alert("CSV の書き出しに失敗しました", isPresented: Binding(
            get: { csvExportErrorMessage != nil },
            set: { if !$0 { csvExportErrorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { csvExportErrorMessage = nil }
        } message: {
            Text(csvExportErrorMessage ?? "")
        }
        .alert("購入完了", isPresented: Binding(
            get: { entitlements.purchaseSuccessNotice != nil },
            set: { if !$0 { entitlements.acknowledgePurchaseSuccessNotice() } }
        )) {
            Button("OK") { entitlements.acknowledgePurchaseSuccessNotice() }
        } message: {
            Text(entitlements.purchaseSuccessNotice ?? "")
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { Color.clear.frame(height: 84) }
    }

    private func moveHomePanelSection(from index: Int, direction: Int) {
        let j = index + direction
        guard panelOrderEdit.indices.contains(j) else { return }
        let a = panelOrderEdit[index]
        let b = panelOrderEdit[j]
        if homePanelSectionLocked(sid: a) || homePanelSectionLocked(sid: b) { return }
        panelOrderEdit.swapAt(index, j)
        homeInfoPanelOrderRaw = panelOrderEdit.map(String.init).joined(separator: ",")
    }

    private func movePlayInfoRow(from index: Int, direction: Int) {
        let j = index + direction
        guard playInfoOrderEdit.indices.contains(j) else { return }
        playInfoOrderEdit.swapAt(index, j)
        playInfoPanelOrderRaw = playInfoOrderEdit.map { String($0.rawValue) }.joined(separator: ",")
        playInfoPanelLimitErrorRowIndex = nil
    }

    /// 未課金時は ③〜⑦（初当たり平均〜回転率Top3）をロック
    private func homePanelSectionLocked(sid: Int) -> Bool {
        guard !entitlements.hasPurchasedPremium else { return false }
        guard let k = HomeInfoPanelSectionID(rawValue: sid) else { return true }
        switch k {
        case .balance, .theoretical: return false
        case .firstHitAvg, .last7Streak, .miniTrend, .affinityTop3, .rotationTop3: return true
        }
    }

    /// 表示オンが 6 個以上ある状態を、並びの先頭から 5 個までに収める（既存データの矯正）
    private func clampPlayInfoPanelVisibleToMaxFive() {
        var h = PlayInfoPanelSettings.hiddenSet(from: playInfoPanelHiddenRaw)
        var visibleCount = 0
        for rid in playInfoOrderEdit {
            if !h.contains(rid.rawValue) {
                visibleCount += 1
                if visibleCount > 5 {
                    h.insert(rid.rawValue)
                }
            }
        }
        playInfoPanelHiddenRaw = PlayInfoPanelSettings.persistHidden(h)
    }

    private func playInfoToggleBinding(rid: PlayInfoPanelRowID, rowIndex idx: Int) -> Binding<Bool> {
        Binding(
            get: { !PlayInfoPanelSettings.hiddenSet(from: playInfoPanelHiddenRaw).contains(rid.rawValue) },
            set: { on in
                var h = PlayInfoPanelSettings.hiddenSet(from: playInfoPanelHiddenRaw)
                if on {
                    if h.contains(rid.rawValue) {
                        let visibleCount = playInfoOrderEdit.filter { !h.contains($0.rawValue) }.count
                        if visibleCount >= 5 {
                            playInfoPanelLimitErrorRowIndex = idx
                            return
                        }
                        h.remove(rid.rawValue)
                    }
                    playInfoPanelLimitErrorRowIndex = nil
                } else {
                    h.insert(rid.rawValue)
                    playInfoPanelLimitErrorRowIndex = nil
                }
                playInfoPanelHiddenRaw = PlayInfoPanelSettings.persistHidden(h)
            }
        )
    }

    @ViewBuilder
    private func playInfoPanelSettingsRow(index idx: Int, rid: PlayInfoPanelRowID) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .center, spacing: 10) {
                Text(rid.settingsLabel(unitSuffix: unitDisplaySuffix))
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.92))
                    .frame(maxWidth: .infinity, alignment: .leading)

                Toggle(isOn: playInfoToggleBinding(rid: rid, rowIndex: idx)) { EmptyView() }
                    .labelsHidden()
                    .tint(cyan)

                VStack(spacing: 2) {
                    Button {
                        movePlayInfoRow(from: idx, direction: -1)
                    } label: {
                        Image(systemName: "chevron.up")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                    .disabled(idx == 0)

                    Button {
                        movePlayInfoRow(from: idx, direction: 1)
                    } label: {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                    .disabled(idx >= playInfoOrderEdit.count - 1)
                }
                .foregroundColor(cyan)
                .opacity(0.95)
            }
            .padding(.vertical, 4)
            if playInfoPanelLimitErrorRowIndex == idx {
                Text("５個までしか選択できません。")
                    .font(AppTypography.annotation)
                    .foregroundColor(.red)
            }
        }
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
        .pstatsPanelStyle()
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

private struct CsvExportSheetPackage: Identifiable {
    let id = UUID()
    let urls: [URL]
}

import SwiftUI
import SwiftData
import WebKit

/// プリセット一覧の1件（サーバー取得 / CloudKitユーザー共有 / アプリ内）
enum PresetItem: Identifiable {
    case server(PresetFromServer)
    case cloudShared(SharedMachineFromCloud)
    case local(PresetMachine)

    var id: String {
        switch self {
        case .server(let s):
            let mid = (s.machineId ?? "").trimmingCharacters(in: .whitespaces)
            return mid.isEmpty ? "s-\(s.name)-\(s.probability ?? "")-\(s.manufacturer ?? "")" : "s-\(mid)"
        case .cloudShared(let c): return "c-\(c.id)"
        case .local(let m): return "l-\(m.persistentModelID.hashValue)"
        }
    }
    var displayName: String {
        switch self {
        case .server(let s): return s.name
        case .cloudShared(let c): return c.name
        case .local(let m): return m.name
        }
    }
    var displaySubtitle: String {
        switch self {
        case .server(let s):
            let type = MachineType(rawValue: s.machineTypeRaw ?? "") ?? .kakugen
            let avg = PresetService.averageNetPerRound(s)
            return "\(type.displayName) / 確率 \(s.probability ?? "") / 1R純増 \(String(format: "%.0f", avg))"
        case .cloudShared(let c):
            let type = MachineType(rawValue: c.machineTypeRaw ?? "") ?? .kakugen
            let avg = PresetService.averageNetPerRound(c.asPresetFromServer)
            return "ユーザー共有・\(type.displayName) / 確率 \(c.probability ?? "") / 1R純増 \(String(format: "%.0f", avg))"
        case .local(let m):
            return "\(m.machineType.displayName) / 確率 \(m.probability) / 1R純増 \(String(format: "%.0f", m.averageNetPerRound))"
        }
    }
}

/// 機種の新規登録または編集。確率は数値ボタン+自由入力、ボーナス種類はライブラリから選択可能。
struct MachineEditView: View, Equatable {
    /// 編集時は既存の機種を渡す。nil のときは新規登録。
    var editing: Machine? = nil

    static func == (lhs: MachineEditView, rhs: MachineEditView) -> Bool {
        lhs.editing?.persistentModelID == rhs.editing?.persistentModelID
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \PresetMachine.name) private var allPresets: [PresetMachine]
    @State private var machineName: String = ""
    @State private var selectedMachineType: MachineType = .kakugen
    @State private var supportLimit: String = "0"
    @State private var timeShortRotations: String = "0"
    @State private var defaultPrize: String = "1500"
    @State private var probability: String = ""
    @State private var border: String = ""
    @State private var countPerRoundStr: String = "10"
    @State private var manufacturerStr: String = ""
    @State private var dmmMachineID: String = ""
    
    @State private var showErrorAlert = false
    @State private var errorMessage = ""

    /// ヘソ当たり1〜5（出玉/RUSH(0or1)/時短）。マスタ書式。
    @State private var draftHesoAtari: [HesoAtariItem] = []
    /// 電チュー（RUSH時）の大当たり種類。hasLT のときは draftRushPrizes / draftLtPrizes を使う
    @State private var draftDenchuPrizes: [DraftPrize] = []
    /// LTあり機種のとき true。RUSH と LT パネルを分けて表示する
    @State private var hasLT = false
    /// hasLT のときの RUSH 用
    @State private var draftRushPrizes: [DraftPrize] = []
    /// hasLT のときの LT 用
    @State private var draftLtPrizes: [DraftPrize] = []

    /// この機種データをCloudKitでみんなとシェアする（保存時のみ送信）
    @State private var shareWithEveryone = false
    /// 通常時（ヘソ）からいきなりLTに突入できる機種か
    @State private var ltFromNormal = false

    @State private var presetSearchText: String = ""
    /// true のとき「新台から探す」で最新20件を表示するモード
    @State private var showNewest20 = false
    /// マスタ一覧は参照用ホルダーで保持（Task.detached にコピーせず渡してメインスレッドをブロックしない）
    @State private var serverPresetsHolder: PresetListHolder?
    @State private var isLoadingPresets = false
    /// マスタ検索の表示用（バックグラウンドでフィルタ＋導入日順ソートした結果）
    @State private var displayPresetsCache: [PresetItem] = []
    /// `index.json` 取得結果（スペック完了フィルタ用）。取得失敗時は `loadedOK == false`。
    @State private var registrationIndexEntries: [MachineMasterIndexEntry] = []
    @State private var registrationIndexLoadedOK = false
    @AppStorage("machineMasterDataURL") private var machineMasterDataURL: String = ""
    /// 遊技画面と同じ。`index.json` の取得元（空なら `PresetServiceConfig.defaultMachineDetailBaseURL`）。
    @AppStorage("machineDetailBaseURL") private var machineDetailBaseURL: String = ""
    @AppStorage("machineMasterListURL") private var machineMasterListURL: String = ""
    @State private var machineMasterItems: [MachineMasterItem] = []
    @State private var showMasterPicker = false
    @State private var masterSearchText: String = ""
    /// マスター由来の導入開始日（表示のみ）
    @State private var introductionDateDisplay: String = ""
    
    @State private var isDMMPanelExpanded = false
    /// 機種を検索で選んだプリセットの id（選択中をハイライトする用）
    @State private var selectedPresetId: String? = nil
    @FocusState private var isPresetSearchFocused: Bool

    private struct DraftPrize: Identifiable {
        let id = UUID()
        var label: String
        var balls: Int
    }

    private var accent: Color { AppGlassStyle.accent }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ZStack {
                    AppGlassStyle.background.ignoresSafeArea()
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 16) {
                            presetPanel
                            editPanel(title: "機種概要") { machineOverviewPanel }
                            editPanel(title: "公式ボーダー（等価ベース）") { borderPanelWithDmmLink }
                            editPanel(title: "データの共有") {
                                Toggle("この機種データをみんなとシェアする", isOn: $shareWithEveryone)
                                    .tint(accent)
                                Text("ONにすると、他のユーザーがマスタから検索したときにあなたの機種データ（1R純増など）を参照できます。")
                                    .font(.caption)
                                    .foregroundStyle(.white.opacity(0.7))
                            }
                        }
                        .padding(16)
                        .padding(.bottom, 100)
                    }
                    .opacity(isDMMPanelExpanded ? 0 : 1)
                    .allowsHitTesting(!isDMMPanelExpanded)
                    .animation(isDMMPanelExpanded ? nil : .easeInOut(duration: 0.25), value: isDMMPanelExpanded)

                    if let url = dmmMachineURL {
                        InAppWebView(url: url)
                            .id(url.absoluteString)
                            .background(AppGlassStyle.background)
                            .opacity(isDMMPanelExpanded ? 1 : 0)
                            .allowsHitTesting(isDMMPanelExpanded)
                            .animation(isDMMPanelExpanded ? nil : .easeInOut(duration: 0.25), value: isDMMPanelExpanded)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .animation(isDMMPanelExpanded ? nil : .spring(response: 0.35, dampingFraction: 0.82), value: isDMMPanelExpanded)

                dmmSwipeBar
            }
            .ignoresSafeArea(edges: .bottom)
            // キーボードは .scrollDismissesKeyboard(.interactively) でリストスクロール時にのみ閉じる（検索結果表示で自動で閉じない）
            .navigationTitle(editing == nil ? "新規機種登録" : "機種を編集")
            .navigationBarTitleDisplayMode(.inline)
            .keyboardDismissToolbar()
            .toolbarColorScheme(.dark, for: .navigationBar)
            .preferredColorScheme(.dark)
            .tint(accent)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                        .foregroundColor(accent)
                        .buttonStyle(.plain)
                        .fixedSize(horizontal: true, vertical: false)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(editing == nil ? "登録" : "保存") {
                        if machineName.trimmingCharacters(in: .whitespaces).isEmpty {
                            errorMessage = "機種名を入力してください"
                            showErrorAlert = true
                            return
                        }
                        if (Int(supportLimit) ?? 0) < 0 || (Int(timeShortRotations) ?? 0) < 0 || (Int(defaultPrize) ?? 1500) < 0 || (Int(countPerRoundStr) ?? 10) < 0 {
                            errorMessage = "負の数は入力できません"
                            showErrorAlert = true
                            return
                        }
                        saveMachine()
                    }
                    .fontWeight(.semibold)
                    .foregroundColor(accent)
                }
            }
            .alert("入力エラー", isPresented: $showErrorAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage)
            }
            .task(id: "\(machineMasterDataURL)_\(machineDetailBaseURL)") {
                let url = machineMasterDataURL.trimmingCharacters(in: .whitespaces).isEmpty
                    ? PresetServiceConfig.defaultMachineMasterDataURL
                    : machineMasterDataURL
                let base = machineDetailBaseURL.trimmingCharacters(in: .whitespaces)
                isLoadingPresets = true
                defer { isLoadingPresets = false }
                async let presetsTask = Task.detached(priority: .userInitiated) {
                    await PresetService.fetchPresets(from: url)
                }.value
                let indexList = await MachineDetailLoader.fetchIndex(baseURL: base.isEmpty ? nil : base)
                let result = await presetsTask
                serverPresetsHolder = result.map { PresetListHolder($0) }
                registrationIndexLoadedOK = (indexList != nil)
                registrationIndexEntries = indexList ?? []
            }
            .task(id: "\(presetSearchText)_\(showNewest20)_\(isLoadingPresets)_\(serverPresetsHolder?.items.count ?? 0)_\(registrationIndexLoadedOK)_\(registrationIndexEntries.count)") {
                if isLoadingPresets && serverPresetsHolder == nil {
                    displayPresetsCache = []
                    return
                }
                let key = presetSearchText.trimmingCharacters(in: .whitespaces).lowercased()
                let showList = showNewest20 || !key.isEmpty
                if !showList {
                    displayPresetsCache = []
                    return
                }
                if let holder = serverPresetsHolder, !holder.items.isEmpty {
                    // index と突合：対象外除外・index のみの行は minimal プリセットで補完（MasterMachineSearchView と同じ）
                    let merged = MasterSpecRegistrationGate.mergeServerPresetsWithIndex(holder.items, indexEntries: registrationIndexLoadedOK ? registrationIndexEntries : nil)
                    let sorted = merged.sorted { (a, b) in
                        (a.introductionDateRaw ?? "") > (b.introductionDateRaw ?? "")
                    }
                    let specReadySorted = sorted
                    let filtered: [PresetFromServer]
                    if key.isEmpty {
                        filtered = Array(specReadySorted.prefix(20))
                    } else {
                        filtered = Array(specReadySorted.filter { $0.name.lowercased().contains(key) }.prefix(30))
                    }
                    displayPresetsCache = filtered.map { PresetItem.server($0) }
                } else {
                    let sorted = allPresets.sorted { ($0.lastUsedAt ?? .distantPast) > ($1.lastUsedAt ?? .distantPast) }
                    let filtered = key.isEmpty ? Array(sorted.prefix(20)) : allPresets.filter { $0.name.lowercased().contains(key) }
                    let limit = key.isEmpty ? 20 : 30
                    displayPresetsCache = Array(filtered.prefix(limit)).map { PresetItem.local($0) }
                }
            }
            .task(id: machineMasterListURL) {
                if !machineMasterListURL.isEmpty {
                    machineMasterItems = await PresetService.fetchMachineMaster(from: machineMasterListURL) ?? []
                } else {
                    machineMasterItems = []
                }
            }
            .sheet(isPresented: $showMasterPicker) {
                MachineMasterPickerSheet(
                    items: machineMasterItems,
                    searchText: $masterSearchText,
                    onSelect: { item in
                        machineName = item.name
                        manufacturerStr = item.manufacturer ?? ""
                        introductionDateDisplay = ""
                        showMasterPicker = false
                    },
                    onDismiss: { showMasterPicker = false }
                )
            }
            .onAppear {
                if let machine = editing {
                    loadMachineIntoForm(machine)
                }
            }
        }
    }

    private func editPanel<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(AppTypography.panelHeading)
                .foregroundColor(.white.opacity(0.95))
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(AppGlassStyle.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(AppGlassStyle.strokeGradient, lineWidth: 1))
    }

    private func editPanel<Trailing: View, Content: View>(title: String, @ViewBuilder trailing: () -> Trailing, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center) {
                Text(title)
                    .font(AppTypography.panelHeading)
                    .foregroundColor(.white.opacity(0.95))
                Spacer(minLength: 8)
                trailing()
            }
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(AppGlassStyle.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(AppGlassStyle.strokeGradient, lineWidth: 1))
    }

    private func emptyPresetListMessage(keyEmpty: Bool, holderHasRows: Bool) -> String {
        if !registrationIndexLoadedOK, holderHasRows {
            return "スペック一覧を取得できないため、ここには表示できません。"
        }
        if keyEmpty {
            return "該当する機種が新台20件に含まれていないか、検索に一致しません。"
        }
        return "該当する機種がありません。"
    }

    @ViewBuilder
    private var presetPanel: some View {
        let keyEmpty = presetSearchText.trimmingCharacters(in: .whitespaces).isEmpty
        let showListArea = showNewest20 || !keyEmpty || isLoadingPresets
            editPanel(title: "機種を検索", trailing: { InfoIconView(explanation: "設定のマスターデータURLから取得した一覧を、マシン詳細マスタ（index.json）と突き合わせます。ステータスが「対象外」（導入から6年経過後など）の機種は表示しません。検索するか「新台から探す」で表示。選ぶと機種名・メーカー以下が自動入力されます。", tint: .white.opacity(0.6)) }) {
            HStack(spacing: 10) {
                TextField("機種名で検索", text: $presetSearchText)
                    .textContentType(.none)
                    .autocapitalization(.none)
                    .focused($isPresetSearchFocused)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
                    .background(Color.white.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                Button {
                    showNewest20 = true
                } label: {
                    Label("新台から探す", systemImage: "sparkles")
                        .font(.caption.weight(.medium))
                }
                .foregroundColor(accent)
                .buttonStyle(.bordered)
            }
            if serverPresetsHolder == nil && !isLoadingPresets {
                Text("マスタを読み込めませんでした。設定のマスターデータURLを確認するか、機種名・メーカーを手入力してください。")
                    .font(.caption)
                    .foregroundStyle(.orange.opacity(0.9))
            }
            if let holder = serverPresetsHolder, !holder.items.isEmpty, !registrationIndexLoadedOK, !isLoadingPresets {
                Text("スペック一覧（index.json）を取得できませんでした。一覧のみの表示になります（対象外の除外ができません）。ネットワークとマシン詳細マスタのベースURLを確認するか、手入力してください。")
                    .font(.caption)
                    .foregroundStyle(.orange.opacity(0.9))
            }
            if registrationIndexLoadedOK {
                Text("※ index.json に載る機種のうち、ステータス「対象外」以外を表示しています。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            if !showListArea {
                Text("検索窓に文字を入力するか「新台から探す」をタップすると、該当機種を導入日が新しい順で表示します。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                if isLoadingPresets && serverPresetsHolder == nil {
                    HStack(spacing: 8) {
                        ProgressView()
                            .scaleEffect(0.9)
                            .tint(.white.opacity(0.8))
                        Text("マスタを取得しています…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                } else if let holder = serverPresetsHolder, holder.items.isEmpty {
                    Text("マスタにデータがありません。設定のマスターデータURLを確認してください。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ScrollView(.vertical, showsIndicators: true) {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(displayPresetsCache.enumerated()), id: \.offset) { _, item in
                                let isSelected = selectedPresetId == item.id
                                Button {
                                    adoptPreset(item)
                                    selectedPresetId = item.id
                                } label: {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(item.displayName).font(.subheadline)
                                                .foregroundColor(isSelected ? accent : .primary)
                                            Text(item.displaySubtitle)
                                                .font(.caption2)
                                                .foregroundStyle(isSelected ? .white.opacity(0.85) : .secondary)
                                        }
                                        Spacer()
                                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                            .font(.caption)
                                            .foregroundStyle(isSelected ? accent : .secondary)
                                    }
                                    .padding(.vertical, 8)
                                    .padding(.horizontal, 10)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(isSelected ? accent.opacity(0.22) : Color.clear)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10)
                                            .stroke(isSelected ? accent.opacity(0.6) : Color.clear, lineWidth: 1.5)
                                    )
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 4)
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .frame(maxHeight: 220)
                    if displayPresetsCache.isEmpty {
                        let holderHasRows = (serverPresetsHolder?.items.isEmpty == false)
                        Text(emptyPresetListMessage(keyEmpty: keyEmpty, holderHasRows: holderHasRows))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var machineOverviewPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("機種名")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.9))
                    .frame(width: 100, alignment: .leading)
                TextField("例: パチンコ〇〇", text: $machineName)
                    .textContentType(.none)
                    .autocapitalization(.none)
                    .multilineTextAlignment(.trailing)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
                    .background(Color.white.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            HStack {
                Text("メーカー")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.9))
                    .frame(width: 100, alignment: .leading)
                TextField("例: サミー", text: $manufacturerStr)
                    .keyboardType(.default)
                    .multilineTextAlignment(.trailing)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
                    .background(Color.white.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            HStack(alignment: .firstTextBaseline) {
                HStack(spacing: 4) {
                    Text("通常時の当選確率")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.9))
                    InfoIconView(explanation: "通常回転時の当選確率。1/399.5のように分母のみ入力。機種を検索で選ぶとマスターから入ります。", tint: .white.opacity(0.6))
                }
                Spacer(minLength: 12)
                HStack(spacing: 0) {
                    Text("1／")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.9))
                    TextField("399.5", text: Binding(
                        get: {
                            guard let i = probability.firstIndex(of: "/") else { return probability }
                            return String(probability[probability.index(after: i)...]).trimmingCharacters(in: .whitespaces)
                        },
                        set: { probability = $0.isEmpty ? "" : "1/\($0)" }
                    ))
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 72)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 10)
                    .background(Color.white.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
            HStack(alignment: .top) {
                Text("導入開始日")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.9))
                    .frame(width: 100, alignment: .leading)
                Text(introductionDateDisplay.trimmingCharacters(in: .whitespaces).isEmpty ? "—" : introductionDateDisplay)
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(introductionDateDisplay.trimmingCharacters(in: .whitespaces).isEmpty ? 0.5 : 0.95))
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            // DMM機種ID は裏で保持（機種を検索で選んだときに adoptPreset でセット）
            if !machineMasterListURL.isEmpty {
                Button {
                    masterSearchText = ""
                    showMasterPicker = true
                } label: {
                    Label("マスタ一覧から機種名を選ぶ", systemImage: "magnifyingglass")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .foregroundColor(accent)
                .disabled(machineMasterItems.isEmpty)
            }
        }
    }

    /// 公式ボーダー入力の直下に DMM ぱちタウンへの導線を置く（アプリ内ブラウザは既存の `InAppWebView`＋下部バーで戻る）
    @ViewBuilder
    private var borderPanelWithDmmLink: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("回転/1000pt")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.9))
                Spacer()
                TextField("16.5", text: $border)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 72)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 10)
                    .background(Color.white.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            Text("店舗設定に基づいて自動的に調整されます。")
                .font(.caption)
                .foregroundColor(.white.opacity(0.7))

            if dmmMachineURL != nil {
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                        isDMMPanelExpanded = true
                    }
                } label: {
                    Label("DMMぱちタウンでこの機種を見る", systemImage: "safari")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(accent.opacity(0.28))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(accent.opacity(0.55), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .foregroundColor(.white)
                Text("アプリ内ブラウザで開きます。画面下の「登録画面」を押すと、この登録フォームにすぐ戻れます。")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.72))
            } else {
                Text("マスタの「機種を検索」で機種ID付きのデータを選ぶと、ぱちタウンの公式ページを開けます。")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
    }

    private func draftPrizeFromDenchu(_ item: ParsedDenchuItem) -> DraftPrize {
        DraftPrize(label: item.displayLabel, balls: item.balls ?? 1500)
    }

    private func adoptPreset(_ item: PresetItem) {
        switch item {
        case .server(let s):
            machineName = s.name
            manufacturerStr = s.manufacturer ?? ""
            dmmMachineID = s.machineId ?? ""
            introductionDateDisplay = (s.introductionDateRaw ?? "").trimmingCharacters(in: .whitespaces)
            selectedMachineType = MachineType(rawValue: s.machineTypeRaw ?? "") ?? .kakugen
            supportLimit = "\(s.supportLimit ?? 160)"
            timeShortRotations = "\(s.timeShortRotations ?? 0)"
            defaultPrize = "\(s.defaultPrize ?? (s.prizeEntries?.first?.balls ?? 1500))"
            probability = s.probability ?? ""
            border = s.border ?? ""
            countPerRoundStr = "\(s.countPerRound ?? 10)"
            draftHesoAtari = s.hesoAtari ?? []
            if let denchu = s.denchu_prizes, !denchu.isEmpty {
                draftDenchuPrizes = PrizeStringParser.parseDenchuPrizes(denchu).map { draftPrizeFromDenchu($0) }
            } else {
                draftDenchuPrizes = []
            }
            hasLT = (s.ltRaw?.contains("あり") == true || s.ltRaw?.contains("有") == true) && !draftDenchuPrizes.isEmpty
            if hasLT {
                draftRushPrizes = draftDenchuPrizes.filter { !$0.label.contains("天国") && !$0.label.contains("LT") }
                draftLtPrizes = draftDenchuPrizes.filter { $0.label.contains("天国") || $0.label.contains("LT") }
                draftDenchuPrizes = []
            } else {
                draftRushPrizes = []
                draftLtPrizes = []
            }
        case .cloudShared(let c):
            let s = c.asPresetFromServer
            machineName = s.name
            manufacturerStr = s.manufacturer ?? ""
            introductionDateDisplay = ""
            dmmMachineID = ""
            supportLimit = "\(s.supportLimit ?? 0)"
            timeShortRotations = "\(s.timeShortRotations ?? 0)"
            defaultPrize = "\(s.defaultPrize ?? 1500)"
            probability = s.probability ?? ""
            border = s.border ?? ""
            draftHesoAtari = s.hesoAtari ?? []
            if let denchu = s.denchu_prizes, !denchu.isEmpty {
                draftDenchuPrizes = PrizeStringParser.parseDenchuPrizes(denchu).map { draftPrizeFromDenchu($0) }
            } else {
                draftDenchuPrizes = []
            }
            hasLT = (s.ltRaw?.contains("あり") == true || s.ltRaw?.contains("有") == true) && !draftDenchuPrizes.isEmpty
            if hasLT {
                draftRushPrizes = draftDenchuPrizes.filter { !$0.label.contains("天国") && !$0.label.contains("LT") }
                draftLtPrizes = draftDenchuPrizes.filter { $0.label.contains("天国") || $0.label.contains("LT") }
                draftDenchuPrizes = []
            } else {
                draftRushPrizes = []
                draftLtPrizes = []
            }
            countPerRoundStr = "10"
        case .local(let preset):
            preset.lastUsedAt = Date()
            machineName = preset.name
            introductionDateDisplay = ""
            dmmMachineID = ""
            selectedMachineType = preset.machineType
            supportLimit = "\(preset.supportLimit)"
            timeShortRotations = "\(preset.timeShortRotations)"
            defaultPrize = "\(preset.defaultPrize)"
            probability = preset.probability
            border = preset.border
            draftHesoAtari = [] // ローカルプリセットには hesoAtari なし
            draftDenchuPrizes = []
            hasLT = false
            draftRushPrizes = []
            draftLtPrizes = []
            countPerRoundStr = "10"
        }
    }

    private func loadMachineIntoForm(_ machine: Machine) {
        machineName = machine.name
        selectedPresetId = nil
        copyFromMachine(machine)
    }

    private func copyFromMachine(_ machine: Machine) {
        introductionDateDisplay = ""
        selectedMachineType = machine.machineType
        supportLimit = "\(machine.supportLimit)"
        timeShortRotations = "\(machine.timeShortRotations)"
        defaultPrize = "\(machine.defaultPrize)"
        probability = machine.probability
        border = machine.border
        manufacturerStr = machine.manufacturer
        countPerRoundStr = "\(machine.countPerRound)"
        dmmMachineID = machine.masterID ?? ""
        ltFromNormal = machine.ltFromNormal
        draftHesoAtari = machine.hesoAtari
        if !machine.denchu_prizes.isEmpty {
            draftDenchuPrizes = PrizeStringParser.parseDenchuPrizes(machine.denchu_prizes).map { draftPrizeFromDenchu($0) }
        } else {
            draftDenchuPrizes = []
        }
        hasLT = false
        draftRushPrizes = []
        draftLtPrizes = []
    }

    private func saveMachine() {
        let name = machineName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else {
            errorMessage = "機種名を入力してください"
            showErrorAlert = true
            return
        }
        let sup = Int(supportLimit) ?? 160
        let timeShort = Int(timeShortRotations) ?? 0
        let prize = Int(defaultPrize) ?? 1500
        let probDenom = parseProbabilityDenominator(probability)
        let borderVal = parseBorderValue(border)
        let cPerRound = Int(countPerRoundStr) ?? 10

        // バリデーションチェック
        if sup < 0 || timeShort < 0 || prize < 0 || cPerRound < 0 {
            errorMessage = "負の数は入力できません"
            showErrorAlert = true
            return
        }
        if !probability.trimmingCharacters(in: .whitespaces).isEmpty && probDenom <= 0 {
            errorMessage = "確率は 1/319 のような形式で入力してください"
            showErrorAlert = true
            return
        }
        if !border.trimmingCharacters(in: .whitespaces).isEmpty && borderVal < 0 {
            errorMessage = "ボーダーに負の数は設定できません"
            showErrorAlert = true
            return
        }

        let denchuPrizesForSave = hasLT ? (draftRushPrizes + draftLtPrizes) : draftDenchuPrizes
        let denchuStr = denchuPrizesForSave.map { "(\($0.balls)個)" }.joined(separator: ",")
        let allPrizes = denchuPrizesForSave  // ヘソは hesoAtari で保存するため prizeEntries には電チューのみ

        let hesoAtariStorageValue: String = {
            guard !draftHesoAtari.isEmpty else { return "" }
            let encoder = JSONEncoder()
            guard let data = try? encoder.encode(draftHesoAtari),
                  let s = String(data: data, encoding: .utf8) else { return "" }
            return s
        }()

        let inferredType: MachineType = sup > 0 ? .st : .kakugen
        if let existing = editing {
            existing.name = name
            existing.supportLimit = sup
            existing.timeShortRotations = timeShort
            existing.defaultPrize = prize
            existing.machineTypeRaw = inferredType.rawValue
            existing.probability = probability
            existing.border = border
            existing.countPerRound = cPerRound
            existing.manufacturer = manufacturerStr.trimmingCharacters(in: .whitespaces)
            existing.masterID = dmmMachineID.trimmingCharacters(in: .whitespaces)
            existing.ltFromNormal = ltFromNormal
            existing.hesoAtariStorage = hesoAtariStorageValue
            existing.denchu_prizes = denchuStr
            for p in existing.prizeEntries {
                modelContext.delete(p)
            }
            for p in allPrizes {
                let mp = MachinePrize(label: p.label, balls: p.balls)
                mp.machine = existing
                modelContext.insert(mp)
            }
        } else {
            let machine = Machine(name: name, supportLimit: sup, defaultPrize: prize, masterID: dmmMachineID.trimmingCharacters(in: .whitespaces))
            machine.timeShortRotations = timeShort
            machine.machineTypeRaw = inferredType.rawValue
            machine.probability = probability
            machine.border = border
            machine.countPerRound = cPerRound
            machine.manufacturer = manufacturerStr.trimmingCharacters(in: .whitespaces)
            machine.ltFromNormal = ltFromNormal
            machine.hesoAtariStorage = hesoAtariStorageValue
            machine.denchu_prizes = denchuStr
            modelContext.insert(machine)
            for p in allPrizes {
                let mp = MachinePrize(label: p.label, balls: p.balls)
                mp.machine = machine
                modelContext.insert(mp)
            }
        }
        if shareWithEveryone {
            let manufacturer = manufacturerStr.trimmingCharacters(in: .whitespaces)
            let inferredType: MachineType = (Int(supportLimit) ?? 0) > 0 ? .st : .kakugen
            let prizeEntriesForCloud = allPrizes.map { (label: $0.label, balls: $0.balls) }
            let netBaseFromPrizes: Double = {
                guard !allPrizes.isEmpty else { return 140 }
                let totalBalls = allPrizes.reduce(0) { $0 + $1.balls }
                let totalFeed = allPrizes.count * cPerRound
                let totalNet = totalBalls - totalFeed
                return allPrizes.count > 0 ? max(50, min(250, Double(max(0, totalNet)) / Double(allPrizes.count))) : 140
            }()
            Task {
                do {
                    try await SharedMachineCloudKitService.saveToCloud(
                        name: name,
                        manufacturer: manufacturer,
                        machineTypeRaw: inferredType.rawValue,
                        supportLimit: sup,
                        timeShortRotations: timeShort,
                        defaultPrize: prize,
                        probability: probability,
                        border: border,
                        entryRate: 100,
                        continuationRate: 100,
                        countPerRound: cPerRound,
                        netPerRoundBase: netBaseFromPrizes,
                        prizeEntries: prizeEntriesForCloud
                    )
                } catch {
                    // ローカル保存は完了しているため、CloudKit失敗時はログのみ（必要ならトースト表示）
                }
            }
        }
        dismiss()
    }
    
    private func parseProbabilityDenominator(_ probStr: String) -> Double {
        let s = probStr.trimmingCharacters(in: .whitespaces)
        guard let slash = s.firstIndex(of: "/") else { return 0 }
        let after = s[s.index(after: slash)...].trimmingCharacters(in: .whitespaces)
        return Double(after) ?? 0
    }
    
    private func parseBorderValue(_ borderStr: String) -> Double {
        let s = borderStr.trimmingCharacters(in: .whitespaces)
        if let v = Double(s) { return v }
        let numStr = s.filter { $0.isNumber || $0 == "." || $0 == "-" }
        return Double(numStr) ?? 0
    }
    
    private var dmmMachineURL: URL? {
        let id = dmmMachineID.trimmingCharacters(in: .whitespaces)
        guard !id.isEmpty else { return nil }
        return URL(string: "https://p-town.dmm.com/machines/\(id)")
    }
    
    /// 最下部に常時表示。左右のタブで「登録画面」「DMMブラウザ」を切り替え。スワイプは補助。
    @ViewBuilder
    private var dmmSwipeBar: some View {
        let handleHeight: CGFloat = 60
        VStack(spacing: 6) {
            Text(isDMMPanelExpanded ? "表示中: DMMブラウザ" : "表示中: 登録画面")
                .font(.caption2.weight(.semibold))
                .foregroundColor(.white.opacity(0.8))

            HStack(spacing: 12) {
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                    isDMMPanelExpanded = false
                }
            } label: {
                        Label("登録画面", systemImage: "doc.text")
                    .font(.caption.weight(.semibold))
                    .padding(.vertical, 6)
                    .padding(.horizontal, 10)
                    .background(isDMMPanelExpanded ? Color.white.opacity(0.08) : AppGlassStyle.accent.opacity(0.35))
                    .clipShape(Capsule())
                    .foregroundColor(.white)
            }
            .buttonStyle(.plain)
            .opacity(isDMMPanelExpanded ? 1 : 0.7)

            VStack(alignment: .leading, spacing: 2) {
                Text("スペックを調べる")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white.opacity(0.98))
                if dmmMachineURL == nil {
                    Text("機種を検索で選ぶとスペックページを開けます")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.7))
                } else {
                    Text("タブをタップして切り替えます")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.8))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                guard dmmMachineURL != nil else { return }
                // 読み込み完了を待たず、タップしたら即ブラウザ表示に切り替える
                isDMMPanelExpanded = true
            } label: {
                Label("ブラウザ", systemImage: "safari")
                    .font(.caption.weight(.semibold))
                    .padding(.vertical, 6)
                    .padding(.horizontal, 10)
                    .background(isDMMPanelExpanded && dmmMachineURL != nil ? AppGlassStyle.accent.opacity(0.35) : Color.white.opacity(0.08))
                    .clipShape(Capsule())
                    .foregroundColor(.white.opacity(dmmMachineURL == nil ? 0.4 : 1.0))
            }
            .buttonStyle(.plain)
            .disabled(dmmMachineURL == nil)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .frame(height: handleHeight)
        .contentShape(Rectangle())
        .highPriorityGesture(
            DragGesture(minimumDistance: 50)
                .onEnded { value in
                    let dx = value.translation.width
                    let dy = value.translation.height
                    guard abs(dx) > abs(dy) * 1.2 else { return }
                    if dx < -40 {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                            isDMMPanelExpanded = true
                        }
                    } else if dx > 40 {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                            isDMMPanelExpanded = false
                        }
                    }
                }
        )
        .background(Color.black.opacity(0.92))
        .overlay(
            RoundedRectangle(cornerRadius: 0)
                .stroke(Color.white.opacity(0.35), lineWidth: 1)
                .padding(1)
        )
    }
}

// MARK: - 機種マスタから機種名・メーカーを選ぶシート
struct MachineMasterPickerSheet: View {
    let items: [MachineMasterItem]
    @Binding var searchText: String
    let onSelect: (MachineMasterItem) -> Void
    let onDismiss: () -> Void

    private var filteredItems: [MachineMasterItem] {
        let key = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        if key.isEmpty { return items }
        return items.filter {
            $0.name.lowercased().contains(key) || ($0.manufacturer?.lowercased().contains(key) ?? false)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                TextField("機種名・メーカーで検索", text: $searchText)
                    .textContentType(.none)
                    .autocapitalization(.none)
                ForEach(Array(filteredItems.enumerated()), id: \.offset) { _, item in
                    Button {
                        onSelect(item)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.name)
                                .font(.subheadline)
                                .foregroundColor(.primary)
                            if let m = item.manufacturer, !m.isEmpty {
                                Text(m)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("機種マスタから選ぶ")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { onDismiss() }
                }
            }
            .overlay {
                if items.isEmpty {
                    ContentUnavailableView(
                        "マスタが空です",
                        systemImage: "tray",
                        description: Text("設定で機種マスタURLを指定し、管理人が用意したJSONを参照できます。")
                    )
                }
            }
        }
        .keyboardDismissToolbar()
    }
}

// MARK: - ライブラリからボーナス種類を選ぶシート（複数選択可）
struct PrizePickerSheet: View {
    let prizeSets: [PrizeSet]
    let onSelectMultiple: ([PrizeSet]) -> Void
    let onDismiss: () -> Void

    @State private var selectedIDs: Set<PersistentIdentifier> = []

    private func toggle(_ id: PersistentIdentifier) {
        if selectedIDs.contains(id) {
            selectedIDs.remove(id)
        } else {
            selectedIDs.insert(id)
        }
    }

    private var selectedItems: [PrizeSet] {
        prizeSets.filter { selectedIDs.contains($0.persistentModelID) }
    }

    var body: some View {
        NavigationStack {
            List(prizeSets, id: \.persistentModelID) { ps in
                Button {
                    toggle(ps.persistentModelID)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(ps.name.isEmpty ? "\(ps.balls)玉" : ps.name)
                                .font(.subheadline)
                            Text("1Rあたり \(String(format: "%.0f", ps.netPerRound)) 玉")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if selectedIDs.contains(ps.persistentModelID) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            .navigationTitle("ボーナス種類を選択")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { onDismiss() }
                        .buttonStyle(.plain)
                }
                ToolbarItem(placement: .secondaryAction) {
                    NavigationLink {
                        PrizeSetListView()
                    } label: {
                        Text("ライブラリ管理")
                    }
                    .buttonStyle(.plain)
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("追加（\(selectedItems.count)件）") {
                        onSelectMultiple(selectedItems)
                    }
                    .disabled(selectedItems.isEmpty)
                    .buttonStyle(.borderedProminent)
                }
            }
            .overlay {
                if prizeSets.isEmpty {
                    ContentUnavailableView(
                        "ライブラリが空です",
                        systemImage: "tray",
                        description: Text("「ライブラリ管理」で先に登録してください")
                    )
                }
            }
        }
    }
}

// MARK: - 分割画面用アプリ内ブラウザ（WKWebView）。URL が変わったら再読み込み。
struct InAppWebView: UIViewRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.load(URLRequest(url: url))
        context.coordinator.lastLoadedURL = url
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        if context.coordinator.lastLoadedURL != url {
            context.coordinator.lastLoadedURL = url
            uiView.load(URLRequest(url: url))
        }
    }

    final class Coordinator {
        var lastLoadedURL: URL?
    }
}

import SwiftUI
import SwiftData

/// マスターデータ（管理人用DB）から機種を検索し、マイリストに追加する画面。
/// マスタは PresetService の URL で取得する JSON（管理人のみ編集可）またはアプリ内 PresetMachine。
struct MasterMachineSearchView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \PresetMachine.name) private var localPresets: [PresetMachine]
    @AppStorage("machineMasterDataURL") private var machineMasterDataURL: String = ""
    @AppStorage("machineDetailBaseURL") private var machineDetailBaseURL: String = ""
    @State private var urlPresets: [PresetFromServer]?
    @State private var urlLoadError: String?
    /// index.json 取得失敗時（一覧を空にした理由）
    @State private var specIndexGateMessage: String?
    @State private var cloudSharedPresets: [SharedMachineFromCloud]?
    @State private var searchText: String = ""
    @State private var searchTextDebounced: String = ""
    @State private var searchFilterTask: Task<Void, Never>?
    /// 検索結果の表示用キャッシュ（バックグラウンドでフィルタ。メインスレッドで5000件フィルタしない）
    @State private var masterItemsCache: [PresetItem] = []
    @State private var selectedItem: PresetItem?
    @State private var isAdding = false
    @State private var refreshID = UUID()
    @State private var showAddedFeedback = false
    @State private var addedMachineName: String = ""

    /// マスターデータ取得に使うURL（設定が空ならデフォルトURL）
    private var effectiveMasterDataURL: String {
        let u = machineMasterDataURL.trimmingCharacters(in: .whitespaces)
        return u.isEmpty ? PresetServiceConfig.defaultMachineMasterDataURL : u
    }

    /// URLから取得したマスタ一覧（設定で変更可能）
    private var mergedRemotePresets: [PresetFromServer] {
        urlPresets ?? []
    }

    private var accent: Color { AppGlassStyle.accent }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                VStack(spacing: 6) {
                    Text("マスタから機種を選び、マイリストに追加できます。")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.75))
                    Text("※ index.json に載る機種のうち、ステータス「対象外」（導入から6年超など）以外を表示します。詳細は machines.json 優先。")
                        .font(AppTypography.annotationSmall)
                        .foregroundStyle(.white.opacity(0.55))
                }
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 10)
                TextField("機種名で検索", text: $searchText)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(AppGlassStyle.rowBackground)
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
                    .onChange(of: searchText) { _, newValue in
                        searchFilterTask?.cancel()
                        searchFilterTask = Task {
                            try? await Task.sleep(nanoseconds: 250_000_000)
                            guard !Task.isCancelled else { return }
                            searchTextDebounced = newValue
                        }
                    }
                    .onAppear { searchTextDebounced = searchText }
                List {
                    if let err = urlLoadError {
                        Section {
                            Text(err)
                                .foregroundStyle(.orange)
                                .font(.subheadline)
                        }
                        .listRowBackground(Color.clear)
                    }
                    if let gateMsg = specIndexGateMessage {
                        Section {
                            Text(gateMsg)
                                .foregroundStyle(.orange)
                                .font(.subheadline)
                        }
                        .listRowBackground(Color.clear)
                    }
                    if mergedRemotePresets.isEmpty && (cloudSharedPresets?.isEmpty ?? true) && localPresets.isEmpty && urlLoadError == nil {
                        ContentUnavailableView(
                            "マスターデータがありません",
                            systemImage: "tray",
                            description: Text("設定で「マスターデータURL」を確認してください。URLからJSONを取得して一覧を表示します。")
                        )
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    }
                    ForEach(masterItemsCache) { item in
                        Button {
                            selectedItem = item
                        } label: {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.displayName)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundColor(.white)
                                    Text(item.displaySubtitle)
                                        .font(AppTypography.annotation)
                                        .foregroundStyle(.white.opacity(0.7))
                                }
                                Spacer(minLength: 8)
                                Image(systemName: "plus.circle.fill")
                                    .font(.title3)
                                    .foregroundStyle(accent)
                            }
                            .padding(.vertical, 4)
                        }
                        .disabled(isAdding)
                        .listRowBackground(AppGlassStyle.rowBackground)
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .scrollDismissesKeyboard(.interactively)
            }
            .background(AppGlassStyle.background)
            .navigationTitle("マスタから検索")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .preferredColorScheme(.dark)
            .task(id: "\(refreshID)_\(effectiveMasterDataURL)_\(machineDetailBaseURL)") {
                urlLoadError = nil
                specIndexGateMessage = nil
                let raw = await PresetService.fetchPresets(from: effectiveMasterDataURL)
                let base = machineDetailBaseURL.trimmingCharacters(in: .whitespaces)
                let idx = await MachineDetailLoader.fetchIndex(baseURL: base.isEmpty ? nil : base)

                if raw == nil && !effectiveMasterDataURL.isEmpty {
                    urlLoadError = "URLからの取得に失敗しました。ネットワーク接続と設定の「マスターデータURL」を確認してください。"
                }

                if let r = raw {
                    if let indexEntries = idx {
                        urlPresets = MasterSpecRegistrationGate.mergeServerPresetsWithIndex(r, indexEntries: indexEntries)
                    } else {
                        urlPresets = r
                        specIndexGateMessage = "index.json を取得できませんでした。一覧はマスターデータのみ表示しています（対象外の除外・index との突合ができません）。ベースURLを確認してください。"
                    }
                } else {
                    urlPresets = nil
                }
                cloudSharedPresets = await SharedMachineCloudKitService.fetchSharedMachines(searchText: nil)
            }
            .task(id: "\(searchTextDebounced)_\(urlPresets?.count ?? 0)_\(cloudSharedPresets?.count ?? 0)_\(localPresets.count)") {
                let key = searchTextDebounced.trimmingCharacters(in: .whitespaces).lowercased()
                var items: [PresetItem] = []
                if let server = urlPresets, !server.isEmpty {
                    let serverCopy = server
                    let serverItems = await Task.detached(priority: .userInitiated) {
                        let list = key.isEmpty ? serverCopy : serverCopy.filter { $0.name.lowercased().contains(key) }
                        return Array(list.prefix(100)).map { PresetItem.server($0) }
                    }.value
                    items.append(contentsOf: serverItems)
                }
                if let cloud = cloudSharedPresets {
                    let list = key.isEmpty ? cloud : cloud.filter {
                        $0.name.lowercased().contains(key) || ($0.manufacturer?.lowercased().contains(key) ?? false)
                    }
                    items.append(contentsOf: Array(list.prefix(100)).map { PresetItem.cloudShared($0) })
                }
                let localList = key.isEmpty ? localPresets : localPresets.filter { $0.name.lowercased().contains(key) }
                items.append(contentsOf: localList.map { PresetItem.local($0) })
                masterItemsCache = Array(items.prefix(150))
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                        .foregroundColor(accent)
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("マスターを更新") {
                        refreshID = UUID()
                    }
                    .foregroundColor(accent)
                }
            }
            .alert("マイリストに追加", isPresented: Binding(
                get: { selectedItem != nil },
                set: { if !$0 { selectedItem = nil } }
            )) {
                Button("追加") {
                    if let item = selectedItem {
                        addToMyList(item)
                        addedMachineName = item.displayName
                        selectedItem = nil
                        showAddedFeedback = true
                    }
                }
                Button("キャンセル", role: .cancel) { selectedItem = nil }
            } message: {
                if let item = selectedItem {
                    Text("「\(item.displayName)」をマイリストに追加します。追加後は編集で細部を変更できます。")
                }
            }
            .alert("マイ機種に追加しました", isPresented: $showAddedFeedback) {
                Button("閉じる") {
                    showAddedFeedback = false
                    dismiss()
                }
            } message: {
                Text("「\(addedMachineName)」をマイ機種に追加しました。")
            }
        }
    }

    private func addToMyList(_ item: PresetItem) {
        isAdding = true
        defer { isAdding = false }
        switch item {
        case .server(let s):
            let defaultPrizeValue = s.defaultPrize ?? s.prizeEntries?.first?.balls ?? 1500
            let machine = Machine(
                name: s.name.trimmingCharacters(in: .whitespaces).isEmpty ? "未設定" : s.name,
                supportLimit: s.supportLimit ?? 160,
                defaultPrize: defaultPrizeValue
            )
            machine.timeShortRotations = s.timeShortRotations ?? 0
            machine.machineTypeRaw = MachineType(rawValue: s.machineTypeRaw ?? "")?.rawValue ?? MachineType.kakugen.rawValue
            machine.probability = s.probability ?? ""
            machine.border = s.border ?? ""
            machine.countPerRound = s.countPerRound ?? 10
            machine.manufacturer = s.manufacturer ?? ""
            if let heso = s.hesoAtari, !heso.isEmpty,
               let data = try? JSONEncoder().encode(heso),
               let str = String(data: data, encoding: .utf8) {
                machine.hesoAtariStorage = str
            }
            machine.denchu_prizes = s.denchu_prizes ?? ""
            modelContext.insert(machine)
            for entry in s.prizeEntries ?? [] {
                let mp = MachinePrize(label: entry.label ?? "", balls: entry.balls)
                mp.machine = machine
                modelContext.insert(mp)
            }
        case .cloudShared(let c):
            let s = c.asPresetFromServer
            let defaultPrizeValue = s.defaultPrize ?? s.prizeEntries?.first?.balls ?? 1500
            let machine = Machine(
                name: s.name.trimmingCharacters(in: .whitespaces).isEmpty ? "未設定" : s.name,
                supportLimit: s.supportLimit ?? 160,
                defaultPrize: defaultPrizeValue
            )
            machine.timeShortRotations = s.timeShortRotations ?? 0
            machine.machineTypeRaw = MachineType(rawValue: s.machineTypeRaw ?? "")?.rawValue ?? MachineType.kakugen.rawValue
            machine.probability = s.probability ?? ""
            machine.border = s.border ?? ""
            machine.countPerRound = s.countPerRound ?? 10
            machine.manufacturer = s.manufacturer ?? ""
            if let heso = s.hesoAtari, !heso.isEmpty,
               let data = try? JSONEncoder().encode(heso),
               let str = String(data: data, encoding: .utf8) {
                machine.hesoAtariStorage = str
            }
            modelContext.insert(machine)
            for entry in s.prizeEntries ?? [] {
                let mp = MachinePrize(label: entry.label ?? "", balls: entry.balls)
                mp.machine = machine
                modelContext.insert(mp)
            }
        case .local(let preset):
            preset.lastUsedAt = Date()
            let defaultPrizeLocal = preset.prizeEntries.first?.balls ?? preset.defaultPrize
            let machine = Machine(name: preset.name, supportLimit: preset.supportLimit, defaultPrize: defaultPrizeLocal)
            machine.timeShortRotations = preset.timeShortRotations
            machine.machineTypeRaw = preset.machineTypeRaw
            machine.probability = preset.probability
            machine.border = preset.border
            machine.countPerRound = 10
            machine.manufacturer = ""
            modelContext.insert(machine)
            for p in preset.prizeEntries {
                let mp = MachinePrize(label: p.label, balls: p.balls)
                mp.machine = machine
                modelContext.insert(mp)
            }
        }
    }
}

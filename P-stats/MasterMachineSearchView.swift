import SwiftUI
import SwiftData

/// マスターデータ（管理人用DB）から機種を検索し、マイリストに追加する画面。
/// マスタは PresetService の URL で取得する JSON（管理人のみ編集可）またはアプリ内 PresetMachine。
struct MasterMachineSearchView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \PresetMachine.name) private var localPresets: [PresetMachine]
    @State private var serverPresets: [PresetFromServer]?
    @State private var searchText: String = ""
    @State private var selectedItem: PresetItem?
    @State private var isAdding = false

    private var masterItems: [PresetItem] {
        let key = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        if let server = serverPresets, !server.isEmpty {
            let list = key.isEmpty ? server : server.filter { $0.name.lowercased().contains(key) }
            return Array(list.prefix(100)).map { PresetItem.server($0) }
        }
        let list = key.isEmpty ? localPresets : localPresets.filter { $0.name.lowercased().contains(key) }
        return list.map { PresetItem.local($0) }
    }

    private var accent: Color { AppGlassStyle.accent }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Text("マスタから機種を選び、マイリストに追加できます。")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.75))
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
                List(masterItems) { item in
                    Button {
                        selectedItem = item
                    } label: {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.displayName)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundColor(.white)
                                Text(item.displaySubtitle)
                                    .font(.caption)
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
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
            .background(AppGlassStyle.background)
            .navigationTitle("マスタから検索")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .preferredColorScheme(.dark)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                        .foregroundColor(accent)
                }
            }
            .task {
                if !PresetServiceConfig.presetListURL.isEmpty {
                    serverPresets = await PresetService.fetchPresets(from: PresetServiceConfig.presetListURL)
                }
            }
            .alert("マイリストに追加", isPresented: Binding(
                get: { selectedItem != nil },
                set: { if !$0 { selectedItem = nil } }
            )) {
                Button("追加") {
                    if let item = selectedItem {
                        addToMyList(item)
                    }
                    selectedItem = nil
                    dismiss()
                }
                Button("キャンセル", role: .cancel) { selectedItem = nil }
            } message: {
                if let item = selectedItem {
                    Text("「\(item.displayName)」をマイリストに追加します。追加後は編集で細部を変更できます。")
                }
            }
        }
    }

    private func addToMyList(_ item: PresetItem) {
        isAdding = true
        defer { isAdding = false }
        switch item {
        case .server(let s):
            let machine = Machine(
                name: s.name.trimmingCharacters(in: .whitespaces).isEmpty ? "未設定" : s.name,
                supportLimit: s.supportLimit ?? 160,
                defaultPrize: s.defaultPrize ?? 1500
            )
            machine.timeShortRotations = s.timeShortRotations ?? 0
            machine.machineTypeRaw = MachineType(rawValue: s.machineTypeRaw ?? "")?.rawValue ?? MachineType.kakugen.rawValue
            machine.probability = s.probability ?? ""
            machine.border = s.border ?? ""
            machine.entryRate = s.entryRate ?? 100
            machine.continuationRate = s.continuationRate ?? 100
            machine.countPerRound = s.countPerRound ?? 10
            let netBase = s.netPerRoundBase ?? PresetService.averageNetPerRound(s)
            machine.netPerRoundBase = netBase > 0 ? netBase : 140
            machine.manufacturer = s.manufacturer ?? ""
            modelContext.insert(machine)
            for entry in s.prizeEntries ?? [] {
                let mp = MachinePrize(label: entry.label ?? "", rounds: entry.rounds, balls: entry.balls)
                mp.machine = machine
                modelContext.insert(mp)
            }
        case .local(let preset):
            preset.lastUsedAt = Date()
            let machine = Machine(name: preset.name, supportLimit: preset.supportLimit, defaultPrize: preset.defaultPrize)
            machine.timeShortRotations = preset.timeShortRotations
            machine.machineTypeRaw = preset.machineTypeRaw
            machine.probability = preset.probability
            machine.border = preset.border
            machine.entryRate = 100
            machine.continuationRate = 100
            machine.countPerRound = 10
            machine.netPerRoundBase = preset.averageNetPerRound > 0 ? preset.averageNetPerRound : 140
            modelContext.insert(machine)
            for p in preset.prizeEntries {
                let mp = MachinePrize(label: p.label, rounds: p.rounds, balls: p.balls)
                mp.machine = machine
                modelContext.insert(mp)
            }
        }
    }
}

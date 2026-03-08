import SwiftUI
import SwiftData

/// 管理人用：アプリ内マスタ（PresetMachine）の一覧・追加・編集・削除
struct PresetMasterListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \PresetMachine.name) private var presets: [PresetMachine]

    @State private var presetToEdit: PresetMachine?
    @State private var showAddSheet = false
    @State private var showEditSheet = false

    var body: some View {
        List {
            Section {
                Text("マスタに登録した機種は、ユーザーが「マスタから検索」でマイリストに追加できます。")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
                    .listRowBackground(AppGlassStyle.rowBackground)
            }
            Section("登録済みマスタ機種") {
                if presets.isEmpty {
                    Text("まだ登録がありません。「追加」でマスタ機種を登録してください。")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.7))
                        .listRowBackground(AppGlassStyle.rowBackground)
                } else {
                    ForEach(presets) { p in
                        Button {
                            presetToEdit = p
                            showEditSheet = true
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(p.name)
                                        .font(.body.weight(.medium))
                                        .foregroundColor(.white)
                                    Text("\(p.machineType.displayName) / 確率 \(p.probability)")
                                        .font(.caption)
                                        .foregroundStyle(.white.opacity(0.7))
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(.white.opacity(0.5))
                            }
                        }
                        .listRowBackground(AppGlassStyle.rowBackground)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                modelContext.delete(p)
                            } label: { Label("削除", systemImage: "trash") }
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(AppGlassStyle.background)
        .navigationTitle("マスタ管理")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .preferredColorScheme(.dark)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("追加") { showAddSheet = true }
            }
        }
        .sheet(isPresented: $showAddSheet) {
            PresetMachineEditView(preset: nil) {
                showAddSheet = false
            }
        }
        .sheet(isPresented: $showEditSheet, onDismiss: { presetToEdit = nil }) {
            if let p = presetToEdit {
                PresetMachineEditView(preset: p) {
                    showEditSheet = false
                }
            }
        }
    }
}


/// マスタ機種（PresetMachine）の新規作成・編集
struct PresetMachineEditView: View {
    let preset: PresetMachine?
    let onDismiss: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var name: String = ""
    @State private var machineTypeRaw: String = MachineType.kakugen.rawValue
    @State private var supportLimitStr: String = "100"
    @State private var timeShortStr: String = "0"
    @State private var defaultPrizeStr: String = "1500"
    @State private var probability: String = ""
    @State private var border: String = ""
    @State private var prizeEntries: [PresetPrizeRow] = []

    private var isNew: Bool { preset == nil }

    struct PresetPrizeRow: Identifiable {
        let id = UUID()
        var label: String
        var rounds: Int
        var balls: Int
    }

    var body: some View {
        NavigationStack {
            List {
                Section("基本") {
                    HStack {
                        Text("機種名")
                        Spacer()
                        TextField("例: 北斗の拳", text: $name)
                            .multilineTextAlignment(.trailing)
                            .foregroundColor(.white)
                    }
                    .listRowBackground(AppGlassStyle.rowBackground)
                    Picker("タイプ", selection: $machineTypeRaw) {
                        ForEach(MachineType.allCases, id: \.rawValue) { t in
                            Text(t.displayName).tag(t.rawValue)
                        }
                    }
                    .foregroundColor(.white)
                    .listRowBackground(AppGlassStyle.rowBackground)
                    HStack {
                        Text("電サポ回数")
                        Spacer()
                        TextField("100", text: $supportLimitStr)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .foregroundColor(.white)
                    }
                    .listRowBackground(AppGlassStyle.rowBackground)
                    HStack {
                        Text("時短（回転）")
                        Spacer()
                        TextField("0", text: $timeShortStr)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .foregroundColor(.white)
                    }
                    .listRowBackground(AppGlassStyle.rowBackground)
                    HStack {
                        Text("デフォルト出玉")
                        Spacer()
                        TextField("1500", text: $defaultPrizeStr)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .foregroundColor(.white)
                    }
                    .listRowBackground(AppGlassStyle.rowBackground)
                }
                Section("確率・ボーダー") {
                    HStack {
                        Text("確率（表示用）")
                        Spacer()
                        TextField("1/319.5", text: $probability)
                            .multilineTextAlignment(.trailing)
                            .foregroundColor(.white)
                    }
                    .listRowBackground(AppGlassStyle.rowBackground)
                    HStack {
                        Text("ボーダー（表示用）")
                        Spacer()
                        TextField("18.5", text: $border)
                            .multilineTextAlignment(.trailing)
                            .foregroundColor(.white)
                    }
                    .listRowBackground(AppGlassStyle.rowBackground)
                }
                Section("ボーナス種類（R・出玉）") {
                    ForEach($prizeEntries) { $row in
                        HStack {
                            TextField("10R", text: $row.label)
                                .frame(width: 56)
                                .foregroundColor(.white)
                            TextField("10", value: $row.rounds, format: .number)
                                .keyboardType(.numberPad)
                                .frame(width: 40)
                                .multilineTextAlignment(.trailing)
                                .foregroundColor(.white)
                            Text("R")
                            TextField("1500", value: $row.balls, format: .number)
                                .keyboardType(.numberPad)
                                .frame(width: 56)
                                .multilineTextAlignment(.trailing)
                                .foregroundColor(.white)
                            Text("玉")
                        }
                        .listRowBackground(AppGlassStyle.rowBackground)
                    }
                    Button("ボーナス種類を追加") {
                        prizeEntries.append(PresetPrizeRow(label: "10R", rounds: 10, balls: 1500))
                    }
                    .foregroundColor(AppGlassStyle.accent)
                    .listRowBackground(AppGlassStyle.rowBackground)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(AppGlassStyle.background)
            .navigationTitle(isNew ? "マスタ機種を追加" : "マスタ機種を編集")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .preferredColorScheme(.dark)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss(); onDismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isNew ? "登録" : "保存") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear { load() }
        }
    }

    private func load() {
        guard let p = preset else {
            prizeEntries = [PresetPrizeRow(label: "10R", rounds: 10, balls: 1500)]
            return
        }
        name = p.name
        machineTypeRaw = p.machineTypeRaw
        supportLimitStr = "\(p.supportLimit)"
        timeShortStr = "\(p.timeShortRotations)"
        defaultPrizeStr = "\(p.defaultPrize)"
        probability = p.probability
        border = p.border
        prizeEntries = p.prizeEntries.map { PresetPrizeRow(label: $0.label, rounds: $0.rounds, balls: $0.balls) }
        if prizeEntries.isEmpty {
            prizeEntries = [PresetPrizeRow(label: "10R", rounds: 10, balls: 1500)]
        }
    }

    private func save() {
        let n = name.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty else { return }
        let support = Int(supportLimitStr) ?? 100
        let timeShort = Int(timeShortStr) ?? 0
        let defaultPrize = Int(defaultPrizeStr) ?? 1500

        if let existing = preset {
            existing.name = n
            existing.machineTypeRaw = machineTypeRaw
            existing.supportLimit = max(1, support)
            existing.timeShortRotations = max(0, timeShort)
            existing.defaultPrize = max(1, defaultPrize)
            existing.probability = probability
            existing.border = border
            existing.prizeEntries.forEach { modelContext.delete($0) }
            for row in prizeEntries {
                let e = PresetMachinePrize(label: row.label, rounds: row.rounds, balls: row.balls)
                e.preset = existing
                modelContext.insert(e)
            }
        } else {
            let p = PresetMachine(name: n, supportLimit: max(1, support), defaultPrize: max(1, defaultPrize))
            p.machineTypeRaw = machineTypeRaw
            p.timeShortRotations = max(0, timeShort)
            p.probability = probability
            p.border = border
            modelContext.insert(p)
            for row in prizeEntries {
                let e = PresetMachinePrize(label: row.label, rounds: row.rounds, balls: row.balls)
                e.preset = p
                modelContext.insert(e)
            }
        }
        dismiss()
        onDismiss()
    }
}


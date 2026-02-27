import SwiftUI
import SwiftData
import WebKit

// MARK: - 確率のクイック選択（数値のみ・名称に縛られない）
private let probabilityQuickValues = [399, 349, 319, 199, 99]

/// プリセット一覧の1件（サーバー取得 or アプリ内）
enum PresetItem: Identifiable {
    case server(PresetFromServer)
    case local(PresetMachine)

    var id: String {
        switch self {
        case .server(let s): return "s-\(s.name)-\(s.probability ?? "")"
        case .local(let m): return "l-\(m.persistentModelID.hashValue)"
        }
    }
    var displayName: String {
        switch self {
        case .server(let s): return s.name
        case .local(let m): return m.name
        }
    }
    var displaySubtitle: String {
        switch self {
        case .server(let s):
            let type = MachineType(rawValue: s.machineTypeRaw ?? "") ?? .kakugen
            let avg = PresetService.averageNetPerRound(s)
            return "\(type.displayName) / 確率 \(s.probability ?? "") / 1R純増 \(String(format: "%.0f", avg))"
        case .local(let m):
            return "\(m.machineType.displayName) / 確率 \(m.probability) / 1R純増 \(String(format: "%.0f", m.averageNetPerRound))"
        }
    }
}

/// 機種の新規登録または編集。確率は数値ボタン+自由入力、当たり種類はライブラリから選択可能。
struct MachineEditView: View, Equatable {
    /// 編集時は既存の機種を渡す。nil のときは新規登録。
    var editing: Machine? = nil

    static func == (lhs: MachineEditView, rhs: MachineEditView) -> Bool {
        lhs.editing?.persistentModelID == rhs.editing?.persistentModelID
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \Machine.name) private var savedMachines: [Machine]
    @Query(sort: \PrizeSet.name) private var prizeSets: [PrizeSet]
    @Query(sort: \PresetMachine.name) private var allPresets: [PresetMachine]
    @Query(sort: \MyMachinePreset.name) private var myPresets: [MyMachinePreset]

    @State private var machineName: String = ""
    @State private var selectedMachineType: MachineType = .kakugen
    @State private var supportLimit: String = "160"
    @State private var timeShortRotations: String = "0"
    @State private var defaultPrize: String = "1500"
    @State private var probability: String = ""
    @State private var border: String = ""
    @State private var entryRateStr: String = "100"
    @State private var continuationRateStr: String = "100"
    @State private var averagePrizeStr: String = ""
    @State private var netPerRoundBaseStr: String = "140"
    @State private var countPerRoundStr: String = "10"
    @State private var manufacturerStr: String = ""

    /// この機種に紐づける当たり種類（編集中の一時リスト）
    @State private var draftPrizes: [DraftPrize] = []

    @State private var copySearchText: String = ""
    @State private var presetSearchText: String = ""
    @State private var serverPresets: [PresetFromServer]?
    /// 分割表示でブラウザを表示するとき true
    @State private var showSpecBrowser = false
    @State private var specSearchURL: URL?
    @State private var showSaveMyPreset = false
    @State private var myPresetNameToSave: String = ""

    struct DraftPrize: Identifiable {
        let id = UUID()
        var label: String
        var rounds: Int
        var balls: Int
        var netPerRound: Double { rounds > 0 ? Double(balls) / Double(rounds) : 0 }
    }

    private var accent: Color { AppGlassStyle.accent }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if showSpecBrowser, let url = specSearchURL {
                    GeometryReader { geo in
                        VStack(spacing: 0) {
                            HStack {
                                Text("スペック検索").font(.caption).foregroundStyle(.secondary)
                                Spacer()
                                Button("閉じる") {
                                    showSpecBrowser = false
                                }
                                .font(.subheadline)
                                .foregroundColor(accent)
                            }
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .background(AppGlassStyle.rowBackground)
                            InAppWebView(url: url)
                                .frame(height: geo.size.height * 0.45)
                            Divider()
                        }
                    }
                    .frame(height: 280)
                }
                formContent
                    .frame(maxHeight: .infinity)
            }
            .background(AppGlassStyle.background)
            .navigationTitle(editing == nil ? "新規機種登録" : "機種を編集")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .preferredColorScheme(.dark)
            .tint(accent)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                        .foregroundColor(accent)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(editing == nil ? "登録" : "保存") { saveMachine() }
                        .fontWeight(.semibold)
                        .foregroundColor(accent)
                        .disabled(machineName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .task {
                if !PresetServiceConfig.presetListURL.isEmpty {
                    serverPresets = await PresetService.fetchPresets(from: PresetServiceConfig.presetListURL)
                }
            }
            .onAppear {
                if let machine = editing {
                    loadMachineIntoForm(machine)
                }
            }
            .sheet(isPresented: $showAddPrizePicker) {
                PrizePickerSheet(prizeSets: prizeSets) { ps in
                    draftPrizes.append(DraftPrize(label: ps.name, rounds: ps.rounds, balls: ps.balls))
                    showAddPrizePicker = false
                } onDismiss: {
                    showAddPrizePicker = false
                }
            }
            .alert("マイプリセットに保存", isPresented: $showSaveMyPreset) {
                TextField("プリセット名", text: $myPresetNameToSave)
                Button("保存") { saveAsMyPreset(name: myPresetNameToSave) }
                Button("キャンセル", role: .cancel) { showSaveMyPreset = false; myPresetNameToSave = "" }
            } message: {
                Text("現在の機種名・確率・ラウンド・カウント・1R純増などを一覧から一撃で呼び出せます。")
            }
        }
    }

    @ViewBuilder
    private var formContent: some View {
        Form {
            Section("機種タイプ") {
                Picker("タイプ", selection: $selectedMachineType) {
                    ForEach(MachineType.allCases, id: \.self) { type in
                        Text(type.displayName).tag(type)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section("プリセットから選ぶ") {
                Text("空なら直近30件。検索で該当機種を表示。").font(.caption).foregroundStyle(.secondary)
                TextField("機種名で検索", text: $presetSearchText)
                    .textContentType(.none)
                    .autocapitalization(.none)
                ForEach(displayPresets) { item in
                    Button {
                        adoptPreset(item)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.displayName).font(.subheadline)
                                Text(item.displaySubtitle)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "checkmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(.green)
                        }
                    }
                }
                if displayPresets.isEmpty {
                    Text(presetSearchText.isEmpty ? "プリセットがありません。" : "該当するプリセットがありません。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("機種名") {
                HStack(spacing: 8) {
                    TextField("例: パチンコ〇〇", text: $machineName)
                        .textContentType(.none)
                        .autocapitalization(.none)
                    PasteButton(binding: $machineName)
                }
                Button {
                    openSpecSearch()
                } label: {
                    Label("スペックを調べる", systemImage: "magnifyingglass")
                        .frame(maxWidth: .infinity)
                }
                .disabled(machineName.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            Section("確率") {
                Text("数値で選択（1/○○）").font(.caption).foregroundStyle(.secondary)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(probabilityQuickValues, id: \.self) { denom in
                            Button("\(denom)") {
                                probability = "1/\(denom)"
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.blue)
                        }
                    }
                    .padding(.vertical, 4)
                }
                HStack(spacing: 8) {
                    TextField("自由入力（例: 1/399.5）", text: $probability)
                        .keyboardType(.numbersAndPunctuation)
                    PasteButton(binding: $probability)
                }
            }

            Section("当たり種類") {
                NavigationLink {
                    PrizeSetListView()
                } label: {
                    Label("当たり種類ライブラリを管理", systemImage: "list.bullet.rectangle")
                }
                if !draftPrizes.isEmpty {
                    let count = Int(countPerRoundStr) ?? 10
                    ForEach(draftPrizes) { p in
                        let netBalls = max(0, p.balls - (p.rounds * count))
                        let netPerR = p.rounds > 0 ? Double(netBalls) / Double(p.rounds) : 0.0
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(p.label.isEmpty ? "\(p.rounds)R（\(p.balls)玉）" : p.label)
                                    .font(.subheadline)
                                Text("実質 \(netBalls) 個（1Rあたり \(String(format: "%.0f", netPerR)) 玉）")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                if p.balls != netBalls {
                                    Text("メーカー公表値では \(p.balls) 個ですが、実質は \(netBalls) 個です")
                                        .font(.caption2)
                                        .foregroundStyle(.orange)
                                }
                            }
                            Spacer()
                            Button(role: .destructive) {
                                draftPrizes.removeAll { $0.id == p.id }
                            } label: {
                                Image(systemName: "trash")
                            }
                        }
                    }
                }
                Button {
                    showAddPrizePicker = true
                } label: {
                    Label("ライブラリから追加", systemImage: "plus.circle")
                }
            }

            Section("その他スペック") {
                if selectedMachineType == .st {
                    LabeledContent("電サポ回数") {
                        HStack(spacing: 8) {
                            TextField("160", text: $supportLimit)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                            PasteButton(binding: $supportLimit)
                        }
                    }
                }
                LabeledContent("通常後の時短回数") {
                    HStack(spacing: 8) {
                        TextField("0", text: $timeShortRotations)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                        PasteButton(binding: $timeShortRotations)
                    }
                }
                .help("通常大当たり後の時短ゲーム数。この間は球を消費せず、終了後から通常回転にカウントされます")
                LabeledContent("1Rあたり純増出玉") {
                    HStack(spacing: 8) {
                        TextField("140", text: $netPerRoundBaseStr)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                        PasteButton(binding: $netPerRoundBaseStr)
                    }
                }
                .help("純増ベース。打ち出しを差し引いた値でボーダーを算出するため、他アプリより辛め（正確）になります")
                LabeledContent("カウント数（賞球数）") {
                    HStack(spacing: 8) {
                        TextField("10", text: $countPerRoundStr)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                        PasteButton(binding: $countPerRoundStr)
                    }
                }
                .help("打ち出し = ラウンド数×この値。10カウント=10、15賞球=15")
                LabeledContent("払い出し（公表・デフォルト）") {
                    HStack(spacing: 8) {
                        TextField("1400", text: $defaultPrize)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                        PasteButton(binding: $defaultPrize)
                    }
                }
                if let payout = Int(defaultPrize), let count = Int(countPerRoundStr), count > 0 {
                    let roundsDefault = 10
                    let netDefault = max(0, payout - (roundsDefault * count))
                    if netDefault != payout {
                        Text("メーカー公表値では \(payout) 個ですが、実質は \(netDefault) 個です（\(roundsDefault)R×\(count)カウントで算出）")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
                LabeledContent("メーカー（分析用）") {
                    TextField("例: サミー", text: $manufacturerStr)
                        .keyboardType(.default)
                        .multilineTextAlignment(.trailing)
                }
                LabeledContent("ボーダー（公表）") {
                    HStack(spacing: 8) {
                        TextField("16.5", text: $border)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                        PasteButton(binding: $border)
                    }
                }
                Text("等価（4円/玉・250玉/1000円）の場合の回転/1000円を入力。店の貸玉料金・交換率で実戦ボーダーは自動補正されます。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("実戦用（動的ボーダー）") {
                Text("突入率・継続率・平均出玉で実戦ボーダーを補正。空欄は公表ベース。").font(.caption).foregroundStyle(.secondary)
                LabeledContent("突入率（%）") {
                    TextField("100", text: $entryRateStr)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                }
                LabeledContent("継続率（%）") {
                    TextField("100", text: $continuationRateStr)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                }
                LabeledContent("平均出玉") {
                    TextField("空で公表値", text: $averagePrizeStr)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                }
            }

            Section("マイプリセット") {
                Button("現在の設定をマイプリセットに保存") {
                    myPresetNameToSave = machineName.isEmpty ? "未保存" : machineName
                    showSaveMyPreset = true
                }
                if !myPresets.isEmpty {
                    ForEach(myPresets) { preset in
                        Button {
                            applyMyPreset(preset)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(preset.name).font(.subheadline)
                                    Text("\(preset.roundConfigLabel) / 確率 \(preset.probability) / 1R純増 \(Int(preset.netPerRoundBase))")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "arrow.down.circle")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }

            Section("登録済み機種からコピー") {
                TextField("機種名で検索", text: $copySearchText)
                    .textContentType(.none)
                    .autocapitalization(.none)
                if !filteredMachinesForCopy.isEmpty {
                    ForEach(filteredMachinesForCopy, id: \.persistentModelID) { machine in
                        Button {
                            copyFromMachine(machine)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(machine.name).font(.subheadline)
                                    Text("確率 \(machine.probability) / 1R純増 \(String(format: "%.0f", machine.averageNetPerRound)) 玉")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "doc.on.doc")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .id("machineEditForm")
        .scrollContentBackground(.hidden)
    }

    @State private var showAddPrizePicker = false

    private func openSpecSearch() {
        let name = machineName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        let query = name + " スペック 解析"
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        specSearchURL = URL(string: "https://www.google.com/search?q=\(encoded)")
        showSpecBrowser = true
    }

    /// 直近利用の上位30件（検索空時）。検索時は該当するプリセットをすべて表示。サーバーURLが設定されていればサーバーを優先。
    private var displayPresets: [PresetItem] {
        let key = presetSearchText.trimmingCharacters(in: .whitespaces).lowercased()
        if let server = serverPresets, !server.isEmpty {
            let filtered = key.isEmpty ? server : server.filter { $0.name.lowercased().contains(key) }
            return Array(filtered.prefix(30)).map { PresetItem.server($0) }
        }
        if key.isEmpty {
            let sorted = allPresets.sorted { ($0.lastUsedAt ?? .distantPast) > ($1.lastUsedAt ?? .distantPast) }
            return Array(sorted.prefix(30)).map { PresetItem.local($0) }
        }
        return allPresets.filter { $0.name.lowercased().contains(key) }.map { PresetItem.local($0) }
    }

    private func adoptPreset(_ item: PresetItem) {
        switch item {
        case .server(let s):
            machineName = s.name
            selectedMachineType = MachineType(rawValue: s.machineTypeRaw ?? "") ?? .kakugen
            supportLimit = "\(s.supportLimit ?? 160)"
            timeShortRotations = "\(s.timeShortRotations ?? 0)"
            defaultPrize = "\(s.defaultPrize ?? 1500)"
            probability = s.probability ?? ""
            border = s.border ?? ""
            draftPrizes = (s.prizeEntries ?? []).map {
                DraftPrize(label: $0.label ?? "", rounds: $0.rounds, balls: $0.balls)
            }
            let serverAvg = PresetService.averageNetPerRound(s)
            netPerRoundBaseStr = serverAvg > 0 ? String(format: "%.0f", serverAvg) : "140"
            countPerRoundStr = "10"
        case .local(let preset):
            preset.lastUsedAt = Date()
            machineName = preset.name
            selectedMachineType = preset.machineType
            supportLimit = "\(preset.supportLimit)"
            timeShortRotations = "\(preset.timeShortRotations)"
            defaultPrize = "\(preset.defaultPrize)"
            probability = preset.probability
            border = preset.border
            draftPrizes = preset.prizeEntries.map {
                DraftPrize(label: $0.label, rounds: $0.rounds, balls: $0.balls)
            }
            netPerRoundBaseStr = preset.averageNetPerRound > 0 ? String(format: "%.0f", preset.averageNetPerRound) : "140"
            countPerRoundStr = "10"
        }
    }

    private var filteredMachinesForCopy: [Machine] {
        let key = copySearchText.trimmingCharacters(in: .whitespaces).lowercased()
        if key.isEmpty { return Array(savedMachines.prefix(20)) }
        return savedMachines.filter { $0.name.lowercased().contains(key) }
    }

    private func applyMyPreset(_ preset: MyMachinePreset) {
        preset.lastUsedAt = Date()
        machineName = preset.name
        selectedMachineType = preset.machineType
        supportLimit = "\(preset.supportLimit)"
        timeShortRotations = "\(preset.timeShortRotations)"
        defaultPrize = "\(preset.defaultPrize)"
        probability = preset.probability
        border = preset.border
        entryRateStr = String(format: "%.2f", preset.entryRate)
        continuationRateStr = String(format: "%.2f", preset.continuationRate)
        averagePrizeStr = preset.averagePrize > 0 ? String(format: "%.2f", preset.averagePrize) : ""
        netPerRoundBaseStr = preset.netPerRoundBase > 0 ? String(format: "%.0f", preset.netPerRoundBase) : "140"
        countPerRoundStr = "\(preset.countPerRound)"
        let balls = Int(round(Double(preset.defaultRounds) * preset.netPerRoundBase))
        draftPrizes = [DraftPrize(label: "\(preset.defaultRounds)R", rounds: preset.defaultRounds, balls: balls)]
    }

    private func saveAsMyPreset(name: String) {
        let preset = MyMachinePreset()
        preset.name = name.trimmingCharacters(in: .whitespaces).isEmpty ? "マイプリセット" : name
        preset.probability = probability
        preset.defaultRounds = draftPrizes.first?.rounds ?? 10
        preset.countPerRound = Int(countPerRoundStr) ?? 10
        preset.netPerRoundBase = Double(netPerRoundBaseStr) ?? 140
        preset.machineTypeRaw = selectedMachineType.rawValue
        preset.supportLimit = Int(supportLimit) ?? 160
        preset.timeShortRotations = Int(timeShortRotations) ?? 0
        preset.defaultPrize = Int(defaultPrize) ?? 1500
        preset.border = border
        preset.entryRate = Double(entryRateStr) ?? 100
        preset.continuationRate = Double(continuationRateStr) ?? 100
        preset.averagePrize = Double(averagePrizeStr) ?? 0
        preset.lastUsedAt = Date()
        modelContext.insert(preset)
        showSaveMyPreset = false
        myPresetNameToSave = ""
    }

    private func loadMachineIntoForm(_ machine: Machine) {
        machineName = machine.name
        copyFromMachine(machine)
    }

    private func copyFromMachine(_ machine: Machine) {
        selectedMachineType = machine.machineType
        supportLimit = "\(machine.supportLimit)"
        timeShortRotations = "\(machine.timeShortRotations)"
        defaultPrize = "\(machine.defaultPrize)"
        probability = machine.probability
        border = machine.border
        manufacturerStr = machine.manufacturer
        entryRateStr = String(format: "%.2f", machine.entryRate)
        continuationRateStr = String(format: "%.2f", machine.continuationRate)
        averagePrizeStr = machine.averagePrize > 0 ? String(format: "%.2f", machine.averagePrize) : ""
        netPerRoundBaseStr = machine.netPerRoundBase > 0 ? String(format: "%.0f", machine.netPerRoundBase) : ""
        countPerRoundStr = "\(machine.countPerRound)"
        draftPrizes = machine.prizeEntries.map {
            DraftPrize(label: $0.label, rounds: $0.rounds, balls: $0.balls)
        }
    }

    private func saveMachine() {
        let name = machineName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        let sup = Int(supportLimit) ?? 160
        let prize = Int(defaultPrize) ?? 1500

        if let existing = editing {
            existing.name = name
            existing.supportLimit = sup
            existing.timeShortRotations = Int(timeShortRotations) ?? 0
            existing.defaultPrize = prize
            existing.machineTypeRaw = selectedMachineType.rawValue
            existing.probability = probability
            existing.border = border
            existing.entryRate = Double(entryRateStr) ?? 100
            existing.continuationRate = Double(continuationRateStr) ?? 100
            existing.averagePrize = Double(averagePrizeStr) ?? 0
            let netStr = netPerRoundBaseStr.trimmingCharacters(in: .whitespaces)
            existing.netPerRoundBase = netStr.isEmpty ? 0 : (Double(netStr) ?? 140)
            existing.countPerRound = Int(countPerRoundStr) ?? 10
            existing.manufacturer = manufacturerStr.trimmingCharacters(in: .whitespaces)
            for p in existing.prizeEntries {
                modelContext.delete(p)
            }
            for p in draftPrizes {
                let mp = MachinePrize(label: p.label, rounds: p.rounds, balls: p.balls)
                mp.machine = existing
                modelContext.insert(mp)
            }
        } else {
            let machine = Machine(name: name, supportLimit: sup, defaultPrize: prize)
            machine.timeShortRotations = Int(timeShortRotations) ?? 0
            machine.machineTypeRaw = selectedMachineType.rawValue
            machine.probability = probability
            machine.border = border
            machine.entryRate = Double(entryRateStr) ?? 100
            machine.continuationRate = Double(continuationRateStr) ?? 100
            machine.averagePrize = Double(averagePrizeStr) ?? 0
            let netStr = netPerRoundBaseStr.trimmingCharacters(in: .whitespaces)
            machine.netPerRoundBase = netStr.isEmpty ? 0 : (Double(netStr) ?? 140)
            machine.countPerRound = Int(countPerRoundStr) ?? 10
            machine.manufacturer = manufacturerStr.trimmingCharacters(in: .whitespaces)
            modelContext.insert(machine)
            for p in draftPrizes {
                let mp = MachinePrize(label: p.label, rounds: p.rounds, balls: p.balls)
                mp.machine = machine
                modelContext.insert(mp)
            }
        }
        dismiss()
    }
}

// MARK: - ライブラリから当たり種類を選ぶシート
struct PrizePickerSheet: View {
    let prizeSets: [PrizeSet]
    let onSelect: (PrizeSet) -> Void
    let onDismiss: () -> Void

    var body: some View {
        NavigationStack {
            List(prizeSets, id: \.persistentModelID) { ps in
                Button {
                    onSelect(ps)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(ps.name.isEmpty ? "\(ps.rounds)R（\(ps.balls)玉）" : ps.name)
                                .font(.subheadline)
                            Text("1Rあたり \(String(format: "%.0f", ps.netPerRound)) 玉")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(.blue)
                    }
                }
            }
            .navigationTitle("当たり種類を選択")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { onDismiss() }
                }
            }
            .overlay {
                if prizeSets.isEmpty {
                    ContentUnavailableView(
                        "ライブラリが空です",
                        systemImage: "tray",
                        description: Text("「当たり種類ライブラリを管理」で先に登録してください")
                    )
                }
            }
        }
    }
}

// MARK: - 貼り付けボタン（クリップボードの内容を一撃で入力）
struct PasteButton: View {
    @Binding var binding: String

    var body: some View {
        Button {
            if let s = UIPasteboard.general.string, !s.isEmpty {
                binding = s.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        } label: {
            Text("貼り付け")
                .font(.caption)
        }
        .buttonStyle(.bordered)
    }
}

// MARK: - 分割画面用アプリ内ブラウザ（WKWebView）
struct InAppWebView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
}

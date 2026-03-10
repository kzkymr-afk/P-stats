import SwiftUI
import SwiftData

/// ボーナス種類ライブラリの一覧・追加・編集
struct PrizeSetListView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor(\PrizeSet.displayOrder), SortDescriptor(\PrizeSet.name)]) private var prizeSets: [PrizeSet]

    @State private var showAdd = false
    @State private var editingSet: PrizeSet?
    @State private var newName = ""
    @State private var newRounds = "10"
    @State private var newBalls = "1500"

    var body: some View {
        List {
            Section {
                Text("例: 10R×150玉＝1500玉。並び順はドラッグで変更できます。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(prizeSets, id: \.persistentModelID) { ps in
                Button {
                    editingSet = ps
                } label: {
                    HStack {
                        Image(systemName: "line.3.horizontal")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(ps.name.isEmpty ? "\(ps.rounds)R（\(ps.balls)玉）" : ps.name)
                                .font(.subheadline)
                            Text("1Rあたり \(String(format: "%.0f", ps.netPerRound)) 玉")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        modelContext.delete(ps)
                    } label: {
                        Label("削除", systemImage: "trash")
                    }
                }
            }
            .onMove(perform: movePrizeSets)
        }
        .navigationTitle("ボーナス種類ライブラリ")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("追加") {
                    newName = ""
                    newRounds = "10"
                    newBalls = "1500"
                    showAdd = true
                }
            }
        }
        .sheet(isPresented: $showAdd) {
            PrizeSetEditSheet(name: $newName, rounds: $newRounds, balls: $newBalls, title: "新規追加") {
                let r = Int(newRounds) ?? 10
                let b = Int(newBalls) ?? 1500
                let name = newName.trimmingCharacters(in: .whitespaces)
                let label = name.isEmpty ? "\(r)R（\(b)玉）" : name
                let ps = PrizeSet(name: label, rounds: r, balls: b)
                ps.displayOrder = (prizeSets.map(\.displayOrder).max() ?? -1) + 1
                modelContext.insert(ps)
                showAdd = false
            }
        }
        .sheet(item: $editingSet) { ps in
            PrizeSetEditSheetExisting(existing: ps) {
                editingSet = nil
            }
        }
    }

    private func movePrizeSets(from source: IndexSet, to destination: Int) {
        var ordered = prizeSets
        ordered.move(fromOffsets: source, toOffset: destination)
        for (index, ps) in ordered.enumerated() {
            ps.displayOrder = index
        }
    }
}

/// ボーナス種類の名前・R・玉数を入力するシート（新規用）
struct PrizeSetEditSheet: View {
    @Binding var name: String
    @Binding var rounds: String
    @Binding var balls: String
    let title: String
    let onSave: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("表示名（任意）") {
                    TextField("例: 10R（1500玉）", text: $name)
                }
                Section("数値") {
                    LabeledContent("回数（R）") {
                        TextField("10", text: $rounds)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                    }
                    LabeledContent("出玉（玉）") {
                        TextField("1500", text: $balls)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                    }
                }
            }
            .navigationTitle(title)
            .keyboardDismissToolbar()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { onSave() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { onSave() }
                }
            }
        }
    }
}

/// 既存 PrizeSet を編集するシート
struct PrizeSetEditSheetExisting: View {
    @Bindable var existing: PrizeSet
    let onDone: () -> Void
    @State private var name: String = ""
    @State private var rounds: String = "10"
    @State private var balls: String = "1500"

    var body: some View {
        NavigationStack {
            Form {
                Section("表示名（任意）") {
                    TextField("例: 10R（1500玉）", text: $name)
                }
                Section("数値") {
                    LabeledContent("回数（R）") {
                        TextField("10", text: $rounds)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                    }
                    LabeledContent("出玉（玉）") {
                        TextField("1500", text: $balls)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                    }
                }
            }
            .navigationTitle("編集")
            .keyboardDismissToolbar()
            .onAppear {
                name = existing.name
                rounds = "\(existing.rounds)"
                balls = "\(existing.balls)"
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { onDone() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        existing.name = name
                        existing.rounds = Int(rounds) ?? 10
                        existing.balls = Int(balls) ?? 1500
                        onDone()
                    }
                }
            }
        }
    }
}

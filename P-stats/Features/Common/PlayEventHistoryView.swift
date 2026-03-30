import SwiftUI
import SwiftData
import UIKit

// MARK: - 大当たり・投資履歴（スワイプ削除・タップで編集）
struct PlayEventHistoryView: View {
    @Bindable var log: GameLog
    let onDismiss: () -> Void

    @State private var editWinId: UUID?
    @State private var editLendingId: UUID?
    @State private var editRotation: String = ""
    @State private var editPrize: String = ""
    @State private var editWinType: WinType = .normal
    @State private var editLendingType: LendingType = .cash
    @State private var editLendingBalls: String = ""
    @State private var editWinRotationPadTrigger = 0
    @State private var editWinPrizePadTrigger = 0
    @State private var editLendingBallsPadTrigger = 0

    private let accent = AppGlassStyle.accent

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(log.winRecords.sorted { ($0.timestamp ?? .distantPast) > ($1.timestamp ?? .distantPast) }) { record in
                        winRow(record)
                            .contentShape(Rectangle())
                            .onTapGesture { openEditWin(record) }
                    }
                    .onDelete(perform: deleteWins)
                } header: {
                    Text("大当たり履歴")
                        .font(AppTypography.panelHeading)
                        .foregroundStyle(.white.opacity(0.95))
                }
                Section {
                    ForEach(log.lendingRecords.sorted { $0.timestamp > $1.timestamp }) { record in
                        lendingRow(record)
                            .contentShape(Rectangle())
                            .onTapGesture { openEditLending(record) }
                    }
                    .onDelete(perform: deleteLendings)
                } header: {
                    Text("投資履歴")
                        .font(AppTypography.panelHeading)
                        .foregroundStyle(.white.opacity(0.95))
                }
            }
            .navigationTitle("大当たり・投資履歴")
            .navigationBarTitleDisplayMode(.inline)
            .keyboardDismissToolbar()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        onDismiss()
                    } label: {
                        Text("＜　実戦へ戻る")
                    }
                    .foregroundColor(accent)
                }
            }
            .sheet(isPresented: Binding(get: { editWinId != nil }, set: { if !$0 { editWinId = nil } })) {
                if let id = editWinId {
                    winEditSheet(winId: id)
                }
            }
            .sheet(isPresented: Binding(get: { editLendingId != nil }, set: { if !$0 { editLendingId = nil } })) {
                if let id = editLendingId {
                    lendingEditSheet(lendingId: id)
                }
            }
        }
    }

    private func winRow(_ record: WinRecord) -> some View {
        HStack {
            Text(record.type == .rush ? "RUSH" : "通常")
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundColor(record.type == .rush ? .red : .blue)
            Spacer()
            Text("\(record.rotationAtWin) G")
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(.secondary)
            Text("\(record.prize ?? 0) 玉")
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }

    private func lendingRow(_ record: LendingRecord) -> some View {
        HStack {
            Text(record.type == .cash ? "現金" : "持ち玉")
                .font(.system(size: 12, weight: .medium, design: .monospaced))
            Spacer()
            if record.type == .cash {
                Text("500pt")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.secondary)
            } else {
                Text("\(record.balls ?? 125) 玉")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private func openEditWin(_ record: WinRecord) {
        editWinId = record.id
        editWinType = record.type
        editRotation = "\(record.rotationAtWin)"
        editPrize = "\(record.prize ?? 0)"
    }

    private func openEditLending(_ record: LendingRecord) {
        editLendingId = record.id
        editLendingType = record.type
        editLendingBalls = record.type == .holdings ? "\(record.balls ?? 125)" : ""
    }

    private func deleteWins(at offsets: IndexSet) {
        let sorted = log.winRecords.sorted { ($0.timestamp ?? .distantPast) > ($1.timestamp ?? .distantPast) }
        let idsToDelete = offsets.compactMap { $0 < sorted.count ? sorted[$0].id : nil }
        for id in idsToDelete {
            log.deleteWinRecord(id: id)
        }
    }

    private func deleteLendings(at offsets: IndexSet) {
        let sorted = log.lendingRecords.sorted { $0.timestamp > $1.timestamp }
        let idsToDelete = offsets.compactMap { $0 < sorted.count ? sorted[$0].id : nil }
        for id in idsToDelete {
            log.deleteLendingRecord(id: id)
        }
    }

    @ViewBuilder
    private func winEditSheet(winId: UUID) -> some View {
        if let record = log.winRecords.first(where: { $0.id == winId }) {
            let rotBinding = Binding(get: { editRotation }, set: { editRotation = $0 })
            let prizeBinding = Binding(get: { editPrize }, set: { editPrize = $0 })
            NavigationStack {
                Form {
                    Section("種別") {
                        Picker("種別", selection: $editWinType) {
                            Text("通常").tag(WinType.normal)
                            Text("RUSH").tag(WinType.rush)
                        }
                        .pickerStyle(.segmented)
                    }
                    Section("回転数") {
                        IntegerPadTextField(
                            text: rotBinding,
                            placeholder: "回転数",
                            maxDigits: 7,
                            font: .preferredFont(forTextStyle: .body),
                            textColor: UIColor.label,
                            accentColor: UIColor(accent),
                            focusTrigger: editWinRotationPadTrigger,
                            onPreviousField: { editWinPrizePadTrigger += 1 },
                            onNextField: { editWinPrizePadTrigger += 1 }
                        )
                    }
                    Section("出玉数（玉）") {
                        IntegerPadTextField(
                            text: prizeBinding,
                            placeholder: "出玉数",
                            maxDigits: 7,
                            font: .preferredFont(forTextStyle: .body),
                            textColor: UIColor.label,
                            accentColor: UIColor(accent),
                            focusTrigger: editWinPrizePadTrigger,
                            onPreviousField: { editWinRotationPadTrigger += 1 },
                            onNextField: { editWinRotationPadTrigger += 1 }
                        )
                    }
                }
                .navigationTitle("大当たりを編集")
                .navigationBarTitleDisplayMode(.inline)
                .keyboardDismissToolbar()
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("キャンセル") { editWinId = nil }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("完了") {
                            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                            if let r = Int(editRotation), let p = Int(editPrize), r >= 0, p >= 0 {
                                log.updateWinRotation(id: winId, rotationAtWin: r)
                                log.updatePrize(id: winId, newPrize: p)
                                log.updateWinType(id: winId, newType: editWinType)
                            }
                            editWinId = nil
                        }
                    }
                }
                .onAppear {
                    editWinType = record.type
                    editRotation = "\(record.rotationAtWin)"
                    editPrize = "\(record.prize ?? 0)"
                    editWinRotationPadTrigger += 1
                }
            }
        }
    }

    @ViewBuilder
    private func lendingEditSheet(lendingId: UUID) -> some View {
        if let record = log.lendingRecords.first(where: { $0.id == lendingId }) {
            NavigationStack {
                Form {
                    Section("種別") {
                        Picker("種別", selection: $editLendingType) {
                            Text("現金").tag(LendingType.cash)
                            Text("持ち玉").tag(LendingType.holdings)
                        }
                        .pickerStyle(.segmented)
                    }
                    if editLendingType == .holdings {
                        Section("玉数") {
                            IntegerPadTextField(
                                text: $editLendingBalls,
                                placeholder: "玉数",
                                maxDigits: 6,
                                font: .preferredFont(forTextStyle: .body),
                                textColor: UIColor.label,
                                accentColor: UIColor(accent),
                                focusTrigger: editLendingBallsPadTrigger
                            )
                        }
                    }
                }
                .navigationTitle("投資を編集")
                .navigationBarTitleDisplayMode(.inline)
                .keyboardDismissToolbar()
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("キャンセル") { editLendingId = nil }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("完了") {
                            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                            let balls: Int? = editLendingType == .holdings ? Int(editLendingBalls).map { max(0, $0) } : nil
                            log.replaceLendingRecord(id: lendingId, type: editLendingType, balls: balls ?? (editLendingType == .holdings ? 125 : nil))
                            editLendingId = nil
                        }
                    }
                }
                .onAppear {
                    editLendingType = record.type
                    editLendingBalls = record.type == .holdings ? "\(record.balls ?? 125)" : ""
                    editLendingBallsPadTrigger += 1
                }
            }
        }
    }
}


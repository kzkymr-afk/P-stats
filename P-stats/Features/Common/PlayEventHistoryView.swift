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
    @State private var editHitCount: String = ""
    @State private var editLendingType: LendingType = .cash
    @State private var editLendingBalls: String = ""
    @State private var editWinHitCountPadTrigger = 0
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

    @ViewBuilder
    private func winRow(_ record: WinRecord) -> some View {
        let hits = max(1, record.bonusSessionHitCount ?? 1)
        let kind = hits >= 2 ? "RUSH" : "通常"
        HStack {
            Text(kind)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundColor(hits >= 2 ? .red : .blue)
            Text("×\(hits)")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundColor(.secondary)
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
            Text(record.type.compactHistoryLabel)
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
        editRotation = "\(record.rotationAtWin)"
        editPrize = "\(record.prize ?? 0)"
        editHitCount = "\(max(1, record.bonusSessionHitCount ?? 1))"
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
        if log.winRecords.first(where: { $0.id == winId }) != nil {
            let rotBinding = Binding(get: { editRotation }, set: { editRotation = $0 })
            let prizeBinding = Binding(get: { editPrize }, set: { editPrize = $0 })
            let hitBinding = Binding(get: { editHitCount }, set: { editHitCount = $0 })
            NavigationStack {
                Form {
                    Section {
                        IntegerPadTextField(
                            text: hitBinding,
                            placeholder: "回数",
                            maxDigits: 5,
                            font: .preferredFont(forTextStyle: .body),
                            textColor: UIColor.label,
                            accentColor: UIColor(accent),
                            focusTrigger: editWinHitCountPadTrigger,
                            onNextField: { editWinPrizePadTrigger += 1 }
                        )
                    } header: {
                        Text("この区間の大当たり回数")
                    } footer: {
                        Text("1 回＝通常、2 回以上＝ RUSH（連チャン）として扱います。")
                    }
                    Section {
                        IntegerPadTextField(
                            text: prizeBinding,
                            placeholder: "玉",
                            maxDigits: 9,
                            font: .preferredFont(forTextStyle: .body),
                            textColor: UIColor.label,
                            accentColor: UIColor(accent),
                            focusTrigger: editWinPrizePadTrigger,
                            onPreviousField: { editWinHitCountPadTrigger += 1 },
                            onNextField: { editWinRotationPadTrigger += 1 }
                        )
                    } header: {
                        Text("総獲得出玉（玉）")
                    }
                    Section {
                        IntegerPadTextField(
                            text: rotBinding,
                            placeholder: "回転数",
                            maxDigits: 7,
                            font: .preferredFont(forTextStyle: .body),
                            textColor: UIColor.label,
                            accentColor: UIColor(accent),
                            focusTrigger: editWinRotationPadTrigger,
                            onPreviousField: { editWinPrizePadTrigger += 1 },
                            onNextField: { editWinHitCountPadTrigger += 1 }
                        )
                    } header: {
                        Text("当選時の総回転（ランプ）")
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
                            let rTrim = editRotation.trimmingCharacters(in: .whitespaces)
                            let pTrim = editPrize.trimmingCharacters(in: .whitespaces)
                            let hTrim = editHitCount.trimmingCharacters(in: .whitespaces)
                            if let r = Int(rTrim), let p = Int(pTrim), let h = Int(hTrim),
                               r >= 0, p >= 0, h >= 1 {
                                log.updateWinRotation(id: winId, rotationAtWin: r)
                                log.updateWinSessionHitsAndPrize(winId: winId, hitCount: h, totalPrizeBalls: p)
                            }
                            editWinId = nil
                        }
                    }
                }
                .onAppear {
                    editWinHitCountPadTrigger += 1
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


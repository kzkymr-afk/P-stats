import SwiftUI
import UIKit

/// 今回の遊技内の大当たり区間（`WinRecord`）を選び、当たり回数（1＝通常・2 以上＝ RUSH）と総獲得出玉を修正する。
struct WinSessionHitPrizeEditSheet: View {
    @Bindable var log: GameLog
    /// nil のときは一覧から選択。
    let initialWinId: UUID?
    /// 棒グラフなどから開いたとき true。一覧に戻らず閉じるのみ（無効な ID のときは false のまま一覧へ）。
    let formOnlyMode: Bool
    let accentColor: Color
    let onDismiss: () -> Void

    @EnvironmentObject private var themeManager: ThemeManager
    @State private var selectedWinId: UUID?
    @State private var hitCountText = ""
    @State private var prizeText = ""
    @State private var hitPadTrigger = 0
    @State private var prizePadTrigger = 0
    @State private var showValidationAlert = false
    @State private var validationMessage = ""

    init(
        log: GameLog,
        initialWinId: UUID?,
        formOnlyMode: Bool,
        accentColor: Color,
        onDismiss: @escaping () -> Void
    ) {
        self._log = Bindable(log)
        self.initialWinId = initialWinId
        self.formOnlyMode = formOnlyMode
        self.accentColor = accentColor
        self.onDismiss = onDismiss
        let start = Self.resolveStart(log: log, initialWinId: initialWinId, formOnlyMode: formOnlyMode)
        _selectedWinId = State(initialValue: start.id)
        _hitCountText = State(initialValue: start.hitText)
        _prizeText = State(initialValue: start.prizeText)
    }

    private var isProvisional: Bool {
        guard let id = selectedWinId else { return false }
        return id == GameLog.provisionalBigHitChartId
    }

    var body: some View {
        let t = themeManager.currentTheme
        NavigationStack {
            Group {
                if selectedWinId == nil {
                    sessionListView(theme: t)
                } else {
                    formView(theme: t)
                }
            }
            .toolbarBackground(Color.black.opacity(DesignTokens.Surface.BlackOverlay.playToolbarBackground), for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .alert("入力を確認してください", isPresented: $showValidationAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(validationMessage)
        }
    }

    @ViewBuilder
    private func sessionListView(theme: any ApplicationTheme) -> some View {
        List {
            if log.isBigHitMode, log.bigHitChainCount > 0 {
                Button {
                    selectSession(GameLog.provisionalBigHitChartId)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("現在の大当たり（未確定）")
                            .font(theme.themedFont(size: 16, weight: .semibold))
                            .foregroundColor(theme.mainTextColor)
                        Text("連チャン \(log.bigHitChainCount) 回・確定後に出玉を記録できます")
                            .font(theme.themedFont(size: 12, weight: .regular))
                            .foregroundColor(theme.subTextColor)
                    }
                }
            }
            if log.winRecords.isEmpty, !log.isBigHitMode {
                Text("まだ確定した大当たり区間がありません")
                    .font(theme.themedFont(size: 14, weight: .regular))
                    .foregroundColor(theme.subTextColor)
                    .listRowBackground(Color.clear)
            }
            ForEach(Array(log.winRecords.enumerated()), id: \.element.id) { index, rec in
                Button {
                    selectSession(rec.id)
                } label: {
                    sessionRow(theme: theme, index: index + 1, record: rec)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(theme.panelBackground.opacity(DesignTokens.Surface.WhiteOnDark.formMuted))
        .navigationTitle("区間を選択")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("閉じる") { onDismiss() }
                    .foregroundColor(accentColor)
            }
        }
    }

    private func sessionRow(theme: any ApplicationTheme, index: Int, record: WinRecord) -> some View {
        let hits = max(1, record.bonusSessionHitCount ?? 1)
        let kind = hits >= 2 ? "RUSH（連チャン）" : "通常"
        let prize = record.prize.map { "\($0) 玉" } ?? "—"
        return VStack(alignment: .leading, spacing: 4) {
            Text("第 \(index) 区間")
                .font(theme.themedFont(size: 16, weight: .semibold))
                .foregroundColor(theme.mainTextColor)
            Text("\(kind)・当たり \(hits) 回・獲得出玉 \(prize)")
                .font(theme.themedFont(size: 12, weight: .regular))
                .foregroundColor(theme.subTextColor)
        }
    }

    @ViewBuilder
    private func formView(theme: any ApplicationTheme) -> some View {
        Form {
            Section {
                IntegerPadTextField(
                    text: $hitCountText,
                    placeholder: "回数",
                    maxDigits: 5,
                    font: .preferredFont(forTextStyle: .body),
                    textColor: UIColor.label,
                    accentColor: UIColor(accentColor),
                    focusTrigger: hitPadTrigger,
                    onNextField: { prizePadTrigger += 1 }
                )
            } header: {
                Text("この区間の大当たり回数")
            } footer: {
                Text("1 回＝通常、2 回以上＝ RUSH（連チャン）として扱います。")
            }
            Section {
                IntegerPadTextField(
                    text: $prizeText,
                    placeholder: "玉",
                    maxDigits: 9,
                    font: .preferredFont(forTextStyle: .body),
                    textColor: UIColor.label,
                    accentColor: UIColor(accentColor),
                    focusTrigger: prizePadTrigger,
                    onPreviousField: { hitPadTrigger += 1 },
                    isEnabled: !isProvisional
                )
            } header: {
                Text("この区間の総獲得出玉（玉）")
            } footer: {
                if isProvisional {
                    Text("未確定の区間は、大当たり確定時に総獲得出玉を入力してください。")
                } else {
                    Text("0 以上の整数で入力してください。")
                }
            }
        }
        .navigationTitle("大当たりを修正")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                if formOnlyMode {
                    Button("閉じる") { onDismiss() }
                        .foregroundColor(accentColor)
                } else {
                    Button("戻る") {
                        selectedWinId = nil
                    }
                    .foregroundColor(accentColor)
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("保存") { save() }
                    .fontWeight(.semibold)
                    .foregroundColor(accentColor)
            }
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                hitPadTrigger += 1
            }
        }
    }

    private func selectSession(_ id: UUID) {
        selectedWinId = id
        if id == GameLog.provisionalBigHitChartId {
            hitCountText = "\(max(1, log.bigHitChainCount))"
            prizeText = ""
        } else if let rec = log.winRecords.first(where: { $0.id == id }) {
            let hits = max(1, rec.bonusSessionHitCount ?? 1)
            hitCountText = "\(hits)"
            prizeText = "\(rec.prize ?? 0)"
        }
    }

    private func save() {
        UIApplication.dismissKeyboard()
        guard let id = selectedWinId else { return }
        let hTrim = hitCountText.trimmingCharacters(in: .whitespaces)
        guard let h = Int(hTrim), h >= 1 else {
            validationMessage = "大当たり回数は 1 以上の整数で入力してください。"
            showValidationAlert = true
            return
        }
        if id == GameLog.provisionalBigHitChartId {
            guard log.isBigHitMode else {
                validationMessage = "大当たりモード中のみ修正できます。"
                showValidationAlert = true
                return
            }
            log.bigHitChainCount = h
            onDismiss()
            return
        }
        let pTrim = prizeText.trimmingCharacters(in: .whitespaces)
        guard let p = Int(pTrim), p >= 0 else {
            validationMessage = "総獲得出玉は 0 以上の整数で入力してください。"
            showValidationAlert = true
            return
        }
        log.updateWinSessionHitsAndPrize(winId: id, hitCount: h, totalPrizeBalls: p)
        onDismiss()
    }

    private struct StartValues {
        let id: UUID?
        let hitText: String
        let prizeText: String
    }

    private static func resolveStart(log: GameLog, initialWinId: UUID?, formOnlyMode: Bool) -> StartValues {
        guard formOnlyMode, let wid = initialWinId else {
            return StartValues(id: nil, hitText: "", prizeText: "")
        }
        if wid == GameLog.provisionalBigHitChartId {
            guard log.isBigHitMode else {
                return StartValues(id: nil, hitText: "", prizeText: "")
            }
            return StartValues(
                id: wid,
                hitText: "\(max(1, log.bigHitChainCount))",
                prizeText: ""
            )
        }
        guard let rec = log.winRecords.first(where: { $0.id == wid }) else {
            return StartValues(id: nil, hitText: "", prizeText: "")
        }
        let hits = max(1, rec.bonusSessionHitCount ?? 1)
        return StartValues(id: wid, hitText: "\(hits)", prizeText: "\(rec.prize ?? 0)")
    }
}

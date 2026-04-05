import SwiftUI
import SwiftData
import UIKit

private struct PhaseDraft: Identifiable, Equatable {
    var id: UUID
    var rotationsUntilFirstHit: String
    var investmentCashPt: String
    var investmentHoldingsBalls: String
    var bigHitCount: String
    var recoveryHoldingsBalls: String

    static func empty(id: UUID = UUID()) -> PhaseDraft {
        PhaseDraft(id: id, rotationsUntilFirstHit: "", investmentCashPt: "", investmentHoldingsBalls: "", bigHitCount: "", recoveryHoldingsBalls: "")
    }
}

private struct SimpleTimelineDraft: Identifiable, Equatable {
    var id: UUID
    var kind: SimplePlayTimelineRowKind
    var investmentRotationsStr: String
    var hitCountStr: String
    var prizeBallsStr: String

    static func normal(id: UUID = UUID()) -> SimpleTimelineDraft {
        SimpleTimelineDraft(id: id, kind: .normal, investmentRotationsStr: "", hitCountStr: "", prizeBallsStr: "")
    }

    static func bonus(id: UUID = UUID()) -> SimpleTimelineDraft {
        SimpleTimelineDraft(id: id, kind: .bonusSession, investmentRotationsStr: "", hitCountStr: "", prizeBallsStr: "")
    }

    static func defaultTriple() -> [SimpleTimelineDraft] {
        [normal(), bonus(), normal()]
    }
}

struct GameSessionEditView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var themeManager: ThemeManager

    @Query private var machines: [Machine]
    @Query private var shops: [Shop]

    let sessionToEdit: GameSession?
    /// 新規のみ `true` 可。既存 `sessionToEdit` がある場合は常に詳細フォームになる。
    let isSimpleInput: Bool

    @State private var date: Date = Date()
    @State private var selectedMachine: Machine?
    @State private var selectedShop: Shop?

    @State private var investmentCash: String = ""
    /// シンプル入力: 回収額（pt）。詳細入力: 最終の総回収出玉
    @State private var recoveryAmountPt: String = ""
    @State private var totalHoldings: String = ""
    /// 詳細のみ。空欄なら各区間の回転合計を総回転として保存
    @State private var totalRotationsOverride: String = ""
    @State private var phases: [PhaseDraft] = [PhaseDraft.empty()]
    @State private var normalWinCount: String = ""
    @State private var showErrorAlert = false
    @State private var errorMessage = ""

    @State private var simpleInvestPadTrigger = 0
    @State private var simpleRecoveryPadTrigger = 0
    @State private var recordSimplePlayTimes = false
    @State private var recordSimpleTimeline = false
    @State private var simplePlayStartedAt = Date()
    @State private var simplePlayEndedAt = Date()
    @State private var simpleTimelineRows: [SimpleTimelineDraft] = SimpleTimelineDraft.defaultTriple()
    @State private var simpleTimelinePadTriggers: [UUID: Int] = [:]

    private var skin: any ApplicationTheme { themeManager.currentTheme }
    private var accent: Color { skin.accentColor }

    init(sessionToEdit: GameSession? = nil, isSimpleInput: Bool? = nil) {
        self.sessionToEdit = sessionToEdit
        // 既存履歴の編集は常に詳細（シンプルは新規のみ）
        if sessionToEdit != nil {
            self.isSimpleInput = false
        } else {
            self.isSimpleInput = isSimpleInput ?? true
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if isSimpleInput {
                    simpleInputRoot
                } else {
                    detailEditRoot
                }
            }
            .navigationTitle(navigationTitleText)
            .navigationBarTitleDisplayMode(.inline)
            .keyboardDismissToolbar()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        if selectedMachine == nil {
                            errorMessage = "機種を選択してください"
                            showErrorAlert = true
                            return
                        }
                        if selectedShop == nil {
                            errorMessage = "店舗を選択してください"
                            showErrorAlert = true
                            return
                        }
                        if isSimpleInput {
                            let inv = Int(investmentCash) ?? 0
                            let rec = Int(recoveryAmountPt) ?? 0
                            if inv < 0 || rec < 0 {
                                errorMessage = "負の数は入力できません"
                                showErrorAlert = true
                                return
                            }
                            let rate = selectedShop?.payoutCoefficient ?? 0
                            if rec > 0, rate <= 0 {
                                errorMessage = "回収額を保存するには店舗の交換率（pt/玉）が必要です。店舗を編集して設定してください。"
                                showErrorAlert = true
                                return
                            }
                        } else {
                            if parsePhasesForSave() == nil {
                                errorMessage = "区間ごとの内訳の数値を確認してください（負の数・未入力は 0 として扱いますが、ブロックは1つ以上必要です）"
                                showErrorAlert = true
                                return
                            }
                            if (Int(totalHoldings) ?? 0) < 0 || (Int(normalWinCount) ?? 0) < 0 {
                                errorMessage = "負の数は入力できません"
                                showErrorAlert = true
                                return
                            }
                            let tor = totalRotationsOverride.trimmingCharacters(in: .whitespaces)
                            if !tor.isEmpty, (Int(tor) ?? -1) < 0 {
                                errorMessage = "負の数は入力できません"
                                showErrorAlert = true
                                return
                            }
                        }
                        save()
                    }
                }
            }
            .alert("入力エラー", isPresented: $showErrorAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage)
            }
            .onAppear {
                guard !isSimpleInput else { return }
                if let s = sessionToEdit {
                    date = s.date
                    selectedMachine = machines.first(where: { $0.name == s.machineName })
                    selectedShop = shops.first(where: { $0.name == s.shopName })
                    totalHoldings = "\(s.totalHoldings)"
                    normalWinCount = "\(s.normalWinCount)"
                    totalRotationsOverride = ""
                    if !s.editSessionPhasesJSON.isEmpty {
                        let decoded = GameSessionEditPhasesStorage.decode(s.editSessionPhasesJSON)
                        phases = decoded.map { p in
                            PhaseDraft(
                                id: p.id,
                                rotationsUntilFirstHit: "\(p.rotationsUntilFirstHit)",
                                investmentCashPt: "\(p.investmentCashPt)",
                                investmentHoldingsBalls: "\(p.investmentHoldingsBalls)",
                                bigHitCount: "\(p.bigHitCount)",
                                recoveryHoldingsBalls: "\(p.recoveryHoldingsBalls)"
                            )
                        }
                    } else {
                        let shop = shops.first(where: { $0.name == s.shopName })
                        let ballsPer1k = shop.map { Double($0.ballsPerCashUnit * 2) } ?? 250.0
                        let cashBalls = Double(s.inputCash) / 1000.0 * ballsPer1k
                        let hBalls = max(0, Int(Double(s.totalUsedBalls) - cashBalls))
                        phases = [
                            PhaseDraft(
                                id: UUID(),
                                rotationsUntilFirstHit: "\(s.normalRotations)",
                                investmentCashPt: "\(s.inputCash)",
                                investmentHoldingsBalls: "\(hBalls)",
                                bigHitCount: "\(s.rushWinCount)",
                                recoveryHoldingsBalls: "\(s.totalHoldings)"
                            )
                        ]
                    }
                } else {
                    phases = [PhaseDraft.empty()]
                    totalRotationsOverride = ""
                    totalHoldings = ""
                    normalWinCount = ""
                }
            }
        }
    }

    private var navigationTitleText: String {
        if isSimpleInput, sessionToEdit == nil { return "シンプル入力" }
        return sessionToEdit == nil ? "過去データを入力" : "履歴を編集"
    }

    private var simpleInputRoot: some View {
        ZStack {
            StaticHomeBackgroundView()
            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 16) {
                        simpleInputCardHeader(title: "実戦日", systemImage: "calendar") {
                            Text(JapaneseDateFormatters.yearMonthDay.string(from: date))
                                .font(AppTypography.bodyRounded)
                                .foregroundColor(skin.mainTextColor)
                            DatePicker("", selection: $date, displayedComponents: .date)
                                .datePickerStyle(.graphical)
                                .labelsHidden()
                                .tint(accent)
                        }
                        .id("simpleDate")

                        simpleInputCardHeader(title: "遊技設定", systemImage: "dice.fill") {
                            VStack(alignment: .leading, spacing: 14) {
                                HStack {
                                    Text("機種")
                                        .font(AppTypography.sectionSubheading)
                                        .foregroundColor(skin.mainTextColor)
                                    Spacer(minLength: 8)
                                    Picker("", selection: $selectedMachine) {
                                        Text("未選択").tag(Machine?(nil))
                                        ForEach(machines) { m in
                                            Text(m.name).tag(Machine?(m))
                                        }
                                    }
                                    .labelsHidden()
                                    .tint(accent)
                                }
                                HStack {
                                    Text("店舗")
                                        .font(AppTypography.sectionSubheading)
                                        .foregroundColor(skin.mainTextColor)
                                    Spacer(minLength: 8)
                                    Picker("", selection: $selectedShop) {
                                        Text("未選択").tag(Shop?(nil))
                                        ForEach(shops) { s in
                                            Text(s.name).tag(Shop?(s))
                                        }
                                    }
                                    .labelsHidden()
                                    .tint(accent)
                                }
                            }
                        }

                        simpleAmountInputPanel(
                            scrollId: "simpleInvest",
                            title: "投資額（pt）",
                            caption: "現金で投資したポイント（貸玉換算の投資額）",
                            text: $investmentCash,
                            padTrigger: $simpleInvestPadTrigger,
                            onPreviousField: nil,
                            onNextField: { simpleRecoveryPadTrigger += 1 }
                        )

                        simpleAmountInputPanel(
                            scrollId: "simpleRecovery",
                            title: "回収額（pt）",
                            caption: "精算・換金したポイント相当。店の交換率（pt/玉）で玉数に換算して保存",
                            text: $recoveryAmountPt,
                            padTrigger: $simpleRecoveryPadTrigger,
                            onPreviousField: { simpleInvestPadTrigger += 1 },
                            onNextField: nil
                        )

                        simpleInputCardHeader(title: "遊技時間（任意）", systemImage: "clock") {
                            VStack(alignment: .leading, spacing: 12) {
                                Toggle(isOn: $recordSimplePlayTimes) {
                                    Text("遊技開始・終了を記録する")
                                        .font(AppTypography.bodyRounded)
                                        .foregroundColor(skin.mainTextColor)
                                }
                                .tint(accent)
                                if recordSimplePlayTimes {
                                    DatePicker(
                                        "遊技開始",
                                        selection: $simplePlayStartedAt,
                                        displayedComponents: [.date, .hourAndMinute]
                                    )
                                    .environment(\.timeZone, TimeZone(identifier: "Asia/Tokyo")!)
                                    .tint(accent)
                                    DatePicker(
                                        "遊技終了",
                                        selection: $simplePlayEndedAt,
                                        displayedComponents: [.date, .hourAndMinute]
                                    )
                                    .environment(\.timeZone, TimeZone(identifier: "Asia/Tokyo")!)
                                    .tint(accent)
                                }
                            }
                        }

                        simpleInputCardHeader(title: "区間の内訳（任意）", systemImage: "square.split.2x1") {
                            VStack(alignment: .leading, spacing: 12) {
                                Toggle(isOn: $recordSimpleTimeline) {
                                    Text("区間の内訳を入力する")
                                        .font(AppTypography.bodyRounded)
                                        .foregroundColor(skin.mainTextColor)
                                }
                                .tint(accent)
                                if recordSimpleTimeline {
                                    ForEach($simpleTimelineRows) { $row in
                                        simpleTimelineRowEditor(row: $row)
                                    }
                                    Button {
                                        simpleTimelineRows.append(SimpleTimelineDraft.bonus())
                                        simpleTimelineRows.append(SimpleTimelineDraft.normal())
                                    } label: {
                                        Label("セッションを追加", systemImage: "plus.circle.fill")
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundColor(accent)
                                    }
                                    .buttonStyle(.plain)
                                    Text("通常時の行には「投資通常回転」、セッションの行には「あたり回数」「獲得出玉」を入力できます。ここに回転数や出玉を入れると、期待値分析・回転率系の集計に反映されます（投資額は上欄のままです）。")
                                        .font(AppTypography.annotation)
                                        .foregroundColor(skin.subTextColor)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }

                        Text("回収額を保存するには、店舗に交換率（pt/玉）が設定されている必要があります。")
                            .font(AppTypography.annotation)
                            .foregroundColor(skin.subTextColor)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 4)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 320)
                }
                .onChange(of: simpleInvestPadTrigger) { _, _ in
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                        withAnimation(.easeInOut(duration: 0.28)) {
                            proxy.scrollTo("simpleInvest", anchor: .center)
                        }
                    }
                }
                .onChange(of: simpleRecoveryPadTrigger) { _, _ in
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                        withAnimation(.easeInOut(duration: 0.28)) {
                            proxy.scrollTo("simpleRecovery", anchor: .center)
                        }
                    }
                }
            }
        }
        .toolbarColorScheme(.dark, for: .navigationBar)
    }

    private func bumpSimpleTimelinePad(id: UUID) {
        simpleTimelinePadTriggers[id, default: 0] += 1
    }

    private func simpleTimelineDraftTitle(draft: SimpleTimelineDraft, in rows: [SimpleTimelineDraft]) -> String {
        var n = 0
        var s = 0
        for r in rows {
            if r.id == draft.id { break }
            switch r.kind {
            case .normal: n += 1
            case .bonusSession: s += 1
            }
        }
        switch draft.kind {
        case .normal: return "通常時\(n + 1)"
        case .bonusSession: return "セッション\(s + 1)"
        }
    }

    @ViewBuilder
    private func simpleTimelineRowEditor(row: Binding<SimpleTimelineDraft>) -> some View {
        let id = row.wrappedValue.id
        let title = simpleTimelineDraftTitle(draft: row.wrappedValue, in: simpleTimelineRows)
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(AppTypography.sectionSubheading)
                .foregroundColor(skin.mainTextColor)
            if row.wrappedValue.kind == .normal {
                HStack(alignment: .center, spacing: 10) {
                    Text("投資通常回転")
                        .font(AppTypography.annotation)
                        .foregroundColor(skin.subTextColor)
                        .frame(width: 120, alignment: .leading)
                    Spacer(minLength: 8)
                    IntegerPadTextField(
                        text: row.investmentRotationsStr,
                        placeholder: "0",
                        maxDigits: 6,
                        font: .systemFont(ofSize: 20, weight: .semibold),
                        textColor: UIColor(skin.mainTextColor),
                        accentColor: UIColor(accent),
                        focusTrigger: simpleTimelinePadTriggers[id, default: 0],
                        adjustsFontSizeToFitWidth: true,
                        minimumFontSize: 12
                    )
                    .frame(width: 88, alignment: .trailing)
                }
                .contentShape(Rectangle())
                .onTapGesture { bumpSimpleTimelinePad(id: id) }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .center, spacing: 10) {
                        Text("あたり回数")
                            .font(AppTypography.annotation)
                            .foregroundColor(skin.subTextColor)
                            .frame(width: 120, alignment: .leading)
                        Spacer(minLength: 8)
                        IntegerPadTextField(
                            text: row.hitCountStr,
                            placeholder: "0",
                            maxDigits: 5,
                            font: .systemFont(ofSize: 20, weight: .semibold),
                            textColor: UIColor(skin.mainTextColor),
                            accentColor: UIColor(accent),
                            focusTrigger: simpleTimelinePadTriggers[id, default: 0],
                            adjustsFontSizeToFitWidth: true,
                            minimumFontSize: 12
                        )
                        .frame(width: 72, alignment: .trailing)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { bumpSimpleTimelinePad(id: id) }
                    HStack(alignment: .center, spacing: 10) {
                        Text("獲得出玉（玉）")
                            .font(AppTypography.annotation)
                            .foregroundColor(skin.subTextColor)
                            .frame(width: 120, alignment: .leading)
                        Spacer(minLength: 8)
                        IntegerPadTextField(
                            text: row.prizeBallsStr,
                            placeholder: "0",
                            maxDigits: 8,
                            font: .systemFont(ofSize: 20, weight: .semibold),
                            textColor: UIColor(skin.mainTextColor),
                            accentColor: UIColor(accent),
                            focusTrigger: simpleTimelinePadTriggers[id, default: 0],
                            adjustsFontSizeToFitWidth: true,
                            minimumFontSize: 12
                        )
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .trailing)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { bumpSimpleTimelinePad(id: id) }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppGlassStyle.rowBackground, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(accent.opacity(0.2), lineWidth: 1))
    }

    private func simpleInputCardHeader<Content: View>(
        title: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 14))
                    .foregroundColor(accent)
                Text(title)
                    .font(AppTypography.panelHeading)
                    .foregroundColor(skin.mainTextColor)
            }
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .pstatsPanelStyle()
    }

    private func simpleAmountInputPanel(
        scrollId: String,
        title: String,
        caption: String,
        text: Binding<String>,
        padTrigger: Binding<Int>,
        onPreviousField: (() -> Void)?,
        onNextField: (() -> Void)?
    ) -> some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(AppTypography.sectionSubheading)
                    .foregroundColor(skin.mainTextColor)
                Text(caption)
                    .font(AppTypography.annotation)
                    .foregroundColor(skin.subTextColor)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(width: 168, alignment: .leading)

            IntegerPadTextField(
                text: text,
                placeholder: "0",
                maxDigits: 9,
                font: .systemFont(ofSize: 22, weight: .semibold),
                textColor: UIColor(skin.mainTextColor),
                accentColor: UIColor(accent),
                focusTrigger: padTrigger.wrappedValue,
                adjustsFontSizeToFitWidth: true,
                minimumFontSize: 14,
                onPreviousField: onPreviousField,
                onNextField: onNextField
            )
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .trailing)
        }
        .padding(16)
        .pstatsPanelStyle()
        .contentShape(RoundedRectangle(cornerRadius: skin.cornerRadius, style: .continuous))
        .onTapGesture {
            padTrigger.wrappedValue += 1
        }
        .id(scrollId)
    }

    private var detailEditRoot: some View {
        ZStack {
            StaticHomeBackgroundView()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    editDetailCard(title: "実戦日", systemImage: "calendar") {
                        Text(JapaneseDateFormatters.yearMonthDay.string(from: date))
                            .font(AppTypography.bodyRounded)
                            .foregroundColor(skin.mainTextColor)
                        DatePicker("", selection: $date, displayedComponents: .date)
                            .datePickerStyle(.graphical)
                            .labelsHidden()
                            .tint(accent)
                    }

                    editDetailCard(title: "基本情報", systemImage: "dice.fill") {
                        editDetailPickerRow(label: "機種") {
                            Picker("", selection: $selectedMachine) {
                                Text("未選択").tag(Machine?(nil))
                                ForEach(machines) { m in
                                    Text(m.name).tag(Machine?(m))
                                }
                            }
                            .labelsHidden()
                            .tint(accent)
                        }
                        editDetailPickerRow(label: "店舗") {
                            Picker("", selection: $selectedShop) {
                                Text("未選択").tag(Shop?(nil))
                                ForEach(shops) { s in
                                    Text(s.name).tag(Shop?(s))
                                }
                            }
                            .labelsHidden()
                            .tint(accent)
                        }
                    }

                    editDetailCard(title: "区間ごとの内訳", systemImage: "square.stack.3d.up.fill") {
                        Text("各区間＝その初当たりまで。RUSH 当選回数は各区間の「大当たり」を合算して保存します。")
                            .font(AppTypography.annotation)
                            .foregroundColor(skin.subTextColor)
                            .fixedSize(horizontal: false, vertical: true)
                        ForEach($phases) { $phase in
                            phaseEditorCard(
                                ordinal: (phases.firstIndex(where: { $0.id == phase.id }) ?? 0) + 1,
                                phase: $phase
                            )
                        }
                        HStack(spacing: 12) {
                            Button {
                                phases.append(PhaseDraft.empty())
                            } label: {
                                Label("区間を追加", systemImage: "plus.circle.fill")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundColor(accent)
                            }
                            .buttonStyle(.plain)
                            Spacer()
                        }
                    }

                    editDetailCard(title: "総回転数（保存）", systemImage: "arrow.triangle.2.circlepath") {
                        Text("空欄なら各区間の回転の合計。保存する総回転と合計が異なるとき、投資（pt・持ち玉）と実質投資は回転比でスケールして誤差を吸収します。")
                            .font(AppTypography.annotation)
                            .foregroundColor(skin.subTextColor)
                            .fixedSize(horizontal: false, vertical: true)
                        editDetailNumberRow(label: "総回転数（通常）", placeholder: "空欄＝区間合計", text: $totalRotationsOverride, maxDigits: 7)
                    }

                    editDetailCard(title: "最終の総回収出玉", systemImage: "circle.grid.cross.fill") {
                        Text("この実戦記録全体の回収出玉の確定値を入力します（区間ごとの回収とは別に扱います）。")
                            .font(AppTypography.annotation)
                            .foregroundColor(skin.subTextColor)
                            .fixedSize(horizontal: false, vertical: true)
                        editDetailNumberRow(label: "総回収出玉（玉）", placeholder: "0", text: $totalHoldings, maxDigits: 9)
                    }

                    editDetailCard(title: "その他の当選", systemImage: "star.fill") {
                        editDetailNumberRow(label: "通常当選回数", placeholder: "0", text: $normalWinCount, maxDigits: 5)
                    }

                    if let rec = sessionToEdit,
                       !rec.settlementModeRaw.isEmpty || rec.exchangeCashProceedsPt > 0 || rec.chodamaBalanceDeltaBalls != 0 {
                        editDetailCard(title: "精算（記録・参照のみ）", systemImage: "doc.plaintext") {
                            settlementReadonlyContent(rec)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 280)
            }
        }
        .toolbarColorScheme(.dark, for: .navigationBar)
        .environment(\.locale, Locale(identifier: "ja_JP"))
    }

    private func editDetailCard<Content: View>(
        title: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 14))
                    .foregroundColor(accent)
                Text(title)
                    .font(AppTypography.panelHeading)
                    .foregroundColor(skin.mainTextColor)
            }
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .pstatsPanelStyle()
    }

    private func editDetailPickerRow<Content: View>(label: String, @ViewBuilder trailing: () -> Content) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Text(label)
                .font(AppTypography.sectionSubheading)
                .foregroundColor(skin.mainTextColor.opacity(0.88))
                .frame(minWidth: 100, alignment: .leading)
            Spacer(minLength: 8)
            trailing()
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    private func editDetailNumberRow(label: String, placeholder: String, text: Binding<String>, maxDigits: Int) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Text(label)
                .font(AppTypography.sectionSubheading)
                .foregroundColor(skin.mainTextColor.opacity(0.88))
                .frame(minWidth: 148, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            IntegerPadTextField(
                text: text,
                placeholder: placeholder,
                maxDigits: maxDigits,
                font: .systemFont(ofSize: 18, weight: .semibold),
                textColor: UIColor(skin.mainTextColor),
                accentColor: UIColor(accent),
                focusTrigger: 0,
                adjustsFontSizeToFitWidth: true,
                minimumFontSize: 12,
                onPreviousField: nil,
                onNextField: nil
            )
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .trailing)
        }
        .padding(.vertical, 4)
    }

    private func phaseEditorCard(ordinal: Int, phase: Binding<PhaseDraft>) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("\(ordinal) 回目の区間（初当たりまで）")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(skin.mainTextColor.opacity(0.92))
                Spacer()
                if phases.count > 1 {
                    Button(role: .destructive) {
                        let pid = phase.wrappedValue.id
                        guard let idx = phases.firstIndex(where: { $0.id == pid }) else { return }
                        phases.remove(at: idx)
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .font(.system(size: 20))
                            .foregroundColor(.orange.opacity(0.95))
                    }
                    .buttonStyle(.plain)
                }
            }
            Rectangle()
                .fill(skin.hairlineDividerColor.opacity(0.9))
                .frame(height: 1)
            editDetailNumberRow(label: "初当たりまでの回転数", placeholder: "0", text: phase.rotationsUntilFirstHit, maxDigits: 7)
            editDetailNumberRow(label: "初当たりまでの投資（pt）", placeholder: "0", text: phase.investmentCashPt, maxDigits: 9)
            editDetailNumberRow(label: "初当たりまでの持ち玉投資（玉）", placeholder: "0", text: phase.investmentHoldingsBalls, maxDigits: 8)
            editDetailNumberRow(label: "この区間の大当たり回数", placeholder: "0", text: phase.bigHitCount, maxDigits: 5)
            editDetailNumberRow(label: "この区間の回収出玉", placeholder: "0", text: phase.recoveryHoldingsBalls, maxDigits: 9)
        }
        .padding(12)
        .background(skin.panelSecondaryBackground, in: RoundedRectangle(cornerRadius: max(12, skin.cornerRadius * 0.85), style: .continuous))
    }

    @ViewBuilder
    private func settlementReadonlyContent(_ rec: GameSession) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let m = SessionSettlementMode(rawValue: rec.settlementModeRaw) {
                HStack {
                    Text("区分").foregroundColor(skin.subTextColor.opacity(0.92))
                    Spacer()
                    Text(m.displayName).foregroundColor(skin.mainTextColor)
                }
                .font(AppTypography.bodyRounded)
            } else if !rec.settlementModeRaw.isEmpty {
                HStack {
                    Text("区分").foregroundColor(skin.subTextColor.opacity(0.92))
                    Spacer()
                    Text(rec.settlementModeRaw).foregroundColor(skin.mainTextColor)
                }
                .font(AppTypography.bodyRounded)
            }
            if rec.exchangeCashProceedsPt > 0 {
                HStack {
                    Text("換金（500pt刻み）").foregroundColor(skin.subTextColor.opacity(0.92))
                    Spacer()
                    Text("\(rec.exchangeCashProceedsPt) pt").foregroundColor(skin.mainTextColor)
                }
                .font(AppTypography.bodyRounded)
            }
            if rec.chodamaBalanceDeltaBalls != 0 {
                HStack {
                    Text(rec.chodamaBalanceDeltaBalls > 0 ? "貯玉残高の増加" : "貯玉残高の減少")
                        .foregroundColor(skin.subTextColor.opacity(0.92))
                    Spacer()
                    Text("\(abs(rec.chodamaBalanceDeltaBalls)) 玉").foregroundColor(skin.mainTextColor)
                }
                .font(AppTypography.bodyRounded)
            }
        }
    }

    /// `nil`＝区間が空、または負の数が含まれる
    private func parsePhasesForSave() -> [GameSessionEditPhaseStored]? {
        guard !phases.isEmpty else { return nil }
        var out: [GameSessionEditPhaseStored] = []
        for pPh in phases {
            let r = Int(pPh.rotationsUntilFirstHit) ?? 0
            let c = Int(pPh.investmentCashPt) ?? 0
            let h = Int(pPh.investmentHoldingsBalls) ?? 0
            let b = Int(pPh.bigHitCount) ?? 0
            let rec = Int(pPh.recoveryHoldingsBalls) ?? 0
            if r < 0 || c < 0 || h < 0 || b < 0 || rec < 0 { return nil }
            out.append(
                GameSessionEditPhaseStored(
                    id: pPh.id,
                    rotationsUntilFirstHit: r,
                    investmentCashPt: c,
                    investmentHoldingsBalls: h,
                    bigHitCount: b,
                    recoveryHoldingsBalls: rec
                )
            )
        }
        return out
    }

    private func save() {
        guard let machine = selectedMachine else {
            errorMessage = "機種を選択してください"
            showErrorAlert = true
            return
        }
        guard let shop = selectedShop else {
            errorMessage = "店舗を選択してください"
            showErrorAlert = true
            return
        }

        if isSimpleInput {
            saveSimpleNewSession(machine: machine, shop: shop)
            dismiss()
            return
        }

        guard let parsedPhases = parsePhasesForSave() else {
            errorMessage = "区間ごとの内訳を確認してください"
            showErrorAlert = true
            return
        }

        let tHoldings = Int(totalHoldings) ?? 0
        let nWin = Int(normalWinCount) ?? 0
        let sumR = GameSessionEditPhasesStorage.sumRotations(parsedPhases)
        let torStr = totalRotationsOverride.trimmingCharacters(in: .whitespaces)
        let nRotations = torStr.isEmpty ? sumR : (Int(torStr) ?? sumR)
        let rWin = parsedPhases.reduce(0) { $0 + $1.bigHitCount }

        // 計算ロジック（区間合計を基準に、保存する総回転との差を回転比でスケールして実質投資へ反映）
        let rate = shop.payoutCoefficient
        let scale: Double = sumR > 0 ? Double(nRotations) / Double(sumR) : 1.0
        let sumCash = parsedPhases.reduce(0) { $0 + $1.investmentCashPt }
        let sumHold = parsedPhases.reduce(0) { $0 + $1.investmentHoldingsBalls }
        let invCash = Int(round(Double(sumCash) * scale))
        let holdBalls = Int(round(Double(sumHold) * scale))
        let realCost = GameSessionEditPhasesStorage.rawTotalRealCost(phases: parsedPhases, payoutPerBall: rate) * scale
        let ballsPer1000 = Double(shop.ballsPerCashUnit * 2)
        let cashToBalls = Double(invCash) / 500.0 * Double(shop.ballsPerCashUnit)
        let effectiveUnitsForBorder = (cashToBalls + Double(holdBalls)) / 250.0
        let economicRealRate: Double = realCost > 0 ? Double(nRotations) / (realCost / 1000.0) : 0.0

        // dynamicBorder の計算（GameLog.dynamicBorder と同一の貸玉・交換補正）
        let formula = parseFormulaBorder(machine.border)
        let effective1RNet = machine.averageNetPerRound
        let dynamicBorder: Double
        let loanCorrection = ballsPer1000 > 0 ? 250.0 / ballsPer1000 : 1.0
        let exchangeCorrection = rate > 0 ? 4.0 / rate : 1.0
        
        if formula > 0 {
            dynamicBorder = formula * loanCorrection * exchangeCorrection
        } else if effective1RNet > 0 && machine.probabilityDenominator > 0 && rate > 0 && ballsPer1000 > 0 {
            dynamicBorder = machine.probabilityDenominator * 250.0 / effective1RNet * loanCorrection * exchangeCorrection
        } else if effective1RNet > 0 && rate > 0 {
            dynamicBorder = 1000.0 / (effective1RNet * rate)
        } else {
            dynamicBorder = 0
        }
        
        let expectationRatio = (dynamicBorder > 0 && effectiveUnitsForBorder > 0) ? (economicRealRate / dynamicBorder) : 1.0
        
        let cashBalls = Int((Double(invCash) / 500.0 * Double(shop.ballsPerCashUnit)).rounded())
        let totalUsedBalls = cashBalls + holdBalls

        if let s = sessionToEdit {
            // 更新
            s.date = date
            s.machineName = machine.name
            s.shopName = shop.name
            s.manufacturerName = machine.manufacturer
            s.inputCash = invCash
            s.totalHoldings = tHoldings
            s.normalRotations = nRotations
            s.totalUsedBalls = totalUsedBalls
            s.payoutCoefficient = rate
            s.totalRealCost = realCost
            s.expectationRatioAtSave = expectationRatio
            s.theoreticalValue = PStatsCalculator.theoreticalValuePt(
                totalRealCostPt: realCost,
                expectationRatio: expectationRatio
            )
            s.rushWinCount = rWin
            s.normalWinCount = nWin
            s.formulaBorderPer1k = formula > 0 ? formula : 0
            s.effectiveBorderPer1kAtSave = dynamicBorder
            s.realRotationRateAtSave = economicRealRate
            s.isCashflowOnlyRecord = false
            s.editSessionPhasesJSON = GameSessionEditPhasesStorage.encode(parsedPhases)
        } else {
            // 新規
            let newSession = GameSession(
                machineName: machine.name,
                shopName: shop.name,
                manufacturerName: machine.manufacturer,
                inputCash: invCash,
                totalHoldings: tHoldings,
                normalRotations: nRotations,
                totalUsedBalls: totalUsedBalls,
                payoutCoefficient: rate,
                totalRealCost: realCost,
                expectationRatioAtSave: expectationRatio,
                rushWinCount: rWin,
                normalWinCount: nWin,
                formulaBorderPer1k: formula > 0 ? formula : 0
            )
            newSession.date = date
            newSession.isCashflowOnlyRecord = false
            newSession.effectiveBorderPer1kAtSave = dynamicBorder
            newSession.realRotationRateAtSave = economicRealRate
            newSession.editSessionPhasesJSON = GameSessionEditPhasesStorage.encode(parsedPhases)
            modelContext.insert(newSession)
        }
        
        dismiss()
    }

    /// シンプル入力：投資・回収は pt。回収は店舗の交換率（pt/玉）で玉数に換算。区間入力で通常回転があれば期待値系を再計算。
    private func saveSimpleNewSession(machine: Machine, shop: Shop) {
        let invCash = Int(investmentCash) ?? 0
        let recPt = Int(recoveryAmountPt) ?? 0
        let rate = shop.payoutCoefficient
        let ballsPer1000 = Double(shop.ballsPerCashUnit * 2)
        let tHoldings: Int
        if rate > 0 {
            tHoldings = Int((Double(recPt) / rate).rounded())
        } else {
            tHoldings = 0
        }
        let formula = parseFormulaBorder(machine.border)
        let cashBalls = ballsPer1000 > 0
            ? Int(Double(invCash) / 1000.0 * ballsPer1000)
            : max(0, Int((Double(invCash) / 1000.0 * 250.0).rounded()))

        let storedTimeline: [SimplePlayTimelineRowStored] = recordSimpleTimeline
            ? simpleTimelineRows.map { d in
                let r = Int(d.investmentRotationsStr.trimmingCharacters(in: .whitespaces)) ?? 0
                let h = Int(d.hitCountStr.trimmingCharacters(in: .whitespaces)) ?? 0
                let p = Int(d.prizeBallsStr.trimmingCharacters(in: .whitespaces)) ?? 0
                return SimplePlayTimelineRowStored(
                    id: d.id,
                    kind: d.kind,
                    investmentNormalRotations: max(0, r),
                    hitCount: max(0, h),
                    prizeBalls: max(0, p)
                )
            }
            : []
        let sumR = recordSimpleTimeline ? GameSessionSimpleTimelineStorage.sumNormalRotations(storedTimeline) : 0
        let sumH = recordSimpleTimeline ? GameSessionSimpleTimelineStorage.sumHitCounts(storedTimeline) : 0
        let timelineJSON = recordSimpleTimeline ? GameSessionSimpleTimelineStorage.encode(storedTimeline) : ""

        let newSession = GameSession(
            machineName: machine.name,
            shopName: shop.name,
            manufacturerName: machine.manufacturer,
            inputCash: invCash,
            totalHoldings: tHoldings,
            normalRotations: recordSimpleTimeline && sumR > 0 ? sumR : 0,
            totalUsedBalls: max(0, cashBalls),
            payoutCoefficient: rate,
            totalRealCost: Double(invCash),
            expectationRatioAtSave: 1.0,
            rushWinCount: recordSimpleTimeline ? sumH : 0,
            normalWinCount: 0,
            formulaBorderPer1k: formula > 0 ? formula : 0
        )
        newSession.date = date
        newSession.simplePlayTimelineJSON = timelineJSON
        if recordSimplePlayTimes {
            var s = simplePlayStartedAt
            var e = simplePlayEndedAt
            if e < s { swap(&s, &e) }
            newSession.startedAt = s
            newSession.endedAt = e
        }
        if recordSimpleTimeline && sumR > 0 {
            let m = expectationMetricsForSimpleSave(machine: machine, shop: shop, invCash: invCash, normalRotations: sumR)
            newSession.isCashflowOnlyRecord = false
            newSession.effectiveBorderPer1kAtSave = m.dynamicBorder
            newSession.realRotationRateAtSave = m.economicRealRate
            newSession.expectationRatioAtSave = m.expectationRatio
            newSession.theoreticalValue = PStatsCalculator.theoreticalValuePt(
                totalRealCostPt: Double(invCash),
                expectationRatio: m.expectationRatio
            )
        } else {
            newSession.isCashflowOnlyRecord = true
        }
        modelContext.insert(newSession)
    }

    private func expectationMetricsForSimpleSave(machine: Machine, shop: Shop, invCash: Int, normalRotations nRot: Int)
        -> (dynamicBorder: Double, economicRealRate: Double, expectationRatio: Double) {
        let rate = shop.payoutCoefficient
        let realCost = Double(invCash)
        let economicRealRate: Double = realCost > 0 ? Double(nRot) / (realCost / 1000.0) : 0.0
        let ballsPer1000 = Double(shop.ballsPerCashUnit * 2)
        let cashToBalls = Double(invCash) / 500.0 * Double(shop.ballsPerCashUnit)
        let effectiveUnitsForBorder = cashToBalls / 250.0
        let formula = parseFormulaBorder(machine.border)
        let effective1RNet = machine.averageNetPerRound
        let loanCorrection = ballsPer1000 > 0 ? 250.0 / ballsPer1000 : 1.0
        let exchangeCorrection = rate > 0 ? 4.0 / rate : 1.0
        let dynamicBorder: Double
        if formula > 0 {
            dynamicBorder = formula * loanCorrection * exchangeCorrection
        } else if effective1RNet > 0 && machine.probabilityDenominator > 0 && rate > 0 && ballsPer1000 > 0 {
            dynamicBorder = Double(machine.probabilityDenominator) * 250.0 / effective1RNet * loanCorrection * exchangeCorrection
        } else if effective1RNet > 0 && rate > 0 {
            dynamicBorder = 1000.0 / (effective1RNet * rate)
        } else {
            dynamicBorder = 0
        }
        let expectationRatio = (dynamicBorder > 0 && effectiveUnitsForBorder > 0) ? (economicRealRate / dynamicBorder) : 1.0
        return (dynamicBorder, economicRealRate, expectationRatio)
    }

    private func parseFormulaBorder(_ borderStr: String) -> Double {
        let s = borderStr.trimmingCharacters(in: .whitespaces)
        if let v = Double(s), v > 0 { return v }
        let numStr = s.filter { $0.isNumber || $0 == "." }
        if !numStr.isEmpty, let v = Double(numStr), v > 0 { return v }
        return 0
    }
}

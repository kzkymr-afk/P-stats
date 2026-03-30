import SwiftUI
import SwiftData
import UIKit

struct GameSessionEditView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query private var machines: [Machine]
    @Query private var shops: [Shop]

    let sessionToEdit: GameSession?
    /// 新規のみ `true` 可。既存 `sessionToEdit` がある場合は常に詳細フォームになる。
    let isSimpleInput: Bool

    @State private var date: Date = Date()
    @State private var selectedMachine: Machine?
    @State private var selectedShop: Shop?

    @State private var investmentCash: String = ""
    /// シンプル入力: 回収額（pt）。詳細入力: 従来どおり回収は「玉」で `totalHoldings` に入れる
    @State private var recoveryAmountPt: String = ""
    @State private var holdingsInvestedBalls: String = "0"
    @State private var totalHoldings: String = ""
    @State private var normalRotations: String = ""
    @State private var rushWinCount: String = ""
    @State private var normalWinCount: String = ""
    @State private var ltWinCount: String = ""
    @State private var showErrorAlert = false
    @State private var errorMessage = ""

    @State private var simpleInvestPadTrigger = 0
    @State private var simpleRecoveryPadTrigger = 0

    private var cyan: Color { AppGlassStyle.accent }

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
                    Form {
                        fullInputSections
                    }
                    .environment(\.locale, Locale(identifier: "ja_JP"))
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
                                errorMessage = "回収額を保存するには店舗の払出係数（pt/玉）が必要です。店舗を編集して設定してください。"
                                showErrorAlert = true
                                return
                            }
                        } else {
                            if (Int(investmentCash) ?? 0) < 0 || (Int(holdingsInvestedBalls) ?? 0) < 0 || (Int(totalHoldings) ?? 0) < 0 || (Int(normalRotations) ?? 0) < 0 || (Int(rushWinCount) ?? 0) < 0 || (Int(normalWinCount) ?? 0) < 0 || (Int(ltWinCount) ?? 0) < 0 {
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
                guard let s = sessionToEdit, !isSimpleInput else { return }
                date = s.date
                selectedMachine = machines.first(where: { $0.name == s.machineName })
                selectedShop = shops.first(where: { $0.name == s.shopName })
                investmentCash = "\(s.inputCash)"
                totalHoldings = "\(s.totalHoldings)"
                normalRotations = "\(s.normalRotations)"
                rushWinCount = "\(s.rushWinCount)"
                normalWinCount = "\(s.normalWinCount)"
                ltWinCount = "\(s.ltWinCount)"
                // holdingsInvestedBalls は厳密な復元が難しいが、totalUsedBalls から現金分を引いて近似する
                let ballsPer1k = selectedShop.map { Double($0.ballsPerCashUnit * 2) } ?? 250.0
                let cashBalls = Double(s.inputCash) / 1000.0 * ballsPer1k
                let hBalls = max(0, Int(Double(s.totalUsedBalls) - cashBalls))
                holdingsInvestedBalls = "\(hBalls)"
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
                        simpleInputCardHeader(title: "実践日", systemImage: "calendar") {
                            Text(JapaneseDateFormatters.yearMonthDay.string(from: date))
                                .font(AppTypography.bodyRounded)
                                .foregroundColor(.white.opacity(0.95))
                            DatePicker("", selection: $date, displayedComponents: .date)
                                .datePickerStyle(.graphical)
                                .labelsHidden()
                                .tint(cyan)
                                .colorScheme(.dark)
                        }
                        .id("simpleDate")

                        simpleInputCardHeader(title: "遊技設定", systemImage: "dice.fill") {
                            VStack(alignment: .leading, spacing: 14) {
                                HStack {
                                    Text("機種")
                                        .font(AppTypography.sectionSubheading)
                                        .foregroundColor(.white.opacity(0.9))
                                    Spacer(minLength: 8)
                                    Picker("", selection: $selectedMachine) {
                                        Text("未選択").tag(Machine?(nil))
                                        ForEach(machines) { m in
                                            Text(m.name).tag(Machine?(m))
                                        }
                                    }
                                    .labelsHidden()
                                    .tint(cyan)
                                }
                                HStack {
                                    Text("店舗")
                                        .font(AppTypography.sectionSubheading)
                                        .foregroundColor(.white.opacity(0.9))
                                    Spacer(minLength: 8)
                                    Picker("", selection: $selectedShop) {
                                        Text("未選択").tag(Shop?(nil))
                                        ForEach(shops) { s in
                                            Text(s.name).tag(Shop?(s))
                                        }
                                    }
                                    .labelsHidden()
                                    .tint(cyan)
                                }
                            }
                        }

                        simpleAmountInputPanel(
                            scrollId: "simpleInvest",
                            title: "投資額（pt）",
                            caption: "現金で投入したポイント（貸玉換算の投入額）",
                            text: $investmentCash,
                            padTrigger: $simpleInvestPadTrigger,
                            onPreviousField: nil,
                            onNextField: { simpleRecoveryPadTrigger += 1 }
                        )

                        simpleAmountInputPanel(
                            scrollId: "simpleRecovery",
                            title: "回収額（pt）",
                            caption: "精算・換金したポイント相当。店の払出係数で玉数に換算して保存",
                            text: $recoveryAmountPt,
                            padTrigger: $simpleRecoveryPadTrigger,
                            onPreviousField: { simpleInvestPadTrigger += 1 },
                            onNextField: nil
                        )

                        Text("回収額を保存するには、店舗に払出係数（pt/玉）が設定されている必要があります。")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.72))
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
        .preferredColorScheme(.dark)
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
                    .foregroundColor(cyan)
                Text(title)
                    .font(AppTypography.panelHeading)
                    .foregroundColor(.white.opacity(0.95))
            }
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(AppGlassStyle.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(AppGlassStyle.strokeGradient, lineWidth: 1)
        )
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
                    .foregroundColor(.white.opacity(0.95))
                Text(caption)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.72))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(width: 168, alignment: .leading)

            IntegerPadTextField(
                text: text,
                placeholder: "0",
                maxDigits: 9,
                font: .systemFont(ofSize: 22, weight: .semibold),
                textColor: .white,
                accentColor: UIColor(cyan),
                focusTrigger: padTrigger.wrappedValue,
                adjustsFontSizeToFitWidth: true,
                minimumFontSize: 14,
                onPreviousField: onPreviousField,
                onNextField: onNextField
            )
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .trailing)
        }
        .padding(16)
        .background(AppGlassStyle.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(AppGlassStyle.strokeGradient, lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 14))
        .onTapGesture {
            padTrigger.wrappedValue += 1
        }
        .id(scrollId)
    }

    @ViewBuilder
    private var fullInputSections: some View {
        Section {
            LabeledContent("実践日") {
                Text(JapaneseDateFormatters.yearMonthDay.string(from: date))
                    .foregroundStyle(.primary)
            }
            DatePicker("", selection: $date, displayedComponents: .date)
                .datePickerStyle(.graphical)
        }

        Section("基本情報") {
            Picker("機種", selection: $selectedMachine) {
                Text("未選択").tag(Machine?(nil))
                ForEach(machines) { m in
                    Text(m.name).tag(Machine?(m))
                }
            }
            Picker("店舗", selection: $selectedShop) {
                Text("未選択").tag(Shop?(nil))
                ForEach(shops) { s in
                    Text(s.name).tag(Shop?(s))
                }
            }
        }

        Section(header: Text("実践データ"), footer: Text("総回転数＝通常回転のみ（時短・電サポ除く）").font(.caption)) {
            IntegerPadTextField(
                text: $normalRotations,
                placeholder: "通常回転数",
                maxDigits: 7,
                font: .preferredFont(forTextStyle: .body),
                textColor: UIColor.label,
                accentColor: UIColor.systemBlue
            )
            IntegerPadTextField(
                text: $investmentCash,
                placeholder: "投入 (pt)",
                maxDigits: 9,
                font: .preferredFont(forTextStyle: .body),
                textColor: UIColor.label,
                accentColor: UIColor.systemBlue
            )
            IntegerPadTextField(
                text: $holdingsInvestedBalls,
                placeholder: "持ち玉投資 (玉)",
                maxDigits: 7,
                font: .preferredFont(forTextStyle: .body),
                textColor: UIColor.label,
                accentColor: UIColor.systemBlue
            )
            IntegerPadTextField(
                text: $totalHoldings,
                placeholder: "回収出玉 (玉)",
                maxDigits: 8,
                font: .preferredFont(forTextStyle: .body),
                textColor: UIColor.label,
                accentColor: UIColor.systemBlue
            )
        }

        Section("当選回数") {
            IntegerPadTextField(
                text: $rushWinCount,
                placeholder: "RUSH回数",
                maxDigits: 5,
                font: .preferredFont(forTextStyle: .body),
                textColor: UIColor.label,
                accentColor: UIColor.systemBlue
            )
            IntegerPadTextField(
                text: $normalWinCount,
                placeholder: "通常回数",
                maxDigits: 5,
                font: .preferredFont(forTextStyle: .body),
                textColor: UIColor.label,
                accentColor: UIColor.systemBlue
            )
            IntegerPadTextField(
                text: $ltWinCount,
                placeholder: "LT回数",
                maxDigits: 5,
                font: .preferredFont(forTextStyle: .body),
                textColor: UIColor.label,
                accentColor: UIColor.systemBlue
            )
        }

        if let rec = sessionToEdit,
           !rec.settlementModeRaw.isEmpty || rec.exchangeCashProceedsPt > 0 || rec.chodamaBalanceDeltaBalls > 0 {
            Section("精算（記録）") {
                if let m = SessionSettlementMode(rawValue: rec.settlementModeRaw) {
                    LabeledContent("区分", value: m.displayName)
                } else if !rec.settlementModeRaw.isEmpty {
                    LabeledContent("区分", value: rec.settlementModeRaw)
                }
                if rec.exchangeCashProceedsPt > 0 {
                    LabeledContent("換金（500pt刻み）", value: "\(rec.exchangeCashProceedsPt) pt")
                }
                if rec.chodamaBalanceDeltaBalls > 0 {
                    LabeledContent("貯玉へ加算", value: "\(rec.chodamaBalanceDeltaBalls) 玉")
                }
            }
        }
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

        let invCash = Int(investmentCash) ?? 0
        let holdBalls = Int(holdingsInvestedBalls) ?? 0
        let tHoldings = Int(totalHoldings) ?? 0
        let nRotations = Int(normalRotations) ?? 0
        let rWin = Int(rushWinCount) ?? 0
        let nWin = Int(normalWinCount) ?? 0
        let lWin = Int(ltWinCount) ?? 0
        if invCash < 0 || holdBalls < 0 || tHoldings < 0 || nRotations < 0 || rWin < 0 || nWin < 0 || lWin < 0 {
            errorMessage = "負の数は入力できません"
            showErrorAlert = true
            return
        }

        // 計算ロジック
        let rate = shop.payoutCoefficient
        let realCost = Double(invCash) + Double(holdBalls) * rate
        let ballsPer1000 = Double(shop.ballsPerCashUnit * 2)
        let cashUnits = ballsPer1000 > 0 ? Double(invCash) * ballsPer1000 / 250000.0 : Double(invCash) / 1000.0
        let effectiveUnitsForBorder = cashUnits + (ballsPer1000 > 0 ? Double(holdBalls) / ballsPer1000 : Double(holdBalls) / 250.0)
        let realRate = effectiveUnitsForBorder > 0 ? Double(nRotations) / effectiveUnitsForBorder : 0.0
        
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
        
        let expectationRatio = (dynamicBorder > 0 && effectiveUnitsForBorder > 0) ? (realRate / dynamicBorder) : 1.0
        
        let cashBalls = Int(Double(invCash) / 1000.0 * ballsPer1000)
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
            s.theoreticalValue = Int(round(realCost * (expectationRatio - 1)))
            s.rushWinCount = rWin
            s.normalWinCount = nWin
            s.ltWinCount = lWin
            s.formulaBorderPer1k = formula > 0 ? formula : 0
            s.isCashflowOnlyRecord = false
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
                ltWinCount: lWin,
                formulaBorderPer1k: formula > 0 ? formula : 0
            )
            newSession.date = date
            newSession.isCashflowOnlyRecord = false
            modelContext.insert(newSession)
        }
        
        dismiss()
    }

    /// シンプル入力：投資・回収は pt。回収は店舗の払出係数で玉数に換算。回転・当選・理論値は 0 / 中立で保存。
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
        let newSession = GameSession(
            machineName: machine.name,
            shopName: shop.name,
            manufacturerName: machine.manufacturer,
            inputCash: invCash,
            totalHoldings: tHoldings,
            normalRotations: 0,
            totalUsedBalls: max(0, cashBalls),
            payoutCoefficient: rate,
            totalRealCost: Double(invCash),
            expectationRatioAtSave: 1.0,
            rushWinCount: 0,
            normalWinCount: 0,
            ltWinCount: 0,
            formulaBorderPer1k: formula > 0 ? formula : 0
        )
        newSession.date = date
        newSession.isCashflowOnlyRecord = true
        modelContext.insert(newSession)
    }

    private func parseFormulaBorder(_ borderStr: String) -> Double {
        let s = borderStr.trimmingCharacters(in: .whitespaces)
        if let v = Double(s), v > 0 { return v }
        let numStr = s.filter { $0.isNumber || $0 == "." }
        if !numStr.isEmpty, let v = Double(numStr), v > 0 { return v }
        return 0
    }
}

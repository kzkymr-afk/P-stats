import SwiftUI
import SwiftData

struct GameSessionEditView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query private var machines: [Machine]
    @Query private var shops: [Shop]

    let sessionToEdit: GameSession?

    @State private var date: Date = Date()
    @State private var selectedMachine: Machine?
    @State private var selectedShop: Shop?

    @State private var investmentCash: String = ""
    @State private var holdingsInvestedBalls: String = "0"
    @State private var totalHoldings: String = ""
    @State private var normalRotations: String = ""
    @State private var rushWinCount: String = ""
    @State private var normalWinCount: String = ""
    @State private var ltWinCount: String = ""
    @State private var showErrorAlert = false
    @State private var errorMessage = ""

    init(sessionToEdit: GameSession? = nil) {
        self.sessionToEdit = sessionToEdit
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("基本情報") {
                    DatePicker("実践日", selection: $date)
                    
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
                    TextField("通常回転数", text: $normalRotations)
                        .keyboardType(.numberPad)
                    
                    TextField("現金投資 (円)", text: $investmentCash)
                        .keyboardType(.numberPad)
                    
                    TextField("持ち玉投資 (玉)", text: $holdingsInvestedBalls)
                        .keyboardType(.numberPad)
                    
                    TextField("回収出玉 (玉)", text: $totalHoldings)
                        .keyboardType(.numberPad)
                }
                
                Section("大当たり回数") {
                    TextField("RUSH回数", text: $rushWinCount)
                        .keyboardType(.numberPad)
                    
                    TextField("通常回数", text: $normalWinCount)
                        .keyboardType(.numberPad)
                    
                    TextField("LT回数", text: $ltWinCount)
                        .keyboardType(.numberPad)
                }
            }
            .navigationTitle(sessionToEdit == nil ? "過去データを入力" : "履歴を編集")
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
                        if (Int(investmentCash) ?? 0) < 0 || (Int(holdingsInvestedBalls) ?? 0) < 0 || (Int(totalHoldings) ?? 0) < 0 || (Int(normalRotations) ?? 0) < 0 || (Int(rushWinCount) ?? 0) < 0 || (Int(normalWinCount) ?? 0) < 0 || (Int(ltWinCount) ?? 0) < 0 {
                            errorMessage = "負の数は入力できません"
                            showErrorAlert = true
                            return
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
                if let s = sessionToEdit {
                    date = s.date
                    selectedMachine = machines.first(where: { $0.name == s.machineName })
                    selectedShop = shops.first(where: { $0.name == s.shopName })
                    investmentCash = "\(s.investmentCash)"
                    totalHoldings = "\(s.totalHoldings)"
                    normalRotations = "\(s.normalRotations)"
                    rushWinCount = "\(s.rushWinCount)"
                    normalWinCount = "\(s.normalWinCount)"
                    ltWinCount = "\(s.ltWinCount)"
                    // holdingsInvestedBalls は厳密な復元が難しいが、totalUsedBalls から現金分を引いて近似する
                    let ballsPer1k = selectedShop.map { Double($0.ballsPerCashUnit * 2) } ?? 250.0
                    let cashBalls = Double(s.investmentCash) / 1000.0 * ballsPer1k
                    let hBalls = max(0, Int(Double(s.totalUsedBalls) - cashBalls))
                    holdingsInvestedBalls = "\(hBalls)"
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
        
        if invCash < 0 || holdBalls < 0 || tHoldings < 0 || nRotations < 0 || rWin < 0 || nWin < 0 || lWin < 0 {
            errorMessage = "負の数は入力できません"
            showErrorAlert = true
            return
        }

        // 計算ロジック
        let rate = shop.exchangeRate
        let realCost = Double(invCash) + Double(holdBalls) * rate
        let ballsPer1000 = Double(shop.ballsPerCashUnit * 2)
        let cashUnits = ballsPer1000 > 0 ? Double(invCash) * ballsPer1000 / 250000.0 : Double(invCash) / 1000.0
        let effectiveUnitsForBorder = cashUnits + Double(holdBalls) / 250.0
        let realRate = effectiveUnitsForBorder > 0 ? Double(nRotations) / effectiveUnitsForBorder : 0.0
        
        // dynamicBorder の計算
        let formula = parseFormulaBorder(machine.border)
        let effective1RNet = machine.averageNetPerRound
        let dynamicBorder: Double
        let loanCorrection = ballsPer1000 > 0 ? ballsPer1000 / 250.0 : 1.0
        let exchangeCorrection = rate > 0 ? 4.0 / rate : 1.0
        
        if formula > 0 {
            dynamicBorder = formula * loanCorrection * exchangeCorrection
        } else if effective1RNet > 0 && machine.probabilityDenominator > 0 && rate > 0 && ballsPer1000 > 0 {
            dynamicBorder = machine.probabilityDenominator * ballsPer1000 / effective1RNet * (4.0 / rate)
        } else if effective1RNet > 0 && rate > 0 && ballsPer1000 > 0 {
            dynamicBorder = 1000.0 * ballsPer1000 / (effective1RNet * 250.0 * rate)
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
            s.investmentCash = invCash
            s.totalHoldings = tHoldings
            s.normalRotations = nRotations
            s.totalUsedBalls = totalUsedBalls
            s.exchangeRate = rate
            s.totalRealCost = realCost
            s.expectationRatioAtSave = expectationRatio
            s.theoreticalProfit = Int(round(realCost * (expectationRatio - 1)))
            s.rushWinCount = rWin
            s.normalWinCount = nWin
            s.ltWinCount = lWin
            s.formulaBorderPer1k = formula > 0 ? formula : 0
        } else {
            // 新規
            let newSession = GameSession(
                machineName: machine.name,
                shopName: shop.name,
                manufacturerName: machine.manufacturer,
                investmentCash: invCash,
                totalHoldings: tHoldings,
                normalRotations: nRotations,
                totalUsedBalls: totalUsedBalls,
                exchangeRate: rate,
                totalRealCost: realCost,
                expectationRatioAtSave: expectationRatio,
                rushWinCount: rWin,
                normalWinCount: nWin,
                ltWinCount: lWin,
                formulaBorderPer1k: formula > 0 ? formula : 0
            )
            newSession.date = date
            modelContext.insert(newSession)
        }
        
        dismiss()
    }
    
    private func parseFormulaBorder(_ borderStr: String) -> Double {
        let s = borderStr.trimmingCharacters(in: .whitespaces)
        if let v = Double(s), v > 0 { return v }
        let numStr = s.filter { $0.isNumber || $0 == "." }
        if !numStr.isEmpty, let v = Double(numStr), v > 0 { return v }
        return 0
    }
}

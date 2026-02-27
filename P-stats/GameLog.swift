import Foundation
import Observation

@Observable
final class GameLog {
    // 初期値としての仮データ（SelectionViewで上書きされます）
    var selectedMachine: Machine = Machine(name: "未選択", supportLimit: 100, defaultPrize: 1500)
    var selectedShop: Shop = Shop(name: "未選択", ballsPerCashUnit: 125, exchangeRate: 4.0)
    
    var totalHoldings: Int = 0
    var totalRotations: Int = 0
    var normalRotations: Int = 0
    /// 新規開始時に設定した台表示数（表示合わせのみ・あとから修正用）
    var initialDisplayRotation: Int = 0
    var currentState: PlayState = .normal
    /// 電サポまたは時短の残り回数（0で自動通常復帰）。ST電サポ・通常後の時短の両方で使用
    var remainingSupportCount: Int = 0
    /// 通常大当たり後の時短中か（表示を「時短中」にするため）
    var isTimeShortMode: Bool = false
    /// 遊技中の1R純増の手動調整値。nilなら機種のeffectiveNetPerRoundForBorderを使用
    var adjustedNetPerRound: Double?

    var winRecords: [WinRecord] = []
    var lendingRecords: [LendingRecord] = []

    /// RUSHフォーカス用：遊技開始時刻（チャート横軸の0）
    var sessionStartDate: Date?
    /// RUSHフォーカス用：(時刻, 損益円) の時系列。最大13時間分
    var chartTimeline: [(Date, Double)] = []
    private let chartMaxHours: Double = 13

    /// 最大3回まで Undo 可能なスタック（操作前に保存した状態）
    private struct StateSnapshot {
        let totalRotations: Int
        let normalRotations: Int
        let totalHoldings: Int
        let currentState: PlayState
        let remainingSupportCount: Int
        let isTimeShortMode: Bool
        let winRecords: [WinRecord]
        let lendingRecords: [LendingRecord]
    }
    private var undoStack: [StateSnapshot] = []
    private let maxUndoCount = 3

    /// 持ち玉投資は 1タップ = 125玉。125未満の残りは全額投資として記録
    private let holdingsBallsPerTap: Int = 125

    init() {}

    /// Undo 可能回数（0〜3）
    var undoCount: Int { undoStack.count }

    func incrementRotation() {
        addRotations(1)
    }

    /// 指定数だけ回転を加算（+10, +100 用）。時短/ST電サポ中は残り回数を減らし0で通常に復帰
    func addRotations(_ n: Int) {
        guard n > 0 else { return }
        saveState()
        var remaining = n
        while remaining > 0 {
            totalRotations += 1
            if currentState == .normal {
                normalRotations += 1
                remaining -= 1
            } else if currentState == .support, remainingSupportCount > 0 {
                // 時短またはST電サポ：残り回数カウントダウン、0で通常へ
                remainingSupportCount -= 1
                remaining -= 1
                if remainingSupportCount <= 0 {
                    currentState = .normal
                    isTimeShortMode = false
                }
            } else {
                // 確変電サポ（残り0＝手動復帰待ち）は回転だけ加算
                remaining -= 1
            }
        }
    }

    func addLending(type: LendingType) {
        saveState()
        if type == .holdings {
            let deduct = min(holdingsBallsPerTap, max(0, totalHoldings))
            guard deduct > 0 else { return }
            totalHoldings -= deduct
            lendingRecords.append(LendingRecord(type: .holdings, timestamp: Date(), balls: deduct))
        } else {
            lendingRecords.append(LendingRecord(type: .cash, timestamp: Date()))
        }
    }

    /// クイック投資：指定円額（500円単位）を一括で現金投資として追加。例: addCashInvestment(5000) で 5k
    func addCashInvestment(yen: Int) {
        let units = max(0, yen / 500)
        guard units > 0 else { return }
        saveState()
        for _ in 0..<units {
            lendingRecords.append(LendingRecord(type: .cash, timestamp: Date()))
        }
    }

    /// 持ち玉投資：指定玉数を一括で記録。125・500・1000玉など
    func addHoldingsInvestment(balls: Int) {
        let deduct = min(balls, max(0, totalHoldings))
        guard deduct > 0 else { return }
        saveState()
        totalHoldings -= deduct
        lendingRecords.append(LendingRecord(type: .holdings, timestamp: Date(), balls: deduct))
    }

    func toggleLendingType(id: UUID) {
        saveState()
        if let index = lendingRecords.firstIndex(where: { $0.id == id }) {
            if lendingRecords[index].type == .cash {
                let deduct = min(holdingsBallsPerTap, max(0, totalHoldings))
                totalHoldings -= deduct
                lendingRecords[index].type = .holdings
                lendingRecords[index].balls = deduct
            } else {
                totalHoldings += lendingRecords[index].balls ?? holdingsBallsPerTap
                lendingRecords[index].type = .cash
                lendingRecords[index].balls = nil
            }
        }
    }

    /// 当たり1回あたりの持ち玉（R数×実戦1R純増）。例: 10R・1R=135 → 1350
    var effectiveBallsPerHit: Int {
        let rounds = selectedMachine.defaultRoundsPerHit
        return Int(round(Double(rounds) * effective1RNetPerRound))
    }

    func addWin(type: WinType, atRotation: Int) {
        saveState()
        let diff = atRotation - totalRotations
        if diff != 0 && currentState == .normal { normalRotations += diff }
        let prize = effectiveBallsPerHit
        winRecords.append(WinRecord(type: type, prize: prize, rotationAtWin: atRotation))
        totalHoldings += prize
        totalRotations = 0
        if type == .normal {
            let timeShort = selectedMachine.timeShortRotations
            if timeShort > 0 {
                // 通常大当たり後は時短：球を消費しない回転が timeShort 回続く
                currentState = .support
                remainingSupportCount = timeShort
                isTimeShortMode = true
            } else {
                currentState = .normal
                remainingSupportCount = 0
                isTimeShortMode = false
            }
        } else {
            currentState = .support
            isTimeShortMode = false
            if selectedMachine.isST {
                remainingSupportCount = selectedMachine.supportLimit
            }
        }
        recordChartPoint()
    }

    // 計算用
    var investment: Int { lendingRecords.filter { $0.type == .cash }.count * 500 }
    /// RUSH 大当たり回数
    var rushWinCount: Int { winRecords.filter { $0.type == .rush }.count }
    /// 通常大当たり回数
    var normalWinCount: Int { winRecords.filter { $0.type == .normal }.count }
    var totalUsedBalls: Int {
        let cashBalls = lendingRecords.filter { $0.type == .cash }.count * selectedShop.ballsPerCashUnit
        let holdingsBalls = lendingRecords.filter { $0.type == .holdings }.reduce(0) { $0 + ($1.balls ?? holdingsBallsPerTap) }
        return cashBalls + holdingsBalls
    }
    /// 持ち玉で投資した玉数（実践ボーダー・チャート損益の算出に使用）
    var holdingsInvestedBalls: Int {
        lendingRecords.filter { $0.type == .holdings }.reduce(0) { $0 + ($1.balls ?? holdingsBallsPerTap) }
    }

    var totalRealCost: Double {
        let cashCost = Double(lendingRecords.filter { $0.type == .cash }.count * 500)
        let holdingsCost = Double(holdingsInvestedBalls) * selectedShop.exchangeRate
        return cashCost + holdingsCost
    }

    /// 収入（円）。出玉×交換率を五百円刻みで端数切り捨て
    var incomeYen500Step: Int {
        let raw = Double(totalHoldings) * selectedShop.exchangeRate
        return Int(raw / 500) * 500
    }

    /// 今回の収支（円）。収入 − 現金投資
    var balanceYen: Int { incomeYen500Step - investment }

    /// 現在の損益（円）。現金投資＋持ち玉投資（交換率で円換算）に対する、現在の持ち玉（交換率で円換算）の差。正＝黒字側
    var chartProfitYen: Double {
        let rate = selectedShop.exchangeRate
        let currentValue = Double(totalHoldings) * rate
        let cost = Double(investment) + Double(holdingsInvestedBalls) * rate
        return currentValue - cost
    }

    /// 大当たり時にチャート用の1点を追加（RUSHフォーカス用）
    func recordChartPoint() {
        let t = Date()
        if sessionStartDate == nil {
            sessionStartDate = t
            chartTimeline = [(t, 0), (t, chartProfitYen)]
        } else {
            var next = chartTimeline + [(t, chartProfitYen)]
            let cutoff = t.addingTimeInterval(-chartMaxHours * 3600)
            next.removeAll { $0.0 < cutoff }
            chartTimeline = next
        }
    }

    /// 実戦で使う1Rあたり純増（遊技中調整 or 機種の突入率・継続率・平均出玉反映値）
    var effective1RNetPerRound: Double {
        adjustedNetPerRound ?? selectedMachine.effectiveNetPerRoundForBorder
    }

    /// 公式ボーダー（等価時）が数値で入力されていればその値。未入力・非数値なら 0
    private var formulaBorderAsNumber: Double {
        let s = selectedMachine.border.trimmingCharacters(in: .whitespaces)
        if let v = Double(s), v > 0 { return v }
        let numStr = s.filter { $0.isNumber || $0 == "." }
        if !numStr.isEmpty, let v = Double(numStr), v > 0 { return v }
        return 0
    }

    /// 公式ボーダー（等価時）の数値。UI表示用
    var formulaBorderValue: Double { formulaBorderAsNumber }

    /// 公式ボーダー（回転/1000円）。メーカー公表値（機種マスターまたはユーザー入力の border）に、
    /// 店舗の貸玉料金（1000円あたり玉数）と交換率（円/玉）を考慮して算出。
    /// 公式＝等価(4円/玉・250玉/1000円)基準。実戦 = 公式 × (貸玉料金/250) × (4/交換率)
    var dynamicBorder: Double {
        let rate = selectedShop.exchangeRate
        guard rate > 0 else { return 0 }
        let ballsPer1000 = Double(selectedShop.ballsPerCashUnit * 2)
        guard ballsPer1000 > 0 else { return 0 }
        let formula = formulaBorderAsNumber
        let loanCorrection = ballsPer1000 / 250.0   // 250玉基準→貸玉料金に変更（230玉なら×0.92）
        let exchangeCorrection = 4.0 / rate         // 交換率補正（3.5円なら×1.14）
        if formula > 0 {
            return formula * loanCorrection * exchangeCorrection
        }
        guard effective1RNetPerRound > 0 else { return 0 }
        let prob = selectedMachine.probabilityDenominator
        if prob > 0 {
            return prob * ballsPer1000 / effective1RNetPerRound * (4.0 / rate)
        }
        return 1000.0 * ballsPer1000 / (effective1RNetPerRound * 250.0 * rate)
    }

    /// 実践ボーダー用：店舗の貸玉料金を考慮した「単位」数。1単位＝等価1000円(250玉)。投資円を貸玉料金で換算
    var effectiveUnitsForBorder: Double {
        let ballsPer1000 = Double(selectedShop.ballsPerCashUnit * 2)
        let cashUnits = ballsPer1000 > 0 ? Double(investment) * ballsPer1000 / 250000.0 : Double(investment) / 1000.0
        return cashUnits + Double(holdingsInvestedBalls) / 250.0
    }

    /// 期待値（実戦ボーダー比）。実質回転率（1000円・250玉単位）÷ 実戦ボーダー。1.0でボーダー、>1で上回り
    var expectationRatio: Double {
        guard dynamicBorder > 0, effectiveUnitsForBorder > 0 else { return 0 }
        return realRate / dynamicBorder
    }

    /// 実質回転率（回転/単位）。1単位＝現金1000円 または 持ち玉250玉。店舗の貸玉料金・交換率は実戦ボーダー側で参照
    var realRate: Double {
        effectiveUnitsForBorder > 0 ? Double(normalRotations) / effectiveUnitsForBorder : 0.0
    }

    /// 実費ベースの回転率（回転/千円）。現金＋持ち玉（交換率で円換算）の実費で割る。現金のみ 60回転・4000円 → 15。ゲージの補足表示用
    var rotationPer1000Yen: Double {
        let realCostThousands = totalRealCost / 1000.0
        guard realCostThousands > 0 else { return 0 }
        return Double(normalRotations) / realCostThousands
    }

    /// 手動で通常へ復帰（確変の「通常落ち」やST・時短の手動切り上げ）
    func backToNormalManually() {
        saveState()
        currentState = .normal
        remainingSupportCount = 0
        isTimeShortMode = false
    }

    /// チャンスモードで「時短終了」押下時。残り時短回数を totalRotations に加算し通常へ（101回転目から通常再開）
    func endTimeShortAndReturnToNormal() {
        saveState()
        totalRotations += remainingSupportCount
        currentState = .normal
        remainingSupportCount = 0
        isTimeShortMode = false
    }

    /// フォーカスモードで「RUSH終了」押下時。STなら電サポゲーム数を totalRotations に加算して通常へ（161から通常再開）。確変なら1から通常
    func endRushAndReturnToNormal() {
        saveState()
        if selectedMachine.isST {
            totalRotations += selectedMachine.supportLimit
        }
        currentState = .normal
        remainingSupportCount = 0
        isTimeShortMode = false
    }

    /// 手動で電サポ中に切り替え（STのときは残り回数をセットしてカウントダウン開始）
    func enterSupportManually() {
        saveState()
        currentState = .support
        isTimeShortMode = false
        if selectedMachine.isST {
            remainingSupportCount = selectedMachine.supportLimit
        }
    }

    func fixTotalChainPrize(finalTotal: Int) {
        saveState()
        let currentTotal = winRecords.reduce(0) { $0 + ($1.prize ?? 0) }
        let diff = finalTotal - currentTotal
        totalHoldings += diff
        if let lastIndex = winRecords.indices.last {
            winRecords[lastIndex].prize = (winRecords[lastIndex].prize ?? 0) + diff
        }
    }

    func adjustForZeroTray(syncRotation: Int) {
        saveState(); let diff = syncRotation - totalRotations; totalRotations = syncRotation
        if currentState == .normal { normalRotations += diff }
    }

    /// データランプなどに表示されているゲーム数とアプリを合わせる。通常時は normalRotations も同期
    func syncTotalRotations(newTotal: Int) {
        saveState()
        totalRotations = newTotal
        if currentState == .normal { normalRotations = newTotal }
    }

    /// 当選時点の投資・持ち玉に合わせて lendingRecords と totalHoldings を上書き（大当たり入力時に使用）
    func syncToSnapshot(cashYen: Int, holdingsBalls: Int, totalHoldingsCount: Int) {
        saveState()
        let cashUnits = max(0, cashYen / 500)
        let hBalls = max(0, holdingsBalls)
        totalHoldings = max(0, totalHoldingsCount)
        lendingRecords.removeAll()
        for _ in 0..<cashUnits {
            lendingRecords.append(LendingRecord(type: .cash, timestamp: Date()))
        }
        if hBalls > 0 {
            lendingRecords.append(LendingRecord(type: .holdings, timestamp: Date(), balls: hBalls))
        }
    }

    /// 新規遊技開始時：台の表示数に合わせるだけ。回転率には自分の回転のみ使うため normalRotations は 0 のまま
    func setInitialDisplayRotation(_ n: Int) {
        saveState()
        let v = max(0, n)
        initialDisplayRotation = v
        totalRotations = v
        normalRotations = 0
    }

    /// 開始時の台表示数をあとから修正（表示を合わせるだけ・normalRotations は変えない）
    func correctInitialDisplayRotation(to newValue: Int) {
        saveState()
        let v = max(0, newValue)
        let diff = v - initialDisplayRotation
        initialDisplayRotation = v
        totalRotations += diff
    }

    /// 当選時点などに回転数を合わせる（回転率に含める）。syncTotalRotations と同じ
    func setRotationsTo(_ n: Int) {
        saveState()
        let v = max(0, n)
        totalRotations = v
        if currentState == .normal { normalRotations = v }
    }

    /// 現金投資額をあとから修正（500円単位。持ち玉投資はそのまま）
    func setCashInvestment(yen: Int) {
        saveState()
        let cashUnits = max(0, yen / 500)
        let holdingsOnly = lendingRecords.filter { $0.type == .holdings }
        lendingRecords = (0..<cashUnits).map { _ in LendingRecord(type: .cash, timestamp: Date()) } + holdingsOnly
    }

    /// 持ち玉投資（玉数）をあとから修正。現金投資はそのまま
    func setHoldingsInvested(balls: Int) {
        saveState()
        let cashOnly = lendingRecords.filter { $0.type == .cash }
        let h = max(0, balls)
        if h == 0 {
            lendingRecords = cashOnly
        } else {
            lendingRecords = cashOnly + [LendingRecord(type: .holdings, timestamp: Date(), balls: h)]
        }
    }

    /// 直近1回の操作を取り消す。最大3回までスタックから復元。
    func undoLastAction() {
        guard let s = undoStack.popLast() else { return }
        totalRotations = s.totalRotations
        normalRotations = s.normalRotations
        totalHoldings = s.totalHoldings
        currentState = s.currentState
        remainingSupportCount = s.remainingSupportCount
        isTimeShortMode = s.isTimeShortMode
        winRecords = s.winRecords
        lendingRecords = s.lendingRecords
    }
    func updatePrize(id: UUID, newPrize: Int) {
        saveState()
        if let index = winRecords.firstIndex(where: { $0.id == id }) {
            let old = winRecords[index].prize ?? 0
            winRecords[index].prize = newPrize; totalHoldings += (newPrize - old)
        }
    }

    /// 大当たり1件を削除（連打で多く入力した場合など）。持ち玉からその分出玉を引く
    func deleteWinRecord(id: UUID) {
        saveState()
        if let index = winRecords.firstIndex(where: { $0.id == id }) {
            let prize = winRecords[index].prize ?? 0
            winRecords.remove(at: index)
            totalHoldings -= prize
        }
    }

    /// 実際の持ち玉数で同期（確変終了後など）。差額で totalHoldings を上書き
    func syncHoldings(actualHoldings: Int) {
        saveState()
        totalHoldings = max(0, actualHoldings)
    }
    private func saveState() {
        let s = StateSnapshot(
            totalRotations: totalRotations,
            normalRotations: normalRotations,
            totalHoldings: totalHoldings,
            currentState: currentState,
            remainingSupportCount: remainingSupportCount,
            isTimeShortMode: isTimeShortMode,
            winRecords: winRecords,
            lendingRecords: lendingRecords
        )
        undoStack.append(s)
        if undoStack.count > maxUndoCount {
            undoStack.removeFirst()
        }
    }
    func reset() {
        undoStack = []
        sessionStartDate = Date()
        chartTimeline = []
        totalHoldings = 0
        totalRotations = 0
        normalRotations = 0
        currentState = .normal
        remainingSupportCount = 0
        adjustedNetPerRound = nil
        winRecords = []
        lendingRecords = []
    }
}

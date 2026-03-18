import Foundation
import Observation

@Observable
final class GameLog {
    // 初期値としての仮データ（SelectionViewで上書きされます）
    var selectedMachine: Machine = Machine(name: "未選択", supportLimit: 100, defaultPrize: 1500)
    var selectedShop: Shop = Shop(name: "未選択", ballsPerCashUnit: 125, payoutCoefficient: 4.0)
    
    /// 初期持ち玉（syncHoldings/syncToSnapshot で調整され、totalHoldings 計算のベースになる）
    var initialHoldings: Int = 0
    var totalRotations: Int = 0
    var normalRotations: Int = 0
    /// 新規開始時に設定した台表示数（表示合わせのみ・あとから修正用）
    var initialDisplayRotation: Int = 0
    var currentState: PlayState = .normal
    /// フェーズ3: 現在の滞在モードID（0=通常, 1=RUSH, 2=LT）。データ駆動の遷移の真実のソース。
    var currentModeID: Int = 0
    /// 電サポまたは時短の残り回数（0で自動通常復帰）。ST電サポ・通常後の時短の両方で使用
    var remainingSupportCount: Int = 0
    /// 現在の時短/STフェーズ開始時の残り回数（前回大当たり以降のゲーム数表示用）
    var supportPhaseInitialCount: Int = 0
    /// 通常大当たり後の時短中か（表示を「時短中」にするため）
    var isTimeShortMode: Bool = false
    /// 遊技中の1R純増の手動調整値。nilなら機種のaverageNetPerRoundを使用
    var adjustedNetPerRound: Double?

    var winRecords: [WinRecord] = []
    var lendingRecords: [LendingRecord] = []

    /// Undo：最後に追加した Record の削除（最大3件）
    private enum UndoAction {
        case removeWin(id: UUID)
        case removeLending(id: UUID)
    }
    private var undoStack: [UndoAction] = []
    private let maxUndoCount = 3

    /// 持ち玉投資は 1タップ = 125玉。125未満の残りは全額投資として記録
    private let holdingsBallsPerTap: Int = 125

    init() {}

    /// 回転で消費した玉数（期待ベース＝回転/250玉 で按分）。収支グラフの過去時点計算用のみ。表示用持ち玉は減らさない（カウントタップで持ち玉が減らないようにする）
    private var consumedBallsByRotation: Int {
        let delta = totalRotations - initialDisplayRotation
        guard delta > 0 else { return 0 }
        let borderPer250 = max(dynamicBorder, 0.01)
        return Int((Double(delta) * 250.0 / borderPer250).rounded())
    }

    /// 持ち玉数（初期＋出玉−持ち玉投資のみ）。現金投資は投資額の把握のみで持ち玉は増やさない
    var totalHoldings: Int {
        let prizes = winRecords.reduce(0) { $0 + ($1.prize ?? 0) }
        let raw = initialHoldings + prizes - holdingsInvestedBalls
        return max(0, raw)
    }

    /// Undo 可能回数（0〜3）
    var undoCount: Int { undoStack.count }

    func incrementRotation() {
        addRotations(1)
    }

    /// 指定数だけ回転を加算（+10, +100 用）。時短/ST電サポ中は残り回数を減らし0で通常に復帰。総回転数は時短・ST中は加算しない（累積のみ）
    func addRotations(_ n: Int) {
        guard n > 0 else { return }
        var remaining = n
        while remaining > 0 {
            if currentState == .normal {
                totalRotations += 1
                normalRotations += 1
                remaining -= 1
            } else if (currentState == .support || currentState == .lt), remainingSupportCount > 0 {
                // 時短またはST電サポ（RUSH/LT）：残り回数カウントダウン、0で通常へ（総回転数は加算しない）
                remainingSupportCount -= 1
                remaining -= 1
                if remainingSupportCount <= 0 {
                    currentState = .normal
                    currentModeID = 0
                    isTimeShortMode = false
                }
            } else {
                // 確変電サポ（残り0＝手動復帰待ち）は総回転数も加算
                totalRotations += 1
                remaining -= 1
            }
        }
    }

    func addLending(type: LendingType) {
        if type == .holdings {
            let deduct = min(holdingsBallsPerTap, max(0, totalHoldings))
            guard deduct > 0 else { return }
            let record = LendingRecord(type: .holdings, timestamp: Date(), balls: deduct)
            lendingRecords.append(record)
            pushUndo(.removeLending(id: record.id))
        } else {
            let record = LendingRecord(type: .cash, timestamp: Date())
            lendingRecords.append(record)
            pushUndo(.removeLending(id: record.id))
        }
    }

    /// クイック投入：指定pt（500pt単位）を一括で現金投入として追加。例: addCashInput(5000) で 5k
    func addCashInput(pt: Int) {
        let units = max(0, pt / 500)
        guard units > 0 else { return }
        for _ in 0..<units {
            let record = LendingRecord(type: .cash, timestamp: Date())
            lendingRecords.append(record)
            pushUndo(.removeLending(id: record.id))
        }
    }

    /// 持ち玉投資：指定玉数を一括で記録。125・500・1000玉など
    func addHoldingsInvestment(balls: Int) {
        let deduct = min(balls, max(0, totalHoldings))
        guard deduct > 0 else { return }
        let record = LendingRecord(type: .holdings, timestamp: Date(), balls: deduct)
        lendingRecords.append(record)
        pushUndo(.removeLending(id: record.id))
    }

    func toggleLendingType(id: UUID) {
        guard let index = lendingRecords.firstIndex(where: { $0.id == id }) else { return }
        if lendingRecords[index].type == .cash {
            let deduct = min(holdingsBallsPerTap, max(0, totalHoldings))
            lendingRecords[index].type = .holdings
            lendingRecords[index].balls = deduct
        } else {
            lendingRecords[index].type = .cash
            lendingRecords[index].balls = nil
        }
    }

    /// 当たり1回あたりの持ち玉（1R想定: 実戦1R純増）
    var effectiveBallsPerHit: Int {
        return Int(round(effective1RNetPerRound))
    }

    /// mode_id から WinType を返す（0=通常, 1=RUSH, 2=LT）
    private static func winType(from modeId: Int) -> WinType {
        switch modeId {
        case 1: return .rush
        case 2: return .lt
        default: return .normal
        }
    }

    /// 当たり1回適用後の状態更新（currentModeID / 電サポ・時短 / currentState）。recordHit と addWin の共通処理。
    private func setStateAfterHit(nextModeId: Int, densapo: Int) {
        currentModeID = nextModeId
        remainingSupportCount = max(0, densapo)
        supportPhaseInitialCount = remainingSupportCount
        if nextModeId == 0 {
            currentState = remainingSupportCount > 0 ? .support : .normal
            isTimeShortMode = remainingSupportCount > 0
        } else if nextModeId == 1 {
            currentState = .support
            isTimeShortMode = false
        } else {
            currentState = .lt
            isTimeShortMode = false
        }
    }

    /// フェーズ3: データ駆動の当たり記録。BonusDetail に従い履歴追加・出玉加算・currentModeID と電サポを更新する。既存の addWin と併存。
    func recordHit(bonus: BonusDetail, atRotation: Int) {
        recordHit(bonus: bonus, totalPrize: nil, atRotation: atRotation)
    }

    /// ユニット連結型対応: totalPrize を渡すとその値で確定（nilなら baseOut を使用）
    func recordHit(bonus: BonusDetail, totalPrize: Int?, atRotation: Int) {
        let diff = atRotation - totalRotations
        if diff != 0, currentState == .normal { normalRotations += diff }
        let resolvedBase = bonus.baseOut > 0 ? bonus.baseOut : bonus.payout
        let raw = totalPrize ?? (resolvedBase > 0 ? resolvedBase : effectiveBallsPerHit)
        let prize = max(0, raw)
        var record = WinRecord(
            type: Self.winType(from: currentModeID),
            prize: prize,
            rotationAtWin: atRotation,
            normalRotationsAtWin: normalRotations
        )
        record.timestamp = Date()
        record.modeIdAtWin = currentModeID
        record.nextModeId = bonus.nextModeId
        record.bonusName = bonus.name
        winRecords.append(record)
        pushUndo(.removeWin(id: record.id))
        totalRotations = atRotation
        setStateAfterHit(nextModeId: bonus.nextModeId, densapo: bonus.densapo)
    }

    /// 大当たりを1件追加。prizeBalls を指定した場合はその玉数（純増）を使用、nil の場合は effectiveBallsPerHit を使用。
    /// timeShortFromHit: 単発（通常）当たりで採用した当たりの時短ゲーム数。指定時は機種の timeShortRotations の代わりにこれを時短残りに加算する。
    func addWin(type: WinType, atRotation: Int, prizeBalls: Int? = nil, timeShortFromHit: Int? = nil) {
        let diff = atRotation - totalRotations
        if diff != 0 && currentState == .normal { normalRotations += diff }
        let prize = prizeBalls ?? effectiveBallsPerHit
        var record = WinRecord(type: type, prize: prize, rotationAtWin: atRotation, normalRotationsAtWin: normalRotations)
        record.timestamp = Date()
        winRecords.append(record)
        pushUndo(.removeWin(id: record.id))
        totalRotations = atRotation
        let (nextModeId, densapo): (Int, Int)
        if type == .normal {
            let timeShort = timeShortFromHit ?? selectedMachine.timeShortRotations
            nextModeId = 0
            densapo = timeShort > 0 ? timeShort : 0
        } else if type == .lt {
            nextModeId = 2
            densapo = selectedMachine.isST ? selectedMachine.supportLimit : 0
        } else {
            nextModeId = 1
            densapo = selectedMachine.isST ? selectedMachine.supportLimit : 0
        }
        currentModeID = nextModeId
        setStateAfterHit(nextModeId: nextModeId, densapo: densapo)
    }

    /// カウントボタン表示用：前回大当たり以降のゲーム数（時短・ST抜けゲーム数含む）
    var gamesSinceLastWin: Int {
        let lastRot = winRecords.last?.rotationAtWin ?? 0
        if winRecords.isEmpty {
            return totalRotations
        }
        let normalSinceWin = totalRotations - lastRot
        let supportPlayed = (currentState == .support || currentState == .lt)
            ? (supportPhaseInitialCount - remainingSupportCount)
            : supportPhaseInitialCount
        return normalSinceWin + supportPlayed
    }

    // 計算用
    var totalInput: Int { lendingRecords.filter { $0.type == .cash }.count * 500 }
    /// RUSH 当選回数
    var rushWinCount: Int { winRecords.filter { $0.type == .rush }.count }
    /// 通常当選回数
    var normalWinCount: Int { winRecords.filter { $0.type == .normal }.count }
    /// LT（上位RUSH）当選回数
    var ltWinCount: Int { winRecords.filter { $0.type == .lt }.count }

    /// 現在の RUSH 連チャン回数（直近から遡って連続する .rush と .lt の件数）。.normal で終わっていれば 0。
    var currentRushChainCount: Int {
        var count = 0
        for r in winRecords.reversed() {
            if r.type == .rush || r.type == .lt { count += 1 }
            else { break }
        }
        return count
    }
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
        let holdingsCost = Double(holdingsInvestedBalls) * selectedShop.payoutCoefficient
        return cashCost + holdingsCost
    }

    /// 収入（pt）。出玉×払出係数を500pt刻みで端数切り捨て
    var incomePt500Step: Int {
        let raw = Double(totalHoldings) * selectedShop.payoutCoefficient
        return Int(raw / 500) * 500
    }

    /// 今回の成績（pt）。収入 − 投入
    var balancePt: Int { incomePt500Step - totalInput }

    /// 現在の損益（pt）。投入＋持ち玉投入（払出係数でpt換算）に対する、現在の持ち玉（払出係数でpt換算）の差。正＝黒字側
    var chartProfitPt: Double {
        let rate = selectedShop.payoutCoefficient
        let currentValue = Double(totalHoldings) * rate
        let cost = Double(totalInput) + Double(holdingsInvestedBalls) * rate
        return currentValue - cost
    }

    /// 成績グラフ用プロット。横軸＝総回転数（電サポ・時短を除く通常ゲーム累積）。縦軸＝損益（pt）
    var liveChartPoints: [(Int, Double)] {
        if let cached = _cachedLiveChartPoints, _lastChartStateHash == chartStateHash {
            return cached
        }
        let rate = selectedShop.payoutCoefficient
        var points: [(Int, Double)] = [(0, 0)]
        let winsOrdered = winRecords.sorted { ($0.timestamp ?? .distantPast) < ($1.timestamp ?? .distantPast) }
        let lendingsOrdered = lendingRecords.sorted { ($0.timestamp) < ($1.timestamp) }
        
        var cumulativePrize = 0
        var currentLendingIndex = 0
        var runningInvYen = 0
        var runningHoldBalls = 0

        for win in winsOrdered {
            let t = win.timestamp ?? .distantPast
            
            while currentLendingIndex < lendingsOrdered.count && lendingsOrdered[currentLendingIndex].timestamp < t {
                let l = lendingsOrdered[currentLendingIndex]
                if l.type == .cash {
                    runningInvYen += 500
                } else {
                    runningHoldBalls += l.balls ?? holdingsBallsPerTap
                }
                currentLendingIndex += 1
            }
            
            cumulativePrize += win.prize ?? 0
            let holdingsAtWin = initialHoldings + cumulativePrize - runningHoldBalls - consumedBallsAt(rotation: win.rotationAtWin)
            let cost = Double(runningInvYen) + Double(runningHoldBalls) * rate
            let profit = Double(max(0, holdingsAtWin)) * rate - cost
            let xRot = win.normalRotationsAtWin ?? win.rotationAtWin
            points.append((xRot, profit))
        }
        
        let lastWinNormal = winsOrdered.last.flatMap { $0.normalRotationsAtWin ?? Optional($0.rotationAtWin) } ?? -1
        if normalRotations > lastWinNormal {
            points.append((normalRotations, chartProfitPt))
        }
        
        _cachedLiveChartPoints = points
        _lastChartStateHash = chartStateHash
        return points
    }

    @ObservationIgnored private var _cachedLiveChartPoints: [(Int, Double)]?
    @ObservationIgnored private var _lastChartStateHash: Int = 0

    private var chartStateHash: Int {
        var hasher = Hasher()
        hasher.combine(winRecords.count)
        if let last = winRecords.last {
            hasher.combine(last.id)
            hasher.combine(last.prize)
            hasher.combine(last.rotationAtWin)
            hasher.combine(last.normalRotationsAtWin)
        }
        hasher.combine(lendingRecords.count)
        if let last = lendingRecords.last {
            hasher.combine(last.id)
        }
        hasher.combine(normalRotations)
        hasher.combine(totalRotations)
        hasher.combine(selectedShop.payoutCoefficient)
        hasher.combine(initialHoldings)
        hasher.combine(initialDisplayRotation)
        hasher.combine(dynamicBorder)
        return hasher.finalize()
    }

    /// 指定回転数時点での消費玉数（liveChartPoints 用）
    private func consumedBallsAt(rotation: Int) -> Int {
        let delta = rotation - initialDisplayRotation
        guard delta > 0 else { return 0 }
        let borderPer250 = max(dynamicBorder, 0.01)
        return Int((Double(delta) * 250.0 / borderPer250).rounded())
    }

    /// 実戦で使う1Rあたり純増（遊技中調整 or 機種のaverageNetPerRound）
    var effective1RNetPerRound: Double {
        adjustedNetPerRound ?? selectedMachine.averageNetPerRound
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

    /// 公式基準値（回転/1000pt）。メーカー公表値（機種マスターまたはユーザー入力の border）に、
    /// 店舗の貸玉料金（1000ptあたり玉数）と払出係数（pt/玉）を考慮して算出。
    /// 公式＝等価(4pt/玉・250玉/1000pt)基準。実戦 = 公式 × (貸玉料金/250) × (4/払出係数)
    /// ※通常回転のみ（時短・電サポは含めない）。実質回転率と比較可能。
    var dynamicBorder: Double {
        let rate = selectedShop.payoutCoefficient
        guard rate > 0 else { return 0 }
        let ballsPer1000 = Double(selectedShop.ballsPerCashUnit * 2)
        guard ballsPer1000 > 0 else { return 0 }
        let formula = formulaBorderAsNumber
        let loanCorrection = ballsPer1000 / 250.0   // 250玉基準→貸玉料金に変更（230玉なら×0.92）
        let exchangeCorrection = 4.0 / rate         // 払出係数補正
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

    /// 実践基準値用：店舗の貸玉料金を考慮した「単位」数。1単位＝等価1000pt(250玉)。投入ptを貸玉料金で換算
    var effectiveUnitsForBorder: Double {
        let ballsPer1000 = Double(selectedShop.ballsPerCashUnit * 2)
        let cashUnits = ballsPer1000 > 0 ? Double(totalInput) * ballsPer1000 / 250000.0 : Double(totalInput) / 1000.0
        return cashUnits + Double(holdingsInvestedBalls) / 250.0
    }

    /// 理論値（実戦基準値比）。実質回転率（1000pt・250玉単位）÷ 実戦基準値。1.0で基準、>1で上回り
    var expectationRatio: Double {
        if let cached = _cachedExpectationRatio, _lastExpectationStateHash == expectationStateHash {
            return cached
        }
        let ratio: Double
        if dynamicBorder > 0 && effectiveUnitsForBorder > 0 {
            ratio = realRate / dynamicBorder
        } else {
            ratio = 0
        }
        _cachedExpectationRatio = ratio
        _lastExpectationStateHash = expectationStateHash
        return ratio
    }
    
    @ObservationIgnored private var _cachedExpectationRatio: Double?
    @ObservationIgnored private var _lastExpectationStateHash: Int = 0
    
    private var expectationStateHash: Int {
        var hasher = Hasher()
        hasher.combine(totalInput)
        hasher.combine(holdingsInvestedBalls)
        hasher.combine(selectedShop.payoutCoefficient)
        hasher.combine(selectedShop.ballsPerCashUnit)
        hasher.combine(formulaBorderAsNumber)
        hasher.combine(effective1RNetPerRound)
        hasher.combine(selectedMachine.probabilityDenominator)
        hasher.combine(normalRotations)
        return hasher.finalize()
    }

    /// 実質回転率（回転/単位）。1単位＝現金1000pt または 持ち玉250玉。店舗の貸玉料金・払出係数は実戦基準値側で参照
    /// 分子は normalRotations（通常回転のみ・時短・電サポ除く）。公式基準値と同定義。
    var realRate: Double {
        effectiveUnitsForBorder > 0 ? Double(normalRotations) / effectiveUnitsForBorder : 0.0
    }

    /// 実費ベースの回転率（回転/千pt）。現金＋持ち玉（払出係数でpt換算）の実費で割る。ゲージの補足表示用
    var rotationPer1000Yen: Double {
        let realCostThousands = totalRealCost / 1000.0
        guard realCostThousands > 0 else { return 0 }
        return Double(normalRotations) / realCostThousands
    }

    /// 手動で通常へ復帰（確変の「通常落ち」やST・時短の手動切り上げ）
    func backToNormalManually() {
        currentModeID = 0
        currentState = .normal
        remainingSupportCount = 0
        isTimeShortMode = false
    }

    /// チャンスモードで「時短終了」押下時。通常へ復帰（総回転数は時短中加算していないのでそのまま）
    func endTimeShortAndReturnToNormal() {
        currentModeID = 0
        currentState = .normal
        remainingSupportCount = 0
        isTimeShortMode = false
    }

    /// フォーカスモードで「RUSH終了」押下時。通常へ復帰（総回転数はST中加算していないのでそのまま）
    func endRushAndReturnToNormal() {
        currentModeID = 0
        currentState = .normal
        remainingSupportCount = 0
        isTimeShortMode = false
    }

    /// フォーカスモードで「LT終了」押下時。通常へ復帰
    func endLtAndReturnToNormal() {
        currentModeID = 0
        currentState = .normal
        remainingSupportCount = 0
        isTimeShortMode = false
    }

    /// RUSHモードからLTモードへ切り替え（機種がRUSH→LT可のとき）
    func switchToLtMode() {
        currentModeID = 2
        currentState = .lt
        // remainingSupportCount / supportPhaseInitialCount はそのまま
    }

    /// 手動で電サポ中に切り替え（STのときは残り回数をセットしてカウントダウン開始）
    func enterSupportManually() {
        currentModeID = 1
        currentState = .support
        isTimeShortMode = false
        if selectedMachine.isST {
            remainingSupportCount = selectedMachine.supportLimit
            supportPhaseInitialCount = selectedMachine.supportLimit
        } else {
            remainingSupportCount = 0
            supportPhaseInitialCount = 0
        }
    }

    /// RUSH終了時に獲得出玉・終了時回転数・RUSHゲーム数を反映する。RUSH終了UIで確定時に呼び出す。
    /// - Parameters:
    ///   - finalTotal: このRUSHの獲得出玉（玉数）
    ///   - rotationAtEnd: RUSH終了時の回転数（未指定なら最後の記録のまま）。反映後に totalRotations もこの値に合わせる
    ///   - rushGamesPlayed: このRUSHで遊んだ総ゲーム数（時短抜け含む）。任意
    func fixTotalChainPrize(finalTotal: Int, rotationAtEnd: Int? = nil, rushGamesPlayed: Int? = nil) {
        let currentTotal = winRecords.reduce(0) { $0 + ($1.prize ?? 0) }
        let diff = finalTotal - currentTotal
        guard let lastIndex = winRecords.indices.last else { return }
        var last = winRecords[lastIndex]
        last.prize = (last.prize ?? 0) + diff
        if let rot = rotationAtEnd, rot >= 0 {
            last.rotationAtWin = rot
        }
        last.rushGamesPlayed = rushGamesPlayed
        winRecords[lastIndex] = last
        // RUSH終了後の表示整合：総回転数を終了時回転数に合わせる（RUSH中は加算していないため）
        if let rot = rotationAtEnd, rot >= 0 {
            totalRotations = rot
        }
    }

    func adjustForZeroTray(syncRotation: Int) {
        let lastRot = winRecords.last?.rotationAtWin ?? 0
        // syncRotation はランプ表示（電サポ/時短込み）想定。
        // 回転率（normalRotations）は「投資して回した分（電サポ/時短除外）」のみなので、差分変換する。
        let currentPaidSinceLastWin = max(0, normalRotations - lastRot)
        let currentLampSinceLastWin = max(0, gamesSinceLastWin)
        let freeSinceLastWin = max(0, currentLampSinceLastWin - currentPaidSinceLastWin)
        let paidFromInput = max(0, syncRotation - freeSinceLastWin)

        // 内部の totalRotations / normalRotations は「電サポ・時短を除く有料回転」基準に揃える
        totalRotations = lastRot + paidFromInput
        normalRotations = lastRot + paidFromInput
    }

    /// データランプなどに表示されているゲーム数（当選後からの回転数）とアプリを合わせる。総回転数は累積のまま
    func syncTotalRotations(newTotal: Int) {
        let lastRot = winRecords.last?.rotationAtWin ?? 0
        // newTotal はランプ表示（電サポ/時短込み）想定。
        // 回転率（normalRotations）は「投資して回した分（電サポ/時短除外）」のみなので、差分変換する。
        let currentPaidSinceLastWin = max(0, normalRotations - lastRot)
        let currentLampSinceLastWin = max(0, gamesSinceLastWin)
        let freeSinceLastWin = max(0, currentLampSinceLastWin - currentPaidSinceLastWin)
        let paidFromInput = max(0, newTotal - freeSinceLastWin)

        // 内部の totalRotations / normalRotations は「電サポ・時短を除く有料回転」基準に揃える
        totalRotations = lastRot + paidFromInput
        normalRotations = lastRot + paidFromInput
    }

    /// 当選時点の投資・持ち玉に合わせて lendingRecords と initialHoldings を設定（大当たり入力時に使用）
    func syncToSnapshot(cashYen: Int, holdingsBalls: Int, totalHoldingsCount: Int) {
        let cashUnits = max(0, cashYen / 500)
        let hBalls = max(0, holdingsBalls)
        lendingRecords.removeAll()
        for _ in 0..<cashUnits {
            lendingRecords.append(LendingRecord(type: .cash, timestamp: Date()))
        }
        if hBalls > 0 {
            lendingRecords.append(LendingRecord(type: .holdings, timestamp: Date(), balls: hBalls))
        }
        let prizes = winRecords.reduce(0) { $0 + ($1.prize ?? 0) }
        initialHoldings = max(0, totalHoldingsCount - prizes + holdingsInvestedBalls)
    }

    /// 新規遊技開始時：台の表示数に合わせるだけ。回転率には自分の回転のみ使うため normalRotations は 0 のまま
    func setInitialDisplayRotation(_ n: Int) {
        let v = max(0, n)
        initialDisplayRotation = v
        totalRotations = v
        normalRotations = 0
    }

    /// 開始時の台表示数をあとから修正（表示を合わせるだけ・normalRotations は変えない）
    func correctInitialDisplayRotation(to newValue: Int) {
        let v = max(0, newValue)
        let diff = v - initialDisplayRotation
        initialDisplayRotation = v
        totalRotations += diff
    }

    /// 当選時点などに回転数を合わせる（回転率に含める）。syncTotalRotations と同じ
    func setRotationsTo(_ n: Int) {
        let v = max(0, n)
        // setRotationsTo は入力値を「有料回転」として扱い揃える（現状この関数は未使用）
        totalRotations = v
        normalRotations = v
    }

    /// 現金投入額をあとから修正（500pt単位。持ち玉投入はそのまま）
    func setCashInput(pt: Int) {
        let cashUnits = max(0, pt / 500)
        let holdingsOnly = lendingRecords.filter { $0.type == .holdings }
        lendingRecords = (0..<cashUnits).map { _ in LendingRecord(type: .cash, timestamp: Date()) } + holdingsOnly
    }

    /// 持ち玉投資（玉数）をあとから修正。現金投資はそのまま
    func setHoldingsInvested(balls: Int) {
        let cashOnly = lendingRecords.filter { $0.type == .cash }
        let h = max(0, balls)
        if h == 0 {
            lendingRecords = cashOnly
        } else {
            lendingRecords = cashOnly + [LendingRecord(type: .holdings, timestamp: Date(), balls: h)]
        }
    }

    /// 当選回数をあとから修正（RUSH回数・通常回数）。持ち玉数は変更しない
    func setWinCounts(rush: Int, normal: Int) {
        let r = max(0, rush)
        let n = max(0, normal)
        let rushRecords = (0..<r).map { _ in WinRecord(type: .rush, prize: 0, rotationAtWin: 0) }
        let normalRecords = (0..<n).map { _ in WinRecord(type: .normal, prize: 0, rotationAtWin: 0) }
        winRecords = rushRecords + normalRecords
    }

    /// 直近1回の操作を取り消す（最後に追加した Win または Lending を削除）。最大3回まで
    func undoLastAction() {
        guard let action = undoStack.popLast() else { return }
        switch action {
        case .removeWin(id: let id):
            winRecords.removeAll { $0.id == id }
        case .removeLending(id: let id):
            lendingRecords.removeAll { $0.id == id }
        }
    }

    private func pushUndo(_ action: UndoAction) {
        undoStack.append(action)
        if undoStack.count > maxUndoCount {
            undoStack.removeFirst()
        }
    }

    func updatePrize(id: UUID, newPrize: Int) {
        if let index = winRecords.firstIndex(where: { $0.id == id }) {
            winRecords[index].prize = newPrize
        }
    }

    /// 大当たり1件を削除（連打で多く入力した場合など）
    func deleteWinRecord(id: UUID) {
        winRecords.removeAll { $0.id == id }
    }

    /// 投資1件を削除（履歴編集用）
    func deleteLendingRecord(id: UUID) {
        lendingRecords.removeAll { $0.id == id }
    }

    /// 大当たりの回転数を修正（履歴編集用）
    func updateWinRotation(id: UUID, rotationAtWin: Int) {
        if let index = winRecords.firstIndex(where: { $0.id == id }) {
            winRecords[index].rotationAtWin = rotationAtWin
        }
    }

    /// 大当たりの種別を修正（履歴編集用）
    func updateWinType(id: UUID, newType: WinType) {
        if let index = winRecords.firstIndex(where: { $0.id == id }) {
            winRecords[index].type = newType
        }
    }

    /// 最後に記録した通常大当たりをRUSH大当たりに昇格させ、RUSHモードへ移行する（チャンスモード等から呼ぶ）。recordHit 相当の状態遷移に寄せた実装。
    func promoteLastNormalToRush() {
        if let lastNormalIndex = winRecords.lastIndex(where: { $0.type == .normal }) {
            winRecords[lastNormalIndex].type = .rush
            winRecords[lastNormalIndex].nextModeId = 1
        }
        let densapo = selectedMachine.isST ? selectedMachine.supportLimit : 0
        setStateAfterHit(nextModeId: 1, densapo: densapo)
    }

    /// 最後に記録した通常大当たりをLT大当たりに昇格させ、LTモードへ移行する。recordHit 相当の状態遷移に寄せた実装。
    func promoteLastNormalToLt() {
        if let lastNormalIndex = winRecords.lastIndex(where: { $0.type == .normal }) {
            winRecords[lastNormalIndex].type = .lt
            winRecords[lastNormalIndex].nextModeId = 2
        }
        let densapo = selectedMachine.isST ? selectedMachine.supportLimit : 0
        setStateAfterHit(nextModeId: 2, densapo: densapo)
    }

    /// 投資1件の内容を差し替え（履歴編集用・timestamp は維持）
    func replaceLendingRecord(id: UUID, type: LendingType, balls: Int?) {
        guard let index = lendingRecords.firstIndex(where: { $0.id == id }) else { return }
        let old = lendingRecords[index]
        lendingRecords[index] = LendingRecord(id: old.id, type: type, timestamp: old.timestamp, balls: balls)
    }

    /// 実際の持ち玉数で同期（終了時や確変終了後など）。
    /// アプリ上の持ち玉(totalHoldings)との差分を計算し、差分を持ち玉投資として追加・相殺する。
    func syncHoldings(actualHoldings: Int) {
        let currentHoldings = totalHoldings
        let diff = currentHoldings - actualHoldings
        
        if diff > 0 {
            // アプリ上の方が多い場合 -> 実戦ではより多く消費（投資）していた
            // 不足分を持ち玉投資として追加
            lendingRecords.append(LendingRecord(type: .holdings, timestamp: Date(), balls: diff))
        } else if diff < 0 {
            // アプリ上の方が少ない場合 -> 実戦では思ったより消費していなかった（または出玉が多かった）
            // マイナスの持ち玉投資（=回収）として追加して相殺
            lendingRecords.append(LendingRecord(type: .holdings, timestamp: Date(), balls: diff))
        }
    }

    func reset() {
        undoStack = []
        initialHoldings = 0
        initialDisplayRotation = 0
        totalRotations = 0
        normalRotations = 0
        currentState = .normal
        currentModeID = 0
        remainingSupportCount = 0
        supportPhaseInitialCount = 0
        isTimeShortMode = false
        adjustedNetPerRound = nil
        winRecords = []
        lendingRecords = []
    }

    /// 現在LTモード（上位RUSH）中か
    var isLtMode: Bool { currentState == .lt }

    /// 続きから：永続化した状態をログに反映する。機種・店舗は呼び出し元で解決済みのものを渡す
    func applyResumableState(_ state: ResumableState, machine: Machine, shop: Shop) {
        selectedMachine = machine
        selectedShop = shop
        initialHoldings = state.initialHoldings
        totalRotations = state.totalRotations
        normalRotations = state.normalRotations
        initialDisplayRotation = state.initialDisplayRotation
        currentState = state.currentState
        currentModeID = state.currentModeID ?? Self.resolvedModeID(from: state.currentState, isTimeShortMode: state.isTimeShortMode)
        remainingSupportCount = state.remainingSupportCount
        supportPhaseInitialCount = state.supportPhaseInitialCount
        isTimeShortMode = state.isTimeShortMode
        adjustedNetPerRound = state.adjustedNetPerRound
        winRecords = state.winRecords
        lendingRecords = state.lendingRecords
        undoStack = []
    }

    /// 保存データに currentModeID が無いとき、currentState から復元する
    private static func resolvedModeID(from currentState: PlayState, isTimeShortMode: Bool) -> Int {
        switch currentState {
        case .lt: return 2
        case .support: return isTimeShortMode ? 0 : 1
        case .normal: return 0
        }
    }
}

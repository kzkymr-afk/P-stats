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
    /// 現在滞在モードの UI ロール（0=通常系, 1=RUSH系, 2=LT）。`mode_id` が 1〜8 でも履歴の WinType・表示と整合させる。
    var currentModeUiRole: Int = 0
    /// 電サポまたは時短の残り回数（0で自動通常復帰）。ST電サポ・通常後の時短の両方で使用
    var remainingSupportCount: Int = 0
    /// 現在の時短/STフェーズ開始時の残り回数（前回大当たり以降のゲーム数表示用）
    var supportPhaseInitialCount: Int = 0
    /// 通常大当たり後の時短中か（表示を「時短中」にするため）
    var isTimeShortMode: Bool = false
    /// 遊技中の1R純増の手動調整値。nilなら機種のaverageNetPerRoundを使用
    var adjustedNetPerRound: Double?

    /// 大当たりモード（時短・RUSH・ST の代わりに、連チャン回数のみを扱う）
    var isBigHitMode: Bool = false
    /// 大当たりモード中の連チャン回数（表示用。確定は「通常へ」で入力）
    var bigHitChainCount: Int = 0

    var winRecords: [WinRecord] = []
    var lendingRecords: [LendingRecord] = []

    /// Undo：最後に追加した Record の削除（最大3件）。当たりは記録直前の回転・mode_id 状態も復元する。
    private enum UndoAction {
        case removeWin(id: UUID, before: RotationModeSnapshot)
        case removeLending(id: UUID)
    }
    private var undoStack: [UndoAction] = []
    private let maxUndoCount = 3

    private func captureRotationModeSnapshot() -> RotationModeSnapshot {
        RotationModeSnapshot(
            totalRotations: totalRotations,
            normalRotations: normalRotations,
            currentState: currentState,
            currentModeID: currentModeID,
            currentModeUiRole: currentModeUiRole,
            remainingSupportCount: remainingSupportCount,
            supportPhaseInitialCount: supportPhaseInitialCount,
            isTimeShortMode: isTimeShortMode,
            isBigHitMode: isBigHitMode,
            bigHitChainCount: bigHitChainCount
        )
    }

    private func restoreRotationModeSnapshot(_ s: RotationModeSnapshot) {
        totalRotations = s.totalRotations
        normalRotations = s.normalRotations
        currentState = s.currentState
        currentModeID = s.currentModeID
        currentModeUiRole = s.currentModeUiRole
        remainingSupportCount = s.remainingSupportCount
        supportPhaseInitialCount = s.supportPhaseInitialCount
        isTimeShortMode = s.isTimeShortMode
        isBigHitMode = s.isBigHitMode ?? false
        bigHitChainCount = s.bigHitChainCount ?? 0
    }

    /// 大当たりシートの「回転数」欄のデフォルト（増分）。`atRotation = 前回当たりの rotationAtWin + 入力` と整合するため、
    /// 前回当たり以降にカウンタタップで積んだ増分（`totalRotations` 差）を使う。電サポ中は total が進まないため通常のみの差分と一致しやすい。
    var defaultWinInputRotationIncrement: Int {
        guard let last = winRecords.last else { return totalRotations }
        return max(0, totalRotations - last.rotationAtWin)
    }

    /// 永続化用（ResumableState.undoStackEntries）
    func persistedUndoStack() -> [PersistedUndoEntry] {
        undoStack.map { action in
            switch action {
            case .removeWin(let id, let snap):
                return PersistedUndoEntry(isWin: true, recordId: id, modeSnapshot: snap)
            case .removeLending(let id):
                return PersistedUndoEntry(isWin: false, recordId: id, modeSnapshot: nil)
            }
        }
    }

    private func restoreUndoStack(from entries: [PersistedUndoEntry]?) {
        guard let entries = entries, !entries.isEmpty else {
            undoStack = []
            return
        }
        undoStack = entries.compactMap { e in
            if e.isWin, let s = e.modeSnapshot {
                return UndoAction.removeWin(id: e.recordId, before: s)
            }
            if !e.isWin {
                return UndoAction.removeLending(id: e.recordId)
            }
            return nil
        }
    }

    /// 持ち玉投資は 1タップ＝店の貸玉数（500ptと同単位の玉数）。残りが少ないときは全額
    private var holdingsBallsPerTap: Int { max(1, selectedShop.ballsPerCashUnit) }

    init() {}

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

    /// 指定数だけ回転を加算（+10, +100 用）。時短/ST電サポ中は残り回数を減らし0で通常に復帰。
    /// 電サポ中はタップごとに total は進めず、フェーズ終了時に「このフェーズで消化した回数」をまとめて totalRotations に加え、台ランプ累積と整合させる。
    func addRotations(_ n: Int) {
        guard n > 0 else { return }
        var remaining = n
        while remaining > 0 {
            if currentState == .normal {
                totalRotations += 1
                normalRotations += 1
                remaining -= 1
            } else if (currentState == .support || currentState == .lt), remainingSupportCount > 0 {
                remainingSupportCount -= 1
                remaining -= 1
                if remainingSupportCount <= 0 {
                    let phaseGames = supportPhaseInitialCount
                    if phaseGames > 0 {
                        totalRotations += phaseGames
                    }
                    supportPhaseInitialCount = 0
                    remainingSupportCount = 0
                    currentState = .normal
                    currentModeID = 0
                    currentModeUiRole = 0
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

    /// 持ち玉投資：指定玉数を一括で記録（省エネのスワイプなど）
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

    /// `next_mode_id` のみわかっている旧データ向けの ui_role 推定（従来分岐と整合）
    private static func inferredUiRole(fromModeId modeId: Int) -> Int {
        switch modeId {
        case 0: return 0
        case 1: return 1
        case 2: return 2
        default: return 2
        }
    }

    // MARK: - 大当たりモード（時短・RUSH・ST とは別系統。連チャン回数のみ→「通常へ」で回数と総出玉を確定）

    /// 通常画面から大当たりモードへ。回転・投資の蓄積は維持する。
    func enterBigHitMode() {
        isBigHitMode = true
        bigHitChainCount = 1
        currentState = .normal
        currentModeID = 0
        currentModeUiRole = 0
        remainingSupportCount = 0
        supportPhaseInitialCount = 0
        isTimeShortMode = false
    }

    func incrementBigHitChain() {
        guard isBigHitMode else { return }
        bigHitChainCount += 1
    }

    /// 棒グラフ用：大当たりモード中は未確定の1区間を末尾に表示（固定 ID で識別）
    static let provisionalBigHitChartId = UUID(uuidString: "A0000000-0000-4000-8000-000000000001")!

    /// 大当たり履歴グラフに渡す配列。大当たりモード中は連チャン数をリアルタイム反映した仮行を末尾に付与する。
    func winRecordsForChartDisplay() -> [WinRecord] {
        var r = winRecords
        if isBigHitMode, bigHitChainCount > 0 {
            var w = WinRecord(type: .normal, prize: nil, rotationAtWin: totalRotations, normalRotationsAtWin: normalRotations)
            w.id = Self.provisionalBigHitChartId
            w.bonusSessionHitCount = bigHitChainCount
            w.timestamp = Date()
            r.append(w)
        }
        return r
    }

    /// 大当たり1件の「連チャン含む回数」を修正（棒グラフの棒に対応）
    func updateBonusSessionHitCount(winId: UUID, count: Int) {
        guard winId != Self.provisionalBigHitChartId else { return }
        if let index = winRecords.firstIndex(where: { $0.id == winId }) {
            winRecords[index].bonusSessionHitCount = max(1, count)
        }
    }

    /// 大当たりモード終了。1区間の当たりとして `winRecords` に1件追加する。
    /// - Parameter electricSupportTurns: 確定後に消化する電サポ残り回数。0 なら即通常。電サポは `addRotations` で減算し、0 になった瞬間にそのフェーズ分が `totalRotations` にまとめて反映され、実機ランプ累積と揃う。
    func commitBigHitSessionToNormal(hitCount: Int, totalPrizeBalls: Int, electricSupportTurns: Int) {
        let beforeSnapshot = captureRotationModeSnapshot()
        let h = max(1, hitCount)
        let prize = max(0, totalPrizeBalls)
        let support = max(0, electricSupportTurns)
        var record = WinRecord(type: .normal, prize: prize, rotationAtWin: totalRotations, normalRotationsAtWin: normalRotations)
        record.timestamp = Date()
        record.bonusSessionHitCount = h
        winRecords.append(record)
        pushUndo(.removeWin(id: record.id, before: beforeSnapshot))
        isBigHitMode = false
        bigHitChainCount = 0
        currentModeID = 0
        currentModeUiRole = 0
        isTimeShortMode = false
        if support > 0 {
            currentState = .support
            remainingSupportCount = support
            supportPhaseInitialCount = support
        } else {
            currentState = .normal
            remainingSupportCount = 0
            supportPhaseInitialCount = 0
        }
    }

    /// 大当たりモードのみ終了し、`winRecords` には追加しない（誤タップで入った場合など）。回転・投入の累積はそのまま。
    func abandonBigHitSessionWithoutRecording() {
        guard isBigHitMode else { return }
        isBigHitMode = false
        bigHitChainCount = 0
    }

    /// カウントボタン表示用：前回大当たり以降のゲーム数（時短・ST抜けゲーム数含む）。
    /// 通常時は totalRotations - lastRot（電サポ終了時に total にフェーズ分をまとめて反映したあと整合）。
    /// 電サポ/LT 消化中は total がまだ進んでいないため、残りカウントダウン分を加算。
    var gamesSinceLastWin: Int {
        let lastRot = winRecords.last?.rotationAtWin ?? 0
        if winRecords.isEmpty {
            return totalRotations
        }
        let normalSinceWin = totalRotations - lastRot
        if currentState == .support || currentState == .lt {
            return normalSinceWin + (supportPhaseInitialCount - remainingSupportCount)
        }
        return normalSinceWin
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
            let consumedAtWin = consumedBallsForWin(win)
            let holdingsAtWin = initialHoldings + cumulativePrize - runningHoldBalls - consumedAtWin
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

    /// 当選時点までの消費玉数（liveChartPoints 用）。通常累積が取れるときは **通常回転のみ**（右打ち・電サポ相当を除外）で按分。旧データは総回転ベースで代替。
    private func consumedBallsForWin(_ win: WinRecord) -> Int {
        if let nr = win.normalRotationsAtWin {
            return consumedBallsAtNormalRotation(nr)
        }
        let delta = win.rotationAtWin - initialDisplayRotation
        guard delta > 0 else { return 0 }
        let borderPer250 = max(dynamicBorder, 0.01)
        return Int((Double(delta) * 250.0 / borderPer250).rounded())
    }

    private func consumedBallsAtNormalRotation(_ normalRotation: Int) -> Int {
        guard normalRotation > 0, dynamicBorder > 0 else { return 0 }
        return Int((Double(normalRotation) * 250.0 / dynamicBorder).rounded())
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
    /// 公式＝等価(4pt/玉・250玉/1000pt)基準。
    /// 実戦＝公式 × (250÷貸玉1000円玉数) × (4÷払出係数)。1000円あたり玉が少ないほど分母が小さくボーダーは上がる（厳しくなる）。
    /// 払出係数が等価4より大きい（換金が良い）ほど (4/係数) でボーダーは下がる。
    /// ※通常回転のみ（時短・電サポは含めない）。実質回転率と比較可能。
    var dynamicBorder: Double {
        let rate = selectedShop.payoutCoefficient
        guard rate > 0 else { return 0 }
        let ballsPer1000 = Double(selectedShop.ballsPerCashUnit * 2)
        guard ballsPer1000 > 0 else { return 0 }
        let formula = formulaBorderAsNumber
        let loanCorrection = 250.0 / ballsPer1000
        let exchangeCorrection = 4.0 / rate
        if formula > 0 {
            return formula * loanCorrection * exchangeCorrection
        }
        guard effective1RNetPerRound > 0 else { return 0 }
        let prob = selectedMachine.probabilityDenominator
        if prob > 0 {
            return prob * 250.0 / effective1RNetPerRound * loanCorrection * exchangeCorrection
        }
        // 確率未使用のフォールバック（旧式の貸玉項を打ち消して等価換算に統一）
        return 1000.0 / (effective1RNetPerRound * rate)
    }

    /// 実践基準値用：店舗の貸玉料金を考慮した「単位」数。1単位＝等価1000pt（＝貸玉×2）。投入ptを貸玉料金で換算
    var effectiveUnitsForBorder: Double {
        let ballsPer1000 = Double(max(1, selectedShop.ballsPerCashUnit * 2))
        let cashUnits = ballsPer1000 > 0 ? Double(totalInput) * ballsPer1000 / 250000.0 : Double(totalInput) / 1000.0
        return cashUnits + Double(holdingsInvestedBalls) / ballsPer1000
    }

    // MARK: - 撃ち玉（T / C / H）・持ち玉比率
    /// **T**：通常回転のタップから推定した消費玉数（時短・電サポ・右打ち中の回転は含めない。`normalRotations` のみ）。実戦基準値で 250 玉/回換算。
    var tapDerivedBallsConsumed: Int {
        guard dynamicBorder > 0, normalRotations > 0 else { return 0 }
        return Int((Double(normalRotations) * 250.0 / dynamicBorder).rounded())
    }

    /// **C**：現金投入から換算した撃ち玉数（店の貸玉料金）。
    var cashOriginBallsConsumed: Int {
        lendingRecords.filter { $0.type == .cash }.count * selectedShop.ballsPerCashUnit
    }

    /// **H**：持ち玉由来の撃ち玉数。二重計上防止のため **H = max(0, T − C)** で一意に定義（T＝`tapDerivedBallsConsumed`）。投入記録の持ち玉玉数と乖離しうる。
    var holdingsOriginBallsFromIdentity: Int {
        max(0, tapDerivedBallsConsumed - cashOriginBallsConsumed)
    }

    /// 持ち玉比率 **H / T**。T が 0 のときは nil。
    var holdingsUsageRatio: Double? {
        let t = tapDerivedBallsConsumed
        guard t > 0 else { return nil }
        return Double(holdingsOriginBallsFromIdentity) / Double(t)
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
        currentModeUiRole = 0
        currentState = .normal
        remainingSupportCount = 0
        isTimeShortMode = false
    }

    /// チャンスモードで「時短終了」押下時。通常へ復帰（総回転数は時短中加算していないのでそのまま）
    func endTimeShortAndReturnToNormal() {
        currentModeID = 0
        currentModeUiRole = 0
        currentState = .normal
        remainingSupportCount = 0
        isTimeShortMode = false
    }

    /// フォーカスモードで「RUSH終了」押下時。通常へ復帰（総回転数はST中加算していないのでそのまま）
    func endRushAndReturnToNormal() {
        currentModeID = 0
        currentModeUiRole = 0
        currentState = .normal
        remainingSupportCount = 0
        isTimeShortMode = false
    }

    /// フォーカスモードで「LT終了」押下時。通常へ復帰
    func endLtAndReturnToNormal() {
        currentModeID = 0
        currentModeUiRole = 0
        currentState = .normal
        remainingSupportCount = 0
        isTimeShortMode = false
    }

    /// RUSHモードからLTモードへ切り替え（機種がRUSH→LT可のとき）
    func switchToLtMode() {
        currentModeID = 2
        currentModeUiRole = 2
        currentState = .lt
        // remainingSupportCount / supportPhaseInitialCount はそのまま
    }

    /// 手動で電サポ中に切り替え（STのときは残り回数をセットしてカウントダウン開始）
    func enterSupportManually() {
        currentModeID = 1
        currentModeUiRole = 1
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
        case .removeWin(id: let id, before: let snap):
            winRecords.removeAll { $0.id == id }
            restoreRotationModeSnapshot(snap)
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
        currentModeUiRole = 0
        remainingSupportCount = 0
        supportPhaseInitialCount = 0
        isTimeShortMode = false
        adjustedNetPerRound = nil
        isBigHitMode = false
        bigHitChainCount = 0
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
        currentModeUiRole = state.currentModeUiRole
            ?? Self.inferredUiRole(fromModeId: currentModeID)
        remainingSupportCount = state.remainingSupportCount
        supportPhaseInitialCount = state.supportPhaseInitialCount
        isTimeShortMode = state.isTimeShortMode
        adjustedNetPerRound = state.adjustedNetPerRound
        winRecords = state.winRecords
        lendingRecords = state.lendingRecords
        isBigHitMode = state.isBigHitMode ?? false
        bigHitChainCount = state.bigHitChainCount ?? 0
        restoreUndoStack(from: state.undoStackEntries)
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

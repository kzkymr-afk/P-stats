import Foundation
import Observation

@Observable
final class GameLog {
    // 初期値としての仮データ（SelectionViewで上書きされます）
    var selectedMachine: Machine = Machine(name: "未選択", supportLimit: 100, defaultPrize: 1500)
    var selectedShop: Shop = Shop(
        name: "未選択",
        ballsPerCashUnit: PersistedDataSemantics.defaultBallsPer500Pt,
        payoutCoefficient: PersistedDataSemantics.defaultPayoutCoefficientPtPerBall
    )
    
    /// 初期持ち玉（syncHoldings/syncToSnapshot で調整され、totalHoldings 計算のベースになる）
    var initialHoldings: Int = 0
    var totalRotations: Int = 0
    var normalRotations: Int = 0
    /// 新規開始時に設定した台表示数（表示合わせのみ・あとから修正用）
    var initialDisplayRotation: Int = 0
    var currentState: PlayState = .normal
    /// フェーズ3: 現在の滞在モードID（マスタ由来。0=通常）
    var currentModeID: Int = 0
    /// 現在滞在モードの UI ロール（0=通常系, 1=RUSH系）。`mode_id` が 1〜8 でも表示と整合させる。
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
    /// 突入シートで確定した当選時点の通常回転（確定当たりレコードの横軸に使用）
    var bigHitSessionNormalRotationsAtWin: Int? = nil
    /// 突入シートで確定した当選時点の総回転（ランプ）
    var bigHitSessionTotalRotationsAtWin: Int? = nil

    var winRecords: [WinRecord] = []
    var lendingRecords: [LendingRecord] = []

    /// 実戦開始時刻（「続きから」復元・時給算出用）
    var sessionStartedAt: Date? = nil

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

    /// 持ち玉投資は 1タップ＝店の「持ち玉1回あたり」設定（未設定時は貸玉と同じ玉数）。残りが少ないときは全額
    private var holdingsBallsPerTap: Int { max(1, selectedShop.interpretedHoldingsBallsPerTap) }

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
            } else if currentState == .support, remainingSupportCount > 0 {
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

    /// クイック投資：指定pt（500pt単位）を一括で現金投資として追加。例: addCashInput(5000) で 5k
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
        case 1, 2: return 1
        default: return 1
        }
    }

    // MARK: - 大当たりモード（時短・RUSH・ST とは別系統。連チャン回数のみ→「通常へ」で回数と総出玉を確定）

    /// 通常画面から大当たりモードへ。回転・投資は `applyBigHitEntryAtWin` で揃えた後に呼ぶ。
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

    /// 大当たり突入時：当選時点の回転・投資を揃えてから大当たりモード開始。持ち玉は「投資玉数」と「残り玉数」のどちらか一方のみ指定。
    func applyBigHitEntryAtWin(normalRotationsAtWin: Int, cashPt: Int, holdingsInvestedBalls: Int?, remainingHoldingsBalls: Int?) {
        let cashUnits = max(0, cashPt / 500)
        reconcileCashLendingCount(toUnits: cashUnits)
        if let invested = holdingsInvestedBalls {
            reconcileHoldingsInvestedTotal(to: max(0, invested))
        } else if let rem = remainingHoldingsBalls {
            applyInitialHoldingsForRemainingAtWin(max(0, rem))
        }
        let n = max(0, normalRotationsAtWin)
        normalRotations = n
        totalRotations = max(totalRotations, n)
        bigHitSessionNormalRotationsAtWin = n
        bigHitSessionTotalRotationsAtWin = totalRotations
        enterBigHitMode()
    }

    private func reconcileCashLendingCount(toUnits target: Int) {
        let current = lendingRecords.filter { $0.type == .cash }.count
        if current > target {
            var remove = current - target
            for i in lendingRecords.indices.reversed() {
                guard lendingRecords[i].type == .cash else { continue }
                lendingRecords.remove(at: i)
                remove -= 1
                if remove == 0 { break }
            }
        } else if current < target {
            for _ in 0..<(target - current) {
                lendingRecords.append(LendingRecord(type: .cash, timestamp: Date()))
            }
        }
    }

    private func reconcileHoldingsInvestedTotal(to targetBalls: Int) {
        let target = max(0, targetBalls)
        let sum = holdingsInvestedBalls
        if sum > target {
            var needRemove = sum - target
            for i in lendingRecords.indices.reversed() {
                guard lendingRecords[i].type == .holdings else { continue }
                let b = lendingRecords[i].balls ?? holdingsBallsPerTap
                if b <= needRemove {
                    needRemove -= b
                    lendingRecords.remove(at: i)
                } else {
                    lendingRecords[i].balls = b - needRemove
                    needRemove = 0
                }
                if needRemove == 0 { break }
            }
        } else if sum < target {
            addHoldingsInvestment(balls: target - sum)
        }
    }

    private func applyInitialHoldingsForRemainingAtWin(_ remaining: Int) {
        let prizeSum = winRecords.reduce(0) { $0 + ($1.prize ?? 0) }
        initialHoldings = max(0, remaining + holdingsInvestedBalls - prizeSum)
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
            let rotW = bigHitSessionTotalRotationsAtWin ?? totalRotations
            let normW = bigHitSessionNormalRotationsAtWin ?? normalRotations
            var w = WinRecord(type: .normal, prize: nil, rotationAtWin: rotW, normalRotationsAtWin: normW)
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
    /// - Parameter electricSupportTurns: 大当たり確定の時点で **すでに消化した** 電サポのゲーム数。ランプ・「当選からのゲーム数」はこの分だけ進んだ扱いにし、通常へ即復帰する（残りカウントダウンにはしない）。
    func commitBigHitSessionToNormal(hitCount: Int, totalPrizeBalls: Int, electricSupportTurns: Int) {
        let beforeSnapshot = captureRotationModeSnapshot()
        let h = max(1, hitCount)
        let prize = max(0, totalPrizeBalls)
        let support = max(0, electricSupportTurns)
        let rotW = bigHitSessionTotalRotationsAtWin ?? totalRotations
        let normW = bigHitSessionNormalRotationsAtWin ?? normalRotations
        var record = WinRecord(type: .normal, prize: prize, rotationAtWin: rotW, normalRotationsAtWin: normW)
        record.timestamp = Date()
        record.bonusSessionHitCount = h
        winRecords.append(record)
        pushUndo(.removeWin(id: record.id, before: beforeSnapshot))
        isBigHitMode = false
        bigHitChainCount = 0
        bigHitSessionNormalRotationsAtWin = nil
        bigHitSessionTotalRotationsAtWin = nil
        currentModeID = 0
        currentModeUiRole = 0
        isTimeShortMode = false
        if support > 0 {
            totalRotations += support
        }
        currentState = .normal
        remainingSupportCount = 0
        supportPhaseInitialCount = 0
    }

    /// 大当たりモードのみ終了し、`winRecords` には追加しない（誤タップで入った場合など）。回転・投資の累積はそのまま。
    func abandonBigHitSessionWithoutRecording() {
        guard isBigHitMode else { return }
        isBigHitMode = false
        bigHitChainCount = 0
        bigHitSessionNormalRotationsAtWin = nil
        bigHitSessionTotalRotationsAtWin = nil
    }

    /// カウントボタン表示用：前回大当たり以降のゲーム数（時短・ST抜けゲーム数含む）。
    /// 通常時は totalRotations - lastRot（電サポ終了時に total にフェーズ分をまとめて反映したあと整合）。
    /// 電サポ消化中は total がまだ進んでいないため、残りカウントダウン分を加算。
    var gamesSinceLastWin: Int {
        let lastRot = winRecords.last?.rotationAtWin ?? 0
        if winRecords.isEmpty {
            return totalRotations
        }
        let normalSinceWin = totalRotations - lastRot
        if currentState == .support {
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

    /// 現在の RUSH 連チャン回数（直近から遡って連続する .rush の件数）。.normal で終わっていれば 0。
    var currentRushChainCount: Int {
        var count = 0
        for r in winRecords.reversed() {
            if r.type == .rush { count += 1 }
            else { break }
        }
        return count
    }
    var totalUsedBalls: Int {
        let cashBalls = lendingRecords.filter { $0.type == .cash }.count * selectedShop.interpretedBallsPer500Pt
        let holdingsBalls = lendingRecords.filter { $0.type == .holdings }.reduce(0) { $0 + ($1.balls ?? holdingsBallsPerTap) }
        return cashBalls + holdingsBalls
    }
    /// 持ち玉で投資した玉数（店補正後のボーダー・チャート損益の算出に使用）
    var holdingsInvestedBalls: Int {
        lendingRecords.filter { $0.type == .holdings }.reduce(0) { $0 + ($1.balls ?? holdingsBallsPerTap) }
    }

    var totalRealCost: Double {
        let cashCost = Double(lendingRecords.filter { $0.type == .cash }.count * 500)
        let holdingsCost = Double(holdingsInvestedBalls) * selectedShop.interpretedPayoutCoefficientPtPerBall
        return cashCost + holdingsCost
    }

    /// 初当たり（時系列で最初の当選）までの実質投資（pt）。当選が無いときは nil。
    func realCostAtFirstWin() -> Double? {
        guard !winRecords.isEmpty else { return nil }
        let sorted = winRecords.enumerated().sorted { a, b in
            let t0 = a.element.timestamp ?? .distantPast
            let t1 = b.element.timestamp ?? .distantPast
            if t0 != t1 { return t0 < t1 }
            return a.offset < b.offset
        }
        guard let first = sorted.first?.element else { return nil }
        let rate = selectedShop.interpretedPayoutCoefficientPtPerBall
        if let cutoff = first.timestamp {
            var runningCashYen = 0
            var runningHoldBalls = 0
            for l in lendingRecords.sorted(by: { $0.timestamp < $1.timestamp }) {
                if l.timestamp >= cutoff { break }
                if l.type == .cash { runningCashYen += 500 }
                else { runningHoldBalls += l.balls ?? holdingsBallsPerTap }
            }
            return Double(runningCashYen) + Double(runningHoldBalls) * rate
        }
        let n0 = Double(first.normalRotationsAtWin ?? first.rotationAtWin)
        let nTot = Double(max(normalRotations, 1))
        let ratio = min(1.0, max(0.0, n0 / nTot))
        return totalRealCost * ratio
    }

    /// 回収（pt）。出玉×払出係数を500pt刻みで端数切り捨て
    var incomePt500Step: Int {
        let raw = Double(totalHoldings) * selectedShop.interpretedPayoutCoefficientPtPerBall
        return Int(raw / 500) * 500
    }

    /// 今回の成績（pt）。回収 − 投入
    var balancePt: Int { incomePt500Step - totalInput }

    /// 現在の損益（pt）。投資＋持ち玉投資（払出係数でpt換算）に対する、現在の持ち玉（払出係数でpt換算）の差。正＝黒字側
    var chartProfitPt: Double {
        let rate = selectedShop.interpretedPayoutCoefficientPtPerBall
        let currentValue = Double(totalHoldings) * rate
        let cost = Double(totalInput) + Double(holdingsInvestedBalls) * rate
        return currentValue - cost
    }

    /// 遊技中の時給（pt/h）。`basis` が期待値のときは理論損益（実費×(期待値比−1)）を時間で割った値。
    func playHourlyWagePt(basis: PlayHourlyWageBasis, elapsedSeconds: TimeInterval) -> Double? {
        guard elapsedSeconds.isFinite, elapsedSeconds > 30 else { return nil }
        let hours = elapsedSeconds / 3600.0
        guard hours > 0 else { return nil }
        switch basis {
        case .actual:
            let w = chartProfitPt / hours
            return w.isFinite ? w : nil
        case .expected:
            guard dynamicBorder > 0, effectiveUnitsForBorder > 0 else { return nil }
            let er = expectationRatio
            guard er.isFinite, !er.isNaN, er >= 0 else { return nil }
            let expectedProfit = totalRealCost * (er - 1.0)
            let w = expectedProfit / hours
            return w.isFinite ? w : nil
        }
    }

    /// 成績グラフ用プロット。横軸＝総回転数（電サポ・時短を除く通常ゲーム累積）。縦軸＝損益（pt）
    var liveChartPoints: [(Int, Double)] {
        if let cached = _cachedLiveChartPoints, _lastChartStateHash == chartStateHash {
            return cached
        }
        let points = SessionSlumpLiveChartPoints.build(
            wins: winRecords,
            lendings: lendingRecords,
            initialHoldings: initialHoldings,
            initialDisplayRotation: initialDisplayRotation,
            normalRotationsEnd: normalRotations,
            dynamicBorder: dynamicBorder,
            payoutCoefficient: selectedShop.interpretedPayoutCoefficientPtPerBall,
            holdingsBallsPerTap: holdingsBallsPerTap,
            finalProfitPt: chartProfitPt,
            timeline: SlumpChartTimelineContext(sessionStart: sessionStartedAt, timelineEnd: Date())
        )
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
        hasher.combine(selectedShop.interpretedPayoutCoefficientPtPerBall)
        hasher.combine(initialHoldings)
        hasher.combine(initialDisplayRotation)
        hasher.combine(dynamicBorder)
        return hasher.finalize()
    }

    /// 実戦で使う1Rあたり純増（遊技中調整 or 機種のaverageNetPerRound）
    var effective1RNetPerRound: Double {
        adjustedNetPerRound ?? selectedMachine.averageNetPerRound
    }

    /// 機種マスタのボーダー（等価時）が数値で入力されていればその値。未入力・非数値なら 0
    private var formulaBorderAsNumber: Double {
        let s = selectedMachine.border.trimmingCharacters(in: .whitespaces)
        if let v = Double(s), v > 0 { return v }
        let numStr = s.filter { $0.isNumber || $0 == "." }
        if !numStr.isEmpty, let v = Double(numStr), v > 0 { return v }
        return 0
    }

    /// ボーダー（等価時）の数値。UI表示用
    var formulaBorderValue: Double { formulaBorderAsNumber }

    /// ボーダー（回転/1000pt）。メーカー公表値（機種マスターまたはユーザー入力の border）に、
    /// 店舗の貸玉料金（1000ptあたり玉数）と払出係数（pt/玉）を考慮して算出。
    /// マスタ上のボーダー＝等価(4pt/玉・250玉/1000pt)基準。
    /// 店補正後＝そのボーダー × (250÷貸玉1000円玉数) × (4÷払出係数)。1000円あたり玉が少ないほど分母が小さくボーダーは上がる（厳しくなる）。
    /// 払出係数が等価4より大きい（換金が良い）ほど (4/係数) でボーダーは下がる。
    /// ※通常回転のみ（時短・電サポは含めない）。実質回転率と比較可能。
    var dynamicBorder: Double {
        let rate = selectedShop.interpretedPayoutCoefficientPtPerBall
        guard rate > 0, rate.isFinite else { return 0 }
        let ballsPer1000 = Double(selectedShop.interpretedBallsPer500Pt * 2)
        guard ballsPer1000 > 0, ballsPer1000.isFinite else { return 0 }
        let formula = formulaBorderAsNumber
        guard formula.isFinite else { return 0 }
        let loanCorrection = 250.0 / ballsPer1000
        let exchangeCorrection = 4.0 / rate
        let oneR = effective1RNetPerRound
        guard oneR.isFinite else { return 0 }
        let raw: Double
        if formula > 0 {
            raw = formula * loanCorrection * exchangeCorrection
        } else if oneR > 0 {
            let prob = selectedMachine.probabilityDenominator
            if prob > 0, prob.isFinite {
                raw = prob * 250.0 / oneR * loanCorrection * exchangeCorrection
            } else {
                // 確率未使用のフォールバック（旧式の貸玉項を打ち消して等価換算に統一）
                raw = 1000.0 / (oneR * rate)
            }
        } else {
            return 0
        }
        guard raw.isFinite, !raw.isNaN, raw > 0 else { return 0 }
        return raw
    }

    /// 店補正後ボーダー用の「単位」数。1単位＝**等価250玉**に固定。現金は500ptごとの貸玉数で玉に換算し、持ち玉投資玉を加えて 250 で割る（貸玉が少ない店でも持ち玉は250玉＝1単位）。
    var effectiveUnitsForBorder: Double {
        let standardBallsPerUnit = 250.0
        let cashToBalls = Double(totalInput / 500) * Double(selectedShop.interpretedBallsPer500Pt)
        let totalBalls = cashToBalls + Double(holdingsInvestedBalls)
        return totalBalls / standardBallsPerUnit
    }

    // MARK: - 撃ち玉（T / C / H）・持ち玉比率
    /// **T**：通常回転のタップから推定した消費玉数（時短・電サポ・右打ち中の回転は含めない。`normalRotations` のみ）。店補正後のボーダーで 250 玉/回換算。
    var tapDerivedBallsConsumed: Int {
        guard dynamicBorder > 0, normalRotations > 0 else { return 0 }
        return Int((Double(normalRotations) * 250.0 / dynamicBorder).rounded())
    }

    /// **C**：現金投資から換算した撃ち玉数（店の貸玉料金）。
    var cashOriginBallsConsumed: Int {
        lendingRecords.filter { $0.type == .cash }.count * selectedShop.interpretedBallsPer500Pt
    }

    /// **H**：持ち玉由来の撃ち玉数。二重計上防止のため **H = max(0, T − C)** で一意に定義（T＝`tapDerivedBallsConsumed`）。投資記録の持ち玉玉数と乖離しうる。
    var holdingsOriginBallsFromIdentity: Int {
        max(0, tapDerivedBallsConsumed - cashOriginBallsConsumed)
    }

    /// 持ち玉比率 **H / T**。T が 0 のときは nil。
    var holdingsUsageRatio: Double? {
        let t = tapDerivedBallsConsumed
        guard t > 0 else { return nil }
        return Double(holdingsOriginBallsFromIdentity) / Double(t)
    }

    // MARK: - 持ち玉区間のみの回転・期待値（通算の実質回転率・期待値％とは別表示）
    /// 持ち玉投資のユニット数。1ユニット＝店の500ptあたり玉数（現金500ptと同列）。
    var holdingsInvestmentUnits: Double {
        let b = Double(selectedShop.interpretedBallsPer500Pt)
        guard b > 0, holdingsInvestedBalls > 0 else { return 0 }
        return Double(holdingsInvestedBalls) / b
    }

    /// 通常回転のうち持ち玉由来とみなす分（`holdingsOriginBallsFromIdentity` / `tapDerivedBallsConsumed` で按分）。
    var holdingsAttributedNormalRotations: Double {
        let t = Double(tapDerivedBallsConsumed)
        guard t > 0 else { return 0 }
        let h = Double(holdingsOriginBallsFromIdentity)
        return Double(normalRotations) * (h / t)
    }

    /// 1ユニットあたりの平均通常回転（持ち玉寄与分のみ）。
    var holdingsAvgRotationsPerUnit: Double? {
        let u = holdingsInvestmentUnits
        guard u > 0 else { return nil }
        let r = holdingsAttributedNormalRotations
        guard r.isFinite, r >= 0 else { return nil }
        let a = r / u
        return a.isFinite ? a : nil
    }

    /// 上記平均の2倍を「持ち玉区間における実質回転率（1000pt相当）」と定義。
    var holdingsSyntheticRealRatePer1k: Double? {
        guard let a = holdingsAvgRotationsPerUnit else { return nil }
        let v = a * 2.0
        return v.isFinite && !v.isNaN ? v : nil
    }

    /// 等価ボーダー（`formulaBorderAsNumber`）に対する比。通算の `expectationRatio` とは別（分母は店補正なしの等価ボーダー）。
    var holdingsExpectationRatioVsFormula: Double? {
        guard let s = holdingsSyntheticRealRatePer1k else { return nil }
        let f = formulaBorderAsNumber
        guard f > 0 else { return nil }
        let q = s / f
        return q.isFinite && !q.isNaN ? q : nil
    }

    /// 持ち玉投資分のみの理論損益（pt）。`コスト×(比−1)`。
    var holdingsSegmentExpectedProfitPt: Double? {
        guard let ratio = holdingsExpectationRatioVsFormula else { return nil }
        let rate = selectedShop.interpretedPayoutCoefficientPtPerBall
        guard rate > 0 else { return nil }
        let cost = Double(holdingsInvestedBalls) * rate
        guard cost > 0 else { return nil }
        let p = cost * (ratio - 1.0)
        return p.isFinite ? p : nil
    }

    /// 持ち玉投資1000ptあたりの理論収支（表示「/k」用）。
    var holdingsExpectedEdgePer1kPt: Double? {
        guard let profit = holdingsSegmentExpectedProfitPt else { return nil }
        let rate = selectedShop.interpretedPayoutCoefficientPtPerBall
        guard rate > 0 else { return nil }
        let cost = Double(holdingsInvestedBalls) * rate
        guard cost > 0 else { return nil }
        let perK = profit / cost * 1000.0
        return perK.isFinite ? perK : nil
    }

    /// 期待値（ボーダー比）。実質回転率（千pt実費）÷ 店補正後のボーダー。1.0で基準、>1で上回り
    var expectationRatio: Double {
        if let cached = _cachedExpectationRatio, _lastExpectationStateHash == expectationStateHash {
            return cached
        }
        let ratio: Double
        if dynamicBorder > 0, dynamicBorder.isFinite,
           effectiveUnitsForBorder > 0, effectiveUnitsForBorder.isFinite {
            let rr = realRate
            if rr.isFinite, !rr.isNaN {
                let q = rr / dynamicBorder
                ratio = (q.isFinite && !q.isNaN && q >= 0) ? q : 0
            } else {
                ratio = 0
            }
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
        hasher.combine(selectedShop.interpretedPayoutCoefficientPtPerBall)
        hasher.combine(selectedShop.interpretedBallsPer500Pt)
        hasher.combine(formulaBorderAsNumber)
        hasher.combine(effective1RNetPerRound)
        hasher.combine(selectedMachine.probabilityDenominator)
        hasher.combine(normalRotations)
        return hasher.finalize()
    }

    /// 実質回転率（回転/千pt実費）。現金投資（pt）＋持ち玉投資（玉×払出係数）の合計を 1000pt を1単位として割る。交換率の影響は主にここに反映。
    /// 分子は normalRotations（通常回転のみ・時短・電サポ除く）。
    var realRate: Double {
        guard totalRealCost.isFinite, totalRealCost > 0 else { return 0 }
        let realCostThousands = totalRealCost / 1000.0
        guard realCostThousands > 0, realCostThousands.isFinite else { return 0 }
        let r = Double(normalRotations) / realCostThousands
        guard r.isFinite, !r.isNaN, r >= 0 else { return 0 }
        return r
    }

    /// 表面回転率（回転/等価250玉単位）。分母は（貸玉換算の玉＋持ち玉投資の玉）÷250。払出係数は含めない「台の純粋な回り」に相当。
    var rotationPer1000Yen: Double {
        let eu = effectiveUnitsForBorder
        guard eu > 0, eu.isFinite else { return 0 }
        let r = Double(normalRotations) / eu
        return r.isFinite && !r.isNaN && r >= 0 ? r : 0
    }

    /// 実戦の実質回転率・期待値％・ゲージ色が「そのまま信じてよいか」。非有限・極端値・内部不整合を弾く。
    enum RotationMetricsDisplayTrust: Equatable {
        case trusted
        /// 数値・色による誤認を防ぐため抑制する。`userHint` は短い日本語（1行目安）
        case untrusted(userHint: String)
    }

    private enum RotationMetricsSanityThresholds {
        /// 回転/単位（等価コスト基準）として現場で想定しうる上限の目安。超えたら入力・店・ボーダーを疑う。
        static let maxRealRate: Double = 450
        /// 期待値比の上限（= ボーダー比。例: 40 → 表示上 4000%）。超えたら設定不整合の可能性が高い。
        static let maxExpectationRatio: Double = 40
        /// 表面回転率（回/等価250玉単位）の上限の目安
        static let maxSurfaceRatePer1k: Double = 800
    }

    /// 実戦メーター・期待値行の表示信頼性。`borderForGauge` は `PlayView.borderForGauge`（店補正ボーダーまたは等価フォールバック）と一致させること。
    func rotationMetricsDisplayTrust(borderForGauge: Double) -> RotationMetricsDisplayTrust {
        let eu = effectiveUnitsForBorder
        let economicRate = realRate
        let er = expectationRatio
        let ballSurfaceRate = rotationPer1000Yen

        let gaugeMeaningful = eu > 0 && borderForGauge > 0
        if gaugeMeaningful {
            guard economicRate.isFinite, !economicRate.isNaN else {
                return .untrusted(userHint: "実質回転率が数として成立しません")
            }
            guard economicRate >= 0 else {
                return .untrusted(userHint: "データに不整合があります")
            }
            if economicRate > RotationMetricsSanityThresholds.maxRealRate {
                return .untrusted(userHint: "実質回転率が想定を超えています。投入・店を確認")
            }
        }

        let expectationDisplayed = dynamicBorder > 0 && eu > 0
        if expectationDisplayed {
            guard er.isFinite, !er.isNaN else {
                return .untrusted(userHint: "期待値比が数として成立しません")
            }
            guard er >= 0 else {
                return .untrusted(userHint: "データに不整合があります")
            }
            if er > RotationMetricsSanityThresholds.maxExpectationRatio {
                return .untrusted(userHint: "期待値比が極端です。ボーダー・店設定を確認")
            }
        }

        if eu > 0, ballSurfaceRate > 0 {
            guard ballSurfaceRate.isFinite, !ballSurfaceRate.isNaN, ballSurfaceRate >= 0 else {
                return .untrusted(userHint: "表面回転率が数として成立しません")
            }
            if ballSurfaceRate > RotationMetricsSanityThresholds.maxSurfaceRatePer1k {
                return .untrusted(userHint: "表面回転率が想定を超えています。投入・回転を確認")
            }
        }

        return .trusted
    }

    /// ボーダーゲージ説明用：現在の店設定から貸玉・交換が実質ボーダーへ与える倍率（タップ時点の値）。
    func borderGaugeAdjustmentSummary() -> String {
        let ballsPer1000 = Double(max(1, selectedShop.interpretedBallsPer500Pt * 2))
        let loanC = 250.0 / ballsPer1000
        let payout = selectedShop.interpretedPayoutCoefficientPtPerBall
        var lines: [String] = []
        lines.append("【いまの店の補正（実質ボーダーが等価ボーダーからずれる主な要因）】")
        lines.append("貸玉補正：×\(loanC.displayFormat("%.2f"))倍（等価は1,000ptで250玉＝基準。この店は約\(Int(ballsPer1000))玉/1,000pt）")
        if payout > 0 {
            let exchC = 4.0 / payout
            lines.append("交換補正：×\(exchC.displayFormat("%.2f"))倍（払出係数 \(payout.displayFormat("%.4g"))pt/玉。等価4pt/玉との比率がボーダーに反映されます）")
        } else {
            lines.append("交換補正：—（払出係数が未設定のため倍率を出せません）")
        }
        return lines.joined(separator: "\n")
    }

    /// ボーダーゲージの ⓘ に載せる「タップした瞬間」の式・値（短文）
    func borderGaugeFormulaExplanation() -> String {
        let shopName = selectedShop.name
        let machineName = selectedMachine.name
        let ballsPer500 = selectedShop.interpretedBallsPer500Pt
        let ballsPer1000 = Double(max(1, selectedShop.interpretedBallsPer500Pt * 2))
        let payout = selectedShop.interpretedPayoutCoefficientPtPerBall
        let loanC = 250.0 / ballsPer1000
        let exchC = payout > 0 ? 4.0 / payout : 0.0 // 等価から算出するときの係数（表示用）
        let formula = formulaBorderAsNumber
        let oneR = effective1RNetPerRound
        let probDenom = selectedMachine.probabilityDenominator
        let cashPt = totalInput
        let holdBalls = holdingsInvestedBalls
        let nRot = normalRotations
        let db = dynamicBorder
        let units = effectiveUnitsForBorder
        let trc = totalRealCost

        var lines: [String] = []
        lines.append("―― いまの値（この説明を開いたとき）――")
        lines.append("店：\(shopName) ／ 機：\(machineName)")
        lines.append("貸玉 \(ballsPer500)玉/500pt → B＝\(Int(ballsPer1000))玉/1kpt ／ 払出 \(payout.displayFormat("%.4g"))pt/玉")
        lines.append("現金 \(cashPt)pt ／ 持ち玉投資 \(holdBalls)玉 ／ 通常回転 \(nRot)")
        lines.append("")
        lines.append("実質ボーダー ≒ \(db.displayFormat("%.2f")) 回/単位")
        if payout <= 0 {
            lines.append("（払出0のため参考になりません）")
        } else if formula > 0 {
            lines.append("＝ 等価\(formula.displayFormat("%.3g")) × 250/B(\(loanC.displayFormat("%.4g"))) × 4/払出(\(exchC.displayFormat("%.4g")))")
        } else if oneR > 0, probDenom > 0 {
            lines.append("＝ 確率分母\(probDenom.displayFormat("%.4g"))×250÷1R\(oneR.displayFormat("%.4g")) × 貸玉・交換補正（同上）")
        } else if oneR > 0, payout > 0 {
            lines.append("＝ 1000÷(1R\(oneR.displayFormat("%.4g"))×払出) など")
        }
        lines.append("")
        let cashBalls = Double(cashPt / 500) * Double(ballsPer500)
        lines.append("コスト単位 ＝ (現金換算 \(cashBalls.displayFormat("%.4g"))玉 + 持ち玉 \(holdBalls)玉) ÷ 250 ＝ \(units.displayFormat("%.4g"))")
        if units > 0 {
            lines.append("表面回転率（等価250玉単位）＝ \(nRot)÷単位 ＝ \(rotationPer1000Yen.displayFormat("%.2f"))")
        } else {
            lines.append("表面回転率＝算出なし（単位0）")
        }
        lines.append("実費 ＝ \(cashPt) + \(holdBalls)×\(payout.displayFormat("%.4g")) ＝ \(trc.displayFormat("%.1f"))pt")
        if trc > 0 {
            lines.append("実質回転率（千pt実費） ＝ \(nRot)÷(実費÷1000) ＝ \(realRate.displayFormat("%.2f"))")
        } else {
            lines.append("実質回転率＝算出なし")
        }
        lines.append("針 ≒ 実質回転率 − 実質ボーダー を目盛にしたもの")
        return lines.joined(separator: "\n")
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

    /// 現金投資額をあとから修正（500pt単位。持ち玉投資はそのまま）
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
    /// 実戦終了確認で入力した「終了時点の通常回転数」へ揃える。`totalRotations` は同じ差分だけ追随し、`total` が `normal` 未満にならないよう抑える。
    func applySessionEndNormalRotations(_ endNormal: Int) {
        let n = max(0, endNormal)
        let d = n - normalRotations
        normalRotations = n
        totalRotations = max(n, totalRotations + d)
    }

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
        sessionStartedAt = nil
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
        bigHitSessionNormalRotationsAtWin = nil
        bigHitSessionTotalRotationsAtWin = nil
        winRecords = []
        lendingRecords = []
    }

    /// 続きから：永続化した状態をログに反映する。機種・店舗は呼び出し元で解決済みのものを渡す
    func applyResumableState(_ state: ResumableState, machine: Machine, shop: Shop) {
        selectedMachine = machine
        selectedShop = shop
        sessionStartedAt = state.sessionStartedAt
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
        bigHitSessionNormalRotationsAtWin = state.bigHitSessionNormalRotationsAtWin
        bigHitSessionTotalRotationsAtWin = state.bigHitSessionTotalRotationsAtWin
        restoreUndoStack(from: state.undoStackEntries)
    }

    /// 保存データに currentModeID が無いとき、currentState から復元する
    private static func resolvedModeID(from currentState: PlayState, isTimeShortMode: Bool) -> Int {
        switch currentState {
        case .support: return isTimeShortMode ? 0 : 1
        case .normal: return 0
        }
    }
}

/// 遊技中の時給の算出基準（`GameLog.playHourlyWagePt` 用）
enum PlayHourlyWageBasis: String, CaseIterable, Sendable {
    /// 現在損益（`chartProfitPt`）÷ 経過時間
    case actual = "actual"
    /// 実費×(期待値比−1) ÷ 経過時間（ボーダー未設定時は算出不可）
    case expected = "expected"
}

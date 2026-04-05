import Foundation

/// スランプ折れ線の「いつまで」を基準にする（遊技中＝いま、履歴＝終了時刻）。
struct SlumpChartTimelineContext: Equatable, Sendable {
    var sessionStart: Date?
    /// 遊技中は `Date()`、保存済みセッションは `endedAt` または `date`
    var timelineEnd: Date
}

/// 実戦中 `GameLog.liveChartPoints` と履歴用デコードデータで共有するスランプ折れ線のプロット生成。
enum SessionSlumpLiveChartPoints {
    /// - Parameter chodamaCarryInBalls: 遊技開始時に台に載せた**貯玉**（カウンター持ち込み分）。今回遊技の収支には含めず、撃ち・持ち玉タップでは先にこのプールから消費する（FIFO）。非貯玉店・旧データは 0。
    static func build(
        wins: [WinRecord],
        lendings: [LendingRecord],
        initialHoldings: Int,
        initialDisplayRotation: Int,
        normalRotationsEnd: Int,
        dynamicBorder: Double,
        payoutCoefficient: Double,
        holdingsBallsPerTap: Int,
        finalProfitPt: Double,
        chodamaCarryInBalls: Int = 0,
        timeline: SlumpChartTimelineContext? = nil
    ) -> [(Int, Double)] {
        guard payoutCoefficient > 0, payoutCoefficient.isFinite else {
            return fallbackTwoPoint(endX: normalRotationsEnd, finalY: finalProfitPt)
        }

        let hTap = max(1, holdingsBallsPerTap)
        let winsOrdered = winsSortedForSlump(wins)
        let lendingsOrdered = lendings.sorted { $0.timestamp < $1.timestamp }
        let chodama = max(0, chodamaCarryInBalls)

        if timeline != nil {
            return buildWithTimeline(
                winsOrdered: winsOrdered,
                lendingsOrdered: lendingsOrdered,
                initialHoldings: initialHoldings,
                initialDisplayRotation: initialDisplayRotation,
                normalRotationsEnd: normalRotationsEnd,
                dynamicBorder: dynamicBorder,
                payoutCoefficient: payoutCoefficient,
                holdingsBallsPerTap: hTap,
                finalProfitPt: finalProfitPt,
                chodamaCarryInBalls: chodama,
                context: timeline!
            )
        }

        return buildWinsOnlyLegacy(
            winsOrdered: winsOrdered,
            lendingsOrdered: lendingsOrdered,
            initialHoldings: initialHoldings,
            initialDisplayRotation: initialDisplayRotation,
            normalRotationsEnd: normalRotationsEnd,
            dynamicBorder: dynamicBorder,
            payoutCoefficient: payoutCoefficient,
            holdingsBallsPerTap: hTap,
            finalProfitPt: finalProfitPt,
            chodamaCarryInBalls: chodama
        )
    }

    /// 貯玉 FIFO を反映した終端損益（pt）。`GameLog.chartProfitPt` 用。
    static func terminalProfitPtWithChodamaFIFO(
        wins: [WinRecord],
        lendings: [LendingRecord],
        initialHoldings: Int,
        initialDisplayRotation: Int,
        normalRotationsEnd: Int,
        dynamicBorder: Double,
        payoutCoefficient: Double,
        holdingsBallsPerTap: Int,
        chodamaCarryInBalls: Int,
        timeline: SlumpChartTimelineContext?
    ) -> Double {
        guard payoutCoefficient > 0, payoutCoefficient.isFinite else { return 0 }
        let hTap = max(1, holdingsBallsPerTap)
        let winsOrdered = winsSortedForSlump(wins)
        let lendingsOrdered = lendings.sorted { $0.timestamp < $1.timestamp }
        let chodama = max(0, chodamaCarryInBalls)
        if let context = timeline {
            return fifoProfitAtEnd(
                winsOrdered: winsOrdered,
                lendingsOrdered: lendingsOrdered,
                initialHoldings: initialHoldings,
                initialDisplayRotation: initialDisplayRotation,
                normalRotationsEnd: normalRotationsEnd,
                dynamicBorder: dynamicBorder,
                payoutCoefficient: payoutCoefficient,
                holdingsBallsPerTap: hTap,
                chodamaCarryInBalls: chodama,
                context: context
            )
        }
        return fifoProfitAtEndLegacy(
            winsOrdered: winsOrdered,
            lendingsOrdered: lendingsOrdered,
            initialHoldings: initialHoldings,
            initialDisplayRotation: initialDisplayRotation,
            normalRotationsEnd: normalRotationsEnd,
            dynamicBorder: dynamicBorder,
            payoutCoefficient: payoutCoefficient,
            holdingsBallsPerTap: hTap,
            chodamaCarryInBalls: chodama
        )
    }

    // MARK: - 時系列マージ（投資で下がり・当たりで上がるジグザグ）

    private static func buildWithTimeline(
        winsOrdered: [WinRecord],
        lendingsOrdered: [LendingRecord],
        initialHoldings: Int,
        initialDisplayRotation: Int,
        normalRotationsEnd: Int,
        dynamicBorder: Double,
        payoutCoefficient: Double,
        holdingsBallsPerTap: Int,
        finalProfitPt: Double,
        chodamaCarryInBalls: Int,
        context: SlumpChartTimelineContext
    ) -> [(Int, Double)] {
        let anchors = rotationTimeAnchors(
            winsOrdered: winsOrdered,
            lendingsOrdered: lendingsOrdered,
            normalRotationsEnd: normalRotationsEnd,
            context: context
        )

        enum Merged {
            case lend(LendingRecord)
            case win(WinRecord)
        }
        var steps: [(Date, Merged)] = []
        let winTimes = effectiveWinDates(winsOrdered: winsOrdered, lendingsOrdered: lendingsOrdered, context: context)
        for l in lendingsOrdered {
            steps.append((l.timestamp, .lend(l)))
        }
        for w in winsOrdered {
            let tw = winTimes[w.id] ?? context.timelineEnd
            steps.append((tw, .win(w)))
        }
        steps.sort { a, b in
            if a.0 != b.0 { return a.0 < b.0 }
            switch (a.1, b.1) {
            case (.lend, .win): return true
            case (.win, .lend): return false
            default: return false
            }
        }

        var points: [(Int, Double)] = [(0, 0)]
        let fifoInit = fifoPoolsInitial(initialHoldings: initialHoldings, chodamaCarryInBalls: chodamaCarryInBalls)
        var chodamaRemaining = fifoInit.chodamaRemaining
        var sessionTray = fifoInit.sessionTray
        var runningInvYen = 0
        var cumConsumedProcessed = 0

        func appendPoint(x rawX: Int, y: Double) {
            let xPrev = points.last?.0 ?? 0
            let x = max(rawX, xPrev)
            if let last = points.last, last.0 == x, abs(last.1 - y) < 0.5 { return }
            if let last = points.last, last.0 == x {
                points[points.count - 1] = (x, y)
            } else {
                points.append((x, y))
            }
        }

        /// 持ち玉は `sessionTray` から既に減っているため、投資分を再度 `×交換率` すると二重計上になる。現金投資のみコスト側に加算。
        func profitNow() -> Double {
            Double(sessionTray) * payoutCoefficient - Double(runningInvYen)
        }

        for (_, step) in steps {
            switch step {
            case .lend(let l):
                let xRaw = normalRotation(at: l.timestamp, anchors: anchors)
                let cTarget = consumedBallsAtNormalRotation(xRaw, dynamicBorder: dynamicBorder)
                let spinDelta = max(0, cTarget - cumConsumedProcessed)
                spendBallsFromPools(spinDelta, chodamaRemaining: &chodamaRemaining, sessionTray: &sessionTray)
                cumConsumedProcessed = cTarget
                if l.type == .cash {
                    runningInvYen += 500
                } else {
                    let b = l.balls ?? holdingsBallsPerTap
                    spendBallsFromPools(b, chodamaRemaining: &chodamaRemaining, sessionTray: &sessionTray)
                }
                appendPoint(x: xRaw, y: profitNow())
            case .win(let win):
                let xRot = max(0, win.normalRotationsAtWin ?? win.rotationAtWin)
                let cTarget = consumedBalls(for: win, dynamicBorder: dynamicBorder, initialDisplayRotation: initialDisplayRotation)
                let spinDelta = max(0, cTarget - cumConsumedProcessed)
                spendBallsFromPools(spinDelta, chodamaRemaining: &chodamaRemaining, sessionTray: &sessionTray)
                cumConsumedProcessed = cTarget
                sessionTray += win.prize ?? 0
                appendPoint(x: xRot, y: profitNow())
            }
        }

        closeWithFinalPoint(
            points: &points,
            normalRotationsEnd: normalRotationsEnd,
            finalProfitPt: finalProfitPt
        )
        return points
    }

    private static func rotationTimeAnchors(
        winsOrdered: [WinRecord],
        lendingsOrdered: [LendingRecord],
        normalRotationsEnd: Int,
        context: SlumpChartTimelineContext
    ) -> [(Date, Int)] {
        let endX = max(0, normalRotationsEnd)
        let tEnd = context.timelineEnd
        let minLend = lendingsOrdered.map(\.timestamp).min()
        let minWin = winsOrdered.compactMap(\.timestamp).min()
        let tStartRaw = context.sessionStart ?? minLend ?? minWin ?? tEnd.addingTimeInterval(-3600)
        let tStart = min(tStartRaw, tEnd.addingTimeInterval(-1))

        var anchors: [(Date, Int)] = [(tStart, 0)]
        let winTimes = effectiveWinDates(winsOrdered: winsOrdered, lendingsOrdered: lendingsOrdered, context: context)
        for w in winsOrdered {
            let tw = winTimes[w.id] ?? tEnd
            let x = max(0, w.normalRotationsAtWin ?? w.rotationAtWin)
            anchors.append((tw, x))
        }
        anchors.append((max(tEnd, anchors.last?.0 ?? tStart), endX))
        anchors.sort { $0.0 < $1.0 }
        var mono: [(Date, Int)] = []
        var lastX = 0
        for (d, x) in anchors {
            let x2 = max(x, lastX)
            mono.append((d, x2))
            lastX = x2
        }
        if let last = mono.last {
            mono[mono.count - 1] = (last.0, max(last.1, endX))
        }
        return mono
    }

    /// 横軸に並べた当たり順で時刻を割り当て、タイムスタンプ欠損でも単調になるようにする。
    private static func effectiveWinDates(
        winsOrdered: [WinRecord],
        lendingsOrdered: [LendingRecord],
        context: SlumpChartTimelineContext
    ) -> [UUID: Date] {
        let winsByNorm = winsOrdered.sorted {
            let x0 = $0.normalRotationsAtWin ?? $0.rotationAtWin
            let x1 = $1.normalRotationsAtWin ?? $1.rotationAtWin
            if x0 != x1 { return x0 < x1 }
            return $0.id.uuidString < $1.id.uuidString
        }
        let tBase = context.sessionStart
            ?? lendingsOrdered.map(\.timestamp).min()
            ?? winsByNorm.compactMap(\.timestamp).min()
            ?? context.timelineEnd.addingTimeInterval(-3600)
        var cursor = min(tBase, context.timelineEnd.addingTimeInterval(-1))
        var map: [UUID: Date] = [:]
        for w in winsByNorm {
            let t: Date
            if let ts = w.timestamp {
                t = max(ts, cursor.addingTimeInterval(0.001))
            } else {
                t = cursor.addingTimeInterval(0.001)
            }
            cursor = t
            map[w.id] = t
        }
        return map
    }

    private static func normalRotation(at date: Date, anchors: [(Date, Int)]) -> Int {
        guard let first = anchors.first, let last = anchors.last else { return 0 }
        if date <= first.0 { return first.1 }
        if date >= last.0 { return last.1 }
        for i in 0..<(anchors.count - 1) {
            let (t0, x0) = anchors[i]
            let (t1, x1) = anchors[i + 1]
            if date >= t0 && date <= t1 {
                let dt = t1.timeIntervalSince(t0)
                if dt <= 1e-6 { return x1 }
                let f = date.timeIntervalSince(t0) / dt
                let xf = Double(x0) + f * Double(x1 - x0)
                return Int(xf.rounded())
            }
        }
        return last.1
    }

    // MARK: - 貯玉 FIFO（スランプ・chartProfitPt 共通）

    private static func fifoPoolsInitial(initialHoldings: Int, chodamaCarryInBalls: Int) -> (chodamaRemaining: Int, sessionTray: Int) {
        let i = max(0, initialHoldings)
        let cap = min(max(0, chodamaCarryInBalls), i)
        return (cap, i - cap)
    }

    /// 台から `balls` 玉減らす。先に貯玉プール、残りは今回遊技の持ち玉（`sessionTray`）。
    private static func spendBallsFromPools(
        _ balls: Int,
        chodamaRemaining: inout Int,
        sessionTray: inout Int
    ) {
        guard balls > 0 else { return }
        let fromChod = min(balls, chodamaRemaining)
        chodamaRemaining -= fromChod
        let fromSession = balls - fromChod
        guard fromSession > 0 else { return }
        sessionTray = max(0, sessionTray - fromSession)
    }

    private static func fifoProfitAtEnd(
        winsOrdered: [WinRecord],
        lendingsOrdered: [LendingRecord],
        initialHoldings: Int,
        initialDisplayRotation: Int,
        normalRotationsEnd: Int,
        dynamicBorder: Double,
        payoutCoefficient: Double,
        holdingsBallsPerTap: Int,
        chodamaCarryInBalls: Int,
        context: SlumpChartTimelineContext
    ) -> Double {
        let anchors = rotationTimeAnchors(
            winsOrdered: winsOrdered,
            lendingsOrdered: lendingsOrdered,
            normalRotationsEnd: normalRotationsEnd,
            context: context
        )
        enum Merged { case lend(LendingRecord); case win(WinRecord) }
        var steps: [(Date, Merged)] = []
        let winTimes = effectiveWinDates(winsOrdered: winsOrdered, lendingsOrdered: lendingsOrdered, context: context)
        for l in lendingsOrdered { steps.append((l.timestamp, .lend(l))) }
        for w in winsOrdered {
            steps.append((winTimes[w.id] ?? context.timelineEnd, .win(w)))
        }
        steps.sort { a, b in
            if a.0 != b.0 { return a.0 < b.0 }
            switch (a.1, b.1) {
            case (.lend, .win): return true
            case (.win, .lend): return false
            default: return false
            }
        }
        let fifoInit = fifoPoolsInitial(initialHoldings: initialHoldings, chodamaCarryInBalls: chodamaCarryInBalls)
        var chodamaRemaining = fifoInit.chodamaRemaining
        var sessionTray = fifoInit.sessionTray
        var runningInvYen = 0
        var cumConsumedProcessed = 0
        for (_, step) in steps {
            switch step {
            case .lend(let l):
                let xRaw = normalRotation(at: l.timestamp, anchors: anchors)
                let cTarget = consumedBallsAtNormalRotation(xRaw, dynamicBorder: dynamicBorder)
                let spinDelta = max(0, cTarget - cumConsumedProcessed)
                spendBallsFromPools(spinDelta, chodamaRemaining: &chodamaRemaining, sessionTray: &sessionTray)
                cumConsumedProcessed = cTarget
                if l.type == .cash {
                    runningInvYen += 500
                } else {
                    let b = l.balls ?? holdingsBallsPerTap
                    spendBallsFromPools(b, chodamaRemaining: &chodamaRemaining, sessionTray: &sessionTray)
                }
            case .win(let win):
                let cTarget = consumedBalls(for: win, dynamicBorder: dynamicBorder, initialDisplayRotation: initialDisplayRotation)
                let spinDelta = max(0, cTarget - cumConsumedProcessed)
                spendBallsFromPools(spinDelta, chodamaRemaining: &chodamaRemaining, sessionTray: &sessionTray)
                cumConsumedProcessed = cTarget
                sessionTray += win.prize ?? 0
            }
        }
        let cEnd = consumedBallsAtNormalRotation(max(0, normalRotationsEnd), dynamicBorder: dynamicBorder)
        let spinToEnd = max(0, cEnd - cumConsumedProcessed)
        spendBallsFromPools(spinToEnd, chodamaRemaining: &chodamaRemaining, sessionTray: &sessionTray)
        return Double(sessionTray) * payoutCoefficient - Double(runningInvYen)
    }

    private static func fifoProfitAtEndLegacy(
        winsOrdered: [WinRecord],
        lendingsOrdered: [LendingRecord],
        initialHoldings: Int,
        initialDisplayRotation: Int,
        normalRotationsEnd: Int,
        dynamicBorder: Double,
        payoutCoefficient: Double,
        holdingsBallsPerTap: Int,
        chodamaCarryInBalls: Int
    ) -> Double {
        let fifoInit = fifoPoolsInitial(initialHoldings: initialHoldings, chodamaCarryInBalls: chodamaCarryInBalls)
        var chodamaRemaining = fifoInit.chodamaRemaining
        var sessionTray = fifoInit.sessionTray
        var runningInvYen = 0
        var cumConsumedProcessed = 0
        var currentLendingIndex = 0
        for win in winsOrdered {
            let t = win.timestamp ?? .distantPast
            while currentLendingIndex < lendingsOrdered.count && lendingsOrdered[currentLendingIndex].timestamp < t {
                let l = lendingsOrdered[currentLendingIndex]
                if l.type == .cash {
                    runningInvYen += 500
                } else {
                    let b = l.balls ?? holdingsBallsPerTap
                    spendBallsFromPools(b, chodamaRemaining: &chodamaRemaining, sessionTray: &sessionTray)
                }
                currentLendingIndex += 1
            }
            let cTarget = consumedBalls(for: win, dynamicBorder: dynamicBorder, initialDisplayRotation: initialDisplayRotation)
            let spinDelta = max(0, cTarget - cumConsumedProcessed)
            spendBallsFromPools(spinDelta, chodamaRemaining: &chodamaRemaining, sessionTray: &sessionTray)
            cumConsumedProcessed = cTarget
            sessionTray += win.prize ?? 0
        }
        while currentLendingIndex < lendingsOrdered.count {
            let l = lendingsOrdered[currentLendingIndex]
            if l.type == .cash {
                runningInvYen += 500
            } else {
                let b = l.balls ?? holdingsBallsPerTap
                spendBallsFromPools(b, chodamaRemaining: &chodamaRemaining, sessionTray: &sessionTray)
            }
            currentLendingIndex += 1
        }
        let cEnd = consumedBallsAtNormalRotation(max(0, normalRotationsEnd), dynamicBorder: dynamicBorder)
        let spinToEnd = max(0, cEnd - cumConsumedProcessed)
        spendBallsFromPools(spinToEnd, chodamaRemaining: &chodamaRemaining, sessionTray: &sessionTray)
        return Double(sessionTray) * payoutCoefficient - Double(runningInvYen)
    }

    // MARK: - 従来ルート（timeline なし・互換）

    private static func buildWinsOnlyLegacy(
        winsOrdered: [WinRecord],
        lendingsOrdered: [LendingRecord],
        initialHoldings: Int,
        initialDisplayRotation: Int,
        normalRotationsEnd: Int,
        dynamicBorder: Double,
        payoutCoefficient: Double,
        holdingsBallsPerTap: Int,
        finalProfitPt: Double,
        chodamaCarryInBalls: Int
    ) -> [(Int, Double)] {
        var points: [(Int, Double)] = [(0, 0)]

        let fifoInit = fifoPoolsInitial(initialHoldings: initialHoldings, chodamaCarryInBalls: chodamaCarryInBalls)
        var chodamaRemaining = fifoInit.chodamaRemaining
        var sessionTray = fifoInit.sessionTray
        var runningInvYen = 0
        var cumConsumedProcessed = 0
        var currentLendingIndex = 0

        for win in winsOrdered {
            let t = win.timestamp ?? .distantPast

            while currentLendingIndex < lendingsOrdered.count && lendingsOrdered[currentLendingIndex].timestamp < t {
                let l = lendingsOrdered[currentLendingIndex]
                if l.type == .cash {
                    runningInvYen += 500
                } else {
                    let b = l.balls ?? holdingsBallsPerTap
                    spendBallsFromPools(b, chodamaRemaining: &chodamaRemaining, sessionTray: &sessionTray)
                }
                currentLendingIndex += 1
            }

            let cTarget = consumedBalls(for: win, dynamicBorder: dynamicBorder, initialDisplayRotation: initialDisplayRotation)
            let spinDelta = max(0, cTarget - cumConsumedProcessed)
            spendBallsFromPools(spinDelta, chodamaRemaining: &chodamaRemaining, sessionTray: &sessionTray)
            cumConsumedProcessed = cTarget
            sessionTray += win.prize ?? 0
            let profit = Double(sessionTray) * payoutCoefficient - Double(runningInvYen)
            let xRot = win.normalRotationsAtWin ?? win.rotationAtWin
            points.append((xRot, profit))
        }

        while currentLendingIndex < lendingsOrdered.count {
            let l = lendingsOrdered[currentLendingIndex]
            if l.type == .cash {
                runningInvYen += 500
            } else {
                let b = l.balls ?? holdingsBallsPerTap
                spendBallsFromPools(b, chodamaRemaining: &chodamaRemaining, sessionTray: &sessionTray)
            }
            currentLendingIndex += 1
        }

        closeWithFinalPoint(
            points: &points,
            normalRotationsEnd: normalRotationsEnd,
            finalProfitPt: finalProfitPt
        )
        return points
    }

    private static func closeWithFinalPoint(
        points: inout [(Int, Double)],
        normalRotationsEnd: Int,
        finalProfitPt: Double
    ) {
        let endX = max(0, normalRotationsEnd)
        if let last = points.last {
            if last.0 == endX {
                if abs(last.1 - finalProfitPt) > 0.5 {
                    points[points.count - 1] = (endX, finalProfitPt)
                }
            } else {
                points.append((endX, finalProfitPt))
            }
        } else {
            points.append((endX, finalProfitPt))
        }
    }

    private static func fallbackTwoPoint(endX: Int, finalY: Double) -> [(Int, Double)] {
        let x = max(0, endX)
        if x == 0 { return [(0, 0)] }
        return [(0, 0), (x, finalY)]
    }

    private static func winsSortedForSlump(_ wins: [WinRecord]) -> [WinRecord] {
        wins.enumerated().sorted { a, b in
            let ta = a.element.timestamp ?? .distantPast
            let tb = b.element.timestamp ?? .distantPast
            if ta != tb { return ta < tb }
            let xa = a.element.normalRotationsAtWin ?? a.element.rotationAtWin
            let xb = b.element.normalRotationsAtWin ?? b.element.rotationAtWin
            if xa != xb { return xa < xb }
            return a.offset < b.offset
        }.map(\.element)
    }

    private static func consumedBalls(for win: WinRecord, dynamicBorder: Double, initialDisplayRotation: Int) -> Int {
        if let nr = win.normalRotationsAtWin {
            return consumedBallsAtNormalRotation(nr, dynamicBorder: dynamicBorder)
        }
        let delta = win.rotationAtWin - initialDisplayRotation
        guard delta > 0 else { return 0 }
        let borderPer250 = max(dynamicBorder, 0.01)
        return Int((Double(delta) * 250.0 / borderPer250).rounded())
    }

    private static func consumedBallsAtNormalRotation(_ normalRotation: Int, dynamicBorder: Double) -> Int {
        guard normalRotation > 0, dynamicBorder > 0 else { return 0 }
        return Int((Double(normalRotation) * 250.0 / dynamicBorder).rounded())
    }
}

extension JSONDecoder {
    static var slumpChart: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    /// ISO8601 以外の日付や軽微な形式差を吸収してスランプ用 JSON を読む。
    static var slumpChartLenient: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { dec in
            let c = try dec.singleValueContainer()
            if let secs = try? c.decode(Double.self) {
                return Date(timeIntervalSince1970: secs)
            }
            let s = try c.decode(String.self)
            let isoFrac = ISO8601DateFormatter()
            isoFrac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let d = isoFrac.date(from: s) { return d }
            let iso = ISO8601DateFormatter()
            iso.formatOptions = [.withInternetDateTime]
            if let d = iso.date(from: s) { return d }
            let df = DateFormatter()
            df.locale = Locale(identifier: "en_US_POSIX")
            df.timeZone = TimeZone(secondsFromGMT: 0)
            df.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS"
            if let d = df.date(from: s) { return d }
            df.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
            if let d = df.date(from: s) { return d }
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "Unparseable date: \(s)")
        }
        return d
    }
}

extension JSONEncoder {
    static var slumpChart: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }
}

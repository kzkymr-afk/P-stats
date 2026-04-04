import Foundation

/// スランプ折れ線の「いつまで」を基準にする（遊技中＝いま、履歴＝終了時刻）。
struct SlumpChartTimelineContext: Equatable, Sendable {
    var sessionStart: Date?
    /// 遊技中は `Date()`、保存済みセッションは `endedAt` または `date`
    var timelineEnd: Date
}

/// 実戦中 `GameLog.liveChartPoints` と履歴用デコードデータで共有するスランプ折れ線のプロット生成。
enum SessionSlumpLiveChartPoints {
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
        timeline: SlumpChartTimelineContext? = nil
    ) -> [(Int, Double)] {
        guard payoutCoefficient > 0, payoutCoefficient.isFinite else {
            return fallbackTwoPoint(endX: normalRotationsEnd, finalY: finalProfitPt)
        }

        let hTap = max(1, holdingsBallsPerTap)
        let winsOrdered = winsSortedForSlump(wins)
        let lendingsOrdered = lendings.sorted { $0.timestamp < $1.timestamp }

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
            finalProfitPt: finalProfitPt
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
        var cumulativePrize = 0
        var runningInvYen = 0
        var runningHoldBalls = 0

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

        for (_, step) in steps {
            switch step {
            case .lend(let l):
                if l.type == .cash {
                    runningInvYen += 500
                } else {
                    runningHoldBalls += l.balls ?? holdingsBallsPerTap
                }
                let xRaw = normalRotation(at: l.timestamp, anchors: anchors)
                let y = profitAt(
                    normalRotations: xRaw,
                    initialHoldings: initialHoldings,
                    cumulativePrize: cumulativePrize,
                    runningHoldBalls: runningHoldBalls,
                    runningInvYen: runningInvYen,
                    payoutCoefficient: payoutCoefficient,
                    dynamicBorder: dynamicBorder
                )
                appendPoint(x: xRaw, y: y)
            case .win(let win):
                cumulativePrize += win.prize ?? 0
                let consumedAtWin = consumedBalls(for: win, dynamicBorder: dynamicBorder, initialDisplayRotation: initialDisplayRotation)
                let holdingsAtWin = initialHoldings + cumulativePrize - runningHoldBalls - consumedAtWin
                let cost = Double(runningInvYen) + Double(runningHoldBalls) * payoutCoefficient
                let profit = Double(max(0, holdingsAtWin)) * payoutCoefficient - cost
                let xRot = max(0, win.normalRotationsAtWin ?? win.rotationAtWin)
                appendPoint(x: xRot, y: profit)
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

    private static func profitAt(
        normalRotations: Int,
        initialHoldings: Int,
        cumulativePrize: Int,
        runningHoldBalls: Int,
        runningInvYen: Int,
        payoutCoefficient: Double,
        dynamicBorder: Double
    ) -> Double {
        let consumed = consumedBallsAtNormalRotation(normalRotations, dynamicBorder: dynamicBorder)
        let holdingsAt = initialHoldings + cumulativePrize - runningHoldBalls - consumed
        let cost = Double(runningInvYen) + Double(runningHoldBalls) * payoutCoefficient
        return Double(max(0, holdingsAt)) * payoutCoefficient - cost
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
        finalProfitPt: Double
    ) -> [(Int, Double)] {
        var points: [(Int, Double)] = [(0, 0)]

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
            let consumedAtWin = consumedBalls(for: win, dynamicBorder: dynamicBorder, initialDisplayRotation: initialDisplayRotation)
            let holdingsAtWin = initialHoldings + cumulativePrize - runningHoldBalls - consumedAtWin
            let cost = Double(runningInvYen) + Double(runningHoldBalls) * payoutCoefficient
            let profit = Double(max(0, holdingsAtWin)) * payoutCoefficient - cost
            let xRot = win.normalRotationsAtWin ?? win.rotationAtWin
            points.append((xRot, profit))
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

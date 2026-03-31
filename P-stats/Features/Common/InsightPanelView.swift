import SwiftUI
import SwiftData

// MARK: - インサイトパネル（右ドロワー）
/// 今日の実戦に基づく「今の欠損額」「あと何回でプラス転換」などを表示。水色・ダークネイビーで統一。左スワイプで閉じる。
struct InsightPanelView: View {
    @Bindable var log: GameLog
    let onClose: () -> Void
    var onCorrectInitialRotation: (() -> Void)? = nil
    var onCorrectCash: (() -> Void)? = nil
    var onCorrectHoldings: (() -> Void)? = nil
    var onCorrectWinCount: (() -> Void)? = nil
    var onOpenHistory: (() -> Void)? = nil
    var onOpenEventHistory: (() -> Void)? = nil
    var onOpenAnalytics: (() -> Void)? = nil
    var onOpenPowerSaving: (() -> Void)? = nil
    var onOpenSettings: (() -> Void)? = nil
    var onToggleRightHandMode: (() -> Void)? = nil
    var isRightHandMode: Bool = false

    private let cyan = AppGlassStyle.accent
    private let darkNavy = AppGlassStyle.background

    /// 実戦中の期待値収支（pt）。正=黒字側、負=欠損側
    private var theoreticalExpectationPt: Int {
        guard log.totalRealCost > 0, log.dynamicBorder > 0 else { return 0 }
        let ratio = log.expectationRatio
        return Int(round(log.totalRealCost * (ratio - 1)))
    }

    /// ボーダーに達するのに必要な通常回転数（現金1000pt・持ち玉250玉単位の実質コストに対する）
    private var borderRotations: Double {
        guard log.dynamicBorder > 0, log.effectiveUnitsForBorder > 0 else { return 0 }
        return log.effectiveUnitsForBorder * log.dynamicBorder
    }

    /// あと何回回せばプラス転換（ボーダー突破）。既に超えていれば 0
    private var spinsToBreakEven: Int {
        let need = borderRotations
        let current = Double(log.normalRotations)
        return max(0, Int(ceil(need - current)))
    }

    var body: some View {
        VStack(spacing: 0) {
            // ヘッダー: 閉じる（左スワイプでも閉じる）
            HStack {
                Text("インサイト")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .tracking(0.5)
                    .foregroundColor(cyan.opacity(0.9))
                Spacer()
                Button(action: { onClose() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundColor(cyan.opacity(0.7))
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 8)

            ScrollView(showsIndicators: true) {
                VStack(alignment: .leading, spacing: 8) {
                // 設定（通常モード中も常に表示）
                if let onOpenSettings = onOpenSettings {
                    Button(action: onOpenSettings) {
                        HStack(alignment: .center) {
                            Image(systemName: "gearshape.fill")
                            VStack(alignment: .leading, spacing: 2) {
                                Text("設定")
                                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                                Text("機種・店舗・テーマなどのアプリ設定")
                                    .font(.system(size: 10, weight: .regular))
                                    .foregroundColor(cyan.opacity(0.6))
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption2)
                                .foregroundColor(cyan.opacity(0.6))
                        }
                        .foregroundColor(cyan)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 12)
                    }
                    .buttonStyle(.plain)
                    .background(AppGlassStyle.rowBackground)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(cyan.opacity(0.2), lineWidth: 1))
                }

                // 閲覧：履歴・分析・大当たり・投資履歴（遊戯中でも開ける）
                if onOpenHistory != nil || onOpenEventHistory != nil || onOpenAnalytics != nil {
                    VStack(alignment: .leading, spacing: 4) {
                        panelTitle("閲覧")
                        if let onOpenHistory = onOpenHistory {
                            Button(action: onOpenHistory) {
                                HStack(alignment: .center) {
                                    Image(systemName: "calendar")
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("実戦履歴")
                                            .font(.system(size: 13, weight: .medium, design: .monospaced))
                                        Text("日付ごとの実戦一覧・保存した記録")
                                            .font(.system(size: 10, weight: .regular))
                                            .foregroundColor(cyan.opacity(0.6))
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.caption2)
                                        .foregroundColor(cyan.opacity(0.6))
                                }
                                .foregroundColor(cyan)
                                .padding(.vertical, 6)
                                .padding(.horizontal, 10)
                            }
                            .buttonStyle(.plain)
                        }
                        if let onOpenEventHistory = onOpenEventHistory {
                            Button(action: onOpenEventHistory) {
                                HStack(alignment: .center) {
                                    Image(systemName: "list.bullet")
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("当選・投入履歴")
                                            .font(.system(size: 13, weight: .medium, design: .monospaced))
                                        Text("今回の当選・投入の時系列")
                                            .font(.system(size: 10, weight: .regular))
                                            .foregroundColor(cyan.opacity(0.6))
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.caption2)
                                        .foregroundColor(cyan.opacity(0.6))
                                }
                                .foregroundColor(cyan)
                                .padding(.vertical, 6)
                                .padding(.horizontal, 10)
                            }
                            .buttonStyle(.plain)
                        }
                        if let onOpenAnalytics = onOpenAnalytics {
                            Button(action: onOpenAnalytics) {
                                HStack(alignment: .center) {
                                    Image(systemName: "chart.bar")
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("データ分析")
                                            .font(.system(size: 13, weight: .medium, design: .monospaced))
                                        Text("収支・回転率・稼働ヒートマップなど")
                                            .font(.system(size: 10, weight: .regular))
                                            .foregroundColor(cyan.opacity(0.6))
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.caption2)
                                        .foregroundColor(cyan.opacity(0.6))
                                }
                                .foregroundColor(cyan)
                                .padding(.vertical, 6)
                                .padding(.horizontal, 10)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(AppGlassStyle.rowBackground)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(cyan.opacity(0.2), lineWidth: 1))
                }

                // 今回の収支
                VStack(alignment: .leading, spacing: 6) {
                    panelTitle("今回の成績")
                    // 上段：実際の成績（投入に対する回収）
                    VStack(alignment: .leading, spacing: 2) {
                        Text("実際の成績")
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .foregroundColor(cyan.opacity(0.75))
                        Text(log.balancePt >= 0 ? "+\(log.balancePt.formattedPtWithUnit)" : "\(log.balancePt.formattedPtWithUnit)")
                            .font(.system(size: 20, weight: .bold, design: .monospaced))
                            .foregroundColor(log.balancePt >= 0 ? cyan : Color.orange.opacity(0.95))
                        Text("収入−投入（収入＝出玉×払出係数・500pt刻み端数切捨て）")
                            .font(.system(size: 9, weight: .regular, design: .rounded))
                            .foregroundColor(cyan.opacity(0.5))
                    }
                    // 下段：期待値収支（期待される損益）
                    VStack(alignment: .leading, spacing: 2) {
                        Text("期待値収支（期待される損益）")
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .foregroundColor(cyan.opacity(0.75))
                        if log.effectiveUnitsForBorder > 0 && log.dynamicBorder > 0 {
                            let pt = theoreticalExpectationPt
                            Text(pt >= 0 ? "+\(pt.formattedPtWithUnit)" : "\(pt.formattedPtWithUnit)")
                                .font(.system(size: 18, weight: .semibold, design: .monospaced))
                                .foregroundColor(pt >= 0 ? cyan : Color.orange.opacity(0.95))
                        } else {
                            Text("—")
                                .font(.system(size: 18, weight: .semibold, design: .monospaced))
                                .foregroundColor(cyan.opacity(0.6))
                        }
                        Text("実費×（期待値比−1）。実費＝投入＋持ち玉投入のpt換算")
                            .font(.system(size: 9, weight: .regular, design: .rounded))
                            .foregroundColor(cyan.opacity(0.5))
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(cyan.opacity(0.08))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(cyan.opacity(0.25), lineWidth: 1))

                // 今回の遊技情報
                VStack(alignment: .leading, spacing: 4) {
                    panelTitle("今回の遊技情報")
                    HStack {
                        HStack(spacing: 4) {
                            labelText("総回転数")
                            InfoIconView(explanation: "通常回転のみの累積（時短・電サポ除く）。", tint: cyan.opacity(0.7))
                        }
                        Spacer()
                        Text("\(log.normalRotations)")
                            .font(.system(size: 13, weight: .medium, design: .monospaced))
                            .foregroundColor(cyan.opacity(0.95))
                    }
                    HStack {
                        labelText("投入額")
                        Spacer()
                        Text(log.totalInput.formattedPtWithUnit)
                            .font(.system(size: 13, weight: .medium, design: .monospaced))
                            .foregroundColor(cyan.opacity(0.95))
                    }
                    HStack {
                        HStack(spacing: 4) {
                            labelText("持ち玉投資")
                            InfoIconView(explanation: "今回の遊技で使った持ち玉の玉数。", tint: cyan.opacity(0.7))
                        }
                        Spacer()
                        Text("\(log.holdingsInvestedBalls) 玉")
                            .font(.system(size: 13, weight: .medium, design: .monospaced))
                            .foregroundColor(cyan.opacity(0.95))
                    }
                    if log.dynamicBorder > 0 {
                        HStack {
                            HStack(spacing: 4) {
                                labelText("推定消費玉（T）")
                                InfoIconView(explanation: "通常回転と店補正後のボーダーから推定した撃ち込み玉数。時短・電サポ・右打ち中の回転は含みません。", tint: cyan.opacity(0.7))
                            }
                            Spacer()
                            Text("\(log.tapDerivedBallsConsumed) 玉")
                                .font(.system(size: 13, weight: .medium, design: .monospaced))
                                .foregroundColor(cyan.opacity(0.95))
                        }
                        HStack {
                            HStack(spacing: 4) {
                                labelText("現金由来（C）")
                                InfoIconView(explanation: "現金投入を店の貸玉料金で換算した玉数。", tint: cyan.opacity(0.7))
                            }
                            Spacer()
                            Text("\(log.cashOriginBallsConsumed) 玉")
                                .font(.system(size: 13, weight: .medium, design: .monospaced))
                                .foregroundColor(cyan.opacity(0.95))
                        }
                        HStack {
                            HStack(spacing: 4) {
                                labelText("持ち玉由来（H）")
                                InfoIconView(explanation: "二重計上を避けるため H＝max(0, T−C) で定義。上の「持ち玉投資」とは一致しない場合があります。", tint: cyan.opacity(0.7))
                            }
                            Spacer()
                            Text("\(log.holdingsOriginBallsFromIdentity) 玉")
                                .font(.system(size: 13, weight: .medium, design: .monospaced))
                                .foregroundColor(cyan.opacity(0.95))
                        }
                        HStack {
                            HStack(spacing: 4) {
                                labelText("持ち玉比率")
                                InfoIconView(explanation: "H÷T。Tが0のときは表示しません。", tint: cyan.opacity(0.7))
                            }
                            Spacer()
                            if let r = log.holdingsUsageRatio {
                                Text(String(format: "%.1f%%", r * 100))
                                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                                    .foregroundColor(cyan.opacity(0.95))
                            } else {
                                Text("—")
                                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                                    .foregroundColor(cyan.opacity(0.6))
                            }
                        }
                    }
                    HStack {
                        HStack(spacing: 4) {
                            labelText("実費換算")
                            InfoIconView(explanation: "現金＋持ち玉を払出係数でpt換算した合計（回転率・期待値の実費ベース）。", tint: cyan.opacity(0.7))
                        }
                        Spacer()
                        Text(String(format: "%.0f pt", log.totalRealCost))
                            .font(.system(size: 13, weight: .medium, design: .monospaced))
                            .foregroundColor(cyan.opacity(0.95))
                    }
                    HStack {
                        HStack(spacing: 4) {
                            labelText("換算単位")
                            InfoIconView(explanation: "回転率の分母。1単位＝等価250玉。現金は500ptごとの貸玉で玉に換算し持ち玉投資を足して250で割ります。", tint: cyan.opacity(0.7))
                        }
                        Spacer()
                        Text(String(format: "%.2f 単位", log.effectiveUnitsForBorder))
                            .font(.system(size: 13, weight: .medium, design: .monospaced))
                            .foregroundColor(cyan.opacity(0.95))
                    }
                    HStack {
                        HStack(spacing: 4) {
                            labelText("ボーダー")
                            InfoIconView(explanation: "メーカー公表の等価ボーダー（回/1000pt）。通常回転のみ。", tint: cyan.opacity(0.7))
                        }
                        Spacer()
                        Text(log.formulaBorderValue > 0 ? String(format: "%.1f 回/1k", log.formulaBorderValue) : "—")
                            .font(.system(size: 13, weight: .medium, design: .monospaced))
                            .foregroundColor(cyan.opacity(0.95))
                    }
                    HStack {
                        HStack(spacing: 4) {
                            labelText("実質ボーダー")
                            InfoIconView(explanation: "店の貸玉料金・払出係数で補正したボーダー（回/1000pt）。", tint: cyan.opacity(0.7))
                        }
                        Spacer()
                        Text(log.dynamicBorder > 0 ? String(format: "%.1f 回/1k", log.dynamicBorder) : "—")
                            .font(.system(size: 13, weight: .medium, design: .monospaced))
                            .foregroundColor(cyan.opacity(0.95))
                    }
                    HStack {
                        HStack(spacing: 4) {
                            labelText("期待値比")
                            InfoIconView(explanation: "実質回転率÷店補正後のボーダー。1.0で基準。", tint: cyan.opacity(0.7))
                        }
                        Spacer()
                        Text(String(format: "%.2f%%", log.expectationRatio * 100))
                            .font(.system(size: 13, weight: .medium, design: .monospaced))
                            .foregroundColor(cyan.opacity(0.95))
                    }
                    if log.totalRealCost > 0 && log.dynamicBorder > 0 {
                        HStack {
                            labelText("プラス転換まであと")
                            Spacer()
                            if spinsToBreakEven == 0 {
                                Text("ボーダー到達")
                                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                                    .foregroundColor(cyan)
                            } else {
                                Text("あと \(spinsToBreakEven) 回")
                                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                                    .foregroundColor(cyan.opacity(0.95))
                            }
                        }
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AppGlassStyle.rowBackground)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(cyan.opacity(0.2), lineWidth: 1))

                // あとから修正
                VStack(alignment: .leading, spacing: 4) {
                    panelTitle("修正")
                    Text("入力ミスや記録漏れをあとから直せます")
                        .font(.system(size: 10, weight: .regular))
                        .foregroundColor(cyan.opacity(0.6))
                        .padding(.horizontal, 10)
                        .padding(.bottom, 2)
                    if let onCorrectInitialRotation = onCorrectInitialRotation {
                        Button(action: onCorrectInitialRotation) {
                            HStack(alignment: .center) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("開始ゲーム数を修正")
                                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                                    Text("遊技開始時の表示回転数")
                                        .font(.system(size: 10, weight: .regular))
                                        .foregroundColor(cyan.opacity(0.6))
                                }
                                .foregroundColor(cyan)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption2)
                                    .foregroundColor(cyan.opacity(0.6))
                            }
                            .padding(.vertical, 6)
                            .padding(.horizontal, 10)
                        }
                        .buttonStyle(.plain)
                    }
                    if let onCorrectCash = onCorrectCash {
                        Button(action: onCorrectCash) {
                            HStack(alignment: .center) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("投資を修正")
                                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                                    Text("総投資（pt・現金の合計）")
                                        .font(.system(size: 10, weight: .regular))
                                        .foregroundColor(cyan.opacity(0.6))
                                }
                                .foregroundColor(cyan)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption2)
                                    .foregroundColor(cyan.opacity(0.6))
                            }
                            .padding(.vertical, 6)
                            .padding(.horizontal, 10)
                        }
                        .buttonStyle(.plain)
                    }
                    if let onCorrectHoldings = onCorrectHoldings {
                        Button(action: onCorrectHoldings) {
                            HStack(alignment: .center) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("持ち玉投資を修正")
                                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                                    Text("使った持ち玉の玉数")
                                        .font(.system(size: 10, weight: .regular))
                                        .foregroundColor(cyan.opacity(0.6))
                                }
                                .foregroundColor(cyan)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption2)
                                    .foregroundColor(cyan.opacity(0.6))
                            }
                            .padding(.vertical, 6)
                            .padding(.horizontal, 10)
                        }
                        .buttonStyle(.plain)
                    }
                    if let onCorrectWinCount = onCorrectWinCount {
                        Button(action: onCorrectWinCount) {
                            HStack(alignment: .center) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("当選回数を修正")
                                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                                    Text("棒グラフの棒をタップして1区間ずつ直すか、ここで RUSH・通常の合計を修正")
                                        .font(.system(size: 10, weight: .regular))
                                        .foregroundColor(cyan.opacity(0.6))
                                }
                                .foregroundColor(cyan)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption2)
                                    .foregroundColor(cyan.opacity(0.6))
                            }
                            .padding(.vertical, 6)
                            .padding(.horizontal, 10)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AppGlassStyle.rowBackground)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(cyan.opacity(0.2), lineWidth: 1))

                // モード切替：左手/右手のみ（省エネは効果が限定的のためドロワーからは外す）
                if onToggleRightHandMode != nil {
                    VStack(alignment: .leading, spacing: 4) {
                        panelTitle("モード切替")
                        if let onToggle = onToggleRightHandMode {
                            Button(action: onToggle) {
                                HStack(alignment: .center) {
                                    Image(systemName: isRightHandMode ? "hand.point.right.fill" : "hand.point.left.fill")
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(isRightHandMode ? "右手操作" : "左手操作（現在）")
                                            .font(.system(size: 13, weight: .medium, design: .monospaced))
                                        Text("ボタン配置の左右反転")
                                            .font(.system(size: 10, weight: .regular))
                                            .foregroundColor(cyan.opacity(0.6))
                                    }
                                    Spacer()
                                    Text("タップで切り替え")
                                        .font(.system(size: 10, weight: .regular, design: .monospaced))
                                        .foregroundColor(cyan.opacity(0.6))
                                }
                                .foregroundColor(cyan)
                                .padding(.vertical, 6)
                                .padding(.horizontal, 10)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(AppGlassStyle.rowBackground)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(cyan.opacity(0.2), lineWidth: 1))
                }
            }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(darkNavy)
        .gesture(
            DragGesture(minimumDistance: 30)
                .onEnded { value in
                    if value.translation.width < -50 {
                        onClose()
                    }
                }
        )
    }

    /// パネルタイトル用（閲覧・収支・今回の遊技情報・修正・モード切替）
    private func panelTitle(_ s: String) -> some View {
        Text(s)
            .font(AppTypography.insightPanelTitle)
            .foregroundColor(cyan.opacity(0.85))
            .textCase(.uppercase)
    }

    private func labelText(_ s: String) -> some View {
        Text(s)
            .font(.system(size: 12, weight: .medium, design: .monospaced))
            .foregroundColor(cyan.opacity(0.6))
    }
}

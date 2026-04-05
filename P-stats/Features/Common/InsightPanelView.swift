import SwiftUI
import SwiftData

// MARK: - インサイトパネル（右ドロワー）
/// 今日の実戦に基づく「今の欠損額」「あと何回でプラス転換」などを表示。スキンのアクセントとインサイト用背景で統一。左スワイプで閉じる。
struct InsightPanelView: View {
    @Bindable var log: GameLog
    @EnvironmentObject private var themeManager: ThemeManager
    let onClose: () -> Void
    var onShareSNS: (() -> Void)? = nil
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

    private var insightAccent: Color { themeManager.currentTheme.accentColor }
    private var drawerBackdrop: Color { themeManager.currentTheme.insightDrawerBackdrop }
    private var sectionSurface: Color { themeManager.currentTheme.insightSectionSurface }

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
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .tracking(0.5)
                    .foregroundColor(insightAccent.opacity(0.9))
                Spacer()
                Button(action: { onClose() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 22, weight: .regular, design: .rounded))
                        .foregroundColor(insightAccent.opacity(0.7))
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
                                    .font(.system(size: 15, weight: .medium, design: .monospaced))
                                Text("機種・店舗・テーマなどのアプリ設定")
                                    .font(.system(size: 12, weight: .regular))
                                    .foregroundColor(insightAccent.opacity(0.6))
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 14, weight: .regular, design: .rounded))
                                .foregroundColor(insightAccent.opacity(0.6))
                        }
                        .foregroundColor(insightAccent)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 12)
                    }
                    .buttonStyle(.plain)
                    .background(sectionSurface)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(insightAccent.opacity(0.2), lineWidth: 1))
                }

                if let onShareSNS = onShareSNS {
                    Button(action: onShareSNS) {
                        HStack(alignment: .center) {
                            Image(systemName: "square.and.arrow.up")
                            VStack(alignment: .leading, spacing: 2) {
                                Text("SNSで共有")
                                    .font(.system(size: 15, weight: .medium, design: .monospaced))
                                Text("今の戦果を画像にして共有（途中でもOK）")
                                    .font(.system(size: 12, weight: .regular))
                                    .foregroundColor(insightAccent.opacity(0.6))
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 14, weight: .regular, design: .rounded))
                                .foregroundColor(insightAccent.opacity(0.6))
                        }
                        .foregroundColor(insightAccent)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 12)
                    }
                    .buttonStyle(.plain)
                    .background(sectionSurface)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(insightAccent.opacity(0.2), lineWidth: 1))
                }

                // 閲覧：履歴・分析・大当たり・投資履歴（遊技中でも開ける）
                if onOpenHistory != nil || onOpenEventHistory != nil || onOpenAnalytics != nil {
                    VStack(alignment: .leading, spacing: 4) {
                        panelTitle("閲覧")
                        if let onOpenHistory = onOpenHistory {
                            Button(action: onOpenHistory) {
                                HStack(alignment: .center) {
                                    Image(systemName: "calendar")
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("実戦履歴")
                                            .font(.system(size: 15, weight: .medium, design: .monospaced))
                                        Text("日付ごとの実戦一覧・保存した記録")
                                            .font(.system(size: 12, weight: .regular))
                                            .foregroundColor(insightAccent.opacity(0.6))
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 14, weight: .regular, design: .rounded))
                                        .foregroundColor(insightAccent.opacity(0.6))
                                }
                                .foregroundColor(insightAccent)
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
                                        Text("当選・投資履歴")
                                            .font(.system(size: 15, weight: .medium, design: .monospaced))
                                        Text("今回の当選・投資の時系列")
                                            .font(.system(size: 12, weight: .regular))
                                            .foregroundColor(insightAccent.opacity(0.6))
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 14, weight: .regular, design: .rounded))
                                        .foregroundColor(insightAccent.opacity(0.6))
                                }
                                .foregroundColor(insightAccent)
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
                                            .font(.system(size: 15, weight: .medium, design: .monospaced))
                                        Text("収支・回転率・稼働ヒートマップなど")
                                            .font(.system(size: 12, weight: .regular))
                                            .foregroundColor(insightAccent.opacity(0.6))
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 14, weight: .regular, design: .rounded))
                                        .foregroundColor(insightAccent.opacity(0.6))
                                }
                                .foregroundColor(insightAccent)
                                .padding(.vertical, 6)
                                .padding(.horizontal, 10)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(sectionSurface)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(insightAccent.opacity(0.2), lineWidth: 1))
                }

                // 今回の収支
                VStack(alignment: .leading, spacing: 6) {
                    panelTitle("今回の成績")
                    // 上段：実際の成績（投入に対する回収）
                    VStack(alignment: .leading, spacing: 2) {
                        Text("実際の成績")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundColor(insightAccent.opacity(0.75))
                        Text(log.balancePt >= 0 ? "+\(log.balancePt.formattedPtWithUnit)" : "\(log.balancePt.formattedPtWithUnit)")
                            .font(.system(size: 20, weight: .bold, design: .monospaced))
                            .foregroundColor(log.balancePt >= 0 ? insightAccent : themeManager.currentTheme.cautionForegroundColor.opacity(0.95))
                        Text("回収−投入（回収＝出玉×交換率(pt/玉)・500pt刻み端数切捨て）")
                            .font(.system(size: 11, weight: .regular, design: .rounded))
                            .foregroundColor(insightAccent.opacity(0.5))
                    }
                    // 下段：期待値収支（期待される損益）
                    VStack(alignment: .leading, spacing: 2) {
                        Text("期待値収支（期待される損益）")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundColor(insightAccent.opacity(0.75))
                        if log.effectiveUnitsForBorder > 0 && log.dynamicBorder > 0 {
                            let pt = theoreticalExpectationPt
                            Text(pt >= 0 ? "+\(pt.formattedPtWithUnit)" : "\(pt.formattedPtWithUnit)")
                                .font(.system(size: 18, weight: .semibold, design: .monospaced))
                                .foregroundColor(pt >= 0 ? insightAccent : themeManager.currentTheme.cautionForegroundColor.opacity(0.95))
                        } else {
                            Text("—")
                                .font(.system(size: 18, weight: .semibold, design: .monospaced))
                                .foregroundColor(insightAccent.opacity(0.6))
                        }
                        Text("実費×（期待値比−1）。実費＝投入＋持ち玉投入のpt換算")
                            .font(.system(size: 11, weight: .regular, design: .rounded))
                            .foregroundColor(insightAccent.opacity(0.5))
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(insightAccent.opacity(0.08))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(insightAccent.opacity(0.25), lineWidth: 1))

                // 今回の遊技情報
                VStack(alignment: .leading, spacing: 4) {
                    panelTitle("今回の遊技情報")
                    HStack {
                        HStack(spacing: 4) {
                            labelText("総回転数")
                            InfoIconView(explanation: "通常回転のみの累積（時短・電サポ除く）。", tint: insightAccent.opacity(0.7))
                        }
                        Spacer()
                        Text("\(log.normalRotations)")
                            .font(.system(size: 15, weight: .medium, design: .monospaced))
                            .foregroundColor(insightAccent.opacity(0.95))
                    }
                    HStack {
                        labelText("投資額")
                        Spacer()
                        Text(log.totalInput.formattedPtWithUnit)
                            .font(.system(size: 15, weight: .medium, design: .monospaced))
                            .foregroundColor(insightAccent.opacity(0.95))
                    }
                    HStack {
                        HStack(spacing: 4) {
                            labelText("持ち玉投資")
                            InfoIconView(explanation: "今回の遊技で使った持ち玉の玉数。", tint: insightAccent.opacity(0.7))
                        }
                        Spacer()
                        Text("\(log.holdingsInvestedBalls) 玉")
                            .font(.system(size: 15, weight: .medium, design: .monospaced))
                            .foregroundColor(insightAccent.opacity(0.95))
                    }
                    if log.dynamicBorder > 0 {
                        HStack {
                            HStack(spacing: 4) {
                                labelText("推定消費玉（T）")
                                InfoIconView(explanation: "通常回転と店補正後のボーダーから推定した撃ち込み玉数。時短・電サポ・右打ち中の回転は含みません。", tint: insightAccent.opacity(0.7))
                            }
                            Spacer()
                            Text("\(log.tapDerivedBallsConsumed) 玉")
                                .font(.system(size: 15, weight: .medium, design: .monospaced))
                                .foregroundColor(insightAccent.opacity(0.95))
                        }
                        HStack {
                            HStack(spacing: 4) {
                                labelText("現金由来（C）")
                                InfoIconView(explanation: "現金投資を店の貸玉数（500ptあたり）で換算した玉数。", tint: insightAccent.opacity(0.7))
                            }
                            Spacer()
                            Text("\(log.cashOriginBallsConsumed) 玉")
                                .font(.system(size: 15, weight: .medium, design: .monospaced))
                                .foregroundColor(insightAccent.opacity(0.95))
                        }
                        HStack {
                            HStack(spacing: 4) {
                                labelText("持ち玉由来（H）")
                                InfoIconView(explanation: "二重計上を避けるため H＝max(0, T−C) で定義。上の「持ち玉投資」とは一致しない場合があります。", tint: insightAccent.opacity(0.7))
                            }
                            Spacer()
                            Text("\(log.holdingsOriginBallsFromIdentity) 玉")
                                .font(.system(size: 15, weight: .medium, design: .monospaced))
                                .foregroundColor(insightAccent.opacity(0.95))
                        }
                        HStack {
                            HStack(spacing: 4) {
                                labelText("持ち玉比率")
                                InfoIconView(explanation: "H÷T。Tが0のときは表示しません。", tint: insightAccent.opacity(0.7))
                            }
                            Spacer()
                            if let r = log.holdingsUsageRatio, r.isValidForNumericDisplay {
                                Text((r * 100).displayFormat("%.1f%%"))
                                    .font(.system(size: 15, weight: .medium, design: .monospaced))
                                    .foregroundColor(insightAccent.opacity(0.95))
                            } else {
                                Text("—")
                                    .font(.system(size: 15, weight: .medium, design: .monospaced))
                                    .foregroundColor(insightAccent.opacity(0.6))
                            }
                        }
                    }
                    HStack {
                        HStack(spacing: 4) {
                            labelText("実費換算")
                            InfoIconView(explanation: "現金＋持ち玉を交換率（pt/玉）でpt換算した合計（回転率・期待値の実費ベース）。", tint: insightAccent.opacity(0.7))
                        }
                        Spacer()
                        Text(log.totalRealCost.displayFormat("%.0f pt"))
                            .font(.system(size: 15, weight: .medium, design: .monospaced))
                            .foregroundColor(insightAccent.opacity(0.95))
                    }
                    HStack {
                        HStack(spacing: 4) {
                            labelText("換算単位")
                            InfoIconView(explanation: "回転率の分母。1単位＝等価250玉。現金は500ptごとの貸玉数で玉に換算し持ち玉投資を足して250で割ります。", tint: insightAccent.opacity(0.7))
                        }
                        Spacer()
                        Text(log.effectiveUnitsForBorder.displayFormat("%.2f 単位"))
                            .font(.system(size: 15, weight: .medium, design: .monospaced))
                            .foregroundColor(insightAccent.opacity(0.95))
                    }
                    HStack {
                        HStack(spacing: 4) {
                            labelText("ボーダー")
                            InfoIconView(explanation: "メーカー公表の等価ボーダー（回/1000pt）。通常回転のみ。", tint: insightAccent.opacity(0.7))
                        }
                        Spacer()
                        Text(log.formulaBorderValue > 0 ? log.formulaBorderValue.displayFormat("%.1f 回/1k") : "—")
                            .font(.system(size: 15, weight: .medium, design: .monospaced))
                            .foregroundColor(insightAccent.opacity(0.95))
                    }
                    HStack {
                        HStack(spacing: 4) {
                            labelText("実質ボーダー")
                            InfoIconView(explanation: "店の貸玉数（500ptあたり）・交換率（pt/玉）で補正したボーダー（回/1000pt）。", tint: insightAccent.opacity(0.7))
                        }
                        Spacer()
                        Text(log.dynamicBorder > 0 ? log.dynamicBorder.displayFormat("%.1f 回/1k") : "—")
                            .font(.system(size: 15, weight: .medium, design: .monospaced))
                            .foregroundColor(insightAccent.opacity(0.95))
                    }
                    HStack {
                        HStack(spacing: 4) {
                            labelText("期待値比")
                            InfoIconView(explanation: "実質回転率÷店補正後のボーダー。1.0で基準。", tint: insightAccent.opacity(0.7))
                        }
                        Spacer()
                        Text((log.expectationRatio * 100).displayFormat("%.2f%%"))
                            .font(.system(size: 15, weight: .medium, design: .monospaced))
                            .foregroundColor(insightAccent.opacity(0.95))
                    }
                    if log.totalRealCost > 0 && log.dynamicBorder > 0 {
                        HStack {
                            labelText("プラス転換まであと")
                            Spacer()
                            if spinsToBreakEven == 0 {
                                Text("ボーダー到達")
                                    .font(.system(size: 15, weight: .medium, design: .monospaced))
                                    .foregroundColor(insightAccent)
                            } else {
                                Text("あと \(spinsToBreakEven) 回")
                                    .font(.system(size: 15, weight: .medium, design: .monospaced))
                                    .foregroundColor(insightAccent.opacity(0.95))
                            }
                        }
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(sectionSurface)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(insightAccent.opacity(0.2), lineWidth: 1))

                // あとから修正
                VStack(alignment: .leading, spacing: 4) {
                    panelTitle("修正")
                    Text("入力ミスや記録漏れをあとから直せます")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(insightAccent.opacity(0.6))
                        .padding(.horizontal, 10)
                        .padding(.bottom, 2)
                    if let onCorrectInitialRotation = onCorrectInitialRotation {
                        Button(action: onCorrectInitialRotation) {
                            HStack(alignment: .center) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("開始ゲーム数を修正")
                                        .font(.system(size: 15, weight: .medium, design: .monospaced))
                                    Text("遊技開始時の表示回転数")
                                        .font(.system(size: 12, weight: .regular))
                                        .foregroundColor(insightAccent.opacity(0.6))
                                }
                                .foregroundColor(insightAccent)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 14, weight: .regular, design: .rounded))
                                    .foregroundColor(insightAccent.opacity(0.6))
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
                                        .font(.system(size: 15, weight: .medium, design: .monospaced))
                                    Text("総投資（pt・現金の合計）")
                                        .font(.system(size: 12, weight: .regular))
                                        .foregroundColor(insightAccent.opacity(0.6))
                                }
                                .foregroundColor(insightAccent)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 14, weight: .regular, design: .rounded))
                                    .foregroundColor(insightAccent.opacity(0.6))
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
                                    Text("現在の持ち玉数に合わせる")
                                        .font(.system(size: 15, weight: .medium, design: .monospaced))
                                    Text("台の残り持ち玉を入力（アプリとの差を投資に反映）")
                                        .font(.system(size: 12, weight: .regular))
                                        .foregroundColor(insightAccent.opacity(0.6))
                                }
                                .foregroundColor(insightAccent)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 14, weight: .regular, design: .rounded))
                                    .foregroundColor(insightAccent.opacity(0.6))
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
                                    Text("大当たり区間を修正")
                                        .font(.system(size: 15, weight: .medium, design: .monospaced))
                                    Text("今回の遊技の区間を選び、当たり回数（1＝通常・2 以上＝RUSH）と総獲得出玉を入力")
                                        .font(.system(size: 12, weight: .regular))
                                        .foregroundColor(insightAccent.opacity(0.6))
                                }
                                .foregroundColor(insightAccent)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 14, weight: .regular, design: .rounded))
                                    .foregroundColor(insightAccent.opacity(0.6))
                            }
                            .padding(.vertical, 6)
                            .padding(.horizontal, 10)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(sectionSurface)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(insightAccent.opacity(0.2), lineWidth: 1))

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
                                            .font(.system(size: 15, weight: .medium, design: .monospaced))
                                        Text("ボタン配置の左右反転")
                                            .font(.system(size: 12, weight: .regular))
                                            .foregroundColor(insightAccent.opacity(0.6))
                                    }
                                    Spacer()
                                    Text("タップで切り替え")
                                        .font(.system(size: 12, weight: .regular, design: .monospaced))
                                        .foregroundColor(insightAccent.opacity(0.6))
                                }
                                .foregroundColor(insightAccent)
                                .padding(.vertical, 6)
                                .padding(.horizontal, 10)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(sectionSurface)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(insightAccent.opacity(0.2), lineWidth: 1))
                }
            }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(drawerBackdrop)
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
            .foregroundColor(insightAccent.opacity(0.85))
            .textCase(.uppercase)
    }

    private func labelText(_ s: String) -> some View {
        Text(s)
            .font(.system(size: 14, weight: .medium, design: .monospaced))
            .foregroundColor(insightAccent.opacity(0.6))
    }
}

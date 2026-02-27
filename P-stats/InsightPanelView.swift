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
    var onOpenHistory: (() -> Void)? = nil
    var onOpenAnalytics: (() -> Void)? = nil
    var onOpenPowerSaving: (() -> Void)? = nil
    var onOpenSettings: (() -> Void)? = nil
    var onToggleRightHandMode: (() -> Void)? = nil
    var isRightHandMode: Bool = false

    private let cyan = AppGlassStyle.accent
    private let darkNavy = AppGlassStyle.background

    /// 理論上の今の期待値（円）。正=黒字側、負=欠損側
    private var theoreticalExpectationYen: Int {
        guard log.totalRealCost > 0, log.dynamicBorder > 0 else { return 0 }
        let ratio = log.expectationRatio
        return Int(round(log.totalRealCost * (ratio - 1)))
    }

    /// ボーダーに達するのに必要な通常回転数（現金1000円・持ち玉250玉単位の実質コストに対する）
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
                Text("INSIGHT")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .tracking(2)
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

            VStack(alignment: .leading, spacing: 8) {
                // 閲覧：履歴・分析（遊戯中でも開ける）
                if onOpenHistory != nil || onOpenAnalytics != nil {
                    VStack(alignment: .leading, spacing: 4) {
                        panelTitle("閲覧")
                        if let onOpenHistory = onOpenHistory {
                            Button(action: onOpenHistory) {
                                HStack {
                                    Image(systemName: "calendar")
                                    Text("実戦履歴")
                                        .font(.system(size: 13, weight: .medium, design: .monospaced))
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
                                HStack {
                                    Image(systemName: "chart.bar")
                                    Text("データ分析")
                                        .font(.system(size: 13, weight: .medium, design: .monospaced))
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
                    panelTitle("今回の収支")
                    // 収支：改行して表示し、その下に算出根拠
                    VStack(alignment: .leading, spacing: 2) {
                        Text(log.balanceYen >= 0 ? "+\(log.balanceYen) 円" : "\(log.balanceYen) 円")
                            .font(.system(size: 20, weight: .bold, design: .monospaced))
                            .foregroundColor(log.balanceYen >= 0 ? cyan : Color.orange.opacity(0.95))
                        Text("収入−現金投資（収入＝出玉×交換率・500円刻み端数切捨て）")
                            .font(.system(size: 9, weight: .regular, design: .rounded))
                            .foregroundColor(cyan.opacity(0.5))
                    }
                    // 今回の期待値：改行して表示し、その下に算出根拠
                    VStack(alignment: .leading, spacing: 2) {
                        if log.effectiveUnitsForBorder > 0 && log.dynamicBorder > 0 {
                            let yen = theoreticalExpectationYen
                            Text(yen >= 0 ? "+\(yen) 円" : "\(yen) 円")
                                .font(.system(size: 18, weight: .semibold, design: .monospaced))
                                .foregroundColor(yen >= 0 ? cyan : Color.orange.opacity(0.95))
                        } else {
                            Text("—")
                                .font(.system(size: 18, weight: .semibold, design: .monospaced))
                                .foregroundColor(cyan.opacity(0.6))
                        }
                        Text("実費×（期待値比−1）。実費＝現金投資＋持ち玉投資の円換算")
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
                        labelText("総回転数")
                        Spacer()
                        Text("\(log.totalRotations)")
                            .font(.system(size: 13, weight: .medium, design: .monospaced))
                            .foregroundColor(cyan.opacity(0.95))
                    }
                    HStack {
                        labelText("現金投資額")
                        Spacer()
                        Text("\(log.investment) 円")
                            .font(.system(size: 13, weight: .medium, design: .monospaced))
                            .foregroundColor(cyan.opacity(0.95))
                    }
                    HStack {
                        labelText("公式ボーダー")
                        Spacer()
                        Text(log.formulaBorderValue > 0 ? String(format: "%.1f 回/千円", log.formulaBorderValue) : "—")
                            .font(.system(size: 13, weight: .medium, design: .monospaced))
                            .foregroundColor(cyan.opacity(0.95))
                    }
                    HStack {
                        labelText("実質ボーダー")
                        Spacer()
                        Text(log.dynamicBorder > 0 ? String(format: "%.1f 回/千円", log.dynamicBorder) : "—")
                            .font(.system(size: 13, weight: .medium, design: .monospaced))
                            .foregroundColor(cyan.opacity(0.95))
                    }
                    HStack {
                        labelText("期待値比")
                        Spacer()
                        Text(String(format: "%.1f%%", log.expectationRatio * 100))
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
                    if let onCorrectInitialRotation = onCorrectInitialRotation {
                        Button(action: onCorrectInitialRotation) {
                            HStack {
                                Text("開始ゲーム数を修正")
                                    .font(.system(size: 13, weight: .medium, design: .monospaced))
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
                            HStack {
                                Text("現金投資を修正")
                                    .font(.system(size: 13, weight: .medium, design: .monospaced))
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
                            HStack {
                                Text("持ち玉投資を修正")
                                    .font(.system(size: 13, weight: .medium, design: .monospaced))
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

                // モード切替：左手/右手・省エネモード・設定
                if onToggleRightHandMode != nil || onOpenPowerSaving != nil || onOpenSettings != nil {
                    VStack(alignment: .leading, spacing: 4) {
                        panelTitle("モード切替")
                        if let onToggle = onToggleRightHandMode {
                            Button(action: onToggle) {
                                HStack {
                                    Image(systemName: isRightHandMode ? "hand.point.right.fill" : "hand.point.left.fill")
                                    Text(isRightHandMode ? "右手操作" : "左手操作（現在）")
                                        .font(.system(size: 13, weight: .medium, design: .monospaced))
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
                        if let onOpenPowerSaving = onOpenPowerSaving {
                            Button(action: onOpenPowerSaving) {
                                HStack {
                                    Image(systemName: "leaf.fill")
                                    Text("省エネモード")
                                        .font(.system(size: 13, weight: .medium, design: .monospaced))
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
                            .accessibilityLabel("省エネモード")
                        }
                        if let onOpenSettings = onOpenSettings {
                            Button(action: onOpenSettings) {
                                HStack {
                                    Image(systemName: "gearshape.fill")
                                    Text("設定")
                                        .font(.system(size: 13, weight: .medium, design: .monospaced))
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
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundColor(cyan.opacity(0.75))
            .textCase(.uppercase)
    }

    private func labelText(_ s: String) -> some View {
        Text(s)
            .font(.system(size: 12, weight: .medium, design: .monospaced))
            .foregroundColor(cyan.opacity(0.6))
    }
}

import SwiftUI
import SwiftData
import Combine
import UIKit

struct PlayView: View {
    @Bindable var log: GameLog
    @Binding var theme: AppTheme
    /// ドロワー「設定」タップ時に呼ぶ。nil でなければ実戦を閉じて設定タブへ遷移
    var onOpenSettingsTab: (() -> Void)? = nil
    @Environment(\.dismiss) var dismiss // ホームに戻るために必要
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("alwaysShowBothInvestmentButtons") private var alwaysShowBothInvestmentButtons = true

    @State private var showSettingsSheet = false
    @State private var showSyncSheet = false
    @State private var showTrayAdjustSheet = false
    @State private var showEndConfirm = false
    @State private var showEmptySaveConfirm = false
    @State private var showFinalHoldingsInput = false
    @State private var finalHoldingsInput: String = ""
    @State private var finalHoldingsPadTrigger = 0
    @State private var finalNormalRotationsInput: String = ""
    @State private var finalNormalRotationsPadTrigger = 0
    /// 回収玉確認後、換金／貯玉の選択
    @State private var showSettlementSheet = false
    /// 保存結果。"ok"＝成功（アラート表示後にdismiss）、"error: ..."＝失敗
    @State private var saveResult: String? = nil
    @State private var showHoldingsSyncSheet = false
    @State private var tempHoldingsSyncValue: String = ""
    @State private var showPowerSavingMode = false
    /// 今回の遊技で省エネを自動表示したか（1回だけ自動表示するため）
    @State private var didAutoOpenPowerSavingThisSession = false
    /// 大当たりモード終了時：回数・総出玉の確定
    @State private var showBigHitExitSheet = false
    /// VoiceOver / 長押し：スライドの代替で大当たり開始を確認
    @State private var showBigHitAccessibilityConfirm = false
    @State private var bigHitExitHitsField = ""
    @State private var bigHitExitPrizeField = ""
    @State private var bigHitExitElectricField = ""
    @State private var showBigHitEntrySheet = false
    @State private var bigHitEntryNormalRotations = ""
    @State private var bigHitEntryCashPt = ""
    /// 大当たり突入フォーム：持ち玉は「投資」か「残り」のどちらで入力するか（設定のデフォルトで初期化）
    @State private var bigHitEntryHoldingsKind: BigHitHoldingsEntryKind = .investedAtWin
    @State private var bigHitEntryHoldingsValue = ""
    @State private var showBigHitAbandonConfirm = false
    @State private var bigHitExitPadFocusTriggers: [Int] = [0, 0, 0]
    @State private var bigHitEntryPadFocusTriggers: [Int] = [0, 0, 0]
    /// スワイプで開く情報ドロワーのオフセット（0=閉, insightPanelWidth=全開）。1:1で指に追従
    @State private var drawerOffset: CGFloat = 0
    /// 隙間ゾーンでスワイプ開始時にシアングロー表示
    @State private var swipeZoneGlow = false
    /// ドロワー「ロック解除」ハプティックを1回だけ発火する用
    @State private var didFireUnlockHaptic = false
    /// 省エネモードから大当たりを開いた場合、入力完了・RUSH終了後に省エネに戻す
    @State private var returnToPowerSavingModeAfterExit = false
    @State private var showInitialRotationCorrectSheet = false
    @State private var showCashCorrectSheet = false
    @State private var showHoldingsCorrectSheet = false
    @State private var showWinCountCorrectSheet = false
    @State private var tempInitialRotationCorrect: String = ""
    @State private var tempCashCorrect: String = ""
    @State private var tempHoldingsCorrectValue: String = ""
    @State private var tempRushWinCount: String = ""
    @State private var tempNormalWinCount: String = ""
    @State private var showWinBonusEditSheet = false
    @State private var tempWinBonusEditId: UUID?
    @State private var tempWinBonusEditCount: String = ""
    @State private var tempWinBonusEditPadTrigger = 0
    /// タップ成功時の波紋アニメーション（期待値に応じた色）
    @State private var rippleScale: CGFloat = 0
    @State private var rippleOpacity: Double = 0
    @State private var rippleColor: Color = .white
    @State private var rippleActive = false

    private let insightPanelWidth: CGFloat = 280

    @State private var tempLampValue: String = ""
    @State private var tempAdjustValue: String = ""
    /// 機種のモード表示用（masterID があるときロード）
    @State private var machineMaster: MachineFullMaster? = nil

    @State private var showErrorAlert = false
    @State private var errorMessage = ""

    /// 大当たり履歴の表示上限（パフォーマンス対策）
    private let winRecordsDisplayLimit = 30
    /// ゲージ再描画用（設定シート戻り時にインクリメント。SwiftDataモデル編集の反映）
    @State private var gaugeRefreshId = 0
    @AppStorage("playViewRightHandMode") private var rightHandMode = false
    @AppStorage("playViewStartWithPowerSaving") private var playViewStartWithPowerSaving = false
    @AppStorage("playDisableIdleTimerDuringPlay") private var playDisableIdleTimerDuringPlay = true
    @AppStorage("machineDetailBaseURL") private var machineDetailBaseURL: String = ""
    @AppStorage("playViewBackgroundStyle") private var playViewBackgroundStyle = "sameAsHome"
    @AppStorage("playViewBackgroundImagePath") private var playViewBackgroundImagePath = ""
    @AppStorage("homeBackgroundStyle") private var homeBackgroundStyle = HomeBackgroundStore.defaultStyle
    @AppStorage("homeBackgroundImagePath") private var homeBackgroundImagePath = ""
    @AppStorage("bigHitHoldingsEntryDefault") private var bigHitHoldingsEntryDefaultRaw = BigHitHoldingsEntryKind.appStorageDefaultRawValue
    @State private var loadedPlayBackgroundImage: UIImage?
    @State private var showHistoryFromPlay = false
    @State private var showEventHistorySheet = false
    @State private var showAnalyticsFromPlay = false
    /// 画面上端〜ダイナミックアイランド下端の高さ（表示後にキーウィンドウから取得）
    @State private var headerTopInset: CGFloat = 59

    @ObservedObject private var adVisibility = AdVisibilityManager.shared
    /// 実戦下部バナーをユーザーがスワイプで隠したか（終了確認中は `playTerminationFlowActive` で再表示）
    @State private var playSessionAdDismissed = false

    private func applyPlayIdleTimerPreference() {
        UIApplication.shared.isIdleTimerDisabled = playDisableIdleTimerDuringPlay
    }

    private func haptic(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .light) {
        HapticUtil.impact(style)
    }

    /// ゲーム数カウント用：最弱のバイブ
    private func hapticSoft() {
        HapticUtil.impact(.soft)
    }

    /// 遊技終了シート：回収出玉・終了時通常回転の両方が有効な整数で埋まっているか
    private var finalSessionEndFormValid: Bool {
        let hTrim = finalHoldingsInput.trimmingCharacters(in: .whitespaces)
        let rTrim = finalNormalRotationsInput.trimmingCharacters(in: .whitespaces)
        guard !hTrim.isEmpty, let h = Int(hTrim), h >= 0 else { return false }
        guard !rTrim.isEmpty, let r = Int(rTrim), r >= 0 else { return false }
        return true
    }

    private func confirmFinalHoldingsFlow() {
        guard finalSessionEndFormValid else { return }
        let hTrim = finalHoldingsInput.trimmingCharacters(in: .whitespaces)
        let rTrim = finalNormalRotationsInput.trimmingCharacters(in: .whitespaces)
        guard let finalBalls = Int(hTrim), finalBalls >= 0,
              let finalNorm = Int(rTrim), finalNorm >= 0
        else {
            errorMessage = "流した球・通常回転数は 0 以上の整数で入力してください。"
            showErrorAlert = true
            return
        }
        log.applySessionEndNormalRotations(finalNorm)
        log.syncHoldings(actualHoldings: finalBalls)
        showFinalHoldingsInput = false
        if log.totalHoldings > 0 {
            showSettlementSheet = true
        } else {
            saveCurrentSession(settlementMode: nil)
            if saveResult == "ok" {
                dismissPlayAfterSaveFlow()
            }
        }
    }

    /// 遊技終了フロー中は下部バナーを閉じられず常に表示（インタースティシャル前の確認と両立）
    private var playTerminationFlowActive: Bool {
        showEndConfirm || showEmptySaveConfirm || showFinalHoldingsInput || showSettlementSheet || saveResult != nil
    }

    /// ヘッダー（機種・店舗）の直下オーバーレイ。大当たり回数・ゲージ等より手前。
    @ViewBuilder
    private func playTopAdOverlay(geo: GeometryProxy) -> some View {
        if adVisibility.shouldShowBanner {
            SwipeDismissiblePlayAdBanner(
                adUnitID: AdMobConfig.bannerUnitID,
                allowDismiss: !playTerminationFlowActive,
                userDismissed: $playSessionAdDismissed
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.top, playTopAdTopInset(geo: geo))
        }
    }

    /// ヘッダー帯＋その直下スペーサまでの高さ（`body` 内の `headerTopMargin` / `h2` / 10pt と整合）
    private func playTopAdTopInset(geo: GeometryProxy) -> CGFloat {
        let H = geo.size.height
        let hHeaderOne = H * 0.05
        let hHeaderBigHitExtra: CGFloat = log.isBigHitMode ? max(34, H * 0.042) : 0
        let h2 = hHeaderOne + hHeaderBigHitExtra
        let headerTopMargin = max(headerTopInset, 20)
        let spacerBelowHeader: CGFloat = 10
        return headerTopMargin + h2 + spacerBelowHeader
    }

    private func dismissPlayAfterSaveFlow() {
        saveResult = nil
        SessionEndInterstitialPresenter.presentAfterSaveIfNeeded {
            dismiss()
        }
    }

    /// トップと同様のグラスモーフィズム（ダークネイビー・水色）／ライト時は明るいベース
    private var focusBg: Color { theme.playScreenBase }
    private var focusAccent: Color { AppGlassStyle.accent }
    /// 表示のみのパネル（タップ不可）— 背景を濃くしてカスタム壁紙上でも文字を読みやすくする
    private var playPanelBackground: Color { theme.playPanelBackground }
    private let playPanelTintOverlayOpacity: Double = 0.06
    private let playPanelStrokeLineWidth: CGFloat = 1
    /// 画面上端〜ダイナミックアイランド下端の高さ（キーウィンドウの safeAreaInsets.top）。fullScreenCover 等で geo の値がずれる場合に備える
    private static var windowSafeAreaTop: CGFloat {
        guard let windowScene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }),
              let window = windowScene.windows.first(where: { $0.isKeyWindow })
        else { return 59 } // フォールバック: ダイナミックアイランド機の典型値
        return window.safeAreaInsets.top
    }

    /// 実戦画面の背景（ホームと同じ / 別画像）。body側でGeometryReaderに.ignoresSafeAreaを付けているためgeoはフル画面サイズ
    @ViewBuilder
    private func playBackgroundLayer(geo: GeometryProxy) -> some View {
        let fullHeight = geo.size.height
        Group {
            if playViewBackgroundStyle == "sameAsHome" {
                if homeBackgroundStyle == "custom", let img = loadedPlayBackgroundImage {
                    Image(uiImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: geo.size.width, height: fullHeight)
                        .clipped()
                } else {
                    focusBg
                }
            } else if playViewBackgroundStyle == "custom", let img = loadedPlayBackgroundImage {
                Image(uiImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: geo.size.width, height: fullHeight)
                    .clipped()
            } else {
                focusBg
            }
        }
        .frame(width: geo.size.width, height: fullHeight)
        .onAppear { loadPlayBackgroundImage() }
        .onChange(of: playViewBackgroundStyle) { _, _ in loadPlayBackgroundImage() }
        .onChange(of: playViewBackgroundImagePath) { _, _ in loadPlayBackgroundImage() }
        .onChange(of: homeBackgroundStyle) { _, _ in loadPlayBackgroundImage() }
        .onChange(of: homeBackgroundImagePath) { _, _ in loadPlayBackgroundImage() }
    }

    private func loadPlayBackgroundImage() {
        if playViewBackgroundStyle == "sameAsHome", homeBackgroundStyle == "custom", !homeBackgroundImagePath.isEmpty {
            let path = homeBackgroundImagePath
            Task.detached(priority: .userInitiated) { @Sendable () async in
                let img = HomeBackgroundStore.loadCustomImage(fileName: path)
                await MainActor.run { loadedPlayBackgroundImage = img }
            }
        } else if playViewBackgroundStyle == "custom", !playViewBackgroundImagePath.isEmpty {
            let path = playViewBackgroundImagePath
            Task.detached(priority: .userInitiated) { @Sendable () async in
                let img = PlayBackgroundStore.loadCustomImage(fileName: path)
                await MainActor.run { loadedPlayBackgroundImage = img }
            }
        } else {
            loadedPlayBackgroundImage = nil
        }
    }

    /// ゲージ・波紋で使うボーダー。針は店補正後のボーダーと実戦回転率の比較にする。表示用に未補正時は機種マスタのボーダーを使用
    private var borderForGauge: Double {
        let dynamic = log.dynamicBorder
        if dynamic > 0 { return dynamic }
        return parseFormulaBorder(log.selectedMachine.border)
    }
    private func parseFormulaBorder(_ s: String) -> Double {
        let t = s.trimmingCharacters(in: .whitespaces)
        if let v = Double(t), v > 0 { return v }
        let num = t.filter { $0.isNumber || $0 == "." }
        return (Double(num) ?? 0)
    }

    /// 波紋の色：機種マスタのボーダー（等価）基準の5段階（AppGlassStyle.edgeGlowColor と同一ロジック）
    private var expectationBorderColor: Color {
        guard borderForGauge > 0, log.effectiveUnitsForBorder > 0 else { return .white }
        return AppGlassStyle.edgeGlowColor(border: borderForGauge, realRate: log.realRate)
    }

    /// 入力成功時に中央から外周へ波紋を広げる（色は期待値に応じる）。連打時は再生中は無視して1本に抑える
    private func triggerRipple() {
        if rippleActive { return }
        rippleColor = expectationBorderColor
        rippleScale = 0.15
        rippleOpacity = 0.5
        rippleActive = true
        withAnimation(.easeOut(duration: 0.65)) {
            rippleScale = 1.35
            rippleOpacity = 0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
            rippleActive = false
            rippleScale = 0.15
        }
    }

    var body: some View {
        GeometryReader { geo in
            let H = geo.size.height
            // 縦方向を全面調整：合計が画面に収まるよう比率を抑え、下部バーは高さ上限あり
            /// ヘッダー1行（機種・店舗）。大当たり時は連チャン行を追加するため下で加算
            let hHeaderOne = H * 0.05
            let hHeaderBigHitExtra: CGFloat = log.isBigHitMode ? max(34, H * 0.042) : 0
            let h2 = hHeaderOne + hHeaderBigHitExtra
            let hWinCount = H * 0.055  // 最上部「大当たり回数」パネル
            /// 大当たり中：ヘッダー化で空いた分をスランプ・履歴へ
            let hSlumpBig = H * 0.168
            let hHistBig = H * 0.118
            let h20info = max(H * 0.182, 148)  // 回転率ゲージ＋右パネル（はみ出し防止の最小高さ）
            let h10 = H * 0.088  // 大当たり履歴（通常時）
            let h22center = H * 0.22  // 中央ボタン
            let barHeight = min(H * 0.18, 96)  // 下部ボタン（通常と同比率で縮小）
            let maxRippleSize = max(geo.size.width, geo.size.height) * 1.4
            ZStack(alignment: .bottomLeading) {
                playBackgroundLayer(geo: geo)
                    .ignoresSafeArea(edges: .all)

                if log.isBigHitMode {
                    bigHitAtmosphereOverlay(geo: geo, chainCount: log.bigHitChainCount)
                        .ignoresSafeArea(edges: .all)
                        .allowsHitTesting(false)
                        .animation(.easeInOut(duration: 0.32), value: log.bigHitChainCount)
                }

                VStack(spacing: 0) {
                    // ヘッダー領域: 上マージン＝画面上端〜ダイナミックアイランド下端（同色）。ヘッダー本体はその直下から
                    let headerTopMargin = max(headerTopInset, 20)
                    ZStack(alignment: .bottom) {
                        theme.playHeaderBackground
                        headerRow(firstRowHeight: hHeaderOne)
                    }
                    .frame(minHeight: headerTopMargin + h2)
                    .frame(maxWidth: .infinity)

                    // ヘッダーと情報群の間のマージン
                    Spacer().frame(height: 10)

                    if log.isBigHitMode {
                        // 通常実戦と同じ縦割り＋壁紙。見た目は従来の RUSH 系（赤系・グラス・大きな操作域）
                        SessionSlumpLineChartView(log: log, height: hSlumpBig, strokeTint: bigHitChainLineTint(log.bigHitChainCount))
                            .padding(.horizontal, infoPanelHorizontalMargin)
                            .animation(.easeInOut(duration: 0.28), value: log.bigHitChainCount)
                        Spacer().frame(height: sectionGap)
                        WinHistoryBarChartView(
                            records: Array(log.winRecordsForChartDisplay().suffix(winRecordsDisplayLimit)),
                            maxHeight: hHistBig,
                            accentStroke: bigHitChainUsesRainbow(log.bigHitChainCount)
                                ? Color.white.opacity(0.92)
                                : bigHitChainPrimaryColor(log.bigHitChainCount),
                            chainBarColor: bigHitChainUsesRainbow(log.bigHitChainCount)
                                ? nil
                                : bigHitChainPrimaryColor(log.bigHitChainCount),
                            chainBarGradient: bigHitChainUsesRainbow(log.bigHitChainCount) ? bigHitRainbowForeground : nil,
                            onSelectRecord: { rec in
                                if rec.id == GameLog.provisionalBigHitChartId { return }
                                tempWinBonusEditId = rec.id
                                tempWinBonusEditCount = "\(max(1, rec.bonusSessionHitCount ?? 1))"
                                showWinBonusEditSheet = true
                            }
                        )
                            .padding(6)
                            .frame(maxWidth: .infinity)
                            .background(playPanelBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                            .overlay(bigHitThemedStroke(cornerRadius: 14, chainCount: log.bigHitChainCount))
                            .animation(.easeInOut(duration: 0.28), value: log.bigHitChainCount)
                            .padding(.horizontal, contentHorizontalPadding)
                        Spacer().frame(height: sectionGap)
                        swipeGapRow(geo: geo)
                            .offset(x: rightHandMode ? drawerOffset : -drawerOffset)
                            .animation(.easeOut(duration: 0.22), value: drawerOffset)
                        Spacer().frame(height: sectionGap)
                        bigHitCenterRow(geo: geo, height: h22center)
                        Spacer().frame(height: sectionGap)
                        bigHitFloatingBottomBar(geo: geo, barHeight: barHeight)
                            .frame(minHeight: barHeight)
                            .frame(maxHeight: .infinity)
                        Spacer(minLength: 0)
                            .frame(height: geo.safeAreaInsets.bottom > 0 ? geo.safeAreaInsets.bottom : 8)
                    } else {
                    // 最上部：大当たり回数パネル（RUSH / 通常）
                    winCountPanel(height: hWinCount)
                    Spacer().frame(height: 4)

                    // 状態表示（ゲージ＝総回転上端〜持ち玉下端、下余白詰め）
                    infoRow(height: h20info)
                    Spacer().frame(height: sectionGap)

                    // 大当たり履歴
                    WinHistoryBarChartView(
                        records: Array(log.winRecords.suffix(winRecordsDisplayLimit)),
                        maxHeight: h10,
                        accentStroke: focusAccent,
                        onSelectRecord: { rec in
                            tempWinBonusEditId = rec.id
                            tempWinBonusEditCount = "\(max(1, rec.bonusSessionHitCount ?? 1))"
                            showWinBonusEditSheet = true
                        }
                    )
                        .padding(6)
                        .frame(maxWidth: .infinity)
                        .background(playPanelBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(glassStroke(tint: focusAccent), lineWidth: playPanelStrokeLineWidth))
                        .padding(.horizontal, contentHorizontalPadding)
                    Spacer().frame(height: sectionGap)

                    // スワイプバー（高さ60pt）
                    swipeGapRow(geo: geo)
                        .offset(x: rightHandMode ? drawerOffset : -drawerOffset)
                        .animation(.easeOut(duration: 0.22), value: drawerOffset)
                    Spacer().frame(height: sectionGap)

                    // 中央 現金・持ち玉・カウント（ボタン間隔は sectionGap と統一）
                    centerActionRow(geo: geo, height: h22center)
                    Spacer().frame(height: sectionGap)

                    // ボタン群（上寄せ・余白はRUSH/通常の高さで吸収）
                    floatingBottomBar(geo: geo, barHeight: barHeight)
                        .frame(minHeight: barHeight)
                        .frame(maxHeight: .infinity)
                    Spacer(minLength: 0)
                        .frame(height: geo.safeAreaInsets.bottom > 0 ? geo.safeAreaInsets.bottom : 8)
                    }
                }
                .frame(minHeight: H)
                .ignoresSafeArea(edges: .top)

                // バナー：最上部・メインより手前／ドロワー・ポップアップより奥（順序のみで z 順）
                playTopAdOverlay(geo: geo)

                // 長押しポップアップ類（最前面）
                popoverOverlays(geo: geo)

                // インサイトパネル（ドラッグ1:1追従ドロワー）。左手=右から、右手=左から
                if drawerOffset > 0 {
                    ZStack(alignment: rightHandMode ? .leading : .trailing) {
                        theme.playDrawerScrim
                            .ignoresSafeArea()
                            .onTapGesture {
                                haptic(.light)
                                withAnimation(.easeOut(duration: 0.22)) {
                                    drawerOffset = 0
                                    didFireUnlockHaptic = false
                                }
                            }
                        InsightPanelView(log: log, onClose: {
                            haptic(.light)
                            withAnimation(.easeOut(duration: 0.22)) {
                                drawerOffset = 0
                                didFireUnlockHaptic = false
                            }
                        }, onCorrectInitialRotation: {
                            tempInitialRotationCorrect = "\(log.initialDisplayRotation)"
                            showInitialRotationCorrectSheet = true
                        }, onCorrectCash: {
                            tempCashCorrect = "\(log.totalInput)"
                            showCashCorrectSheet = true
                        }, onCorrectHoldings: {
                            tempHoldingsCorrectValue = "\(log.holdingsInvestedBalls)"
                            showHoldingsCorrectSheet = true
                        }, onCorrectWinCount: {
                            tempRushWinCount = "\(log.rushWinCount)"
                            tempNormalWinCount = "\(log.normalWinCount)"
                            showWinCountCorrectSheet = true
                        }, onOpenHistory: {
                            showHistoryFromPlay = true
                        }, onOpenEventHistory: {
                            showEventHistorySheet = true
                        }, onOpenAnalytics: {
                            showAnalyticsFromPlay = true
                        }, onOpenPowerSaving: {
                            showPowerSavingMode = true
                            haptic(.light)
                        }, onOpenSettings: {
                            if let onOpenSettingsTab = onOpenSettingsTab {
                                onOpenSettingsTab()
                            } else {
                                showSettingsSheet = true
                            }
                            haptic(.light)
                        }, onToggleRightHandMode: {
                            rightHandMode = !rightHandMode
                            haptic(.light)
                        }, isRightHandMode: rightHandMode)
                        .frame(width: insightPanelWidth)
                        .offset(x: rightHandMode ? (-insightPanelWidth + drawerOffset) : (insightPanelWidth - drawerOffset))
                    }
                    .transition(.opacity)
                }

                // 期待値に応じた波紋（中央→外周・タップ成功時）。放射グラデで柔らかく、連打時は1本のみ
                if rippleActive {
                    let size = maxRippleSize
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    rippleColor.opacity(rippleOpacity),
                                    rippleColor.opacity(rippleOpacity * 0.4),
                                    rippleColor.opacity(rippleOpacity * 0.15),
                                    Color.clear
                                ],
                                center: .center,
                                startRadius: 0,
                                endRadius: size / 2
                            )
                        )
                        .frame(width: size, height: size)
                        .scaleEffect(rippleScale)
                        .position(x: geo.size.width / 2, y: geo.size.height / 2)
                        .blur(radius: 0.8)
                        .allowsHitTesting(false)
                }
            }
        }
        .ignoresSafeArea(edges: .all)
        .keyboardDismissToolbar()
        // --- シート類 ---
        .sheet(isPresented: $showSettingsSheet) {
            MachineShopSelectionView(log: log, presentedFromPlaySession: true)
        }
        .onChange(of: showSettingsSheet) { _, show in
            if !show { gaugeRefreshId += 1 }
        }
        .task(id: "\(log.selectedMachine.masterID ?? "")|\(log.selectedMachine.name)|\(machineDetailBaseURL)") {
            let base = machineDetailBaseURL.trimmingCharacters(in: .whitespaces)
            machineMaster = await MachineDetailLoader.fetchMachineDetail(
                machineId: log.selectedMachine.masterID,
                machineName: log.selectedMachine.name,
                baseURL: base.isEmpty ? nil : base
            )
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .inactive || newPhase == .background {
                ResumableStateStore.autosave(from: log, force: true)
                UIApplication.shared.isIdleTimerDisabled = false
            }
            if newPhase == .active {
                applyPlayIdleTimerPreference()
            }
        }
        .onAppear {
            applyPlayIdleTimerPreference()
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
        }
        .onChange(of: playDisableIdleTimerDuringPlay) { _, _ in
            applyPlayIdleTimerPreference()
        }
        /// フリーズ・強制終了対策: 低頻度タイマー＋最短間隔スロットル（バッテリー負荷を抑える）
        .onReceive(Timer.publish(every: 75, on: .main, in: .common).autoconnect()) { _ in
            guard scenePhase == .active else { return }
            ResumableStateStore.autosave(from: log, force: false)
        }
        .sheet(isPresented: $showSyncSheet) { SyncInputView(title: "ゲーム数同期", label: "データランプの現在表示数（自分の回転数と合わせる・回転率に反映されます）", val: $tempLampValue) { if let v = Int(tempLampValue) { log.syncTotalRotations(newTotal: v) }; showSyncSheet = false } }
        .sheet(isPresented: $showTrayAdjustSheet) { SyncInputView(title: "上皿精算", label: "ランプ回転数", val: $tempAdjustValue) { if let v = Int(tempAdjustValue) { log.adjustForZeroTray(syncRotation: v) }; showTrayAdjustSheet = false } }
        .sheet(isPresented: $showHoldingsSyncSheet) {
            SyncInputView(title: "持ち玉同期", label: "実際の持ち玉数（確変終了後など）", val: $tempHoldingsSyncValue) {
                if let v = Int(tempHoldingsSyncValue) { log.syncHoldings(actualHoldings: v) }
                showHoldingsSyncSheet = false
            }
        }
        .sheet(isPresented: $showInitialRotationCorrectSheet) {
            SyncInputView(title: "開始ゲーム数修正", label: "開始時の台表示数（表示合わせのみ・回転率には影響しません）", val: $tempInitialRotationCorrect) {
                if let v = Int(tempInitialRotationCorrect) {
                    log.correctInitialDisplayRotation(to: v)
                }
                showInitialRotationCorrectSheet = false
            }
        }
        .sheet(isPresented: $showCashCorrectSheet) {
            SyncInputView(title: "投資を修正", label: "総投資（pt・500pt単位で記録されます）", val: $tempCashCorrect) {
                if let v = Int(tempCashCorrect) {
                    log.setCashInput(pt: v)
                }
                showCashCorrectSheet = false
            }
        }
        .sheet(isPresented: $showHoldingsCorrectSheet) {
            SyncInputView(title: "持ち玉投資を修正", label: "今回遊技に使った持ち玉数（玉）", val: $tempHoldingsCorrectValue) {
                if let v = Int(tempHoldingsCorrectValue) {
                    log.setHoldingsInvested(balls: v)
                }
                showHoldingsCorrectSheet = false
            }
        }
        .sheet(isPresented: $showWinCountCorrectSheet) {
            WinCountCorrectView(rushCount: $tempRushWinCount, normalCount: $tempNormalWinCount) {
                let r = Int(tempRushWinCount.trimmingCharacters(in: .whitespaces)) ?? 0
                let n = Int(tempNormalWinCount.trimmingCharacters(in: .whitespaces)) ?? 0
                log.setWinCounts(rush: r, normal: n)
                showWinCountCorrectSheet = false
            }
        }
        .sheet(isPresented: $showWinBonusEditSheet) {
            NavigationStack {
                Form {
                    Section {
                        IntegerPadTextField(
                            text: $tempWinBonusEditCount,
                            placeholder: "連チャン含む回数",
                            maxDigits: 5,
                            font: .preferredFont(forTextStyle: .body),
                            textColor: UIColor.label,
                            accentColor: UIColor(focusAccent),
                            focusTrigger: tempWinBonusEditPadTrigger
                        )
                    } footer: {
                        Text("棒を長押しするか、VoiceOver の「当たり回数を修正」で、その区間の連チャン含む回数を変更できます。")
                    }
                }
                .navigationTitle("当たり回数")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("キャンセル") {
                            showWinBonusEditSheet = false
                            tempWinBonusEditId = nil
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("保存") {
                            if let id = tempWinBonusEditId, let v = Int(tempWinBonusEditCount.trimmingCharacters(in: .whitespaces)) {
                                log.updateBonusSessionHitCount(winId: id, count: v)
                            }
                            showWinBonusEditSheet = false
                            tempWinBonusEditId = nil
                        }
                    }
                }
                .onAppear { tempWinBonusEditPadTrigger += 1 }
            }
        }
        .fullScreenCover(isPresented: $showPowerSavingMode) {
            PowerSavingModeView(
                log: log,
                rightHandMode: rightHandMode,
                machineMaster: machineMaster,
                onExit: { showPowerSavingMode = false },
                onBigHit: {
                    returnToPowerSavingModeAfterExit = true
                    showPowerSavingMode = false
                    bigHitEntryNormalRotations = "\(log.normalRotations)"
                    bigHitEntryCashPt = "\(log.totalInput)"
                    showBigHitEntrySheet = true
                    haptic(.medium)
                }
            )
        }
        .fullScreenCover(isPresented: $showHistoryFromPlay) {
            NavigationStack {
                HistoryListView()
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button {
                                showHistoryFromPlay = false
                            } label: {
                                Text("＜　実戦へ戻る")
                            }
                            .foregroundColor(focusAccent)
                        }
                    }
            }
            .playOverlayBottomAdInset()
        }
        .fullScreenCover(isPresented: $showEventHistorySheet) {
            PlayEventHistoryView(log: log) { showEventHistorySheet = false }
        }
        .fullScreenCover(isPresented: $showAnalyticsFromPlay) {
            NavigationStack {
                StandaloneAnalyticsDashboardView()
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button {
                                showAnalyticsFromPlay = false
                            } label: {
                                Text("＜　実戦へ戻る")
                            }
                            .foregroundColor(focusAccent)
                        }
                    }
            }
            .playOverlayBottomAdInset()
        }
        .sheet(isPresented: $showBigHitExitSheet) {
            bigHitExitSheetView()
        }
        .sheet(isPresented: $showBigHitEntrySheet) {
            bigHitEntrySheetView()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)) { _ in
            if UIDevice.current.orientation == .faceDown && drawerOffset > 0 {
                withAnimation(.easeOut(duration: 0.2)) {
                    drawerOffset = 0
                    didFireUnlockHaptic = false
                }
            }
        }
        .onAppear {
            playSessionAdDismissed = false
            UIDevice.current.beginGeneratingDeviceOrientationNotifications()
            DispatchQueue.main.async { headerTopInset = Self.windowSafeAreaTop }
            if playViewStartWithPowerSaving, !didAutoOpenPowerSavingThisSession, !log.isBigHitMode {
                didAutoOpenPowerSavingThisSession = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { showPowerSavingMode = true }
            }
        }
        .onDisappear {
            UIDevice.current.endGeneratingDeviceOrientationNotifications()
        }
    }

    /// スワイプバー: 高さ60pt・角丸4pt・左右16ptマージン。サイバーメタリック＋ヘアライン＋ネオンライン
    private func swipeGapRow(geo: GeometryProxy) -> some View {
        let openThreshold = geo.size.width * 0.25
        let unlockHapticThreshold: CGFloat = 10
        let swipeBarHeight: CGFloat = 60
        let swipeBarCornerRadius: CGFloat = 4
        let swipeBarHorizontalMargin: CGFloat = 16
        let isLight = theme == .light
        let stainlessBase = isLight
            ? Color(red: 0.9, green: 0.91, blue: 0.93)
            : Color(red: 0.22, green: 0.23, blue: 0.25)
        let cyanNeon = Color(hex: "00FFFF")
        let magentaNeon = Color(hex: "FF00FF")
        let bgGradient = LinearGradient(
            colors: [stainlessBase, stainlessBase.opacity(0.98), stainlessBase],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        // 横方向ヘアラインのみ：本物のステンレスような微細な直線の反射
        let hairlineGradient = LinearGradient(
            stops: [
                .init(color: Color.white.opacity(0), location: 0),
                .init(color: Color.white.opacity(0.04), location: 0.2),
                .init(color: Color.white.opacity(0.11), location: 0.35),
                .init(color: Color.white.opacity(0.06), location: 0.5),
                .init(color: Color.white.opacity(0.12), location: 0.65),
                .init(color: Color.white.opacity(0.03), location: 0.8),
                .init(color: Color.white.opacity(0), location: 1)
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
        return ZStack {
            RoundedRectangle(cornerRadius: swipeBarCornerRadius)
                .fill(bgGradient)
            RoundedRectangle(cornerRadius: swipeBarCornerRadius)
                .fill(hairlineGradient)
            if swipeZoneGlow {
                RoundedRectangle(cornerRadius: swipeBarCornerRadius)
                    .fill(focusAccent.opacity(0.15))
                    .blur(radius: 8)
                    .animation(.easeOut(duration: 0.15), value: swipeZoneGlow)
            }
            HStack(spacing: 8) {
                Image(systemName: "chevron.left.2")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(isLight ? Color.black.opacity(0.38) : Color.white.opacity(0.5))
                Spacer()
                Text("スワイプで情報")
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundColor(isLight ? Color.black.opacity(0.52) : Color.white.opacity(0.7))
                Spacer()
                Color.clear.frame(width: 24, height: 1)
            }
            .padding(.horizontal, 12)
        }
        .overlay(alignment: .top) {
            Rectangle().fill(cyanNeon.opacity(isLight ? 0.35 : 1)).frame(height: 0.5)
                .shadow(color: cyanNeon.opacity(isLight ? 0.2 : 0.7), radius: 4)
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(magentaNeon.opacity(isLight ? 0.3 : 1)).frame(height: 0.5)
                .shadow(color: magentaNeon.opacity(isLight ? 0.18 : 0.7), radius: 4)
        }
        .clipShape(RoundedRectangle(cornerRadius: swipeBarCornerRadius))
        .frame(height: swipeBarHeight)
        .padding(.horizontal, swipeBarHorizontalMargin)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 8)
                .onChanged { value in
                    if !swipeZoneGlow { swipeZoneGlow = true }
                    let delta = rightHandMode ? value.translation.width : -value.translation.width
                    let newOffset = min(insightPanelWidth, max(0, delta))
                    drawerOffset = newOffset
                    if newOffset >= unlockHapticThreshold && !didFireUnlockHaptic {
                        haptic(.light)
                        didFireUnlockHaptic = true
                    }
                }
                .onEnded { value in
                    swipeZoneGlow = false
                    let delta = rightHandMode ? value.translation.width : -value.translation.width
                    let current = min(insightPanelWidth, max(0, delta))
                    if current > openThreshold {
                        withAnimation(.easeOut(duration: 0.22)) { drawerOffset = insightPanelWidth }
                    } else {
                        withAnimation(.easeOut(duration: 0.2)) {
                            drawerOffset = 0
                            didFireUnlockHaptic = false
                        }
                    }
                }
        )
    }

    /// 画面上端は黒背景。1行目＝Undo・機種・店舗。大当たり中は2行目に連チャン（ゲージ用の余白を確保するためパネルは使わない）
    @ViewBuilder
    private func headerRow(firstRowHeight: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 12) {
                if rightHandMode {
                    headerRowTrailingButtons(height: firstRowHeight)
                    headerMachineShopButton()
                    headerRowUndoButton()
                } else {
                    headerRowUndoButton()
                    headerMachineShopButton()
                    headerRowTrailingButtons(height: firstRowHeight)
                }
            }
            .frame(minHeight: firstRowHeight)

            if log.isBigHitMode {
                let n = log.bigHitChainCount
                let c = bigHitChainPrimaryColor(n)
                let rainbow = bigHitChainUsesRainbow(n)
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("大当たり中")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .modifier(BigHitThemedForeground(isRainbow: rainbow, solid: c))
                    Text("連チャン")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundColor(theme.playLabelSecondary)
                    Text("\(n)")
                        .font(.system(size: 22, weight: .heavy, design: .monospaced))
                        .modifier(BigHitThemedForeground(isRainbow: rainbow, solid: c))
                    Text("回")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .modifier(BigHitThemedForeground(isRainbow: rainbow, solid: c))
                    Spacer(minLength: 0)
                }
                .padding(.top, 2)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private func headerMachineShopButton() -> some View {
        Button(action: { showSettingsSheet = true; haptic(.light) }) {
            HStack(alignment: .center, spacing: 8) {
                Text(log.selectedMachine.name)
                    .font(AppTypography.sectionSubheading)
                    .foregroundColor(theme.playLabelPrimary)
                    .lineLimit(1)
                Text(log.selectedShop.name)
                    .font(AppTypography.bodyRounded)
                    .foregroundColor(theme.playLabelPrimary.opacity(0.9))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: rightHandMode ? .trailing : .leading)
    }

    private func headerRowUndoButton() -> some View {
        Button(action: {
            if log.undoCount > 0 { log.undoLastAction(); haptic(.medium) }
        }) {
            Image(systemName: "arrow.uturn.backward.circle.fill")
                .font(.system(size: 30))
                .foregroundColor(log.undoCount > 0 ? theme.playLabelPrimary : theme.playMutedIcon)
        }
        .disabled(log.undoCount == 0)
        .padding(2)
    }

    /// 設定はドロワー「モード切替」から開く
    private func headerRowTrailingButtons(height: CGFloat) -> some View {
        EmptyView()
    }

    /// 上半円メーターの最大半径（右側コンテンツ高さを超えない）
    private let maxMeterRadius: CGFloat = 85

    /// 指定パネルデザイン（75%不透明・角丸20–24・シアン極細縁）で包む
    private let infoPanelCornerRadius: CGFloat = 20
    private let infoPanelHorizontalMargin: CGFloat = 16

    /// 最上部：大当たり回数パネル（1つにまとめて RUSH○回・通常○回）
    @ViewBuilder
    private func winCountPanel(height: CGFloat) -> some View {
        HStack(spacing: 16) {
            Text("RUSH")
                .font(AppTypography.sectionSubheading)
                .foregroundColor(AppGlassStyle.rushColor.opacity(0.95))
            Text("\(log.rushWinCount)回")
                .font(.system(size: 17, weight: .bold, design: .monospaced))
                .foregroundColor(focusAccent)
            Text("通常")
                .font(AppTypography.sectionSubheading)
                .foregroundColor(AppGlassStyle.normalColor.opacity(0.95))
            Text("\(log.normalWinCount)回")
                .font(.system(size: 17, weight: .bold, design: .monospaced))
                .foregroundColor(focusAccent)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .padding(.horizontal, 16)
        .background(playPanelBackground)
        .clipShape(RoundedRectangle(cornerRadius: infoPanelCornerRadius))
        .overlay(RoundedRectangle(cornerRadius: infoPanelCornerRadius).stroke(glassStroke(tint: focusAccent), lineWidth: playPanelStrokeLineWidth))
        .padding(.horizontal, infoPanelHorizontalMargin)
        .frame(height: height)
        .frame(maxWidth: .infinity)
    }

    // 左＝ゲージ、右＝総回転数・期待値・総現金投資・総持ち玉投資・持ち玉のパネル（RUSH/通常は大当たり回数パネルへ移動済み）
    /// - Parameter accent: 枠・数値の強調色。大当たりモード時は `rushColor` で従来 RUSH 画面に寄せる
    @ViewBuilder
    private func infoRow(height: CGFloat, accent: Color? = nil) -> some View {
        let a = accent ?? focusAccent
        // ゲージ本体の縦内容が枠からはみ出さないよう、高さに応じて幅（半径）を抑える
        let meterR = min(maxMeterRadius, height * 0.42)
        /// 左ゲージを約10％広げ、右の情報群が自動的に狭くなる
        let gaugeWidth = meterR * 2 * 1.1
        let statGap: CGFloat = 2
        let statRows = 5
        let statRowH = max(0, (height - statGap * CGFloat(statRows - 1)) / CGFloat(statRows))
        HStack(alignment: .top, spacing: 10) {
            BorderMeterView(
                borderForGauge: borderForGauge,
                realRate: log.realRate,
                rotationPer1000Yen: log.rotationPer1000Yen,
                totalRealCost: log.totalRealCost,
                effectiveUnitsForBorder: log.effectiveUnitsForBorder,
                normalRotations: log.normalRotations,
                formulaBorderRaw: log.formulaBorderValue,
                formulaBorderLabel: log.dynamicBorder > 0 ? String(format: "%.1f", log.dynamicBorder) : "—",
                accent: a,
                gaugeExplanation: {
                    BorderGaugeHelp.explanation
                        + "\n\n"
                        + log.borderGaugeAdjustmentSummary()
                        + "\n\n"
                        + log.borderGaugeFormulaExplanation()
                }
            )
            .id("\(log.normalRotations)-\(log.totalInput)-\(log.holdingsInvestedBalls)-\(gaugeRefreshId)")
            .frame(width: gaugeWidth, height: height)
            .clipped()
            .background(playPanelBackground)
            .clipShape(RoundedRectangle(cornerRadius: infoPanelCornerRadius))
            .overlay(RoundedRectangle(cornerRadius: infoPanelCornerRadius).stroke(glassStroke(tint: a), lineWidth: playPanelStrokeLineWidth))

            VStack(alignment: .leading, spacing: statGap) {
                infoStatPanel(strokeTint: a) {
                    HStack {
                        HStack(spacing: 4) {
                            Text("総回転数")
                                .font(AppTypography.sectionSubheading)
                                .foregroundColor(a.opacity(0.85))
                            InfoIconView(explanation: "ゲーム開始から現在までの通常回転の累積（時短・電サポを除く）。金を払って回した回転数。", tint: a.opacity(0.6))
                        }
                        Spacer()
                        Text("\(log.normalRotations)")
                            .font(.system(size: 17, weight: .bold, design: .monospaced))
                            .foregroundColor(a)
                    }
                    .padding(.horizontal, 10)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(height: statRowH)
                infoStatPanel(strokeTint: a) {
                    HStack {
                        HStack(spacing: 4) {
                            Text("期待値")
                                .font(AppTypography.sectionSubheading)
                                .foregroundColor(a.opacity(0.85))
                            InfoIconView(explanation: "実質回転率÷店補正後のボーダー。1.0で基準、1.0超で期待値プラス。", tint: a.opacity(0.6))
                        }
                        Spacer()
                        Text(log.dynamicBorder > 0 && log.effectiveUnitsForBorder > 0 ? String(format: "%.2f%%", log.expectationRatio * 100) : "—")
                            .font(.system(size: 17, weight: .bold, design: .monospaced))
                            .foregroundColor(a)
                    }
                    .padding(.horizontal, 10)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(height: statRowH)
                infoStatPanel(strokeTint: a) {
                    HStack {
                        Text("総投入")
                            .font(AppTypography.sectionSubheading)
                            .foregroundColor(a.opacity(0.85))
                        Spacer()
                        Text(log.totalInput.formattedPtWithUnit)
                            .font(.system(size: 16, weight: .bold, design: .monospaced))
                            .foregroundColor(a)
                    }
                    .padding(.horizontal, 10)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(height: statRowH)
                infoStatPanel(strokeTint: a) {
                    HStack {
                        Text("総持ち玉投資")
                            .font(AppTypography.sectionSubheading)
                            .foregroundColor(a.opacity(0.85))
                        Spacer()
                        Text("\(log.holdingsInvestedBalls)玉")
                            .font(.system(size: 16, weight: .bold, design: .monospaced))
                            .foregroundColor(a)
                    }
                    .padding(.horizontal, 10)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(height: statRowH)
                infoStatPanel(strokeTint: a) {
                    HStack {
                        Text("持ち玉")
                            .font(AppTypography.sectionSubheading)
                            .foregroundColor(a.opacity(0.85))
                        Spacer()
                        Text("\(log.totalHoldings)玉")
                            .font(.system(size: 16, weight: .bold, design: .monospaced))
                            .foregroundColor(a)
                    }
                    .padding(.horizontal, 10)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(height: statRowH)
            }
            .frame(maxWidth: .infinity)
            .frame(height: height)
        }
        .padding(.horizontal, infoPanelHorizontalMargin)
        .padding(.bottom, 0)
        .frame(maxWidth: .infinity)
        .frame(height: height)
    }

    @ViewBuilder
    private func infoStatPanel<Content: View>(strokeTint: Color, @ViewBuilder content: () -> Content) -> some View {
        content()
            .frame(maxWidth: .infinity)
            .background(playPanelBackground)
            .clipShape(RoundedRectangle(cornerRadius: infoPanelCornerRadius))
            .overlay(RoundedRectangle(cornerRadius: infoPanelCornerRadius).stroke(glassStroke(tint: strokeTint), lineWidth: playPanelStrokeLineWidth))
    }

    /// トップページ風：半透明＋角丸＋角度で変わる枠線（パネル用・読みやすさ優先）
    private func glassStroke(tint: Color) -> LinearGradient {
        switch theme {
        case .dark:
            let o: Double = 0.93
            return LinearGradient(
                colors: [
                    Color.white.opacity(o * 0.5),
                    tint.opacity(o * 0.35),
                    Color.white.opacity(o * 0.1)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .light:
            return LinearGradient(
                colors: [
                    Color.black.opacity(0.14),
                    tint.opacity(0.4),
                    Color.black.opacity(0.07)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    /// タップ可能なボタン用：グラデーション＋影でパネルより少し立体的に見せる
    @ViewBuilder
    private func playButtonChrome(cornerRadius: CGFloat, tint: Color) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.12),
                            Color.black.opacity(0.74),
                            Color.black.opacity(0.88)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(tint.opacity(playPanelTintOverlayOpacity))
        }
        .shadow(color: .black.opacity(0.55), radius: 5, x: 0, y: 3)
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius)
                .stroke(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.38),
                            tint.opacity(0.42),
                            Color.white.opacity(0.1)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: playPanelStrokeLineWidth
                )
        )
    }

    /// 現金・持ち玉・カウント・RUSH・通常・遊技終了まわりで統一
    private let buttonGap: CGFloat = 8
    private let buttonCornerRadius: CGFloat = 16
    /// 投資ボタン見出し（赤系・視認性優先）
    private let investmentTextColor = Color(red: 1.0, green: 0.35, blue: 0.32)
    private let investmentSubTextColor = Color(red: 1.0, green: 0.48, blue: 0.44)
    /// 下部「大当たり」スライドのアクセント（テーマに合わせる）
    private var bigHitBarTitleColor: Color { theme.accentColor }
    /// 中央・下部ボタン・大当たり履歴の左右余白を統一（端を揃える）
    private let contentHorizontalPadding: CGFloat = 12
    /// 情報群・大当たり履歴・スワイプバー・ボタン群の間隔（すべて統一）
    private let sectionGap: CGFloat = 8

    // 30%: 現金 | 持ち玉 | カウント（ホームグリッドと同じカード面・押下挙動）。右手モード時は左右入れ替え。
    @ViewBuilder
    private func centerActionRow(geo: GeometryProxy, height: CGFloat) -> some View {
        let titlePt: CGFloat = 20
        let subPt: CGFloat = 15
        let totalPt: CGFloat = 12
        let ballsPerTap = max(1, log.selectedShop.ballsPerCashUnit)
        let investmentColumn: some View = Group {
            if alwaysShowBothInvestmentButtons {
                VStack(spacing: buttonGap) {
                    zoneButton(
                        content: {
                            VStack(spacing: 3) {
                                Text("現金").font(.system(size: titlePt, weight: .bold, design: .monospaced)).foregroundColor(investmentTextColor)
                                Text("500pt").font(.system(size: subPt, weight: .medium, design: .monospaced)).foregroundColor(investmentSubTextColor)
                                Text("計 \(log.totalInput)pt")
                                    .font(.system(size: totalPt, weight: .semibold, design: .monospaced))
                                    .foregroundColor(investmentSubTextColor.opacity(0.92))
                                    .minimumScaleFactor(0.72)
                                    .lineLimit(1)
                            }
                        },
                        onTap: { log.addLending(type: .cash); haptic(.medium); triggerRipple() },
                        disabled: false
                    )
                    zoneButton(
                        content: {
                            VStack(spacing: 3) {
                                Text("持ち玉").font(.system(size: titlePt, weight: .bold, design: .monospaced)).foregroundColor(investmentTextColor)
                                Text("\(ballsPerTap)玉").font(.system(size: subPt, weight: .medium, design: .monospaced)).foregroundColor(investmentSubTextColor)
                                Text("計 \(log.holdingsInvestedBalls)玉")
                                    .font(.system(size: totalPt, weight: .semibold, design: .monospaced))
                                    .foregroundColor(investmentSubTextColor.opacity(0.92))
                                    .minimumScaleFactor(0.72)
                                    .lineLimit(1)
                            }
                        },
                        onTap: {
                            guard log.totalHoldings > 0 else { return }
                            log.addLending(type: .holdings); haptic(.medium); triggerRipple()
                        },
                        disabled: log.totalHoldings == 0
                    )
                }
            } else if log.totalHoldings == 0 {
                zoneButton(
                    content: {
                        VStack(spacing: 3) {
                            Text("現金").font(.system(size: titlePt, weight: .bold, design: .monospaced)).foregroundColor(investmentTextColor)
                            Text("500pt").font(.system(size: subPt, weight: .medium, design: .monospaced)).foregroundColor(investmentSubTextColor)
                            Text("計 \(log.totalInput)pt")
                                .font(.system(size: totalPt, weight: .semibold, design: .monospaced))
                                .foregroundColor(investmentSubTextColor.opacity(0.92))
                                .minimumScaleFactor(0.72)
                                .lineLimit(1)
                        }
                    },
                    onTap: { log.addLending(type: .cash); haptic(.medium); triggerRipple() },
                    disabled: false
                )
            } else {
                zoneButton(
                    content: {
                        VStack(spacing: 3) {
                            Text("持ち玉").font(.system(size: titlePt, weight: .bold, design: .monospaced)).foregroundColor(investmentTextColor)
                            Text("\(ballsPerTap)玉").font(.system(size: subPt, weight: .medium, design: .monospaced)).foregroundColor(investmentSubTextColor)
                            Text("計 \(log.holdingsInvestedBalls)玉")
                                .font(.system(size: totalPt, weight: .semibold, design: .monospaced))
                                .foregroundColor(investmentSubTextColor.opacity(0.92))
                                .minimumScaleFactor(0.72)
                                .lineLimit(1)
                        }
                    },
                    onTap: {
                        log.addLending(type: .holdings); haptic(.medium); triggerRipple()
                    },
                    disabled: false
                )
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)

        let countButton = Button {
            log.addRotations(1)
            hapticSoft()
            triggerRipple()
        } label: {
            ZStack {
                HomeStylePlayCardBackground(cornerRadius: buttonCornerRadius, appTheme: theme)
                VStack(spacing: 4) {
                    Text("\(log.gamesSinceLastWin)")
                        .font(.system(size: min(geo.size.width * 0.14, height * 0.32), weight: .black, design: .monospaced))
                        .foregroundColor(theme == .light ? theme.playLabelPrimary : AppGlassStyle.normalColor)
                    Text(log.currentState == .normal ? "タップ+1" : (log.isTimeShortMode ? "時短中" : "電サポ中"))
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                        .foregroundColor(theme == .light ? theme.playLabelSecondary : AppGlassStyle.normalColor.opacity(0.9))
                    Text("長押しで回転数入力")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(theme == .light ? theme.playLabelSecondary : AppGlassStyle.normalColor.opacity(0.72))
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .contentShape(Rectangle())
        }
        .buttonStyle(HomeStyleGridButtonPressStyle())
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.5).onEnded { _ in
                tempLampValue = "\(log.gamesSinceLastWin)"
                showSyncSheet = true
                haptic(.medium)
            }
        )

        HStack(spacing: buttonGap) {
            if rightHandMode {
                countButton
                investmentColumn
            } else {
                investmentColumn
                countButton
            }
        }
        .padding(.horizontal, contentHorizontalPadding)
        .frame(height: height)
    }

    private func zoneButton<Content: View>(
        @ViewBuilder content: () -> Content,
        onTap: @escaping () -> Void,
        disabled: Bool = false
    ) -> some View {
        Button {
            if !disabled { onTap() }
        } label: {
            ZStack {
                HomeStylePlayCardBackground(cornerRadius: buttonCornerRadius, appTheme: theme)
                content()
            }
            .frame(maxWidth: .infinity).frame(maxHeight: .infinity)
            .opacity(disabled ? 0.5 : 1)
        }
        .buttonStyle(HomeStyleGridButtonPressStyle())
        .disabled(disabled)
    }

    /// フローティング下部バー用：機種に応じた左右マージン（縁から等間隔）
    private func floatingBarHorizontalMargin(geo: GeometryProxy) -> CGFloat {
        max(12, min(20, geo.size.width * 0.04))
    }

    /// 下部ボタン群の間隔（sectionGap と統一）
    private let bottomBarSpacing: CGFloat = 8

    @ViewBuilder
    private func floatingBottomBar(geo: GeometryProxy, barHeight: CGFloat) -> some View {
        let horizontalMargin = floatingBarHorizontalMargin(geo: geo)
        // パディング内の利用幅（normalAndEndRow 内で HStack の spacing 分を差し引いて 2:1 配分する）
        let rawContentW = geo.size.width - horizontalMargin * 2
        let contentWidth = rawContentW.isFinite ? max(0, rawContentW) : 0
        let bottomPadding: CGFloat = 8

        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: bottomBarSpacing) {
                // 通常時: 大当たり＋遊技終了
                normalAndEndRow(width: contentWidth, height: barHeight, curveRadius: buttonCornerRadius)
            }
            .frame(maxHeight: .infinity)
            .padding(.horizontal, horizontalMargin)
        }
        .frame(minHeight: barHeight)
        .frame(maxWidth: .infinity)
        .padding(.bottom, bottomPadding + geo.safeAreaInsets.bottom)
        .confirmationDialog("実戦を終了", isPresented: $showEndConfirm, titleVisibility: .visible) {
            Button("保存して終了") {
                let isEmpty = log.normalRotations == 0 && log.totalInput == 0
                if isEmpty {
                    showEmptySaveConfirm = true
                } else {
                    finalHoldingsInput = "\(log.totalHoldings)"
                    finalNormalRotationsInput = "\(log.normalRotations)"
                    showFinalHoldingsInput = true
                }
            }
            Button("保存しないで終了", role: .destructive) { dismiss() }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("保存してから終了しますか？")
        }
        .confirmationDialog("記録がありません", isPresented: $showEmptySaveConfirm, titleVisibility: .visible) {
            Button("保存する") {
                showEmptySaveConfirm = false
                finalHoldingsInput = "\(log.totalHoldings)"
                finalNormalRotationsInput = "\(log.normalRotations)"
                showFinalHoldingsInput = true
            }
            Button("キャンセル", role: .cancel) { showEmptySaveConfirm = false }
        } message: {
            Text("回転数・投資がありませんが保存しますか？")
        }
        .sheet(isPresented: $showFinalHoldingsInput) {
            NavigationStack {
                VStack(alignment: .leading, spacing: 18) {
                    Text("実際に流した玉数（回収出玉）と、やめた時点の通常回転数（時短・電サポ除く）を入力してください。どちらも必須です（0 なら 0 と入力）。流した玉はアプリ上の持ち玉（\(log.totalHoldings)玉）との差分を自動調整します。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("流した球（回収出玉）")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        IntegerPadTextField(
                            text: $finalHoldingsInput,
                            placeholder: "必須",
                            maxDigits: 8,
                            font: .systemFont(ofSize: 24, weight: .semibold),
                            textColor: .label,
                            accentColor: UIColor(focusAccent),
                            focusTrigger: finalHoldingsPadTrigger,
                            onNextField: { finalNormalRotationsPadTrigger += 1 }
                        )
                        .frame(maxWidth: .infinity, minHeight: 48)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("辞めた時点の通常回転数")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        IntegerPadTextField(
                            text: $finalNormalRotationsInput,
                            placeholder: "必須",
                            maxDigits: 7,
                            font: .systemFont(ofSize: 24, weight: .semibold),
                            textColor: .label,
                            accentColor: UIColor(focusAccent),
                            focusTrigger: finalNormalRotationsPadTrigger,
                            onPreviousField: { finalHoldingsPadTrigger += 1 }
                        )
                        .frame(maxWidth: .infinity, minHeight: 48)
                    }
                    Spacer()
                }
                .padding()
                .navigationTitle("遊技終了の確認")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("キャンセル") { showFinalHoldingsInput = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("完了") { confirmFinalHoldingsFlow() }
                            .disabled(!finalSessionEndFormValid)
                    }
                }
                .onAppear {
                    finalHoldingsPadTrigger += 1
                }
            }
            .presentationDetents([.medium, .large])
        }
        .alert("入力エラー", isPresented: $showErrorAlert) {
            Button("閉じる", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
        .alert("保存しました", isPresented: Binding(
            get: { saveResult == "ok" },
            set: { if !$0 { saveResult = nil } }
        )) {
            Button("閉じる") {
                dismissPlayAfterSaveFlow()
            }
        } message: {
            Text("実戦記録を保存しました。")
        }
        .alert("保存に失敗しました", isPresented: Binding(
            get: { saveResult.map { $0.hasPrefix("error:") } ?? false },
            set: { if !$0 { saveResult = nil } }
        )) {
            Button("閉じる") { saveResult = nil }
        } message: {
            if let r = saveResult, r.hasPrefix("error:") {
                Text(String(r.dropFirst(7)))
            }
        }
        .sheet(isPresented: $showSettlementSheet) {
            SessionSettlementSheet(
                recoveryBalls: log.totalHoldings,
                payoutCoefficient: log.selectedShop.payoutCoefficient,
                supportsChodama: log.selectedShop.supportsChodamaService,
                onCancel: { showSettlementSheet = false },
                onConfirm: { mode in
                    showSettlementSheet = false
                    saveCurrentSession(settlementMode: mode)
                    if saveResult == "ok" {
                        dismissPlayAfterSaveFlow()
                    }
                }
            )
            .presentationDetents([.medium, .large])
        }
        .confirmationDialog("大当たりモード", isPresented: $showBigHitAccessibilityConfirm, titleVisibility: .visible) {
            Button("開始") {
                showBigHitAccessibilityConfirm = false
                haptic(.medium)
                bigHitEntryNormalRotations = "\(log.normalRotations)"
                bigHitEntryCashPt = "\(log.totalInput)"
                showBigHitEntrySheet = true
            }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("大当たり記録（連チャンなど）を開始します。よろしいですか？")
        }
    }

    /// 通常時: 左＝大当たりスライドレール、右＝遊技終了（タップ）。スライドのみで大当たり確定
    private func normalAndEndRow(width: CGFloat, height: CGFloat, curveRadius: CGFloat) -> some View {
        let w = width.isFinite ? max(0, width) : 0
        let h = height.isFinite ? max(0, height) : 0
        let r = curveRadius.isFinite ? max(0, curveRadius) : 0
        let spacing = bottomBarSpacing
        let available = max(0, w - spacing)
        let minEnd: CGFloat = 100
        let minRail: CGFloat = 120
        var railW: CGFloat
        var endW: CGFloat
        if available < minEnd + minRail {
            // `railW` を `available` 超にしない（endW が負・非有限になるのを防ぐ）
            railW = min(max(96, available * 0.47), max(0, available))
            endW = max(0, available - railW)
        } else {
            var rw = min(268, max(minRail, available - minEnd))
            var ew = available - rw
            if ew < minEnd {
                ew = minEnd
                rw = max(minRail, available - ew)
            }
            railW = rw
            endW = ew
        }
        // レイアウトの取りこぼしで幅の合計が available を超えないようにする
        railW = max(0, min(railW, available))
        endW = max(0, available - railW)

        let safeRailW = railW.isFinite ? max(0, railW) : 0
        let safeEndW = endW.isFinite ? max(0, endW) : 0
        let safeH = h.isFinite ? max(0, h) : 0

        return HStack(alignment: .center, spacing: spacing) {
            SlideToConfirmBigHitRail(
                height: safeH,
                cornerRadius: r,
                accent: bigHitBarTitleColor,
                chrome: theme.bigHitRailChrome,
                onConfirmed: {
                    haptic(.medium)
                    bigHitEntryNormalRotations = "\(log.normalRotations)"
                    bigHitEntryCashPt = "\(log.totalInput)"
                    showBigHitEntrySheet = true
                },
                onAccessibilityConfirmRequested: {
                    showBigHitAccessibilityConfirm = true
                }
            )
            .frame(width: safeRailW, height: safeH)

            Button {
                showEndConfirm = true
                haptic(.medium)
            } label: {
                ZStack {
                    HomeStylePlayCardBackground(cornerRadius: r, appTheme: theme)
                    Text("遊技終了")
                        .font(.system(size: 17, weight: .bold, design: .monospaced))
                        .foregroundColor(theme.playLabelPrimary.opacity(0.96))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .buttonStyle(HomeStyleGridButtonPressStyle())
            .frame(width: safeEndW, height: safeH)
        }
        .frame(width: w)
        .frame(minHeight: safeH)
        .frame(maxHeight: .infinity)
    }

    @ViewBuilder
    private func popoverOverlays(geo: GeometryProxy) -> some View {
        EmptyView()
    }

    /// `GameLog.selectedShop` が環境の `modelContext` に登録された `Shop` と同一インスタンスでない場合、貯玉の加算が保存されないことがあるため、保存直前に必ず解決する。
    private func resolvePersistedShop(matching reference: Shop) -> Shop? {
        if let resolved = modelContext.model(for: reference.persistentModelID) as? Shop {
            return resolved
        }
        let searchName = reference.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !searchName.isEmpty, searchName != "未選択" else { return nil }
        let name = searchName
        let predicate = #Predicate<Shop> { shop in shop.name == name }
        var descriptor = FetchDescriptor<Shop>(predicate: predicate)
        descriptor.fetchLimit = 32
        guard let matches = try? modelContext.fetch(descriptor), !matches.isEmpty else { return nil }
        if matches.count == 1 { return matches[0] }
        let coef = reference.payoutCoefficient
        let ballsPer = reference.ballsPerCashUnit
        let chodamaOn = reference.supportsChodamaService
        return matches.first(where: {
            $0.payoutCoefficient == coef && $0.ballsPerCashUnit == ballsPer && $0.supportsChodamaService == chodamaOn
        }) ?? matches.first
    }

    /// - Parameter settlementMode: 回収玉が 1 玉以上のとき実戦フローで選択。`nil` は未精算（旧挙動・回収 0）
    private func saveCurrentSession(settlementMode: SessionSettlementMode?) {
        let refShop = log.selectedShop
        let persistedShop = resolvePersistedShop(matching: refShop)
        var settlementRaw = ""
        var exchangePt = 0
        var chodamaDelta = 0
        if let mode = settlementMode {
            settlementRaw = mode.rawValue
            let balls = log.totalHoldings
            let rate = refShop.payoutCoefficient
            switch mode {
            case .chodama:
                if let shop = persistedShop, shop.supportsChodamaService {
                    chodamaDelta = balls
                    shop.chodamaBalanceBalls += balls
                }
            case .exchange:
                let bd = ChodamaSettlement.exchangeBreakdown(balls: balls, yenPerBall: rate)
                exchangePt = bd.cashProceedsPt
                if let shop = persistedShop, shop.supportsChodamaService {
                    chodamaDelta = bd.remainderBalls
                    shop.chodamaBalanceBalls += bd.remainderBalls
                }
            }
        }
        // 期待値計算用：実質投資が0の場合は現金＋持ち玉円換算で補正（記録漏れ対策）
        let realCost = log.totalRealCost > 0
            ? log.totalRealCost
            : Double(log.totalInput) + Double(log.holdingsInvestedBalls) * log.selectedShop.payoutCoefficient
        let ratio = log.expectationRatio > 0 ? log.expectationRatio : 1.0
        let formulaBorder = parseFormulaBorder(log.selectedMachine.border)
        let session = GameSession(
            machineName: log.selectedMachine.name,
            shopName: log.selectedShop.name,
            manufacturerName: log.selectedMachine.manufacturer,
            inputCash: log.totalInput,
            totalHoldings: log.totalHoldings,
            normalRotations: log.normalRotations,
            totalUsedBalls: log.totalUsedBalls,
            payoutCoefficient: log.selectedShop.payoutCoefficient,
            totalRealCost: realCost,
            expectationRatioAtSave: ratio,
            rushWinCount: log.rushWinCount,
            normalWinCount: log.normalWinCount,
            formulaBorderPer1k: formulaBorder > 0 ? formulaBorder : 0
        )
        session.firstHitRealCostPt = log.realCostAtFirstWin()
        session.effectiveBorderPer1kAtSave = log.dynamicBorder
        session.realRotationRateAtSave = log.realRate
        session.settlementModeRaw = settlementRaw
        session.exchangeCashProceedsPt = exchangePt
        session.chodamaBalanceDeltaBalls = chodamaDelta
        session.isCashflowOnlyRecord = false
        modelContext.insert(session)
        ResumableStateStore.save(from: log)
        do {
            try modelContext.save()
            saveResult = "ok"
        } catch {
            saveResult = "error: 保存に失敗しました。もう一度お試しください。"
        }
    }

    // MARK: - 大当たりモード（連チャン数で色テーマ：1=青・2〜4=赤・5〜9=金・10+=レインボー）

    /// 壁紙の上に乗せるセッション全体の色味（初当たり=青、連チャンで赤→金→レインボー）
    @ViewBuilder
    private func bigHitAtmosphereOverlay(geo: GeometryProxy, chainCount: Int) -> some View {
        let w = geo.size.width
        let h = geo.size.height
        Group {
            if chainCount >= 10 {
                TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: false)) { timeline in
                    let t = timeline.date.timeIntervalSinceReferenceDate
                    let cx = 0.5 + 0.45 * cos(t * 0.9)
                    let cy = 0.5 + 0.45 * sin(t * 0.9)
                    LinearGradient(
                        colors: [
                            Color(red: 0.98, green: 0.32, blue: 0.38).opacity(0.28),
                            Color(red: 1.0, green: 0.72, blue: 0.18).opacity(0.24),
                            Color(red: 0.42, green: 0.95, blue: 0.48).opacity(0.22),
                            Color(red: 0.32, green: 0.72, blue: 1.0).opacity(0.26),
                            Color(red: 0.82, green: 0.42, blue: 1.0).opacity(0.24),
                            Color(red: 0.98, green: 0.32, blue: 0.38).opacity(0.26)
                        ],
                        startPoint: UnitPoint(x: cx, y: cy),
                        endPoint: UnitPoint(x: 1 - cx, y: 1 - cy)
                    )
                }
            } else if chainCount >= 5 {
                LinearGradient(
                    colors: [
                        Color(red: 1.0, green: 0.78, blue: 0.22).opacity(0.34),
                        Color(red: 0.92, green: 0.62, blue: 0.08).opacity(0.22),
                        Color(red: 0.55, green: 0.38, blue: 0.06).opacity(0.12)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            } else if chainCount >= 2 {
                LinearGradient(
                    colors: [
                        AppGlassStyle.rushColor.opacity(0.32),
                        Color.red.opacity(0.2),
                        AppGlassStyle.rushColor.opacity(0.14)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            } else {
                LinearGradient(
                    colors: [
                        Color(red: 0.35, green: 0.58, blue: 0.96).opacity(0.4),
                        Color(red: 0.22, green: 0.45, blue: 0.88).opacity(0.24),
                        Color(red: 0.15, green: 0.35, blue: 0.72).opacity(0.14)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        }
        .frame(width: w, height: h)
        .blendMode(.plusLighter)
    }

    /// 突入1回=青、連チャンが増えるほど赤→金→レインボー
    private var bigHitRainbowForeground: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 0.98, green: 0.32, blue: 0.38),
                Color(red: 1.0, green: 0.72, blue: 0.18),
                Color(red: 0.42, green: 0.95, blue: 0.48),
                Color(red: 0.32, green: 0.72, blue: 1.0),
                Color(red: 0.82, green: 0.42, blue: 1.0),
                Color(red: 0.98, green: 0.32, blue: 0.38)
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    private func bigHitChainPrimaryColor(_ n: Int) -> Color {
        switch n {
        case 1:
            return Color(red: 0.45, green: 0.72, blue: 0.98)
        case 2 ..< 5:
            return AppGlassStyle.rushColor
        case 5 ..< 10:
            return Color(red: 1.0, green: 0.78, blue: 0.22)
        default:
            return Color(red: 0.85, green: 0.45, blue: 0.98)
        }
    }

    private func bigHitChainUsesRainbow(_ n: Int) -> Bool { n >= 10 }

    /// 折れ線・ゲージ等に渡す単色（レインボー帯は代表色）
    private func bigHitChainLineTint(_ n: Int) -> Color {
        bigHitChainUsesRainbow(n) ? Color(red: 0.75, green: 0.4, blue: 0.95) : bigHitChainPrimaryColor(n)
    }

    @ViewBuilder
    private func bigHitThemedStroke(cornerRadius: CGFloat, chainCount: Int) -> some View {
        if bigHitChainUsesRainbow(chainCount) {
            RoundedRectangle(cornerRadius: cornerRadius)
                .stroke(bigHitRainbowForeground, lineWidth: playPanelStrokeLineWidth)
        } else {
            RoundedRectangle(cornerRadius: cornerRadius)
                .stroke(glassStroke(tint: bigHitChainPrimaryColor(chainCount)), lineWidth: playPanelStrokeLineWidth)
        }
    }

    /// 大当たり終了シート：大当たり数・獲得出玉・電サポ回数はいずれも必須（0 は明示入力）
    private var bigHitExitFormValid: Bool {
        let hTrim = bigHitExitHitsField.trimmingCharacters(in: .whitespaces)
        guard let h = Int(hTrim), h >= 1 else { return false }
        let pTrim = bigHitExitPrizeField.trimmingCharacters(in: .whitespaces)
        guard !pTrim.isEmpty, let p = Int(pTrim), p >= 0 else { return false }
        let eTrim = bigHitExitElectricField.trimmingCharacters(in: .whitespaces)
        guard !eTrim.isEmpty, let e = Int(eTrim), e >= 0 else { return false }
        return true
    }

    @ViewBuilder
    private func bigHitExitSheetView() -> some View {
        NavigationStack {
            ZStack {
                Color.black.opacity(0.97).ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("大当たり数・総獲得出玉数・電サポ回数はすべて必須です。出玉や電サポがない場合は 0 と入力してください。テンキー付属バーの矢印で欄を移動できます。")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.88))
                            .fixedSize(horizontal: false, vertical: true)

                        bigHitExitInputPanel(
                            fieldIndex: 0,
                            title: "大当たり数（初当たり含む）",
                            footnote: "「初当たりのあと連チャンでさらに1回当たった」なら累計は2回。入力欄にはその合計回数（初当たりを1として数えた回数）を入れます。画面上の連チャン数と同じ値が目安です。",
                            text: $bigHitExitHitsField,
                            maxDigits: 4,
                            placeholder: ""
                        )
                        bigHitExitInputPanel(
                            fieldIndex: 1,
                            title: "総獲得出玉数",
                            footnote: "必須。獲得出玉がない場合は 0 を入力してください。",
                            text: $bigHitExitPrizeField,
                            maxDigits: 7,
                            placeholder: ""
                        )
                        bigHitExitInputPanel(
                            fieldIndex: 2,
                            title: "電サポ回数",
                            footnote: "必須。大当たり確定の時点ですでに消化した電サポのゲーム数（ない場合は 0）。カウントの「当選からのゲーム数」に反映され、通常へ戻った直後からその続きとして +1 できます。",
                            text: $bigHitExitElectricField,
                            maxDigits: 5,
                            placeholder: ""
                        )

                        Button {
                            guard bigHitExitFormValid,
                                  let hits = Int(bigHitExitHitsField.trimmingCharacters(in: .whitespaces)),
                                  let prize = Int(bigHitExitPrizeField.trimmingCharacters(in: .whitespaces)),
                                  let elec = Int(bigHitExitElectricField.trimmingCharacters(in: .whitespaces))
                            else { return }
                            log.commitBigHitSessionToNormal(hitCount: hits, totalPrizeBalls: prize, electricSupportTurns: elec)
                            showBigHitExitSheet = false
                            if returnToPowerSavingModeAfterExit {
                                returnToPowerSavingModeAfterExit = false
                                showPowerSavingMode = true
                            }
                            ResumableStateStore.autosave(from: log, force: true)
                        } label: {
                            Text("確定して通常へ戻る")
                                .font(.system(size: 17, weight: .bold, design: .rounded))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 15)
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(.white)
                        .background(Color.cyan.opacity(0.28))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(focusAccent.opacity(0.55), lineWidth: 1.2))
                        .disabled(!bigHitExitFormValid)
                        .opacity(bigHitExitFormValid ? 1 : 0.45)

                        VStack(alignment: .leading, spacing: 10) {
                            Text("誤って大当たりモードに入った場合など、当たり区間を記録せず実戦画面に戻れます。")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.55))
                                .fixedSize(horizontal: false, vertical: true)

                            Button { showBigHitAbandonConfirm = true } label: {
                                Text("記録しないで通常に戻る")
                                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                            }
                            .buttonStyle(.plain)
                            .foregroundColor(.white.opacity(0.95))
                            .background(Color(red: 0.52, green: 0.14, blue: 0.16))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.red.opacity(0.45), lineWidth: 1))
                        }
                        .padding(.top, 4)
                    }
                    .padding(16)
                    .padding(.bottom, 8)
                }
            }
            .navigationTitle("大当たりを確定")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.black.opacity(0.95), for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("戻る") { showBigHitExitSheet = false }
                        .foregroundColor(focusAccent)
                }
            }
            .onAppear {
                bigHitExitPadFocusTriggers = [0, 0, 0]
                bigHitExitPadFocusTriggers[0] += 1
            }
            .alert("記録せず通常画面に戻りますか？", isPresented: $showBigHitAbandonConfirm) {
                Button("いいえ", role: .cancel) {}
                Button("はい", role: .destructive) {
                    log.abandonBigHitSessionWithoutRecording()
                    showBigHitExitSheet = false
                    haptic(.light)
                    if returnToPowerSavingModeAfterExit {
                        returnToPowerSavingModeAfterExit = false
                        showPowerSavingMode = true
                    }
                    ResumableStateStore.autosave(from: log, force: true)
                }
            } message: {
                Text("この当たり区間のデータは履歴に残りません。")
            }
        }
    }

    private func bigHitExitInputPanel(
        fieldIndex: Int,
        title: String,
        footnote: String?,
        text: Binding<String>,
        maxDigits: Int,
        placeholder: String = ""
    ) -> some View {
        let accentUi = UIColor(focusAccent)
        let padNav: ((Int) -> Void) = { delta in
            let n = bigHitExitPadFocusTriggers.count
            guard n > 0 else { return }
            var idx = fieldIndex
            idx = (idx + delta) % n
            if idx < 0 { idx += n }
            bigHitExitPadFocusTriggers[idx] += 1
        }
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                Text(title)
                    .font(AppTypography.sectionSubheading)
                    .foregroundColor(.white.opacity(0.92))
                    .frame(maxWidth: .infinity, alignment: .leading)
                IntegerPadTextField(
                    text: text,
                    placeholder: placeholder,
                    maxDigits: maxDigits,
                    font: .monospacedSystemFont(ofSize: 20, weight: .bold),
                    textColor: UIColor(focusAccent),
                    accentColor: accentUi,
                    focusTrigger: bigHitExitPadFocusTriggers[fieldIndex],
                    onPreviousField: { padNav(-1) },
                    onNextField: { padNav(1) }
                )
                .frame(width: 100, height: 44, alignment: .trailing)
                .background(Color.black.opacity(0.35))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.18), lineWidth: 1))
            }
            if let footnote, !footnote.isEmpty {
                Text(footnote)
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.58))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(playPanelBackground)
        .clipShape(RoundedRectangle(cornerRadius: infoPanelCornerRadius))
        .overlay(RoundedRectangle(cornerRadius: infoPanelCornerRadius).stroke(glassStroke(tint: focusAccent), lineWidth: playPanelStrokeLineWidth))
    }

    private var bigHitEntryFormValid: Bool {
        guard let nRot = Int(bigHitEntryNormalRotations.trimmingCharacters(in: .whitespaces)), nRot >= 0 else { return false }
        guard let cash = Int(bigHitEntryCashPt.trimmingCharacters(in: .whitespaces)), cash >= 0 else { return false }
        let needsHoldings = log.holdingsInvestedBalls > 0
        let hTrim = bigHitEntryHoldingsValue.trimmingCharacters(in: .whitespaces)
        if needsHoldings {
            guard let hv = Int(hTrim), hv >= 0 else { return false }
        } else {
            if !hTrim.isEmpty, Int(hTrim) == nil { return false }
            if let v = Int(hTrim), v < 0 { return false }
        }
        return true
    }

    /// 持ち玉：セグメントで「投資」／「残り」を切り替え、入力欄は1つだけ。実戦で持ち玉投資が無い場合はグレーアウト。
    private func bigHitEntryHoldingsPanel(fieldIndex: Int, requiresHoldings: Bool) -> some View {
        let accentUi = UIColor(focusAccent)
        let padNav: ((Int) -> Void) = { delta in
            let n = bigHitEntryPadFocusTriggers.count
            guard n > 0 else { return }
            var idx = fieldIndex
            idx = (idx + delta) % n
            if idx < 0 { idx += n }
            bigHitEntryPadFocusTriggers[idx] += 1
        }
        return VStack(alignment: .leading, spacing: 10) {
            Text(requiresHoldings ? "持ち玉（必須）" : "持ち玉（この実戦で持ち玉投資なし）")
                .font(AppTypography.sectionSubheading)
                .foregroundColor(.white.opacity(requiresHoldings ? 0.92 : 0.55))
            Picker("入力の種類", selection: $bigHitEntryHoldingsKind) {
                ForEach(BigHitHoldingsEntryKind.allCases) { k in
                    Text(k.sheetSegmentLabel).tag(k)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .accessibilityLabel("持ち玉の入力の種類")
            .disabled(!requiresHoldings)
            .opacity(requiresHoldings ? 1 : 0.55)
            .onChange(of: bigHitEntryHoldingsKind) { _, newKind in
                guard requiresHoldings else {
                    bigHitEntryHoldingsValue = ""
                    return
                }
                bigHitEntryHoldingsValue = newKind == .investedAtWin ? "\(log.holdingsInvestedBalls)" : "\(log.totalHoldings)"
            }

            HStack(alignment: .center, spacing: 12) {
                Text(bigHitEntryHoldingsKind.sheetFieldTitle)
                    .font(AppTypography.sectionSubheading)
                    .foregroundColor(.white.opacity(requiresHoldings ? 0.92 : 0.55))
                    .frame(maxWidth: .infinity, alignment: .leading)
                IntegerPadTextField(
                    text: $bigHitEntryHoldingsValue,
                    placeholder: "",
                    maxDigits: 7,
                    font: .monospacedSystemFont(ofSize: 18, weight: .semibold),
                    textColor: .white,
                    accentColor: accentUi,
                    focusTrigger: bigHitEntryPadFocusTriggers[fieldIndex],
                    onPreviousField: { padNav(-1) },
                    onNextField: { padNav(1) },
                    isEnabled: requiresHoldings
                )
                .frame(width: 100, height: 44, alignment: .trailing)
                .background(Color.black.opacity(0.35))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.18), lineWidth: 1))
            }

            Text(requiresHoldings ? bigHitEntryHoldingsKind.sheetFootnote : "このセッションで一度も持ち玉投資していないため入力できません。アプリが把握している値を自動で反映する必要はありません。")
                .font(.caption2)
                .foregroundColor(.white.opacity(0.58))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(playPanelBackground)
        .clipShape(RoundedRectangle(cornerRadius: infoPanelCornerRadius))
        .overlay(RoundedRectangle(cornerRadius: infoPanelCornerRadius).stroke(glassStroke(tint: focusAccent), lineWidth: playPanelStrokeLineWidth))
        .opacity(requiresHoldings ? 1 : 0.72)
        .accessibilityElement(children: .contain)
        .accessibilityHint(requiresHoldings ? "持ち玉投資があるため、この欄の入力が必要です。" : "持ち玉投資がないため、この欄は使えません。")
    }

    @ViewBuilder
    private func bigHitEntrySheetView() -> some View {
        NavigationStack {
            ZStack {
                Color.black.opacity(0.97).ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("当選時点の通常回転・投入を入力して大当たり記録を開始します。この実戦ですでに持ち玉投資している場合は、下の持ち玉欄も必須です（切替と値はアプリが把握している数で初期表示されます）。持ち玉投資が一度もない場合はその欄は使えません。初期の切替は設定から変更できます。")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.88))
                            .fixedSize(horizontal: false, vertical: true)

                        bigHitEntryInputPanel(
                            fieldIndex: 0,
                            title: "当選時点の通常回転数",
                            footnote: "時短・電サポを除いた通常の累積回転です。",
                            text: $bigHitEntryNormalRotations,
                            maxDigits: 5
                        )
                        bigHitEntryInputPanel(
                            fieldIndex: 1,
                            title: "当選時点の現金投資（pt）",
                            footnote: "500円単位で累計pt。端数は切り捨てて記録されます。",
                            text: $bigHitEntryCashPt,
                            maxDigits: 8
                        )
                        bigHitEntryHoldingsPanel(fieldIndex: 2, requiresHoldings: log.holdingsInvestedBalls > 0)

                        Button {
                            guard let nRot = Int(bigHitEntryNormalRotations.trimmingCharacters(in: .whitespaces)),
                                  let cash = Int(bigHitEntryCashPt.trimmingCharacters(in: .whitespaces)),
                                  bigHitEntryFormValid
                            else { return }
                            let needsHoldings = log.holdingsInvestedBalls > 0
                            let hTrim = bigHitEntryHoldingsValue.trimmingCharacters(in: .whitespaces)
                            let hVal: Int? = needsHoldings ? Int(hTrim) : nil
                            let inv = needsHoldings && bigHitEntryHoldingsKind == .investedAtWin ? hVal : nil
                            let rem = needsHoldings && bigHitEntryHoldingsKind == .remainingAtWin ? hVal : nil
                            log.applyBigHitEntryAtWin(
                                normalRotationsAtWin: nRot,
                                cashPt: cash,
                                holdingsInvestedBalls: inv,
                                remainingHoldingsBalls: rem
                            )
                            showBigHitEntrySheet = false
                            ResumableStateStore.autosave(from: log, force: true)
                            haptic(.medium)
                        } label: {
                            Text("大当たり記録を開始")
                                .font(.system(size: 17, weight: .bold, design: .rounded))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 15)
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(.white)
                        .background(Color.cyan.opacity(0.28))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(focusAccent.opacity(0.55), lineWidth: 1.2))
                        .disabled(!bigHitEntryFormValid)
                        .opacity(bigHitEntryFormValid ? 1 : 0.45)
                    }
                    .padding(16)
                    .padding(.bottom, 8)
                }
            }
            .navigationTitle("大当たり突入")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.black.opacity(0.95), for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { showBigHitEntrySheet = false }
                        .foregroundColor(focusAccent)
                }
            }
            .onAppear {
                bigHitEntryHoldingsKind = BigHitHoldingsEntryKind(rawValue: bigHitHoldingsEntryDefaultRaw) ?? .investedAtWin
                if log.holdingsInvestedBalls > 0 {
                    bigHitEntryHoldingsValue = bigHitEntryHoldingsKind == .investedAtWin
                        ? "\(log.holdingsInvestedBalls)"
                        : "\(log.totalHoldings)"
                } else {
                    bigHitEntryHoldingsValue = ""
                }
                bigHitEntryPadFocusTriggers = [0, 0, 0]
                bigHitEntryPadFocusTriggers[0] += 1
            }
        }
    }

    private func bigHitEntryInputPanel(fieldIndex: Int, title: String, footnote: String?, text: Binding<String>, maxDigits: Int) -> some View {
        let accentUi = UIColor(focusAccent)
        let padNav: ((Int) -> Void) = { delta in
            let n = bigHitEntryPadFocusTriggers.count
            guard n > 0 else { return }
            var idx = fieldIndex
            idx = (idx + delta) % n
            if idx < 0 { idx += n }
            bigHitEntryPadFocusTriggers[idx] += 1
        }
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                Text(title)
                    .font(AppTypography.sectionSubheading)
                    .foregroundColor(.white.opacity(0.92))
                    .frame(maxWidth: .infinity, alignment: .leading)
                IntegerPadTextField(
                    text: text,
                    placeholder: "",
                    maxDigits: maxDigits,
                    font: .monospacedSystemFont(ofSize: 18, weight: .semibold),
                    textColor: .white,
                    accentColor: accentUi,
                    focusTrigger: bigHitEntryPadFocusTriggers[fieldIndex],
                    onPreviousField: { padNav(-1) },
                    onNextField: { padNav(1) }
                )
                .frame(width: 100, height: 44, alignment: .trailing)
                .background(Color.black.opacity(0.35))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.18), lineWidth: 1))
            }
            if let footnote, !footnote.isEmpty {
                Text(footnote)
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.58))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(playPanelBackground)
        .clipShape(RoundedRectangle(cornerRadius: infoPanelCornerRadius))
        .overlay(RoundedRectangle(cornerRadius: infoPanelCornerRadius).stroke(glassStroke(tint: focusAccent), lineWidth: playPanelStrokeLineWidth))
    }

    /// 中央：ホームと同じカード＋押下（連チャン追加）
    private func bigHitCenterRow(geo: GeometryProxy, height: CGFloat) -> some View {
        let n = log.bigHitChainCount
        let c = bigHitChainPrimaryColor(n)
        let rainbow = bigHitChainUsesRainbow(n)
        let titleSize = min(geo.size.width * 0.092, height * 0.26)
        let subtitleSize = max(12, min(16, height * 0.09))
        return Button {
            log.incrementBigHitChain()
            HapticUtil.bigHitChainIncrement()
        } label: {
            ZStack {
                HomeStylePlayCardBackground(cornerRadius: buttonCornerRadius, appTheme: theme)
                VStack(spacing: 8) {
                    Text("連チャン数 \(n)回")
                        .font(.system(size: titleSize, weight: .black, design: .rounded))
                        .minimumScaleFactor(0.65)
                        .lineLimit(1)
                        .modifier(BigHitThemedForeground(isRainbow: rainbow, solid: c))
                    Text("タップで＋1")
                        .font(.system(size: subtitleSize, weight: .semibold, design: .rounded))
                        .foregroundColor(rainbow ? .white.opacity(0.82) : c.opacity(0.85))
                }
            }
        }
        .buttonStyle(HomeStyleGridButtonPressStyle())
        .overlay(bigHitThemedStroke(cornerRadius: buttonCornerRadius, chainCount: n))
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .padding(.horizontal, contentHorizontalPadding)
        .animation(.easeInOut(duration: 0.28), value: n)
        .accessibilityLabel("連チャン数\(n)回")
        .accessibilityHint("タップで連チャンを1回追加します")
    }

    /// 下部：確定シートへ（ホームと同じカード）
    private func bigHitFloatingBottomBar(geo: GeometryProxy, barHeight: CGFloat) -> some View {
        let horizontalMargin = contentHorizontalPadding
        let bottomPadding: CGFloat = 8
        let n = log.bigHitChainCount
        let c = bigHitChainPrimaryColor(n)
        let rainbow = bigHitChainUsesRainbow(n)
        return VStack(spacing: 0) {
            Button {
                haptic(.medium)
                bigHitExitHitsField = "\(log.bigHitChainCount)"
                bigHitExitPrizeField = ""
                bigHitExitElectricField = ""
                showBigHitExitSheet = true
            } label: {
                ZStack {
                    HomeStylePlayCardBackground(cornerRadius: buttonCornerRadius, appTheme: theme)
                    Text("通常へ")
                        .font(.system(size: 18, weight: .bold, design: .monospaced))
                        .modifier(BigHitThemedForeground(isRainbow: rainbow, solid: c))
                }
                .frame(maxWidth: .infinity)
                .frame(minHeight: barHeight)
            }
            .buttonStyle(HomeStyleGridButtonPressStyle())
            .overlay(bigHitThemedStroke(cornerRadius: buttonCornerRadius, chainCount: n))
            .padding(.horizontal, horizontalMargin)
        }
        .frame(minHeight: barHeight)
        .frame(maxWidth: .infinity)
        .padding(.bottom, bottomPadding + geo.safeAreaInsets.bottom)
        .animation(.easeInOut(duration: 0.28), value: n)
    }
}

/// 大当たりモードの文字色（レインボー帯 or 単色）
private struct BigHitThemedForeground: ViewModifier {
    let isRainbow: Bool
    let solid: Color

    func body(content: Content) -> some View {
        if isRainbow {
            content.foregroundStyle(
                LinearGradient(
                    colors: [
                        Color(red: 0.98, green: 0.32, blue: 0.38),
                        Color(red: 1.0, green: 0.72, blue: 0.18),
                        Color(red: 0.42, green: 0.95, blue: 0.48),
                        Color(red: 0.32, green: 0.72, blue: 1.0),
                        Color(red: 0.82, green: 0.42, blue: 1.0)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
        } else {
            content.foregroundColor(solid)
        }
    }
}

// MARK: - 下向き三角（縦長）マーカー用
private struct DownTriangle: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.closeSubpath()
        return p
    }
}

// MARK: - ボーダーゲージ用ヘルプ（ゲージ端の ⓘ から表示）
private enum BorderGaugeHelp {
    static let explanation = """
📊 数値の見方ガイド（ポップアップ用）
このゲージは、お店のルール（貸玉料金や交換率）をすべて計算に入れ、「その台が本当に勝てる台か」をリアルタイムで判定しています。

1. 等価ボーダー
1,000pt（250玉）あたり何回まわればトントンかという、機種ごとの基準値で、全ての計算の土台となります。

2. 実質ボーダー
等価ボーダーに「お店の手数料（貸玉料金）」と「交換の差損」を加味した、その店専用の目標値です。

手数料が高い店ほど、この数字は上がります。「この店で勝つには最低これだけ回さなければならない」という本当の目標値です。

3. 実質回転率
現金投資で打った玉も、持ち玉で打った玉も、すべて「250玉（等価の1,000円分）」単位に換算して算出した回転数です。

お店のルールに左右されない「台の本当の回りやすさ」を表します。これが「実質ボーダー」を超えていれば期待値がプラスになります。

4. 表面回転率
単純に「使った現金 ÷ 1,000」で計算した回転数です。

注意: 貸玉手数料がある店では、1,000円で250玉借りられないため、実質回転率とは数字がズレます。
"""
}

// MARK: - ボーダーメーター（縦5行：等価→実質ボーダー→ゲージ→実質回転率→表面回転率）
struct BorderMeterView: View {
    let borderForGauge: Double
    let realRate: Double
    /// 表面回転率（千円実費あたり）。分母は `totalRealCost`
    let rotationPer1000Yen: Double
    let totalRealCost: Double
    let effectiveUnitsForBorder: Double
    let normalRotations: Int
    /// 機種マスタのボーダー（等価・回/千円）。表示用
    let formulaBorderRaw: Double
    /// 店補正後のボーダー（回/千円）。ゲージ基準
    let formulaBorderLabel: String
    let accent: Color
    /// タップまたは ⓘ で evaluated される全文（静的説明＋補正倍率＋`GameLog.borderGaugeFormulaExplanation()`）
    let gaugeExplanation: () -> String

    @State private var showGaugeSheet = false
    @State private var gaugeSheetExplanation = ""

    private var gaugeEnabled: Bool { effectiveUnitsForBorder > 0 && borderForGauge > 0 }

    /// 実質回転率ベースのボーダーとの差を0.1刻みでスナップ（マーカー位置用）
    private var snappedDiff: Double {
        guard gaugeEnabled else { return -5 }
        let d = realRate - borderForGauge
        return (d * 10).rounded() / 10
    }

    /// マーカー位置用：±5を超える場合は端にクランプ（枠外に出さない）
    private var clampedDiffForMarker: Double { min(max(snappedDiff, -5), 5) }

    /// マーカー色：負→赤、0→白、正→青を線形補間
    private var markerColor: Color {
        let d = min(max(snappedDiff, -5), 5)
        if d <= 0 {
            let t = (d + 5) / 5
            return Color(red: 1 * (1 - t) + 1 * t, green: 0.25 * (1 - t) + 1 * t, blue: 0.25 * (1 - t) + 1 * t)
        } else {
            let t = d / 5
            return Color(red: 1 * (1 - t) + 0.2 * t, green: 1 * (1 - t) + 0.5 * t, blue: 1 * (1 - t) + 1 * t)
        }
    }

    private let valueFontSize: CGFloat = 14
    private let compactLabelFontSize: CGFloat = 12

    /// 表面回転率の表示用（投入実費が無いときは —）
    private var surfaceRateDisplay: String {
        guard totalRealCost > 0, rotationPer1000Yen > 0 else { return "—" }
        return String(format: "%.1f", rotationPer1000Yen)
    }

    var body: some View {
        GeometryReader { g in
            let W = g.size.width
            let H = g.size.height
            let pad: CGFloat = 14
            let barHeight: CGFloat = 20
            let tickHeight: CGFloat = 8
            ZStack(alignment: .topTrailing) {
                VStack(spacing: 0) {
                    // 1行目：等価ボーダー（中央・ラベル・数値とも太字にしない）
                    HStack(spacing: 6) {
                        Spacer(minLength: 0)
                        Text("等価ボーダー")
                            .font(.system(size: compactLabelFontSize, weight: .regular))
                            .foregroundColor(.white.opacity(0.92))
                            .lineLimit(1)
                            .minimumScaleFactor(0.65)
                        Text(formulaBorderRaw > 0 ? String(format: "%.1f", formulaBorderRaw) : "—")
                            .font(.system(size: valueFontSize, weight: .regular, design: .monospaced))
                            .foregroundColor(markerColor)
                        Spacer(minLength: 0)
                    }
                    .padding(.top, 6)
                    .frame(maxWidth: .infinity)

                    // 2行目：実質ボーダー（中央）
                    HStack(spacing: 6) {
                        Spacer(minLength: 0)
                        Text("実質ボーダー")
                            .font(AppTypography.sectionSubheading)
                            .foregroundColor(.white.opacity(0.92))
                            .lineLimit(1)
                            .minimumScaleFactor(0.65)
                        Text(formulaBorderLabel)
                            .font(.system(size: valueFontSize, weight: .bold, design: .monospaced))
                            .foregroundColor(markerColor)
                        Spacer(minLength: 0)
                    }
                    .padding(.top, 4)
                    .frame(maxWidth: .infinity)

                    // 3行目：ゲージ（残り高さを優先使用）
                    GeometryReader { barGeo in
                    let rawBarOuterW = barGeo.size.width
                    let safeBarOuterW = rawBarOuterW.isFinite ? max(0, rawBarOuterW) : 0
                    let rawBarOuterH = barGeo.size.height
                    let safeBarOuterH = rawBarOuterH.isFinite ? max(0, rawBarOuterH) : 0
                    // 狭い幅でも barW が負にならないよう pad を縮める
                    let effectivePad = min(pad, safeBarOuterW / 2)
                    let barW = max(0, safeBarOuterW - effectivePad * 2)
                    let barX0 = effectivePad
                    VStack(spacing: 0) {
                        Spacer(minLength: 0)
                        // バー＋目盛＋マーカーを barGeo 幅に収め、バーは barW 幅で中央に配置
                        ZStack {
                            // バートラック：左右パディングで barW を確保（Spacer+固定幅は提案幅と食い違うと負寸法になり得る）
                            HStack(spacing: 0) {
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color.white.opacity(0.08))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6)
                                            .strokeBorder(Color.white.opacity(0.22), lineWidth: 1)
                                    )
                                    .frame(width: max(0, barW), height: barHeight)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.horizontal, effectivePad)
                            // 中央±0の縦線（座標は barGeo 幅内で barX0 + barW/2）
                            Rectangle()
                                .fill(Color.white.opacity(0.5))
                                .frame(width: 1, height: barHeight + tickHeight)
                                .position(x: barX0 + barW / 2, y: barHeight / 2 + tickHeight / 2)
                            // 目盛線
                            ForEach([-5, -4, -3, -2, -1, 0, 1, 2, 3, 4, 5], id: \.self) { v in
                                let val = Double(v)
                                let xVal = barX0 + CGFloat((val + 5) / 10) * barW
                                let isZero = (v == 0)
                                Rectangle()
                                    .fill(isZero ? Color.white.opacity(0.45) : Color.white.opacity(0.25))
                                    .frame(width: max(0, isZero ? 1.2 : 0.8), height: tickHeight)
                                    .position(x: xVal, y: barHeight + tickHeight / 2)
                            }
                            // マーカー
                            DownTriangle()
                                .fill(markerColor)
                                .overlay(DownTriangle().stroke(Color.white.opacity(0.4), lineWidth: 0.8))
                                .frame(width: 12, height: 16)
                                .position(x: barX0 + CGFloat((clampedDiffForMarker + 5) / 10) * barW, y: barHeight / 2 + 1)
                        }
                        .frame(width: safeBarOuterW, height: barHeight + tickHeight)
                        // -5 / ±0 / +5（バー幅に合わせて中央に配置）
                        HStack(spacing: 0) {
                            Text("-5")
                                .font(.system(size: 9, weight: .medium, design: .monospaced))
                                .foregroundColor(.red.opacity(0.9))
                                .frame(width: max(0, barW / 10), alignment: .leading)
                            Spacer(minLength: 0)
                            Text("±0")
                                .font(.system(size: 9, weight: .medium, design: .monospaced))
                                .foregroundColor(.white)
                            Spacer(minLength: 0)
                            Text("+5")
                                .font(.system(size: 9, weight: .medium, design: .monospaced))
                                .foregroundColor(.blue.opacity(0.9))
                                .frame(width: max(0, barW / 10), alignment: .trailing)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, effectivePad)
                        .padding(.top, 4)
                        Spacer(minLength: 0)
                    }
                    .frame(width: safeBarOuterW, height: safeBarOuterH)
                }
                .frame(minHeight: 58)
                .frame(maxHeight: .infinity)

                    // 4行目：実質回転率（中央）
                    HStack(spacing: 6) {
                        Spacer(minLength: 0)
                        Text("実質回転率")
                            .font(AppTypography.sectionSubheading)
                            .foregroundColor(.white.opacity(0.92))
                            .lineLimit(1)
                            .minimumScaleFactor(0.65)
                        Text(gaugeEnabled ? String(format: "%.1f", realRate) : "\(normalRotations)")
                            .font(.system(size: valueFontSize, weight: .bold, design: .monospaced))
                            .foregroundColor(markerColor)
                        Spacer(minLength: 0)
                    }
                    .padding(.top, 6)
                    .frame(maxWidth: .infinity)

                    // 5行目：表面回転率（中央・太字にしない）
                    HStack(spacing: 6) {
                        Spacer(minLength: 0)
                        Text("表面回転率")
                            .font(.system(size: compactLabelFontSize, weight: .regular))
                            .foregroundColor(.white.opacity(0.92))
                            .lineLimit(1)
                            .minimumScaleFactor(0.65)
                        Text(surfaceRateDisplay)
                            .font(.system(size: valueFontSize, weight: .regular, design: .monospaced))
                            .foregroundColor(markerColor)
                        Spacer(minLength: 0)
                    }
                    .padding(.top, 4)
                    .padding(.bottom, 6)
                    .frame(maxWidth: .infinity)
                }
                .frame(width: W, height: H)
                .contentShape(Rectangle())
                .onTapGesture {
                    gaugeSheetExplanation = gaugeExplanation()
                    showGaugeSheet = true
                }

                Button {
                    gaugeSheetExplanation = gaugeExplanation()
                    showGaugeSheet = true
                } label: {
                    Image(systemName: "info.circle")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white.opacity(0.72))
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
                .padding(.trailing, 2)
            }
        }
        .sheet(isPresented: $showGaugeSheet) {
            InfoExplanationSheet(explanation: gaugeSheetExplanation)
        }
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
    }
}

/// 針用（ダウファイン型・パテック風。上向きが先端、シャープで上品）
private struct DauphineNeedle: Shape {
    func path(in rect: CGRect) -> Path {
        let mx = rect.midX
        let h = rect.height
        // 先端から根元へ：中央1/3で最大幅、根元は細く絞る
        let tip = CGPoint(x: mx, y: rect.minY)
        let leftWide = CGPoint(x: mx - rect.width * 0.38, y: rect.minY + h * 0.42)
        let leftBase = CGPoint(x: mx - rect.width * 0.08, y: rect.maxY)
        let rightBase = CGPoint(x: mx + rect.width * 0.08, y: rect.maxY)
        let rightWide = CGPoint(x: mx + rect.width * 0.38, y: rect.minY + h * 0.42)
        var p = Path()
        p.move(to: tip)
        p.addLine(to: leftWide)
        p.addLine(to: leftBase)
        p.addLine(to: rightBase)
        p.addLine(to: rightWide)
        p.closeSubpath()
        return p
    }
}

/// スワイプバー用：六角形（ハニカム）パターン overlay
private struct HoneycombOverlay: View {
    private let hexRadius: CGFloat = 3
    var body: some View {
        Canvas { context, size in
            let w = size.width
            let h = size.height
            let dx = hexRadius * 1.732
            let dy = hexRadius * 1.5
            var y: CGFloat = -dy
            var row: Int = 0
            while y < h + dy {
                var x: CGFloat = (row % 2 == 0) ? 0 : dx / 2
                while x < w + dx {
                    let center = CGPoint(x: x, y: y)
                    var path = Path()
                    for i in 0..<6 {
                        let angle = CGFloat(i) * .pi / 3 - .pi / 6
                        let p = CGPoint(x: center.x + hexRadius * cos(angle), y: center.y + hexRadius * sin(angle))
                        if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
                    }
                    path.closeSubpath()
                    context.stroke(path, with: .color(.white), lineWidth: 0.5)
                    x += dx
                }
                y += dy * 0.5
                row += 1
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - 大当たり履歴（棒グラフ：左＝最新。棒高＝前当たりからの通常回転差、下段＝単発1青／連チャン数赤）
struct WinHistoryBarChartView: View {
    let records: [WinRecord]
    var maxHeight: CGFloat? = nil
    /// 枠・ラベル用の強調色
    var accentStroke: Color = AppGlassStyle.accent
    /// 連チャン棒の色。nil のときは従来どおり `rushColor`
    var chainBarColor: Color? = nil
    /// 連チャン棒を塗るグラデーション（10連以上のレインボー帯など）。指定時は `chainBarColor` より優先
    var chainBarGradient: LinearGradient? = nil
    /// 棒タップで当該当たりの連チャン回数を修正する
    var onSelectRecord: ((WinRecord) -> Void)? = nil

    private let defaultBarHeight: CGFloat = 56
    /// 棒の太さ（列幅とは別。下の数字は列幅を広く取り2桁でも1行に収める）
    private let barWidth: CGFloat = 12
    /// 1本あたりの列幅（数字用。狭いと2桁が折り返して二重に見える）
    private let columnWidth: CGFloat = 30
    private let barSpacing: CGFloat = 8
    private let labelRowHeight: CGFloat = 20
    private let vStackLabelSpacing: CGFloat = 3
    /// 「大当たり履歴」行の高さ（上余白・フォント・下余白）。棒グラフはこの下から始まる
    private let chartTitleReserveHeight: CGFloat = 34
    private let vStackTitleChartSpacing: CGFloat = 6
    private var chainColor: Color { chainBarColor ?? AppGlassStyle.rushColor }
    private var singleColor: Color { AppGlassStyle.normalColor }

    /// 時系列（古い→新しい）で「前当たりからの通常回転差」
    private var rotationsBetweenById: [UUID: Int] {
        let sorted = records.sorted {
            let n0 = $0.normalRotationsAtWin ?? $0.rotationAtWin
            let n1 = $1.normalRotationsAtWin ?? $1.rotationAtWin
            return n0 < n1
        }
        var prev = 0
        var map: [UUID: Int] = [:]
        for w in sorted {
            let nr = w.normalRotationsAtWin ?? w.rotationAtWin
            map[w.id] = max(0, nr - prev)
            prev = nr
        }
        return map
    }

    private var maxRotBetween: Int {
        let m = rotationsBetweenById.values.max() ?? 1
        return max(m, 1)
    }

    private var orderedRecords: [WinRecord] {
        Array(records.reversed())
    }

    /// タイトル下のスクロール領域の縦幅（棒＋下段数字まで）
    private var chartScrollAreaHeight: CGFloat {
        guard let h = maxHeight, h > 0 else {
            return defaultBarHeight + labelRowHeight + vStackLabelSpacing + 6
        }
        return max(52, h - chartTitleReserveHeight - vStackTitleChartSpacing)
    }

    private var effectiveBarHeight: CGFloat {
        let scrollPadding: CGFloat = 2 + 4
        let reserved = scrollPadding + labelRowHeight + vStackLabelSpacing
        let forBars = chartScrollAreaHeight - reserved
        return min(defaultBarHeight, max(20, forBars))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: vStackTitleChartSpacing) {
            Text("大当たり履歴")
                .font(AppTypography.sectionSubheading)
                .foregroundColor(accentStroke.opacity(0.95))
                .padding(.horizontal, 8)
                .padding(.top, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityAddTraits(.isHeader)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .bottom, spacing: barSpacing) {
                    ForEach(orderedRecords) { record in
                        singleBar(record: record)
                    }
                }
                .padding(.horizontal, 4)
                .padding(.top, 2)
                .padding(.bottom, 4)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(Color.white.opacity(0.18))
                        .frame(height: 1)
                        .padding(.bottom, labelRowHeight + 2)
                        .padding(.horizontal, 4)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: chartScrollAreaHeight)
        }
        .frame(maxWidth: .infinity)
        .frame(height: maxHeight)
    }

    private func displayHitCount(_ r: WinRecord) -> Int {
        max(1, r.bonusSessionHitCount ?? 1)
    }

    @ViewBuilder
    private func singleBar(record: WinRecord) -> some View {
        let between = rotationsBetweenById[record.id] ?? 0
        let cc = displayHitCount(record)
        let isChain = cc >= 2
        let barTint = isChain ? chainColor : singleColor
        let useChainGradient = isChain && chainBarGradient != nil
        let countColor: Color = {
            if !isChain { return singleColor }
            if useChainGradient { return .white }
            return chainColor
        }()
        let ratio = maxRotBetween > 0 ? CGFloat(between) / CGFloat(maxRotBetween) : 0
        let barH = ratio * effectiveBarHeight

        let column = VStack(alignment: .center, spacing: vStackLabelSpacing) {
            Spacer(minLength: 0)
            Group {
                if useChainGradient, let g = chainBarGradient {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(g)
                } else {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(barTint.opacity(0.92))
                }
            }
            .frame(width: barWidth, height: max(3, barH))
            Text("\(cc)")
                .font(.system(size: cc >= 10 ? 11 : 12, weight: .bold, design: .monospaced))
                .foregroundColor(countColor)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .frame(width: columnWidth, height: labelRowHeight, alignment: .center)
                .multilineTextAlignment(.center)
        }
        .frame(width: columnWidth, height: effectiveBarHeight + labelRowHeight + vStackLabelSpacing)
        .contentShape(Rectangle())
        .onLongPressGesture(minimumDuration: 0.45) {
            onSelectRecord?(record)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabelForBar(between: between, hitCount: cc))

        if onSelectRecord != nil {
            column
                .accessibilityHint("長押し、またはここで「当たり回数を修正」で連チャン含む回数を変更できます。")
                .accessibilityAddTraits(.allowsDirectInteraction)
                .accessibilityActions {
                    Button("当たり回数を修正") {
                        onSelectRecord?(record)
                    }
                }
        } else {
            column
        }
    }

    private func accessibilityLabelForBar(between: Int, hitCount: Int) -> String {
        "当たり、通常回転差 \(between)、連チャン含む \(hitCount) 回"
    }
}


struct SyncInputView: View {
    let title: String
    let label: String
    @Binding var val: String
    var onConfirm: () -> Void
    @State private var showErrorAlert = false
    @State private var padTrigger = 0

    var body: some View {
        VStack(spacing: 20) {
            Text(title).bold()
            Text(label).font(.caption).foregroundColor(.gray)
            IntegerPadTextField(
                text: $val,
                placeholder: "",
                maxDigits: 9,
                font: .monospacedSystemFont(ofSize: 34, weight: .medium),
                textColor: .label,
                accentColor: .systemBlue,
                focusTrigger: padTrigger
            )
            .frame(maxWidth: .infinity)
            .multilineTextAlignment(.center)
            Button("確定") {
                UIApplication.dismissKeyboard()
                if let v = Int(val), v < 0 {
                    showErrorAlert = true
                } else {
                    onConfirm()
                }
            }
            .buttonStyle(.borderedProminent)
            Spacer()
        }
        .padding()
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                padTrigger += 1
            }
        }
        .presentationDetents([.height(300)])
        .alert("入力エラー", isPresented: $showErrorAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("負の数は入力できません")
        }
    }
}

struct WinCountCorrectView: View {
    @Binding var rushCount: String
    @Binding var normalCount: String
    var onConfirm: () -> Void
    @State private var showErrorAlert = false
    @State private var rushPadTrigger = 0
    @State private var normalPadTrigger = 0

    var body: some View {
        VStack(spacing: 20) {
            Text("当選回数を修正")
                .font(.headline)
            VStack(alignment: .leading, spacing: 4) {
                Text("RUSH 当選回数")
                    .font(.caption)
                    .foregroundColor(.secondary)
                IntegerPadTextField(
                    text: $rushCount,
                    placeholder: "",
                    maxDigits: 5,
                    font: .monospacedSystemFont(ofSize: 22, weight: .medium),
                    textColor: .label,
                    accentColor: .systemBlue,
                    focusTrigger: rushPadTrigger,
                    onPreviousField: { normalPadTrigger += 1 },
                    onNextField: { normalPadTrigger += 1 }
                )
                .frame(maxWidth: .infinity, minHeight: 44)
                .multilineTextAlignment(.center)
                .background(Color(UIColor.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("通常当選回数")
                    .font(.caption)
                    .foregroundColor(.secondary)
                IntegerPadTextField(
                    text: $normalCount,
                    placeholder: "",
                    maxDigits: 5,
                    font: .monospacedSystemFont(ofSize: 22, weight: .medium),
                    textColor: .label,
                    accentColor: .systemBlue,
                    focusTrigger: normalPadTrigger,
                    onPreviousField: { rushPadTrigger += 1 },
                    onNextField: { rushPadTrigger += 1 }
                )
                .frame(maxWidth: .infinity, minHeight: 44)
                .multilineTextAlignment(.center)
                .background(Color(UIColor.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            Button("確定") {
                UIApplication.dismissKeyboard()
                let r = Int(rushCount.trimmingCharacters(in: .whitespaces)) ?? 0
                let n = Int(normalCount.trimmingCharacters(in: .whitespaces)) ?? 0
                if r < 0 || n < 0 {
                    showErrorAlert = true
                    return
                }
                onConfirm()
            }
            .buttonStyle(.borderedProminent)
            Spacer()
        }
        .padding()
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                rushPadTrigger += 1
            }
        }
        .presentationDetents([.height(360)])
        .alert("入力エラー", isPresented: $showErrorAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("負の数は入力できません")
        }
    }
}

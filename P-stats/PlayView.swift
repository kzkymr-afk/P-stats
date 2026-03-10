import SwiftUI
import SwiftData

struct PlayView: View {
    @Bindable var log: GameLog
    @Binding var theme: AppTheme
    /// ドロワー「設定」タップ時に呼ぶ。nil でなければ実戦を閉じて設定タブへ遷移
    var onOpenSettingsTab: (() -> Void)? = nil
    @Environment(\.dismiss) var dismiss // ホームに戻るために必要
    @Environment(\.modelContext) private var modelContext
    @AppStorage("alwaysShowBothInvestmentButtons") private var alwaysShowBothInvestmentButtons = true

    // --- 1. シートの表示管理用変数 ---
    @State private var showSettingsSheet = false
    @State private var showSyncSheet = false
    @State private var showTrayAdjustSheet = false
    @State private var showWinInputSheet = false
    @State private var showEndConfirm = false
    @State private var showEmptySaveConfirm = false
    @State private var showFinalHoldingsInput = false
    @State private var finalHoldingsInput: String = ""
    /// 保存結果。"ok"＝成功（アラート表示後にdismiss）、"error: ..."＝失敗
    @State private var saveResult: String? = nil
    @State private var showHoldingsSyncSheet = false
    @State private var tempHoldingsSyncValue: String = ""
    @State private var showBonusMonitor = false
    @State private var showPowerSavingMode = false
    /// 今回の遊技で省エネを自動表示したか（1回だけ自動表示するため）
    @State private var didAutoOpenPowerSavingThisSession = false
    @State private var isBonusStandby = false
    @State private var showChainResult = false
    /// スワイプで開く情報ドロワーのオフセット（0=閉, insightPanelWidth=全開）。1:1で指に追従
    @State private var drawerOffset: CGFloat = 0
    /// 隙間ゾーンでスワイプ開始時にシアングロー表示
    @State private var swipeZoneGlow = false
    /// ドロワー「ロック解除」ハプティックを1回だけ発火する用
    @State private var didFireUnlockHaptic = false
    @State private var showRushFocusMode = false
    @State private var showLtFocusMode = false
    @State private var showChanceMode = false
    @State private var showRushLtChoiceSheet = false
    /// 続きから復帰時に RUSH/LT/時短 のフルスクリーンを一度だけ自動表示したか
    @State private var hasRestoredFocusView = false
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
    /// タップ成功時の波紋アニメーション（期待値に応じた色）
    @State private var rippleScale: CGFloat = 0
    @State private var rippleOpacity: Double = 0
    @State private var rippleColor: Color = .white
    @State private var rippleActive = false

    private let insightPanelWidth: CGFloat = 280

    @State private var tempLampValue: String = ""
    @State private var tempAdjustValue: String = ""
    @State private var tempWinType: WinType = .rush
    /// 大当たり入力用：当選時ゲーム数・現金投資・持ち玉投資・持ち玉数
    @State private var tempWinRotation: String = ""
    @State private var tempWinCashYen: String = ""
    @State private var tempWinHoldingsBalls: String = ""
    @State private var tempWinHoldingsCount: String = ""
    
    @State private var showErrorAlert = false
    @State private var errorMessage = ""

    @FocusState private var focusedField: FocusField?
    enum FocusField { case sync, adjust, win }

    /// 大当たり履歴の表示上限（パフォーマンス対策）
    private let winRecordsDisplayLimit = 30
    /// ゲージ再描画用（設定シート戻り時にインクリメント。SwiftDataモデル編集の反映）
    @State private var gaugeRefreshId = 0
    @AppStorage("playViewRightHandMode") private var rightHandMode = false
    @AppStorage("playViewStartWithPowerSaving") private var playViewStartWithPowerSaving = false
    @AppStorage("playViewBackgroundStyle") private var playViewBackgroundStyle = "sameAsHome"
    @AppStorage("playViewBackgroundImagePath") private var playViewBackgroundImagePath = ""
    @AppStorage("homeBackgroundStyle") private var homeBackgroundStyle = HomeBackgroundStore.defaultStyle
    @AppStorage("homeBackgroundImagePath") private var homeBackgroundImagePath = ""
    @State private var loadedPlayBackgroundImage: UIImage?
    @State private var showHistoryFromPlay = false
    @State private var showEventHistorySheet = false
    @State private var showAnalyticsFromPlay = false
    /// 画面上端〜ダイナミックアイランド下端の高さ（表示後にキーウィンドウから取得）
    @State private var headerTopInset: CGFloat = 59

    private func haptic(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .light) {
        HapticUtil.impact(style)
    }

    /// ゲーム数カウント用：最弱のバイブ
    private func hapticSoft() {
        HapticUtil.impact(.soft)
    }

    /// トップと同様のグラスモーフィズム（ダークネイビー・水色）
    private var focusBg: Color { AppGlassStyle.background }
    private var focusAccent: Color { AppGlassStyle.accent }
    /// 通常モードのパネル・ボタン用背景（不透明度85%）
    /// 通常遊戯中のボタン・パネル共通：背景・枠線・オーバーレイ透明度を統一
    private var playPanelBackground: Color { Color.black.opacity(playPanelBackgroundOpacity) }
    private let playPanelBackgroundOpacity: Double = 0.85
    private let playPanelTintOverlayOpacity: Double = 0.06
    private let playPanelStrokeLineWidth: CGFloat = 1
    /// ヘッダー本体・上マージン用（あと20%透明 = 0.75×0.8）
    private var playHeaderBackground: Color { Color.black.opacity(0.6) }

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

    /// ゲージ・波紋で使うボーダー。針は補正ボーダー（実戦ボーダー）と実戦回転率の比較にする。表示用に未補正時は公式を使用
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

    /// 波紋の色：公式ボーダー基準の5段階（AppGlassStyle.edgeGlowColor と同一ロジック）
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
            let h2 = H * 0.05   // ヘッダー
            let hWinCount = H * 0.055  // 最上部「大当たり回数」パネル
            let h20info = H * 0.17  // 情報群（ゲージ＝総回転上端〜持ち玉下端に合わせて縮小）
            let h10 = H * 0.10  // 大当たり履歴
            let h22center = H * 0.255  // 中央ボタン（詰めた分を均等に拡大）
            let barHeight = min(H * 0.22, 110)  // 下部ボタン（詰めた分を均等に拡大）
            let maxRippleSize = max(geo.size.width, geo.size.height) * 1.4
            ZStack(alignment: .bottomLeading) {
                playBackgroundLayer(geo: geo)
                    .ignoresSafeArea(edges: .all)

                VStack(spacing: 0) {
                    // ヘッダー領域: 上マージン＝画面上端〜ダイナミックアイランド下端（同色）。ヘッダー本体はその直下から
                    let headerTopMargin = max(headerTopInset, 20)
                    ZStack(alignment: .bottom) {
                        Rectangle()
                            .fill(playHeaderBackground)
                        headerRow(height: h2)
                    }
                    .frame(height: headerTopMargin + h2)
                    .frame(maxWidth: .infinity)

                    // ヘッダーと情報群の間のマージン
                    Spacer().frame(height: 12)

                    // 最上部：大当たり回数パネル（RUSH / 通常）
                    winCountPanel(height: hWinCount)
                    Spacer().frame(height: 4)

                    // 状態表示（ゲージ＝総回転上端〜持ち玉下端、下余白詰め）
                    infoRow(height: h20info)
                    Spacer().frame(height: sectionGap)

                    // 大当たり履歴
                    WinHistoryBarChartView(records: Array(log.winRecords.suffix(winRecordsDisplayLimit)), maxHeight: h10)
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
                .frame(minHeight: H)
                .ignoresSafeArea(edges: .top)

                // 長押しポップアップ類（最前面）
                popoverOverlays(geo: geo)

                // Bonus Standby: 暗転・呼吸する円・ダブルタップで結果入力
                if isBonusStandby {
                    BonusStandbyOverlay(onDoubleTap: {
                        showChainResult = true
                    })
                    .zIndex(2)
                }

                // インサイトパネル（ドラッグ1:1追従ドロワー）。左手=右から、右手=左から
                if drawerOffset > 0 && !isBonusStandby {
                    ZStack(alignment: rightHandMode ? .leading : .trailing) {
                        Color.black.opacity(0.35)
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
                            tempCashCorrect = "\(log.investment)"
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
        // --- シート類 ---
        .sheet(isPresented: $showSettingsSheet) {
            MachineShopSelectionView(log: log)
        }
        .onChange(of: showSettingsSheet) { _, show in
            if !show { gaugeRefreshId += 1 }
        }
        .overlay {
            if showWinInputSheet {
                ZStack(alignment: .bottom) {
                    Color.black.opacity(0.5)
                        .ignoresSafeArea()
                        .onTapGesture {
                            showWinInputSheet = false
                            if returnToPowerSavingModeAfterExit {
                                showPowerSavingMode = true
                                returnToPowerSavingModeAfterExit = false
                            }
                        }
                    WinInputSheetView(
                        machine: log.selectedMachine,
                        winType: tempWinType,
                        rotation: $tempWinRotation,
                        cashYen: $tempWinCashYen,
                        holdingsBalls: $tempWinHoldingsBalls,
                        holdingsCount: $tempWinHoldingsCount,
                        onConfirm: { prizeBalls, resolvedWinType in
                            guard let rot = Int(tempWinRotation), rot >= 0,
                                  let cash = Int(tempWinCashYen), cash >= 0,
                                  let hBalls = Int(tempWinHoldingsBalls), hBalls >= 0,
                                  let hCount = Int(tempWinHoldingsCount), hCount >= 0 else {
                                showWinInputSheet = false
                                return
                            }
                            log.syncToSnapshot(cashYen: cash, holdingsBalls: hBalls, totalHoldingsCount: hCount)
                            let atRotation = (log.winRecords.last?.rotationAtWin ?? 0) + rot
                            log.addWin(type: resolvedWinType, atRotation: atRotation, prizeBalls: prizeBalls)
                            showWinInputSheet = false
                            if returnToPowerSavingModeAfterExit {
                                if resolvedWinType == .normal {
                                    showPowerSavingMode = true
                                    returnToPowerSavingModeAfterExit = false
                                    return
                                }
                            }
                            if resolvedWinType == .rush {
                                OrganicHaptics.playRushHeartbeat()
                                showRushFocusMode = true
                            } else if resolvedWinType == .lt {
                                showLtFocusMode = true
                            } else if resolvedWinType == .normal {
                                showChanceMode = true
                            }
                        },
                        onCancel: {
                            showWinInputSheet = false
                            if returnToPowerSavingModeAfterExit {
                                showPowerSavingMode = true
                                returnToPowerSavingModeAfterExit = false
                            }
                        }
                    )
                    .frame(maxWidth: 400)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 28)
                    .padding(.top, 16)
                }
                .transition(.opacity)
                .zIndex(100)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: showWinInputSheet)
        .onAppear {
            guard !hasRestoredFocusView else { return }
            if log.currentState == .support {
                showRushFocusMode = true
                hasRestoredFocusView = true
            } else if log.currentState == .lt {
                showLtFocusMode = true
                hasRestoredFocusView = true
            } else if log.isTimeShortMode {
                showChanceMode = true
                hasRestoredFocusView = true
            }
        }
        .sheet(isPresented: $showSyncSheet) { SyncInputView(title: "ゲーム数同期", label: "データランプの現在表示数（自分の回転数と合わせる・回転率に反映されます）", val: $tempLampValue, focus: $focusedField, fieldType: .sync) { if let v = Int(tempLampValue) { log.syncTotalRotations(newTotal: v) }; showSyncSheet = false } }
        .sheet(isPresented: $showTrayAdjustSheet) { SyncInputView(title: "上皿精算", label: "ランプ回転数", val: $tempAdjustValue, focus: $focusedField, fieldType: .adjust) { if let v = Int(tempAdjustValue) { log.adjustForZeroTray(syncRotation: v) }; showTrayAdjustSheet = false } }
        .sheet(isPresented: $showHoldingsSyncSheet) {
            SyncInputView(title: "持ち玉同期", label: "実際の持ち玉数（確変終了後など）", val: $tempHoldingsSyncValue, focus: $focusedField, fieldType: .adjust) {
                if let v = Int(tempHoldingsSyncValue) { log.syncHoldings(actualHoldings: v) }
                showHoldingsSyncSheet = false
            }
        }
        .sheet(isPresented: $showInitialRotationCorrectSheet) {
            SyncInputView(title: "開始ゲーム数修正", label: "開始時の台表示数（表示合わせのみ・回転率には影響しません）", val: $tempInitialRotationCorrect, focus: $focusedField, fieldType: .adjust) {
                if let v = Int(tempInitialRotationCorrect) {
                    log.correctInitialDisplayRotation(to: v)
                }
                showInitialRotationCorrectSheet = false
            }
        }
        .sheet(isPresented: $showCashCorrectSheet) {
            SyncInputView(title: "現金投資修正", label: "総現金投資額（円・500円単位で記録されます）", val: $tempCashCorrect, focus: $focusedField, fieldType: .adjust) {
                if let v = Int(tempCashCorrect) {
                    log.setCashInvestment(yen: v)
                }
                showCashCorrectSheet = false
            }
        }
        .sheet(isPresented: $showHoldingsCorrectSheet) {
            SyncInputView(title: "持ち玉投資を修正", label: "今回遊技に使った持ち玉数（玉）", val: $tempHoldingsCorrectValue, focus: $focusedField, fieldType: .adjust) {
                if let v = Int(tempHoldingsCorrectValue) {
                    log.setHoldingsInvested(balls: v)
                }
                showHoldingsCorrectSheet = false
            }
        }
        .sheet(isPresented: $showWinCountCorrectSheet) {
            WinCountCorrectView(rushCount: $tempRushWinCount, normalCount: $tempNormalWinCount) {
                if let r = Int(tempRushWinCount), let n = Int(tempNormalWinCount) {
                    log.setWinCounts(rush: r, normal: n)
                }
                showWinCountCorrectSheet = false
            }
        }
        .fullScreenCover(isPresented: $showBonusMonitor) {
            BonusMonitorView(
                machine: log.selectedMachine,
                ballsPer1000: Double(log.selectedShop.ballsPerCashUnit * 2),
                exchangeRate: log.selectedShop.exchangeRate
            ) { val in
                log.adjustedNetPerRound = val
                showBonusMonitor = false
            }
        }
        .fullScreenCover(isPresented: $showPowerSavingMode) {
            PowerSavingModeView(
                log: log,
                rightHandMode: rightHandMode,
                onExit: { showPowerSavingMode = false },
                onOpenRush: {
                    returnToPowerSavingModeAfterExit = true
                    showPowerSavingMode = false
                    prepareWinInput(type: .rush)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        showWinInputSheet = true
                        OrganicHaptics.playRushHeartbeat()
                    }
                },
                onOpenNormal: {
                    returnToPowerSavingModeAfterExit = true
                    showPowerSavingMode = false
                    prepareWinInput(type: .normal)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        showWinInputSheet = true
                        haptic(.medium)
                    }
                },
                onOpenLt: {
                    returnToPowerSavingModeAfterExit = true
                    showPowerSavingMode = false
                    prepareWinInput(type: .lt)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        showWinInputSheet = true
                    }
                }
            )
        }
        .fullScreenCover(isPresented: $showRushFocusMode) {
            RushFocusView(log: log, onSwitchToLt: {
                showRushFocusMode = false
                showLtFocusMode = true
            }) {
                showRushFocusMode = false
                if returnToPowerSavingModeAfterExit {
                    showPowerSavingMode = true
                    returnToPowerSavingModeAfterExit = false
                }
            }
        }
        .fullScreenCover(isPresented: $showLtFocusMode) {
            LtFocusView(log: log) {
                showLtFocusMode = false
                if returnToPowerSavingModeAfterExit {
                    showPowerSavingMode = true
                    returnToPowerSavingModeAfterExit = false
                }
            }
        }
        .fullScreenCover(isPresented: $showChanceMode) {
            ChanceModeView(log: log, onRushExit: {
                showChanceMode = false
                showRushFocusMode = true
            }, onLtExit: {
                showChanceMode = false
                showLtFocusMode = true
            }, onTimeShortEnd: { showChanceMode = false })
        }
        .confirmationDialog("RUSH / LT", isPresented: $showRushLtChoiceSheet, titleVisibility: .visible) {
            Button("RUSH") {
                handleWinSelection(type: .rush)
                OrganicHaptics.playRushHeartbeat()
            }
            Button("LT（上位RUSH）") {
                handleWinSelection(type: .lt)
            }
            Button("キャンセル", role: .cancel) { }
        } message: {
            Text("RUSH または LT を選んでください")
        }
        .fullScreenCover(isPresented: $showHistoryFromPlay) {
            NavigationStack {
                HistoryListView()
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("閉じる") { showHistoryFromPlay = false }
                                .foregroundColor(focusAccent)
                        }
                    }
            }
        }
        .fullScreenCover(isPresented: $showEventHistorySheet) {
            PlayEventHistoryView(log: log) { showEventHistorySheet = false }
        }
        .fullScreenCover(isPresented: $showAnalyticsFromPlay) {
            NavigationStack {
                AnalyticsDashboardView()
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("閉じる") { showAnalyticsFromPlay = false }
                                .foregroundColor(focusAccent)
                        }
                    }
            }
        }
        .sheet(isPresented: $showChainResult) {
            ChainResultInputView(
                machine: log.selectedMachine,
                ballsPer1000: Double(log.selectedShop.ballsPerCashUnit * 2),
                exchangeRate: log.selectedShop.exchangeRate,
                totalRealCost: log.totalRealCost,
                normalRotations: log.normalRotations,
                onDismiss: { showChainResult = false; isBonusStandby = false },
                onAppliedNetPerRound: { log.adjustedNetPerRound = $0 }
            )
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
            UIDevice.current.beginGeneratingDeviceOrientationNotifications()
            DispatchQueue.main.async { headerTopInset = Self.windowSafeAreaTop }
            if playViewStartWithPowerSaving, !didAutoOpenPowerSavingThisSession {
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
        let stainlessBase = Color(red: 0.22, green: 0.23, blue: 0.25)
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
                    .foregroundColor(.white.opacity(0.5))
                Spacer()
                Text("SWIPE for Information")
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundColor(.white.opacity(0.7))
                Spacer()
                Color.clear.frame(width: 24, height: 1)
            }
            .padding(.horizontal, 12)
        }
        .overlay(alignment: .top) {
            Rectangle().fill(cyanNeon).frame(height: 0.5)
                .shadow(color: cyanNeon.opacity(0.7), radius: 4)
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(magentaNeon).frame(height: 0.5)
                .shadow(color: magentaNeon.opacity(0.7), radius: 4)
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

    // 最上部: 透過度の低い背景で可読性確保（ゲーム数カウントと同程度）。アイコンは白。
    @ViewBuilder
    private func headerRow(height: CGFloat) -> some View {
        HStack(alignment: .center, spacing: 16) {
            if rightHandMode {
                headerRowTrailingButtons(height: height)
                Button(action: { showSettingsSheet = true; haptic(.light) }) {
                    HStack(alignment: .center, spacing: 8) {
                        Text(log.selectedMachine.name)
                            .font(.system(size: 15, weight: .bold, design: .monospaced))
                            .foregroundColor(.white)
                            .lineLimit(1)
                        Text(log.selectedShop.name)
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .foregroundColor(.white.opacity(0.85))
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, alignment: .trailing)
                headerRowUndoButton()
            } else {
                headerRowUndoButton()
                Button(action: { showSettingsSheet = true; haptic(.light) }) {
                    HStack(alignment: .center, spacing: 8) {
                        Text(log.selectedMachine.name)
                            .font(.system(size: 15, weight: .bold, design: .monospaced))
                            .foregroundColor(.white)
                            .lineLimit(1)
                        Text(log.selectedShop.name)
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .foregroundColor(.white.opacity(0.85))
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, alignment: .leading)
                headerRowTrailingButtons(height: height)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: height)
        .background(playHeaderBackground)
    }

    private func headerRowUndoButton() -> some View {
        Button(action: {
            if log.undoCount > 0 { log.undoLastAction(); haptic(.medium) }
        }) {
            Image(systemName: "arrow.uturn.backward.circle.fill")
                .font(.title2)
                .foregroundColor(log.undoCount > 0 ? .white : .white.opacity(0.35))
        }
        .disabled(log.undoCount == 0)
        .padding(4)
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
                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                .foregroundColor(AppGlassStyle.rushColor.opacity(0.95))
            Text("\(log.rushWinCount)回")
                .font(.system(size: 17, weight: .bold, design: .monospaced))
                .foregroundColor(focusAccent)
            Text("通常")
                .font(.system(size: 14, weight: .semibold, design: .monospaced))
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
    @ViewBuilder
    private func infoRow(height: CGFloat) -> some View {
        let meterR = min(maxMeterRadius, height)
        HStack(alignment: .top, spacing: 10) {
            BorderMeterView(
                borderForGauge: borderForGauge,
                realRate: log.realRate,
                rotationPer1000Yen: log.rotationPer1000Yen,
                effectiveUnitsForBorder: log.effectiveUnitsForBorder,
                normalRotations: log.normalRotations,
                formulaBorderRaw: log.formulaBorderValue,
                formulaBorderLabel: log.dynamicBorder > 0 ? String(format: "%.1f", log.dynamicBorder) : "—",
                accent: focusAccent
            )
            .id("\(log.normalRotations)-\(log.investment)-\(log.holdingsInvestedBalls)-\(gaugeRefreshId)")
            .frame(width: meterR * 2, height: height)
            .background(playPanelBackground)
            .clipShape(RoundedRectangle(cornerRadius: infoPanelCornerRadius))
            .overlay(RoundedRectangle(cornerRadius: infoPanelCornerRadius).stroke(glassStroke(tint: focusAccent), lineWidth: playPanelStrokeLineWidth))

            VStack(alignment: .leading, spacing: 2) {
                infoStatPanel {
                    HStack {
                        HStack(spacing: 4) {
                            Text("総回転数")
                                .font(.system(size: 13, weight: .medium, design: .monospaced))
                                .foregroundColor(focusAccent.opacity(0.7))
                            InfoIconView(explanation: "ゲーム開始から現在までの通常回転の累積（時短・電サポを除く）。金を払って回した回転数。", tint: focusAccent.opacity(0.6))
                        }
                        Spacer()
                        Text("\(log.normalRotations)")
                            .font(.system(size: 17, weight: .bold, design: .monospaced))
                            .foregroundColor(focusAccent)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                }
                infoStatPanel {
                    HStack {
                        HStack(spacing: 4) {
                            Text("期待値")
                                .font(.system(size: 13, weight: .medium, design: .monospaced))
                                .foregroundColor(focusAccent.opacity(0.7))
                            InfoIconView(explanation: "実質回転率÷実戦ボーダー。1.0でボーダー、1.0超で期待値プラス。", tint: focusAccent.opacity(0.6))
                        }
                        Spacer()
                        Text(log.dynamicBorder > 0 && log.effectiveUnitsForBorder > 0 ? String(format: "%.2f%%", log.expectationRatio * 100) : "—")
                            .font(.system(size: 17, weight: .bold, design: .monospaced))
                            .foregroundColor(focusAccent)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                }
                infoStatPanel {
                    HStack {
                        Text("総現金投資")
                            .font(.system(size: 13, weight: .medium, design: .monospaced))
                            .foregroundColor(focusAccent.opacity(0.7))
                        Spacer()
                        Text("\(log.investment.formattedYen)円")
                            .font(.system(size: 16, weight: .bold, design: .monospaced))
                            .foregroundColor(focusAccent)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                }
                infoStatPanel {
                    HStack {
                        Text("総持ち玉投資")
                            .font(.system(size: 13, weight: .medium, design: .monospaced))
                            .foregroundColor(focusAccent.opacity(0.7))
                        Spacer()
                        Text("\(log.holdingsInvestedBalls)玉")
                            .font(.system(size: 16, weight: .bold, design: .monospaced))
                            .foregroundColor(focusAccent)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                }
                infoStatPanel {
                    HStack {
                        Text("持ち玉")
                            .font(.system(size: 13, weight: .medium, design: .monospaced))
                            .foregroundColor(focusAccent.opacity(0.7))
                        Spacer()
                        Text("\(log.totalHoldings)玉")
                            .font(.system(size: 16, weight: .bold, design: .monospaced))
                            .foregroundColor(focusAccent)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                }
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
    private func infoStatPanel<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .frame(maxWidth: .infinity)
            .background(playPanelBackground)
            .clipShape(RoundedRectangle(cornerRadius: infoPanelCornerRadius))
            .overlay(RoundedRectangle(cornerRadius: infoPanelCornerRadius).stroke(glassStroke(tint: focusAccent), lineWidth: playPanelStrokeLineWidth))
    }

    /// トップページ風：半透明＋角丸＋角度で変わる枠線。背景と統一して不透明度85%ベース
    private func glassStroke(tint: Color) -> LinearGradient {
        let o: Double = 0.85
        return LinearGradient(
            colors: [
                Color.white.opacity(o * 0.5),
                tint.opacity(o * 0.35),
                Color.white.opacity(o * 0.1)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    /// 現金・持ち玉・カウント・RUSH・通常・遊技終了まわりで統一
    private let buttonGap: CGFloat = 8
    private let buttonCornerRadius: CGFloat = 16
    /// 中央・下部ボタン・大当たり履歴の左右余白を統一（端を揃える）
    private let contentHorizontalPadding: CGFloat = 12
    /// 情報群・大当たり履歴・スワイプバー・ボタン群の間隔（すべて統一）
    private let sectionGap: CGFloat = 8

    // 30%: 現金 | 持ち玉 | カウント（トップ風グラスボタン・均等に細い隙間）。右手モード時は左右入れ替え。設定で「両方表示」オフ時は1ボタン表示
    @ViewBuilder
    private func centerActionRow(geo: GeometryProxy, height: CGFloat) -> some View {
        let investmentColumn: some View = Group {
            if alwaysShowBothInvestmentButtons {
                VStack(spacing: buttonGap) {
                    zoneButton(
                        tint: .red,
                        content: {
                            VStack(spacing: 4) {
                                Text("現金").font(.system(size: 18, weight: .bold, design: .monospaced)).foregroundColor(.red.opacity(0.95))
                                Text("500円").font(.system(size: 14, weight: .medium, design: .monospaced)).foregroundColor(.red.opacity(0.9))
                            }
                        },
                        onTap: { log.addLending(type: .cash); haptic(.medium); triggerRipple() },
                        disabled: false
                    )
                    zoneButton(
                        tint: .red,
                        content: {
                            VStack(spacing: 4) {
                                Text("持ち玉").font(.system(size: 18, weight: .bold, design: .monospaced)).foregroundColor(.red.opacity(0.95))
                                Text("125玉").font(.system(size: 14, weight: .medium, design: .monospaced)).foregroundColor(.red.opacity(0.9))
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
                    tint: .red,
                    content: {
                        VStack(spacing: 4) {
                            Text("現金").font(.system(size: 18, weight: .bold, design: .monospaced)).foregroundColor(.red.opacity(0.95))
                            Text("500円").font(.system(size: 14, weight: .medium, design: .monospaced)).foregroundColor(.red.opacity(0.9))
                        }
                    },
                    onTap: { log.addLending(type: .cash); haptic(.medium); triggerRipple() },
                    disabled: false
                )
            } else {
                zoneButton(
                    tint: .red,
                    content: {
                        VStack(spacing: 4) {
                            Text("持ち玉").font(.system(size: 18, weight: .bold, design: .monospaced)).foregroundColor(.red.opacity(0.95))
                            Text("125玉").font(.system(size: 14, weight: .medium, design: .monospaced)).foregroundColor(.red.opacity(0.9))
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

        let countButton = ZStack {
            RoundedRectangle(cornerRadius: buttonCornerRadius)
                .fill(playPanelBackground)
            RoundedRectangle(cornerRadius: buttonCornerRadius)
                .fill(focusAccent.opacity(playPanelTintOverlayOpacity))
            VStack(spacing: 4) {
                Text("\(log.gamesSinceLastWin)")
                    .font(.system(size: min(geo.size.width * 0.14, height * 0.32), weight: .black, design: .monospaced))
                    .foregroundColor(focusAccent)
                Text(log.currentState == .normal ? "タップ+1" : (log.isTimeShortMode ? "時短中" : "電サポ中"))
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(focusAccent.opacity(0.8))
            }
        }
        .overlay(RoundedRectangle(cornerRadius: buttonCornerRadius).stroke(glassStroke(tint: focusAccent), lineWidth: playPanelStrokeLineWidth))
        .contentShape(Rectangle())
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .onTapGesture { if !isBonusStandby { log.addRotations(1); hapticSoft(); triggerRipple() } }
        .onLongPressGesture(minimumDuration: 0.5) {
            tempLampValue = "\(log.gamesSinceLastWin)"
            showSyncSheet = true
            haptic(.medium)
        }

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
        tint: Color,
        @ViewBuilder content: () -> Content,
        onTap: @escaping () -> Void,
        disabled: Bool = false
    ) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: buttonCornerRadius)
                .fill(playPanelBackground)
            RoundedRectangle(cornerRadius: buttonCornerRadius)
                .fill(tint.opacity(playPanelTintOverlayOpacity))
            content()
        }
        .overlay(RoundedRectangle(cornerRadius: buttonCornerRadius).stroke(glassStroke(tint: tint), lineWidth: playPanelStrokeLineWidth))
        .contentShape(Rectangle())
        .frame(maxWidth: .infinity).frame(maxHeight: .infinity)
        .opacity(disabled ? 0.5 : 1)
        .allowsHitTesting(!disabled)
        .onTapGesture { if !disabled { onTap() } }
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
        let contentWidth = geo.size.width - horizontalMargin * 2 - bottomBarSpacing
        let rushWidth = contentWidth * 0.55
        let normalEndWidth = contentWidth * 0.45
        let bottomPadding: CGFloat = 8

        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: bottomBarSpacing) {
                if rightHandMode {
                    normalAndEndRow(width: normalEndWidth, height: barHeight, curveRadius: buttonCornerRadius)
                    rushButton(height: barHeight, curveRadius: buttonCornerRadius)
                        .frame(width: rushWidth)
                } else {
                    rushButton(height: barHeight, curveRadius: buttonCornerRadius)
                        .frame(width: rushWidth)
                    normalAndEndRow(width: normalEndWidth, height: barHeight, curveRadius: buttonCornerRadius)
                }
            }
            .frame(maxHeight: .infinity)
            .padding(.horizontal, horizontalMargin)
        }
        .frame(minHeight: barHeight)
        .frame(maxWidth: .infinity)
        .padding(.bottom, bottomPadding + geo.safeAreaInsets.bottom)
        .confirmationDialog("実戦を終了", isPresented: $showEndConfirm, titleVisibility: .visible) {
            Button("保存して終了") {
                let isEmpty = log.normalRotations == 0 && log.investment == 0
                if isEmpty {
                    showEmptySaveConfirm = true
                } else if log.totalHoldings > 0 {
                    finalHoldingsInput = "\(log.totalHoldings)"
                    showFinalHoldingsInput = true
                } else {
                    saveCurrentSession()
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
                if log.totalHoldings > 0 {
                    finalHoldingsInput = "\(log.totalHoldings)"
                    showFinalHoldingsInput = true
                } else {
                    saveCurrentSession()
                }
            }
            Button("キャンセル", role: .cancel) { showEmptySaveConfirm = false }
        } message: {
            Text("回転数・投資がありませんが保存しますか？")
        }
        .alert("回収出玉の確認", isPresented: $showFinalHoldingsInput) {
            TextField("回収出玉", text: $finalHoldingsInput)
                .keyboardType(.numberPad)
            Button("完了") {
                if let finalBalls = Int(finalHoldingsInput) {
                    if finalBalls < 0 {
                        errorMessage = "負の数は入力できません"
                        showErrorAlert = true
                        return
                    } else {
                        log.syncHoldings(actualHoldings: finalBalls)
                    }
                }
                showFinalHoldingsInput = false
                saveCurrentSession()
                dismiss()
            }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("実際の回収出玉（流した玉数）を入力してください。\nアプリ上の持ち玉（\(log.totalHoldings)玉）との差分を自動調整します。")
        }
        .alert("入力エラー", isPresented: $showErrorAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
        .alert("保存しました", isPresented: Binding(
            get: { saveResult == "ok" },
            set: { if !$0 { saveResult = nil } }
        )) {
            Button("OK") {
                saveResult = nil
                dismiss()
            }
        } message: {
            Text("実戦記録を保存しました。")
        }
        .alert("保存に失敗しました", isPresented: Binding(
            get: { saveResult.map { $0.hasPrefix("error:") } ?? false },
            set: { if !$0 { saveResult = nil } }
        )) {
            Button("OK") { saveResult = nil }
        } message: {
            if let r = saveResult, r.hasPrefix("error:") {
                Text(String(r.dropFirst(7)))
            }
        }
    }

    private func rushButton(height: CGFloat, curveRadius: CGFloat) -> some View {
        Button(action: {
            if log.selectedMachine.ltFromNormal {
                showRushLtChoiceSheet = true
            } else {
                handleWinSelection(type: .rush)
                OrganicHaptics.playRushHeartbeat()
            }
        }) {
            ZStack {
                RoundedRectangle(cornerRadius: buttonCornerRadius)
                    .fill(playPanelBackground)
                RoundedRectangle(cornerRadius: buttonCornerRadius)
                    .fill(AppGlassStyle.rushColor.opacity(playPanelTintOverlayOpacity))
                Text("RUSH")
                    .font(.system(size: 18, weight: .bold, design: .monospaced))
                    .foregroundColor(AppGlassStyle.rushColor.opacity(AppGlassStyle.rushTitleOpacity))
            }
            .frame(minHeight: height)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(RoundedRectangle(cornerRadius: buttonCornerRadius).stroke(glassStroke(tint: AppGlassStyle.rushColor), lineWidth: playPanelStrokeLineWidth))
        }
        .buttonStyle(.plain)
        .clipShape(RoundedRectangle(cornerRadius: buttonCornerRadius))
    }

    /// 通常ボタン（左2/3）と遊技終了（右1/3）を横並び
    private func normalAndEndRow(width: CGFloat, height: CGFloat, curveRadius: CGFloat) -> some View {
        HStack(spacing: bottomBarSpacing) {
            Button(action: { handleWinSelection(type: .normal); haptic(.medium) }) {
                ZStack {
                    RoundedRectangle(cornerRadius: curveRadius)
                        .fill(playPanelBackground)
                    RoundedRectangle(cornerRadius: curveRadius)
                        .fill(AppGlassStyle.normalColor.opacity(playPanelTintOverlayOpacity))
                    Text("通常\n大当たり")
                        .font(.system(size: 15, weight: .bold, design: .monospaced))
                        .foregroundColor(AppGlassStyle.normalColor.opacity(AppGlassStyle.normalTitleOpacity))
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay(RoundedRectangle(cornerRadius: curveRadius).stroke(glassStroke(tint: AppGlassStyle.normalColor), lineWidth: playPanelStrokeLineWidth))
            }
            .buttonStyle(.plain)
            .frame(width: width * 2 / 3)

            Button(action: { showEndConfirm = true; haptic(.medium) }) {
                ZStack {
                    RoundedRectangle(cornerRadius: curveRadius)
                        .fill(playPanelBackground)
                    RoundedRectangle(cornerRadius: curveRadius)
                        .fill(AppGlassStyle.rushColor.opacity(playPanelTintOverlayOpacity))
                    Text("遊技終了")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(AppGlassStyle.rushColor)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay(RoundedRectangle(cornerRadius: curveRadius).stroke(glassStroke(tint: AppGlassStyle.rushColor), lineWidth: playPanelStrokeLineWidth))
            }
            .buttonStyle(.plain)
            .frame(width: width * 1 / 3)
        }
        .frame(width: width)
        .frame(minHeight: height)
        .frame(maxHeight: .infinity)
    }

    @ViewBuilder
    private func popoverOverlays(geo: GeometryProxy) -> some View {
        EmptyView()
    }

    /// 大当たり入力シート用にログの現在値で temp をセット（通常/RUSH/省エネ共通）。当選時ゲーム数は見かけの値（時短・ST含む）
    private func prepareWinInput(type: WinType) {
        tempWinType = type
        tempWinRotation = "\(log.gamesSinceLastWin)"
        tempWinCashYen = "\(log.investment)"
        tempWinHoldingsBalls = "\(log.holdingsInvestedBalls)"
        tempWinHoldingsCount = "\(log.totalHoldings)"
    }

    private func handleWinSelection(type: WinType) {
        prepareWinInput(type: type)
        showWinInputSheet = true
    }
    // --- ヘルパー関数を PlayView 構造体の中に追加 ---
    private func saveCurrentSession() {
        // 理論期待値計算用：実質投資が0の場合は現金＋持ち玉円換算で補正（記録漏れ対策）
        let realCost = log.totalRealCost > 0
            ? log.totalRealCost
            : Double(log.investment) + Double(log.holdingsInvestedBalls) * log.selectedShop.exchangeRate
        let ratio = log.expectationRatio > 0 ? log.expectationRatio : 1.0
        let formulaBorder = parseFormulaBorder(log.selectedMachine.border)
        let session = GameSession(
            machineName: log.selectedMachine.name,
            shopName: log.selectedShop.name,
            manufacturerName: log.selectedMachine.manufacturer,
            investmentCash: log.investment,
            totalHoldings: log.totalHoldings,
            normalRotations: log.normalRotations,
            totalUsedBalls: log.totalUsedBalls,
            exchangeRate: log.selectedShop.exchangeRate,
            totalRealCost: realCost,
            expectationRatioAtSave: ratio,
            rushWinCount: log.rushWinCount,
            normalWinCount: log.normalWinCount,
            ltWinCount: log.ltWinCount,
            formulaBorderPer1k: formulaBorder > 0 ? formulaBorder : 0
        )
        modelContext.insert(session)
        ResumableStateStore.save(from: log)
        do {
            try modelContext.save()
            saveResult = "ok"
        } catch {
            saveResult = "error: \(error.localizedDescription)"
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

// MARK: - ボーダーメーター（横バー偏差表示。基準は実質ボーダー。公式・実質を横並び表示）
struct BorderMeterView: View {
    let borderForGauge: Double
    let realRate: Double
    let rotationPer1000Yen: Double
    let effectiveUnitsForBorder: Double
    let normalRotations: Int
    /// 公式ボーダー（等価・回/千円）。表示用
    let formulaBorderRaw: Double
    /// 実質ボーダー（店の交換率考慮・回/千円）。ゲージ基準
    let formulaBorderLabel: String
    let accent: Color

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

    /// 実質回転率と同じフォントサイズ（上部公式ボーダーと揃える）
    private let valueFontSize: CGFloat = 14

    var body: some View {
        GeometryReader { g in
            let W = g.size.width
            let H = g.size.height
            let pad: CGFloat = 14
            let barHeight: CGFloat = 20
            let tickHeight: CGFloat = 8

            VStack(spacing: 0) {
                // 横バーの上：公式ボーダーと実質ボーダーを横並び（ゲージ基準は実質）
                HStack(spacing: 12) {
                    VStack(spacing: 2) {
                        Text("公式")
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundColor(.white.opacity(0.8))
                        Text(formulaBorderRaw > 0 ? String(format: "%.1f", formulaBorderRaw) : "—")
                            .font(.system(size: valueFontSize, weight: .bold, design: .monospaced))
                            .foregroundColor(.white)
                    }
                    .frame(maxWidth: .infinity)
                    VStack(spacing: 2) {
                        Text("実質")
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundColor(.white.opacity(0.8))
                        Text(formulaBorderLabel)
                            .font(.system(size: valueFontSize, weight: .bold, design: .monospaced))
                            .foregroundColor(accent)
                    }
                    .frame(maxWidth: .infinity)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 6)

                // 横バー（幅は barW で固定し pad で中央寄せ。上下中央に配置）
                GeometryReader { barGeo in
                    let barW = barGeo.size.width - pad * 2
                    let barX0 = pad
                    VStack(spacing: 0) {
                        Spacer(minLength: 0)
                        // バー＋目盛＋マーカーを barGeo 幅に収め、バーは barW 幅で中央に配置
                        ZStack {
                            // バートラック：明示幅 barW で中央に配置（.padding で幅を膨らませない）
                            HStack(spacing: 0) {
                                Spacer(minLength: 0)
                                    .frame(width: pad)
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color.white.opacity(0.08))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6)
                                            .strokeBorder(Color.white.opacity(0.22), lineWidth: 1)
                                    )
                                    .frame(width: barW, height: barHeight)
                                Spacer(minLength: 0)
                                    .frame(width: pad)
                            }
                            .frame(width: barGeo.size.width)
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
                                    .frame(width: isZero ? 1.2 : 0.8, height: tickHeight)
                                    .position(x: xVal, y: barHeight + tickHeight / 2)
                            }
                            // マーカー
                            DownTriangle()
                                .fill(markerColor)
                                .overlay(DownTriangle().stroke(Color.white.opacity(0.4), lineWidth: 0.8))
                                .frame(width: 12, height: 16)
                                .position(x: barX0 + CGFloat((clampedDiffForMarker + 5) / 10) * barW, y: barHeight / 2 + 1)
                        }
                        .frame(width: barGeo.size.width, height: barHeight + tickHeight)
                        // -5 / ±0 / +5（バー幅に合わせて中央に配置）
                        HStack(spacing: 0) {
                            Spacer(minLength: 0)
                                .frame(width: pad)
                            HStack(spacing: 0) {
                                Text("-5")
                                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                                    .foregroundColor(.red.opacity(0.9))
                                    .frame(width: barW / 10, alignment: .leading)
                                Spacer(minLength: 0)
                                Text("±0")
                                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                                    .foregroundColor(.white)
                                Spacer(minLength: 0)
                                Text("+5")
                                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                                    .foregroundColor(.blue.opacity(0.9))
                                    .frame(width: barW / 10, alignment: .trailing)
                            }
                            .frame(width: barW)
                            Spacer(minLength: 0)
                                .frame(width: pad)
                        }
                        .frame(width: barGeo.size.width)
                        .padding(.top, 4)
                        Spacer(minLength: 0)
                    }
                    .frame(width: barGeo.size.width, height: barGeo.size.height)
                }
                .frame(minHeight: 58)
                .frame(maxHeight: .infinity)

                // 横バーの下：実質回転率・表面回転率の2種（表面はやや控えめ）
                VStack(spacing: 4) {
                    HStack(spacing: 6) {
                        Text("実質回転率")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundColor(.white.opacity(0.85))
                        Text(gaugeEnabled ? String(format: "%.1f", realRate) : "\(normalRotations)")
                            .font(.system(size: valueFontSize, weight: .bold, design: .monospaced))
                            .foregroundColor(markerColor)
                    }
                    HStack(spacing: 6) {
                        Text("表面回転率")
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundColor(.white.opacity(0.6))
                        Text(gaugeEnabled && rotationPer1000Yen > 0 ? String(format: "%.1f", rotationPer1000Yen) : "—")
                            .font(.system(size: 12, weight: .regular, design: .monospaced))
                            .foregroundColor(.white.opacity(0.65))
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
            }
            .frame(width: W, height: H)
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

// MARK: - 大当たり履歴（棒グラフ：左＝最新、0回転の位置に横線、ラベルは常に左上）
struct WinHistoryBarChartView: View {
    let records: [WinRecord]
    var maxHeight: CGFloat? = nil

    private let defaultBarHeight: CGFloat = 56
    private let barWidth: CGFloat = 10
    private let barSpacing: CGFloat = 8
    private let rushColor = Color.red
    private let normalColor = Color.blue

    private var maxRotation: Int {
        records.map(\.rotationAtWin).max() ?? 1
    }

    private var orderedRecords: [WinRecord] {
        Array(records.reversed())
    }

    private var effectiveBarHeight: CGFloat {
        guard let h = maxHeight, h > 0 else { return defaultBarHeight }
        let forBars = h - 28
        return min(defaultBarHeight, max(20, forBars))
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .bottom, spacing: barSpacing) {
                    ForEach(orderedRecords) { record in
                        singleBar(record: record)
                    }
                }
                .padding(.horizontal, 4)
                .padding(.top, 20)
                .padding(.bottom, 4)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(Color.white.opacity(0.18))
                        .frame(height: 1)
                        .padding(.bottom, 16)
                        .padding(.horizontal, 4)
                }
            }
            .frame(maxWidth: .infinity)
            Text("大当たり履歴")
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundColor(.white.opacity(0.7))
                .padding(8)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .allowsHitTesting(false)
        }
        .frame(maxWidth: .infinity)
        .frame(height: maxHeight)
    }

    private var ltColor: Color { AppGlassStyle.ltColor }

    private func singleBar(record: WinRecord) -> some View {
        let color: Color = record.type == .rush ? rushColor : (record.type == .lt ? ltColor : normalColor)
        let ratio = maxRotation > 0 ? CGFloat(record.rotationAtWin) / CGFloat(maxRotation) : 0
        let height = ratio * effectiveBarHeight

        return VStack(alignment: .center, spacing: 2) {
            Spacer(minLength: 0)
            RoundedRectangle(cornerRadius: 2)
                .fill(color.opacity(0.9))
                .frame(width: barWidth, height: max(3, height))
            Text("\(record.rotationAtWin)")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundColor(color)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(width: barWidth + 4, height: effectiveBarHeight + 16)
    }
}

/// 大当たり入力：ボーナス種類（heso_prizes/denchu_prizes または prizeEntries）を動的表示 → 回転数 → 確定。
/// P-Sync 対応：通常時は heso_prizes をカンマ区切りでパースしてボタン生成し、"RUSH"/"通常" で遷移種別を自動分岐。RUSH時は denchu_prizes で「天国」「上乗せ」を強調。
struct WinInputSheetView: View {
    let machine: Machine
    let winType: WinType
    @Binding var rotation: String
    @Binding var cashYen: String
    @Binding var holdingsBalls: String
    @Binding var holdingsCount: String
    /// 確定時: (選択したボーナスの純増, 実際の種別)。heso で選んだボタンが RUSH/通常 を決める。nil の場合は機種デフォルト。
    var onConfirm: (Int?, WinType) -> Void
    var onCancel: () -> Void

    private let accent = AppGlassStyle.accent
    private let panelBg = Color.black.opacity(0.75)
    private let panelBgSelected = Color.black.opacity(0.85)

    @State private var selectedPrizeIndex: Int = 0
    @State private var showExtraFields = false
    @State private var showErrorAlert = false
    @State private var errorMessage = ""

    /// 通常時: heso_prizes が空でなければパース結果、否则 prizeEntries
    private var hesoItems: [ParsedHesoItem] {
        let raw = machine.heso_prizes.trimmingCharacters(in: .whitespaces)
        guard !raw.isEmpty else { return [] }
        return PrizeStringParser.parseHesoPrizes(raw)
    }

    /// RUSH時: denchu_prizes が空でなければパース結果、否则 prizeEntries
    private var denchuItems: [ParsedDenchuItem] {
        let raw = machine.denchu_prizes.trimmingCharacters(in: .whitespaces)
        guard !raw.isEmpty else { return [] }
        return PrizeStringParser.parseDenchuPrizes(raw)
    }

    private var prizeEntries: [MachinePrize] {
        machine.prizeEntries
    }

    /// 通常時で heso が有効なとき true
    private var useHesoDynamic: Bool {
        winType == .normal && !hesoItems.isEmpty
    }

    /// RUSH時で denchu が有効なとき true
    private var useDenchuDynamic: Bool {
        winType == .rush && !denchuItems.isEmpty
    }

    /// LT時：denchu のうち「天国」「LT」等（isSpecial）のみ
    private var ltItems: [ParsedDenchuItem] {
        denchuItems.filter { $0.isSpecial }
    }
    private var useLtDynamic: Bool {
        winType == .lt && !ltItems.isEmpty
    }

    /// 動的ボタンも従来ボタンもないとき → カスタム当たり追加フォールバック
    private var useCustomFallback: Bool {
        if useHesoDynamic || useDenchuDynamic || useLtDynamic { return false }
        if !prizeEntries.isEmpty { return false }
        return true
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // ヘッダー：タイトル＋キャンセル（コンパクト）
            HStack {
                Text(winType == .lt ? "LT大当たり" : (winType == .rush ? "RUSH大当たり" : "通常大当たり"))
                    .font(.title3.weight(.bold))
                    .foregroundColor(.white)
                Spacer()
                Button("キャンセル") { onCancel() }
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(accent)
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 8)

            Spacer(minLength: 0)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    // 1. ボーナス種類（動的 or 従来 or カスタムフォールバック）
                    VStack(alignment: .leading, spacing: 8) {
                        Text("ボーナス種類")
                            .font(.headline.weight(.semibold))
                            .foregroundColor(.white.opacity(0.9))
                        if useHesoDynamic {
                            VStack(spacing: 8) {
                                ForEach(Array(hesoItems.enumerated()), id: \.element.id) { index, item in
                                    hesoPrizeButton(item: item, isSelected: index == selectedPrizeIndex) {
                                        selectedPrizeIndex = index
                                    }
                                }
                            }
                        } else if useDenchuDynamic {
                            VStack(spacing: 8) {
                                ForEach(Array(denchuItems.enumerated()), id: \.element.id) { index, item in
                                    denchuPrizeButton(item: item, isSelected: index == selectedPrizeIndex) {
                                        selectedPrizeIndex = index
                                    }
                                }
                            }
                        } else if useLtDynamic {
                            VStack(spacing: 8) {
                                ForEach(Array(ltItems.enumerated()), id: \.element.id) { index, item in
                                    denchuPrizeButton(item: item, isSelected: index == selectedPrizeIndex) {
                                        selectedPrizeIndex = index
                                    }
                                }
                            }
                        } else if !prizeEntries.isEmpty {
                            VStack(spacing: 8) {
                                ForEach(Array(prizeEntries.enumerated()), id: \.element.persistentModelID) { index, entry in
                                    prizePanel(entry: entry, isSelected: index == selectedPrizeIndex) {
                                        selectedPrizeIndex = index
                                    }
                                }
                            }
                        } else {
                            // データが空・取得できなかった場合のフォールバック
                            customFallbackLabel()
                        }
                    }

                    // 2. 大当たり時の回転数（デフォルトで現在の回転数が入力済み）
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 4) {
                            Text("大当たり時の回転数")
                                .font(.headline.weight(.semibold))
                                .foregroundColor(.white.opacity(0.9))
                            InfoIconView(explanation: "前回の大当たりからこの大当たりまでのゲーム数（見かけ）。時短・電サポ中も含めた台の表示に合わせて入力。", tint: .white.opacity(0.6))
                        }
                        TextField("回転数", text: $rotation)
                            .keyboardType(.numberPad)
                            .font(.system(size: 18, weight: .semibold, design: .monospaced))
                            .foregroundColor(.white)
                            .padding(.vertical, 12)
                            .padding(.horizontal, 14)
                            .background(panelBg)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(AppGlassStyle.strokeGradient, lineWidth: 1))
                    }

                    // 投資額・持ち玉（折りたたみ）
                    DisclosureGroup(isExpanded: $showExtraFields) {
                        VStack(spacing: 10) {
                            labeledField("投資額（現金）円", text: $cashYen)
                            labeledField("投資額（持ち玉）玉", text: $holdingsBalls)
                            labeledField("持ち玉数", text: $holdingsCount)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(panelBg)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    } label: {
                        Text("投資・持ち玉を変更")
                            .font(.subheadline.weight(.medium))
                            .foregroundColor(.white.opacity(0.7))
                    }
                    .tint(accent)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 8)
            }
            .frame(maxHeight: 220)

            // 3. 確定ボタン（最下部・操作性のため下詰め）
            Button(action: confirmAction) {
                Text("確定")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(accent)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(LinearGradient(colors: [.white.opacity(0.4), accent.opacity(0.3)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 20)
        }
        .background(AppGlassStyle.background)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.white.opacity(0.15), lineWidth: 1))
        .keyboardDismissToolbar()
        .alert("入力エラー", isPresented: $showErrorAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
    }

    private func hesoPrizeButton(item: ParsedHesoItem, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(item.displayLabel)
                .font(.system(size: 15, weight: .semibold, design: .monospaced))
                .foregroundColor(isSelected ? accent : .white.opacity(0.9))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .padding(.horizontal, 12)
                .background(isSelected ? panelBgSelected : panelBg)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(isSelected ? accent : Color.white.opacity(0.2), lineWidth: isSelected ? 2 : 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    private func denchuPrizeButton(item: ParsedDenchuItem, isSelected: Bool, action: @escaping () -> Void) -> some View {
        let highlightColor: Color = item.isSpecial ? .orange : accent
        return Button(action: action) {
            Text(item.displayLabel)
                .font(.system(size: 15, weight: .semibold, design: .monospaced))
                .foregroundColor(isSelected ? highlightColor : (item.isSpecial ? Color.orange.opacity(0.95) : .white.opacity(0.9)))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .padding(.horizontal, 12)
                .background(isSelected ? panelBgSelected : panelBg)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(isSelected ? highlightColor : (item.isSpecial ? Color.orange.opacity(0.6) : Color.white.opacity(0.2)), lineWidth: isSelected ? 2 : 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func customFallbackLabel() -> some View {
        Text("カスタム当たり追加（機種デフォルトで記録）")
            .font(.caption)
            .foregroundColor(.white.opacity(0.6))
            .padding(.vertical, 6)
    }

    private func prizePanel(entry: MachinePrize, isSelected: Bool, action: @escaping () -> Void) -> some View {
        let displayText = "\(entry.rounds)R  \(entry.balls)発"
        return Button(action: action) {
            Text(displayText)
                .font(.system(size: 15, weight: .semibold, design: .monospaced))
                .foregroundColor(isSelected ? accent : .white.opacity(0.9))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .padding(.horizontal, 12)
                .background(isSelected ? panelBgSelected : panelBg)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(isSelected ? accent : Color.white.opacity(0.2), lineWidth: isSelected ? 2 : 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    private func labeledField(_ label: String, text: Binding<String>) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundColor(.white.opacity(0.65))
                .frame(width: 140, alignment: .leading)
            TextField("", text: text)
                .keyboardType(.numberPad)
                .font(.system(size: 16, weight: .medium, design: .monospaced))
                .foregroundColor(.white)
                .multilineTextAlignment(.trailing)
        }
    }

    private func confirmAction() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        if rotation.trimmingCharacters(in: .whitespaces).isEmpty {
            errorMessage = "回転数を入力してください"
            showErrorAlert = true
            return
        }

        let rot = Int(rotation) ?? 0
        let cash = Int(cashYen) ?? 0
        let hBalls = Int(holdingsBalls) ?? 0
        let hCount = Int(holdingsCount) ?? 0

        if rot < 0 || cash < 0 || hBalls < 0 || hCount < 0 {
            errorMessage = "負の数は入力できません"
            showErrorAlert = true
            return
        }

        var prizeBalls: Int? = nil
        var resolvedWinType: WinType = winType

        if useHesoDynamic, selectedPrizeIndex < hesoItems.count {
            let item = hesoItems[selectedPrizeIndex]
            resolvedWinType = item.winType
            let r = item.rounds ?? machine.defaultRoundsPerHit
            let b = item.balls ?? machine.defaultPrize
            prizeBalls = machine.netBallsForPrize(rounds: r, payoutBalls: b)
        } else if useDenchuDynamic, selectedPrizeIndex < denchuItems.count {
            let item = denchuItems[selectedPrizeIndex]
            let r = item.rounds ?? machine.defaultRoundsPerHit
            let b = item.balls ?? machine.defaultPrize
            prizeBalls = machine.netBallsForPrize(rounds: r, payoutBalls: b)
        } else if useLtDynamic, selectedPrizeIndex < ltItems.count {
            resolvedWinType = .lt
            let item = ltItems[selectedPrizeIndex]
            let r = item.rounds ?? machine.defaultRoundsPerHit
            let b = item.balls ?? machine.defaultPrize
            prizeBalls = machine.netBallsForPrize(rounds: r, payoutBalls: b)
        } else if !prizeEntries.isEmpty, selectedPrizeIndex < prizeEntries.count {
            let entry = prizeEntries[selectedPrizeIndex]
            prizeBalls = machine.netBallsForPrize(rounds: entry.rounds, payoutBalls: entry.balls)
        }
        onConfirm(prizeBalls, resolvedWinType)
    }
}

struct SyncInputView: View {
    let title: String; let label: String; @Binding var val: String
    var focus: FocusState<PlayView.FocusField?>.Binding; let fieldType: PlayView.FocusField; var onConfirm: () -> Void
    @State private var showErrorAlert = false
    var body: some View {
        VStack(spacing: 20) {
            Text(title).bold(); Text(label).font(.caption).foregroundColor(.gray)
            TextField("", text: $val).keyboardType(.numberPad).textFieldStyle(.roundedBorder).multilineTextAlignment(.center).font(.largeTitle).focused(focus, equals: fieldType)
            Button("確定") {
                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
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
        .keyboardDismissToolbar()
        .onAppear { DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { focus.wrappedValue = fieldType } }
        .presentationDetents([.height(280)])
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
    var body: some View {
        VStack(spacing: 20) {
            Text("大当たり回数を修正")
                .font(.headline)
            VStack(alignment: .leading, spacing: 4) {
                Text("RUSH 大当たり回数")
                    .font(.caption)
                    .foregroundColor(.secondary)
                TextField("0", text: $rushCount)
                    .keyboardType(.numberPad)
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.center)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("通常大当たり回数")
                    .font(.caption)
                    .foregroundColor(.secondary)
                TextField("0", text: $normalCount)
                    .keyboardType(.numberPad)
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.center)
            }
            Button("確定") {
                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                if let r = Int(rushCount), r < 0 {
                    showErrorAlert = true
                    return
                }
                if let n = Int(normalCount), n < 0 {
                    showErrorAlert = true
                    return
                }
                onConfirm()
            }
            .buttonStyle(.borderedProminent)
            Spacer()
        }
        .padding()
        .keyboardDismissToolbar()
        .presentationDetents([.height(320)])
        .alert("入力エラー", isPresented: $showErrorAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("負の数は入力できません")
        }
    }
}

import SwiftUI
import SwiftData
import UIKit

/// 遊技開始ゲート用：店舗・機種が未選択のときは遊技開始できない
struct MachineShopSelectionView: View {
    @Bindable var log: GameLog
    /// true のとき「遊技開始」「キャンセル」を表示し、決定時は onGateStart / onGateCancel を呼ぶ
    var gateMode: Bool = false
    var onGateStart: (() -> Void)? = nil
    var onGateCancel: (() -> Void)? = nil
    /// 実戦画面のシートから開いたとき true（左上に「実戦へ戻る」）
    var presentedFromPlaySession: Bool = false

    @Environment(\.dismiss) var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var themeManager: ThemeManager

    private var t: any ApplicationTheme { themeManager.currentTheme }

    @Query(sort: \Machine.name) private var savedMachines: [Machine]
    @Query(sort: \Shop.name) private var savedShops: [Shop]
    @Query(sort: \GameSession.date, order: .reverse) private var recentSessions: [GameSession]

    @State private var machineToEdit: Machine?
    @State private var showNewMachineSheet = false
    @State private var shopToEdit: Shop?
    @State private var showNewShopSheet = false
    @State private var showMasterSearch = false
    @State private var showErrorAlert = false
    @State private var errorMessage = ""
    /// 新規開始時：台・ランプの現在回転数（ゲート時のみ使用）
    @State private var initialRotationText = ""
    /// 開始回転パネル全体タップでテンキーを出す
    @State private var rotationFieldFocusTrigger = 0
    /// 持ち玉欄のテンキーを開く／前項目からのフォーカス移動用
    @State private var holdingsFieldFocusTrigger = 0
    /// 新規開始時：貯玉で開始する場合の持ち玉数（ゲート時のみ使用）
    @State private var initialHoldingsText = ""
    @AppStorage(UserDefaultsKey.initialHoldingsGatePolicy.rawValue) private var initialHoldingsGatePolicyRaw: String = InitialHoldingsGatePolicy.manual.rawValue

    /// 選択中の機種が登録一覧に含まれるか
    private var isSelectedMachineValid: Bool {
        !savedMachines.isEmpty && savedMachines.contains { $0.persistentModelID == log.selectedMachine.persistentModelID }
    }
    /// 選択中の店舗が登録一覧に含まれるか
    private var isSelectedShopValid: Bool {
        !savedShops.isEmpty && savedShops.contains { $0.persistentModelID == log.selectedShop.persistentModelID }
    }
    /// 開始時の台表示数が有効（0以上の数値が入力済み）
    private var hasValidInitialRotation: Bool {
        let s = initialRotationText.trimmingCharacters(in: .whitespaces)
        guard !s.isEmpty, let n = Int(s) else { return false }
        return n >= 0
    }
    
    /// 持ち玉が有効（空または0以上の数値）
    private var hasValidInitialHoldings: Bool {
        let s = initialHoldingsText.trimmingCharacters(in: .whitespaces)
        if s.isEmpty { return true }
        if let n = Int(s), n >= 0 { return true }
        return false
    }

    /// 機種選択用。初期・マイリスト閲覧時は未選択可。gateMode時は必須
    private var machineSelection: Binding<Machine?> {
        Binding(
            get: {
                if isSelectedMachineValid { return log.selectedMachine }
                return nil
            },
            set: {
                if let m = $0 {
                    log.selectedMachine = m
                } else {
                    log.selectedMachine = Machine(name: "未選択", supportLimit: 100, defaultPrize: 1500)
                }
            }
        )
    }
    private var shopSelection: Binding<Shop?> {
        Binding(
            get: {
                if isSelectedShopValid { return log.selectedShop }
                return nil
            },
            set: {
                if let s = $0 {
                    log.selectedShop = s
                } else {
                    log.selectedShop = Shop(
                        name: "未選択",
                        ballsPerCashUnit: PersistedDataSemantics.defaultBallsPer500Pt,
                        payoutCoefficient: PersistedDataSemantics.defaultPayoutCoefficientPtPerBall
                    )
                }
            }
        )
    }

    private var accent: Color { t.accentColor }

    /// 実戦で最近使った順の機種（新しい順）
    private var sortedMachines: [Machine] {
        let order = recentSessions.reduce(into: [(name: String, date: Date)]()) { acc, s in
            let n = s.machineName.isEmpty ? "未設定" : s.machineName
            if !acc.contains(where: { $0.name == n }) { acc.append((n, s.date)) }
        }
        let names = order.map(\.name)
        return savedMachines.sorted { m1, m2 in
            let i1 = names.firstIndex(of: m1.name) ?? names.count
            let i2 = names.firstIndex(of: m2.name) ?? names.count
            if i1 != i2 { return i1 < i2 }
            return m1.name < m2.name
        }
    }
    /// 実戦で最近使った順の店舗（新しい順）
    private var sortedShops: [Shop] {
        let order = recentSessions.reduce(into: [(name: String, date: Date)]()) { acc, s in
            let n = s.shopName.isEmpty ? "未設定" : s.shopName
            if !acc.contains(where: { $0.name == n }) { acc.append((n, s.date)) }
        }
        let names = order.map(\.name)
        return savedShops.sorted { s1, s2 in
            let i1 = names.firstIndex(of: s1.name) ?? names.count
            let i2 = names.firstIndex(of: s2.name) ?? names.count
            if i1 != i2 { return i1 < i2 }
            return s1.name < s2.name
        }
    }

    /// パネル共通：セクション見出し（`AppTypography.panelHeading` に統一）
    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(AppTypography.panelHeading)
            .foregroundColor(t.mainTextColor.opacity(0.96))
    }

    /// パネル共通：グラスカード（インサイト・収支パネルと同じスタイル）
    private func glassCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppGlassStyle.rowBackground, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(accent.opacity(0.2), lineWidth: 1))
    }

    /// ゲート用：選択可能な1行カード（タップで選択・チェックマーク表示）
    private func gateSelectRow(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: 10) {
                Text(title)
                    .font(AppTypography.bodyRounded)
                    .foregroundColor(t.mainTextColor)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(accent)
                }
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 16)
            .background(isSelected ? accent.opacity(0.18) : t.formCanvasMutedBackground, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(isSelected ? accent.opacity(0.5) : t.hairlineDividerColor, lineWidth: isSelected ? 1.5 : 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: - ゲートモード（新規遊技）：機種 → 店舗 → 回転数 → 持ち玉 → 遊技開始（外側はスクロールなし・高さは比率配分）
    private var gateModeContent: some View {
        GeometryReader { outerGeo in
            let h = outerGeo.size.height
            let topPad: CGFloat = 8
            let bottomPad: CGFloat = 8
            let gapCount: CGFloat = 4
            let gap = max(6, min(12, h * 0.012))
            let gapTotal = gap * gapCount
            let contentH = max(120, h - topPad - bottomPad - gapTotal)
            let mH = contentH * 0.34
            let sH = contentH * 0.29
            let rH = contentH * 0.12
            let hH = contentH * 0.10
            let bH = contentH * 0.15

            VStack(spacing: gap) {
                gateMachineSection(height: mH)
                gateShopSection(height: sH)
                gateRotationSection(height: rH)
                gateHoldingsSection(height: hH)
                gateStartButtonArea(height: bH)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.horizontal, 16)
            .padding(.top, topPad)
            .padding(.bottom, bottomPad)
        }
        .onAppear {
            applyInitialHoldingsForGate()
        }
        .onChange(of: log.selectedShop.persistentModelID) { _, _ in
            applyInitialHoldingsForGate()
        }
        .onChange(of: log.selectedShop.supportsChodamaService) { _, _ in
            applyInitialHoldingsForGate()
        }
        .onChange(of: log.selectedShop.chodamaBalanceBalls) { _, _ in
            applyInitialHoldingsForGate()
        }
        .onChange(of: initialHoldingsGatePolicyRaw) { _, _ in
            applyInitialHoldingsForGate()
        }
    }

    /// 開始時の持ち玉欄を埋める。貯玉対応店では **常に** 店の貯玉残高（0 含む）を反映。それ以外は設定の `InitialHoldingsGatePolicy` に従う。
    private func applyInitialHoldingsForGate() {
        InitialHoldingsGatePolicy.migrateFromLegacyIfNeeded()
        let shop = log.selectedShop
        if shop.supportsChodamaService {
            initialHoldingsText = "\(max(0, shop.chodamaBalanceBalls))"
            return
        }
        guard let policy = InitialHoldingsGatePolicy(rawValue: initialHoldingsGatePolicyRaw) else {
            initialHoldingsText = ""
            return
        }
        initialHoldingsText = policy.initialText(for: shop)
    }

    private func gateMachineSection(height: CGFloat) -> some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .center, spacing: 8) {
                    sectionTitle("機種")
                    Spacer(minLength: 4)
                    NavigationLink {
                        MyListMachinesView(log: log)
                    } label: {
                        Image(systemName: "list.bullet.rectangle")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(accent)
                            .frame(width: 36, height: 36)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("機種マイリストの編集")
                }
                if savedMachines.isEmpty {
                    HStack {
                        Text("機種がありません")
                            .font(AppTypography.bodyRounded)
                            .foregroundColor(t.mainTextColor.opacity(0.92))
                        Spacer()
                        Button(action: { showNewMachineSheet = true }) {
                            HStack(spacing: 6) {
                                Image(systemName: "plus.circle.fill")
                                    .font(.subheadline)
                                Text("追加")
                                    .font(AppTypography.bodyRounded)
                                    .fontWeight(.semibold)
                            }
                            .foregroundColor(accent)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                        }
                        .buttonStyle(.plain)
                    }
                } else {
                    VStack(spacing: 8) {
                        ForEach(sortedMachines) { m in
                            gateSelectRow(
                                title: m.name,
                                isSelected: log.selectedMachine.persistentModelID == m.persistentModelID
                            ) {
                                log.selectedMachine = m
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .background(AppGlassStyle.rowBackground, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(accent.opacity(0.2), lineWidth: 1))
    }

    private func gateShopSection(height: CGFloat) -> some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .center, spacing: 8) {
                    sectionTitle("店舗")
                    Spacer(minLength: 4)
                    NavigationLink {
                        MyListShopsView(log: log)
                    } label: {
                        Image(systemName: "list.bullet.rectangle")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(accent)
                            .frame(width: 36, height: 36)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("店舗マイリストの編集")
                }
                if savedShops.isEmpty {
                    HStack {
                        Text("店舗がありません")
                            .font(AppTypography.bodyRounded)
                            .foregroundColor(t.mainTextColor.opacity(0.92))
                        Spacer()
                        Button(action: { showNewShopSheet = true }) {
                            HStack(spacing: 6) {
                                Image(systemName: "plus.circle.fill")
                                    .font(.subheadline)
                                Text("追加")
                                    .font(AppTypography.bodyRounded)
                                    .fontWeight(.semibold)
                            }
                            .foregroundColor(accent)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                        }
                        .buttonStyle(.plain)
                    }
                } else {
                    VStack(spacing: 8) {
                        ForEach(sortedShops) { s in
                            gateSelectRow(
                                title: s.name,
                                isSelected: log.selectedShop.persistentModelID == s.persistentModelID
                            ) {
                                log.selectedShop = s
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .background(AppGlassStyle.rowBackground, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(accent.opacity(0.2), lineWidth: 1))
    }

    private func gateRotationSection(height: CGFloat) -> some View {
        /// 最大4桁のみ。等幅16pt＋`adjustsFontSizeToFitWidth` で桁に見合う狭い列幅
        let rotationFieldWidth: CGFloat = 52
        return HStack(alignment: .center, spacing: 6) {
            Button {
                rotationFieldFocusTrigger += 1
            } label: {
                HStack(spacing: 4) {
                    Text("開始時の回転数")
                        .foregroundColor(t.mainTextColor.opacity(0.96))
                    Text("（必須）")
                        .foregroundColor(.red)
                        .fixedSize(horizontal: true, vertical: false)
                }
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .layoutPriority(1)
            Spacer(minLength: 2)
                .frame(minHeight: 36)
                .contentShape(Rectangle())
                .onTapGesture { rotationFieldFocusTrigger += 1 }
            IntegerPadTextField(
                text: $initialRotationText,
                placeholder: "",
                maxDigits: 4,
                font: .monospacedSystemFont(ofSize: 16, weight: .semibold),
                textColor: UIColor(t.mainTextColor),
                accentColor: UIColor(accent),
                focusTrigger: rotationFieldFocusTrigger,
                adjustsFontSizeToFitWidth: true,
                minimumFontSize: 11,
                onPreviousField: nil,
                onNextField: { holdingsFieldFocusTrigger += 1 },
                fieldNavFixedArrows: true,
                prevNavEnabled: false,
                nextNavEnabled: true
            )
            .frame(width: rotationFieldWidth, alignment: .trailing)
            .layoutPriority(2)
            InfoIconView(explanation: "遊技開始時点のデータランプに表示された回転数を入力してください。見出し・余白をタップしてもテンキーを開けます。", tint: accent.opacity(0.6))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .frame(minHeight: max(height, 56))
        .background(AppGlassStyle.rowBackground, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(accent.opacity(0.2), lineWidth: 1))
    }

    private func gateHoldingsSection(height: CGFloat) -> some View {
        HStack(alignment: .center, spacing: 6) {
            Text("開始時の持ち玉")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(t.mainTextColor.opacity(0.96))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .layoutPriority(1)
            Spacer(minLength: 4)
            IntegerPadTextField(
                text: $initialHoldingsText,
                placeholder: "",
                maxDigits: 5,
                font: .monospacedSystemFont(ofSize: 17, weight: .semibold),
                textColor: UIColor(t.mainTextColor),
                accentColor: UIColor(accent),
                focusTrigger: holdingsFieldFocusTrigger,
                onPreviousField: { rotationFieldFocusTrigger += 1 },
                onNextField: nil,
                fieldNavFixedArrows: true,
                prevNavEnabled: true,
                nextNavEnabled: false
            )
            .frame(width: 88, alignment: .trailing)
            InfoIconView(explanation: "この実戦の開始時点の持ち玉です。遊技中は持ち玉投資で減り、大当たりの出玉で増えます。店舗で貯玉サービスをオンにしている店を選ぶと、記録されている貯玉残高が自動で入ります（必要なら編集できます）。貯玉を使わない店では、設定の「新規遊技開始時の持ち玉の初期表示」に従います。", tint: accent.opacity(0.6))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .background(AppGlassStyle.rowBackground, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(accent.opacity(0.2), lineWidth: 1))
    }

    private func gateStartButtonArea(height: CGFloat) -> some View {
        let canStart = isSelectedMachineValid && isSelectedShopValid && hasValidInitialRotation && hasValidInitialHoldings
        let gateDisabledReason: String? = {
            if !isSelectedMachineValid { return "機種を選択してください" }
            if !isSelectedShopValid { return "店舗を選択してください" }
            if !hasValidInitialRotation { return "開始時の回転数を入力してください" }
            if !hasValidInitialHoldings { return "持ち玉は0以上の数値で入力してください" }
            return nil
        }()
        return VStack(spacing: 6) {
            if !canStart, let reason = gateDisabledReason {
                Text(reason)
                    .font(AppTypography.annotationMedium)
                    .foregroundColor(t.subTextColor.opacity(0.92))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
            Button {
                let n = Int(initialRotationText.trimmingCharacters(in: .whitespaces)) ?? 0
                if n < 0 {
                    errorMessage = "負の数は入力できません"
                    showErrorAlert = true
                    return
                }
                log.setInitialDisplayRotation(max(0, n))
                let holdings = Int(initialHoldingsText.trimmingCharacters(in: .whitespaces)) ?? 0
                if holdings < 0 {
                    errorMessage = "負の数は入力できません"
                    showErrorAlert = true
                    return
                }
                log.initialHoldings = max(0, holdings)
                log.slumpChartChodamaCarryInBalls = log.selectedShop.supportsChodamaService ? max(0, holdings) : 0
                onGateStart?()
            } label: {
                Text("遊技開始")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundColor(t.mainTextColor)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.horizontal, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(canStart ? accent : accent.opacity(0.35))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(
                                LinearGradient(
                                    colors: [
                                        t.chromeSheetBorderColor.opacity(canStart ? 1.0 : 0.55),
                                        accent.opacity(canStart ? 0.3 : 0.15),
                                        t.formCanvasMutedBackground
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    )
            }
            .disabled(!canStart)
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)
            .frame(maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .alert(isPresented: $showErrorAlert) {
            Alert(title: Text("エラー"), message: Text(errorMessage), dismissButton: .default(Text("閉じる")))
        }
    }

    // MARK: - マイリストモード
    private var myListContent: some View {
        List {
            Section {
                if savedMachines.isEmpty {
                    Label("機種がありません", systemImage: "tray")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .listRowBackground(AppGlassStyle.rowBackground)
                } else {
                    Picker("機種", selection: machineSelection) {
                        Text("— 選択なし")
                            .tag(nil as Machine?)
                        ForEach(sortedMachines) { m in
                            Text(m.name).tag(m as Machine?)
                        }
                    }
                    .listRowBackground(AppGlassStyle.rowBackground)
                    .tint(accent)

                    if isSelectedMachineValid {
                        Button {
                            machineToEdit = log.selectedMachine
                        } label: {
                            Label("この機種を編集", systemImage: "pencil")
                                .foregroundColor(accent)
                        }
                        .listRowBackground(AppGlassStyle.rowBackground)
                    }
                }

                HStack(spacing: 10) {
                    Button { showMasterSearch = true } label: {
                        Label("マスタ検索", systemImage: "magnifyingglass")
                            .font(.subheadline.weight(.medium))
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(accent.opacity(0.85))

                    Button { showNewMachineSheet = true } label: {
                        Label("新規登録", systemImage: "plus.circle.fill")
                            .font(.subheadline.weight(.medium))
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(accent.opacity(0.85))

                    NavigationLink(destination: MyListMachinesView(log: log)) {
                        HStack(spacing: 4) {
                            Text("一覧")
                            Text("\(savedMachines.count)")
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(accent)
                        }
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    }
                    .foregroundColor(t.mainTextColor)
                }
                .listRowBackground(AppGlassStyle.rowBackground)
                .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
            } header: {
                Text("機種")
                    .font(AppTypography.panelHeading)
                    .foregroundColor(t.mainTextColor.opacity(0.96))
            }

            Section {
                if savedShops.isEmpty {
                    Label("店舗がありません", systemImage: "tray")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .listRowBackground(AppGlassStyle.rowBackground)
                } else {
                    Picker("店舗", selection: shopSelection) {
                        Text("— 選択なし")
                            .tag(nil as Shop?)
                        ForEach(sortedShops) { s in
                            Text(s.name).tag(s as Shop?)
                        }
                    }
                    .listRowBackground(AppGlassStyle.rowBackground)
                    .tint(accent)

                    if isSelectedShopValid {
                        Button {
                            shopToEdit = log.selectedShop
                        } label: {
                            Label("この店舗を編集", systemImage: "pencil")
                                .foregroundColor(accent)
                        }
                        .listRowBackground(AppGlassStyle.rowBackground)
                    }
                }

                HStack(spacing: 10) {
                    Button {
                        shopToEdit = nil
                        showNewShopSheet = true
                    } label: {
                        Label("新規登録", systemImage: "plus.circle.fill")
                            .font(.subheadline.weight(.medium))
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(accent.opacity(0.85))

                    NavigationLink(destination: MyListShopsView(log: log)) {
                        HStack(spacing: 4) {
                            Text("一覧")
                            Text("\(savedShops.count)")
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(accent)
                        }
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    }
                    .foregroundColor(t.mainTextColor)
                }
                .listRowBackground(AppGlassStyle.rowBackground)
                .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
            } header: {
                Text("店舗")
                    .font(AppTypography.panelHeading)
                    .foregroundColor(t.mainTextColor.opacity(0.96))
            }

            Section {
                Button("この設定で開始") { dismiss() }
                    .frame(maxWidth: .infinity)
                    .fontWeight(.semibold)
                    .foregroundColor(t.mainTextColor)
                    .listRowBackground(accent.opacity(0.3))
            }
        }
        .listStyle(.insetGrouped)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                StaticHomeBackgroundView()
                Group {
                    if gateMode {
                        gateModeContent
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        myListContent
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle(gateMode ? "新規遊技" : "マイリスト")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarBackground(t.navigationBarBackdropColor, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .preferredColorScheme(.dark)
            /// 回転数・持ち玉は `NumberPadTextField` の inputAccessoryView で「完了」を表示（フルスクリーンでも確実に閉じられる）
            .toolbar {
                if gateMode {
                    ToolbarItem(placement: .cancellationAction) {
                        Button {
                            onGateCancel?()
                        } label: {
                            if presentedFromPlaySession {
                                Text("＜　実戦へ戻る")
                            } else {
                                Text("キャンセル")
                            }
                        }
                        .foregroundColor(t.mainTextColor)
                    }
                } else if presentedFromPlaySession {
                    ToolbarItem(placement: .cancellationAction) {
                        Button {
                            dismiss()
                        } label: {
                            Text("＜　実戦へ戻る")
                        }
                        .foregroundColor(t.mainTextColor)
                    }
                }
            }
            .sheet(isPresented: $showMasterSearch) {
                MasterMachineSearchView()
            }
            .sheet(item: $machineToEdit, onDismiss: { machineToEdit = nil }) { machine in
                MachineEditView(editing: machine)
                    .equatable()
                    .presentationDetents([.large])
            }
            .sheet(isPresented: $showNewMachineSheet) {
                MachineEditView(editing: nil, onNewMachineSaved: { log.selectedMachine = $0 })
                    .equatable()
                    .presentationDetents([.large])
            }
            .sheet(item: $shopToEdit, onDismiss: { shopToEdit = nil }) { shop in
                ShopEditView(shop: shop) {
                    shopToEdit = nil
                }
                .presentationDetents([.large])
            }
            .sheet(isPresented: $showNewShopSheet) {
                ShopEditView(shop: nil) {
                    showNewShopSheet = false
                } onNewShopSaved: { log.selectedShop = $0 }
                .presentationDetents([.large])
            }
            .onAppear {
                if gateMode, !savedMachines.isEmpty || !savedShops.isEmpty {
                    let defaultMachineName = UserDefaults.standard.string(for: .defaultMachineName)
                    let defaultShopName = UserDefaults.standard.string(for: .defaultShopName)
                    if !savedMachines.isEmpty {
                        if let name = defaultMachineName, !name.isEmpty, let m = savedMachines.first(where: { $0.name == name }) {
                            log.selectedMachine = m
                        } else if !isSelectedMachineValid {
                            log.selectedMachine = sortedMachines.first ?? savedMachines[0]
                        }
                    }
                    if !savedShops.isEmpty {
                        if let name = defaultShopName, !name.isEmpty, let s = savedShops.first(where: { $0.name == name }) {
                            log.selectedShop = s
                        } else if !isSelectedShopValid {
                            log.selectedShop = sortedShops.first ?? savedShops[0]
                        }
                    }
                }
            }
        }
    }
}

// MARK: - マイリスト「一覧」内：控えめなスワイプ案内
private struct MyListSwipeHintBar: View {
    @EnvironmentObject private var themeManager: ThemeManager
    let text: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "arrow.left.arrow.right")
                .font(AppTypography.annotationSmallSemibold)
            Text(text)
                .font(AppTypography.annotationSmall)
        }
        .foregroundColor(themeManager.currentTheme.accentColor.opacity(0.5))
        .frame(maxWidth: .infinity)
        .padding(.vertical, 5)
        .padding(.horizontal, 16)
        .allowsHitTesting(false)
    }
}

// MARK: - 登録済み機種一覧（タップで選択、スワイプで編集）
struct MyListMachinesView: View {
    @Bindable var log: GameLog
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var themeManager: ThemeManager
    @Query(sort: \Machine.name) private var savedMachines: [Machine]
    @Query(sort: \GameSession.date, order: .reverse) private var recentSessions: [GameSession]
    @State private var machineToEdit: Machine?
    @State private var showNewSheet = false

    private var accent: Color { AppGlassStyle.accent }
    private var sortedMachinesForList: [Machine] {
        let order = recentSessions.reduce(into: [String]()) { acc, s in
            let n = s.machineName.isEmpty ? "未設定" : s.machineName
            if !acc.contains(n) { acc.append(n) }
        }
        return savedMachines.sorted { m1, m2 in
            let i1 = order.firstIndex(of: m1.name) ?? order.count
            let i2 = order.firstIndex(of: m2.name) ?? order.count
            if i1 != i2 { return i1 < i2 }
            return m1.name < m2.name
        }
    }

    var body: some View {
        ZStack {
            StaticHomeBackgroundView()
            VStack(spacing: 0) {
                MyListSwipeHintBar(text: "左にスワイプで選択　右にスワイプで編集・削除")
                List {
                ForEach(sortedMachinesForList) { m in
                    Button {
                        log.selectedMachine = m
                        dismiss()
                    } label: {
                        HStack {
                            Text(m.name)
                                .foregroundColor(themeManager.currentTheme.mainTextColor)
                            if log.selectedMachine.persistentModelID == m.persistentModelID {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.subheadline)
                                    .foregroundStyle(AppGlassStyle.accent)
                            }
                            Spacer(minLength: 0)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(AppGlassStyle.rowBackground)
                    .listSelectionStyle(isSelected: log.selectedMachine.persistentModelID == m.persistentModelID)
                    .swipeActions(edge: .leading, allowsFullSwipe: false) {
                        Button("選択") {
                            log.selectedMachine = m
                            dismiss()
                        }
                        .tint(accent)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            modelContext.delete(m)
                        } label: { Label("削除", systemImage: "trash") }
                        Button {
                            machineToEdit = m
                        } label: { Label("編集", systemImage: "pencil") }
                        .tint(accent)
                    }
                }
                Button {
                    showNewSheet = true
                } label: {
                    Label("新規機種を登録", systemImage: "plus.circle")
                        .foregroundColor(accent)
                }
                .listRowBackground(AppGlassStyle.rowBackground)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .navigationTitle("登録済み機種")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarBackground(themeManager.currentTheme.navigationBarBackdropColor, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .preferredColorScheme(.dark)
        .tint(themeManager.currentTheme.mainTextColor)
        .sheet(item: $machineToEdit, onDismiss: { machineToEdit = nil }) { m in
            MachineEditView(editing: m)
                .equatable()
                .presentationDetents([.large])
        }
        .sheet(isPresented: $showNewSheet) {
            MachineEditView(editing: nil, onNewMachineSaved: { log.selectedMachine = $0 })
                .equatable()
                .presentationDetents([.large])
        }
    }
}

// MARK: - 登録済み店舗一覧（タップで選択、スワイプで編集）
struct MyListShopsView: View {
    @Bindable var log: GameLog
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var themeManager: ThemeManager
    @Query(sort: \Shop.name) private var savedShops: [Shop]
    @Query(sort: \GameSession.date, order: .reverse) private var recentSessions: [GameSession]
    @State private var shopToEdit: Shop?
    @State private var showNewSheet = false

    private var accent: Color { AppGlassStyle.accent }
    private var sortedShopsForList: [Shop] {
        let order = recentSessions.reduce(into: [String]()) { acc, s in
            let n = s.shopName.isEmpty ? "未設定" : s.shopName
            if !acc.contains(n) { acc.append(n) }
        }
        return savedShops.sorted { s1, s2 in
            let i1 = order.firstIndex(of: s1.name) ?? order.count
            let i2 = order.firstIndex(of: s2.name) ?? order.count
            if i1 != i2 { return i1 < i2 }
            return s1.name < s2.name
        }
    }

    var body: some View {
        ZStack {
            StaticHomeBackgroundView()
            VStack(spacing: 0) {
                MyListSwipeHintBar(text: "左にスワイプで選択　右にスワイプで編集・削除")
                List {
                ForEach(sortedShopsForList) { s in
                    Button {
                        log.selectedShop = s
                        dismiss()
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(s.name)
                                .foregroundColor(themeManager.currentTheme.mainTextColor)
                            if s.supportsChodamaService || s.chodamaBalanceBalls > 0 {
                                Text("貯玉 \(s.chodamaBalanceBalls)玉")
                                    .font(AppTypography.annotationSmall)
                                    .foregroundStyle(themeManager.currentTheme.subTextColor.opacity(0.88))
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(AppGlassStyle.rowBackground)
                    .listSelectionStyle(isSelected: log.selectedShop.persistentModelID == s.persistentModelID)
                    .swipeActions(edge: .leading, allowsFullSwipe: false) {
                        Button("選択") {
                            log.selectedShop = s
                            dismiss()
                        }
                        .tint(accent)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            modelContext.delete(s)
                        } label: { Label("削除", systemImage: "trash") }
                        Button {
                            shopToEdit = s
                        } label: { Label("編集", systemImage: "pencil") }
                        .tint(accent)
                    }
                }
                Button {
                    showNewSheet = true
                } label: {
                    Label("新規店舗を登録", systemImage: "plus.circle")
                        .foregroundColor(accent)
                }
                .listRowBackground(AppGlassStyle.rowBackground)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .navigationTitle("登録済み店舗")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarBackground(themeManager.currentTheme.navigationBarBackdropColor, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .preferredColorScheme(.dark)
        .tint(themeManager.currentTheme.mainTextColor)
        .sheet(item: $shopToEdit, onDismiss: { shopToEdit = nil }) { s in
            ShopEditView(shop: s) { shopToEdit = nil }
                .presentationDetents([.large])
        }
        .sheet(isPresented: $showNewSheet) {
            ShopEditView(shop: nil) { showNewSheet = false } onNewShopSaved: { log.selectedShop = $0 }
                .presentationDetents([.large])
        }
    }
}

// MARK: - 特定日ルール1件（店舗設定用）
private enum SpecificDayRuleType: String, CaseIterable {
    case monthDay = "毎月N日"
    case lastDigit = "Nのつく日"
}

// MARK: - 払出係数プリセット（pt/玉 = 100÷玉/100pt）
private enum ExchangeRatePreset: String, CaseIterable {
    case rate25 = "25.0玉/100pt：4.00pt交換"
    case rate27_5 = "27.5玉/100pt：約3.63pt交換"
    case rate28 = "28.0玉/100pt：約3.57pt交換"
    case rate30 = "30.0玉/100pt：約3.33pt交換"
    case rate33_3 = "33.3玉/100pt：約3.00pt交換"
    case rate35_7 = "35.7玉/100pt：約2.80pt交換"
    case rate40 = "40.0玉/100pt：2.50pt交換"
    case other = "その他"

    var yenPerBall: Double? {
        switch self {
        case .rate25: return 4.00
        case .rate27_5: return 100.0 / 27.5
        case .rate28: return 100.0 / 28.0
        case .rate30: return 100.0 / 30.0
        case .rate33_3: return 100.0 / 33.3
        case .rate35_7: return 100.0 / 35.7
        case .rate40: return 2.50
        case .other: return nil
        }
    }

    var ballsPer100Yen: Double? {
        switch self {
        case .rate25: return 25.0
        case .rate27_5: return 27.5
        case .rate28: return 28.0
        case .rate30: return 30.0
        case .rate33_3: return 33.3
        case .rate35_7: return 35.7
        case .rate40: return 40.0
        case .other: return nil
        }
    }
}

// MARK: - 店舗の新規登録・編集（レートを店補正後のボーダー算出に利用）
struct ShopEditView: View {
    /// 編集時は既存の店舗を渡す。nil のときは新規登録。
    let shop: Shop?
    let onDismiss: () -> Void
    /// 新規登録保存直後に呼ぶ（遊技ゲートで即選択に使う）
    var onNewShopSaved: ((Shop) -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var themeManager: ThemeManager

    private var t: any ApplicationTheme { themeManager.currentTheme }

    @State private var name: String = ""
    @State private var address: String = ""
    @State private var placeID: String?
    @State private var ballsPerCashUnitStr: String = "125"
    /// 空欄保存時は貸玉と同じ（DB 上 0）。画面では貸玉と同じ数を初期表示する。
    @State private var holdingsBallsPerButtonStr: String = "125"
    @State private var exchangeRatePreset: ExchangeRatePreset = .rate25
    @State private var customBallsPer100YenStr: String = ""
    @State private var customYenPerBallStr: String = ""
    @State private var isSyncingCustomRate = false
    /// 特定日ルール最大4件。追加順に 特定日① 毎月13日, 特定日② 5のつく日 のように表示
    @State private var specificDayEntries: [(type: SpecificDayRuleType, value: String)] = Array(repeating: (.lastDigit, ""), count: 4)
    @State private var supportsChodamaService = false
    @State private var chodamaBalanceStr: String = "0"

    @State private var showErrorAlert = false
    @State private var errorMessage = ""
    @StateObject private var placeSearchService = PlaceSearchService()
    /// Places API 失敗時のトースト
    @State private var showPlacesToast = false
    @State private var placesToastText = ""
    /// 下部バー：左＝登録フォーム、右＝店名＋「交換率」で Google 検索（アプリ内）
    @State private var isShopBrowserExpanded = false

    private var isNew: Bool { shop == nil }
    private var accent: Color { AppGlassStyle.accent }

    /// その他時：玉/100円から円/玉を算出
    private var customYenPerBallFromBalls: Double? {
        guard let v = Double(customBallsPer100YenStr.trimmingCharacters(in: .whitespaces)), v > 0 else { return nil }
        return 100.0 / v
    }
    /// その他時：円/玉から玉/100円を算出
    private var customBallsPer100FromYen: Double? {
        guard let v = Double(customYenPerBallStr.trimmingCharacters(in: .whitespaces)), v > 0 else { return nil }
        return 100.0 / v
    }

    /// 貸玉（500pt あたり）から「4円（250玉／1k）」形式の補助表示。1k＝1000pt あたりの払い出し玉数、円/玉＝1000÷その玉数。
    private var lendingRateSupplementaryLine: String? {
        let trimmed = ballsPerCashUnitStr.trimmingCharacters(in: .whitespaces)
        guard let ballsPer500 = Int(trimmed), ballsPer500 > 0 else { return nil }
        let ballsPer1k = ballsPer500 * 2
        let yenPerBall = 1000.0 / Double(ballsPer1k)
        guard yenPerBall.isValidForNumericDisplay else { return nil }
        let yenPart: String
        if abs(yenPerBall - yenPerBall.rounded()) < 0.000_001 {
            yenPart = "\(Int(yenPerBall.rounded()))円"
        } else {
            yenPart = "\(yenPerBall.displayFormat("%.2f"))円"
        }
        return "\(yenPart)（\(ballsPer1k)玉／1k）"
    }

    /// 保存用の交換率（円/玉）。プリセットまたはその他入力から算出。
    private var effectiveExchangeRate: Double? {
        if exchangeRatePreset != .other, let rate = exchangeRatePreset.yenPerBall { return rate }
        if exchangeRatePreset == .other {
            if let y = Double(customYenPerBallStr.trimmingCharacters(in: .whitespaces)), y > 0 { return y }
            return customYenPerBallFromBalls
        }
        return nil
    }

    /// アプリ内ブラウザ：`店舗名` と「交換率」での Google 検索（店名が空なら nil）
    private var shopResearchGoogleURL: URL? {
        let raw = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return nil }
        let query = "\(raw) 交換率"
        var c = URLComponents(string: "https://www.google.com/search")
        c?.queryItems = [URLQueryItem(name: "q", value: query)]
        return c?.url
    }

    @ViewBuilder
    private func placeCandidateRow(_ candidate: PlaceCandidate) -> some View {
        Button {
            name = candidate.name
            address = candidate.address
            placeID = candidate.id
            placeSearchService.searchText = ""
            placeSearchService.clearCandidates()
        } label: {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(candidate.name)
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(t.mainTextColor)
                    if !candidate.address.isEmpty {
                        Text(candidate.address)
                            .font(AppTypography.annotation)
                            .foregroundColor(t.subTextColor.opacity(0.88))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if let distLabel = candidate.distanceLabel {
                    Text(distLabel)
                        .font(AppTypography.annotationMedium)
                        .foregroundColor(accent.opacity(0.9))
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(t.formCanvasMutedBackground)
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }

    /// 店舗選択パネル内「現在地周辺から探す」：キーワード結果を閉じてから周辺検索へ切り替え
    private func tapNearbyPachinkoSearchFromPanel() {
        name = ""
        placeSearchService.searchText = ""
        placeSearchService.clearCandidates()
        placeSearchService.requestLocation()
        placeSearchService.fetchNearbyPachinkoIfNeeded()
    }

    private func displayLabel(for index: Int) -> String {
        let e = specificDayEntries[index]
        let v = e.value.trimmingCharacters(in: .whitespaces)
        guard !v.isEmpty else { return "" }
        switch e.type {
        case .monthDay:
            if let n = Int(v), (1...31).contains(n) { return "毎月\(n)日" }
            return "毎月\(v)日"
        case .lastDigit:
            if let n = Int(v), (0...9).contains(n) { return "\(n)のつく日" }
            return "\(v)のつく日"
        }
    }

    private func shopEditPanel<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(AppTypography.panelHeading)
                .foregroundColor(t.mainTextColor.opacity(0.96))
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .pstatsPanelStyle()
    }

    private func shopEditPanel<Trailing: View, Content: View>(title: String, @ViewBuilder trailing: () -> Trailing, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center) {
                Text(title)
                    .font(AppTypography.panelHeading)
                    .foregroundColor(t.mainTextColor.opacity(0.96))
                Spacer(minLength: 8)
                trailing()
            }
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .pstatsPanelStyle()
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ZStack {
                    AppGlassStyle.background.ignoresSafeArea()
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 16) {
                            shopEditPanel(title: "店舗選択", trailing: { InfoIconView(explanation: "店名・チェーン名で検索するか、このパネル内の「現在地周辺から探す」で近くのホールを表示します。候補をタップすると店舗名と住所が自動で入ります。", tint: t.subTextColor.opacity(0.72)) }) {
                                if !placeSearchService.isApiKeyConfigured {
                                    HStack(spacing: 8) {
                                        Image(systemName: "exclamationmark.triangle.fill")
                                            .foregroundColor(.orange.opacity(0.9))
                                        Text("Google Places APIキーが未設定です。Info.plist の GooglePlacesAPIKey にキーを設定すると実際の店舗検索が利用できます。")
                                            .font(AppTypography.annotation)
                                            .foregroundColor(t.subTextColor.opacity(0.92))
                                    }
                                }
                                // 検索欄と現在地周辺ボタンを同一パネル内にまとめる
                                VStack(alignment: .leading, spacing: 10) {
                                    TextField("店名・チェーン名で検索", text: $name)
                                        .textContentType(.none)
                                        .foregroundColor(t.mainTextColor)
                                        .onChange(of: name) { _, newValue in
                                            placeSearchService.searchText = newValue
                                        }
                                    if placeSearchService.isLocationDenied {
                                        HStack(alignment: .top, spacing: 8) {
                                            Image(systemName: "location.slash")
                                                .foregroundColor(.orange.opacity(0.9))
                                            Text("設定から位置情報をオンにすると、現在地周辺のホールを表示できます。")
                                                .font(AppTypography.annotation)
                                                .foregroundColor(t.subTextColor.opacity(0.88))
                                        }
                                    } else {
                                        Button {
                                            tapNearbyPachinkoSearchFromPanel()
                                        } label: {
                                            HStack(spacing: 8) {
                                                Image(systemName: "location.circle.fill")
                                                    .foregroundColor(accent)
                                                Text("現在地周辺から探す")
                                                    .font(.subheadline.weight(.medium))
                                                    .foregroundColor(accent)
                                                Spacer(minLength: 8)
                                                if placeSearchService.isFetchingNearby {
                                                    ProgressView()
                                                        .scaleEffect(0.8)
                                                        .tint(accent)
                                                }
                                            }
                                            .padding(.vertical, 4)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                        }
                                        .buttonStyle(.plain)
                                        .disabled(placeSearchService.isFetchingNearby)
                                    }
                                }
                                .padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(t.formCanvasMutedBackground)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                if !placeSearchService.nearbyCandidates.isEmpty && name.trimmingCharacters(in: .whitespaces).isEmpty {
                                    Text("現在地周辺のホール")
                                        .font(AppTypography.annotationSemibold)
                                        .foregroundColor(accent.opacity(0.9))
                                    VStack(spacing: 8) {
                                        ForEach(placeSearchService.nearbyCandidates) { candidate in
                                            placeCandidateRow(candidate)
                                        }
                                    }
                                }
                                if !placeSearchService.candidates.isEmpty {
                                    Text("検索結果")
                                        .font(AppTypography.annotationSemibold)
                                        .foregroundColor(accent.opacity(0.9))
                                    VStack(spacing: 8) {
                                        ForEach(placeSearchService.candidates) { candidate in
                                            placeCandidateRow(candidate)
                                        }
                                    }
                                }
                                if placeSearchService.isSearching {
                                    HStack(spacing: 8) {
                                        ProgressView()
                                            .scaleEffect(0.9)
                                            .tint(accent)
                                        Text("検索中...")
                                            .font(AppTypography.annotation)
                                            .foregroundColor(t.subTextColor.opacity(0.88))
                                    }
                                }
                                if placeSearchService.hasNextPage && !placeSearchService.isSearching {
                                    Button {
                                        placeSearchService.loadMoreKeywordResults()
                                    } label: {
                                        HStack(spacing: 8) {
                                            if placeSearchService.isLoadingMore {
                                                ProgressView().scaleEffect(0.8).tint(accent)
                                            }
                                            Text(placeSearchService.isLoadingMore ? "読み込み中..." : "もっと見る")
                                                .font(.subheadline.weight(.medium))
                                                .foregroundColor(accent)
                                        }
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 8)
                                    }
                                    .disabled(placeSearchService.isLoadingMore)
                                }
                            }
                            shopEditPanel(title: "レート設定", trailing: { InfoIconView(explanation: "貸玉数は 500pt あたりの玉数。交換率は 1 玉あたりの換金（pt）。メニューでよくある組み合わせを選ぶか「その他」で自由入力。玉/100pt と pt/玉は連動します。", tint: t.subTextColor.opacity(0.72)) }) {
                                HStack {
                                    Text("貸玉数（500ptあたり）")
                                        .foregroundColor(t.mainTextColor.opacity(0.92))
                                        .fixedSize(horizontal: true, vertical: false)
                                    Spacer()
                                    IntegerPadTextField(
                                        text: $ballsPerCashUnitStr,
                                        placeholder: "125",
                                        maxDigits: 4,
                                        font: .preferredFont(forTextStyle: .body),
                                        textColor: UIColor(t.mainTextColor),
                                        accentColor: UIColor(accent)
                                    )
                                        .multilineTextAlignment(.trailing)
                                }
                                if let lendingLine = lendingRateSupplementaryLine {
                                    Text(lendingLine)
                                        .font(AppTypography.annotationMedium)
                                        .foregroundColor(t.subTextColor.opacity(0.88))
                                        .frame(maxWidth: .infinity, alignment: .trailing)
                                }
                                Text("貸玉数は、貸玉ボタンを押した際に払い出される玉の数です。")
                                    .font(AppTypography.annotationSmall)
                                    .foregroundColor(t.subTextColor.opacity(0.78))
                                    .fixedSize(horizontal: false, vertical: true)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                HStack(alignment: .top, spacing: 10) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("持ち玉払い出し数")
                                            .foregroundColor(t.mainTextColor.opacity(0.92))
                                        Text("持ち玉払い出しボタンを押した時に出てくる玉の数です。デフォルトは貸玉数と同じに設定されています。")
                                            .font(AppTypography.annotationSmall)
                                            .foregroundColor(t.subTextColor.opacity(0.78))
                                    }
                                    Spacer(minLength: 8)
                                    IntegerPadTextField(
                                        text: $holdingsBallsPerButtonStr,
                                        placeholder: "125",
                                        maxDigits: 4,
                                        font: .preferredFont(forTextStyle: .body),
                                        textColor: UIColor(t.mainTextColor),
                                        accentColor: UIColor(accent)
                                    )
                                        .multilineTextAlignment(.trailing)
                                        .frame(minWidth: 72, alignment: .trailing)
                                }
                                HStack(alignment: .center, spacing: 10) {
                                    Text("交換率")
                                        .foregroundColor(t.mainTextColor.opacity(0.92))
                                        .lineLimit(1)
                                    Spacer(minLength: 8)
                                    Picker("交換率", selection: $exchangeRatePreset) {
                                        ForEach(ExchangeRatePreset.allCases, id: \.self) { preset in
                                            Text(preset.rawValue)
                                                .lineLimit(1)
                                                .minimumScaleFactor(0.82)
                                                .tag(preset)
                                        }
                                    }
                                    .labelsHidden()
                                    .pickerStyle(.menu)
                                    .tint(accent)
                                    .frame(maxWidth: .infinity, alignment: .trailing)
                                }
                                .accessibilityElement(children: .combine)
                                .accessibilityLabel("交換率")
                                if exchangeRatePreset == .other {
                                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                                        Text("玉/100pt")
                                            .foregroundColor(t.mainTextColor.opacity(0.88))
                                        DecimalPadTextField(
                                            text: $customBallsPer100YenStr,
                                            placeholder: "25.0",
                                            maxIntegerDigits: 4,
                                            maxFractionDigits: 3,
                                            font: .preferredFont(forTextStyle: .body),
                                            textColor: UIColor(t.mainTextColor),
                                            accentColor: UIColor(accent)
                                        )
                                            .multilineTextAlignment(.trailing)
                                            .onChange(of: customBallsPer100YenStr) { _, new in
                                                guard !isSyncingCustomRate, !new.isEmpty, let y = customYenPerBallFromBalls else { return }
                                                isSyncingCustomRate = true
                                                customYenPerBallStr = y.displayFormat("%.2f")
                                                DispatchQueue.main.async { isSyncingCustomRate = false }
                                            }
                                        Text(customYenPerBallFromBalls.map { "→ \($0.displayFormat("%.2f"))pt/玉" } ?? "→ — pt/玉")
                                            .font(AppTypography.annotation)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                                        Text("pt交換")
                                            .foregroundColor(t.mainTextColor.opacity(0.88))
                                        DecimalPadTextField(
                                            text: $customYenPerBallStr,
                                            placeholder: "4.00",
                                            maxIntegerDigits: 4,
                                            maxFractionDigits: 4,
                                            font: .preferredFont(forTextStyle: .body),
                                            textColor: UIColor(t.mainTextColor),
                                            accentColor: UIColor(accent)
                                        )
                                            .multilineTextAlignment(.trailing)
                                            .onChange(of: customYenPerBallStr) { _, new in
                                                guard !isSyncingCustomRate, !new.isEmpty, let b = customBallsPer100FromYen else { return }
                                                isSyncingCustomRate = true
                                                customBallsPer100YenStr = b.displayFormat("%.1f")
                                                DispatchQueue.main.async { isSyncingCustomRate = false }
                                            }
                                        Text(customBallsPer100FromYen.map { "→ \($0.displayFormat("%.1f"))玉/100pt" } ?? "→ — 玉/100pt")
                                            .font(AppTypography.annotation)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                }
                            }
                            shopEditPanel(title: "貯玉", trailing: { InfoIconView(explanation: "貯玉（カウンター預かり）に対応している店だけオンにしてください。オンにすると実戦終了時に「貯玉」精算が選べ、換金時の端数玉を残高へ自動加算できます。残高は手入力で合わせたり、精算のたびに増えます。", tint: t.subTextColor.opacity(0.72)) }) {
                                Toggle("貯玉サービスを利用する", isOn: $supportsChodamaService)
                                    .foregroundColor(t.mainTextColor.opacity(0.94))
                                HStack {
                                    Text("貯玉残高（玉）")
                                        .foregroundColor(t.mainTextColor.opacity(0.92))
                                    Spacer()
                                    IntegerPadTextField(
                                        text: $chodamaBalanceStr,
                                        placeholder: "0",
                                        maxDigits: 9,
                                        font: .preferredFont(forTextStyle: .body),
                                        textColor: UIColor(t.mainTextColor),
                                        accentColor: UIColor(accent)
                                    )
                                        .multilineTextAlignment(.trailing)
                                }
                            }
                            shopEditPanel(title: "特定日ルール（分析で使用・最大4つ）", trailing: { InfoIconView(explanation: "種類で「毎月N日」か「Nのつく日」を選び、右のN欄に数字を入力。個別店舗分析の「特定日傾向」に追加順で表示されます。", tint: t.subTextColor.opacity(0.72)) }) {
                                VStack(alignment: .leading, spacing: 12) {
                                    HStack(spacing: 6) {
                                        Text("種類")
                                            .font(AppTypography.annotation)
                                            .foregroundColor(t.subTextColor.opacity(0.88))
                                            .frame(width: 36, alignment: .leading)
                                        Text("N")
                                            .font(AppTypography.annotation)
                                            .foregroundColor(t.subTextColor.opacity(0.88))
                                            .frame(width: 28, alignment: .center)
                                    }
                                    .padding(.leading, 28)
                                    ForEach(0..<4, id: \.self) { i in
                                        HStack(spacing: 8) {
                                            Text(["①", "②", "③", "④"][i])
                                                .font(.subheadline.weight(.medium))
                                                .foregroundColor(t.mainTextColor.opacity(0.92))
                                                .frame(width: 20, alignment: .center)
                                            Picker("", selection: Binding(
                                                get: { specificDayEntries[i].type },
                                                set: { newVal in
                                                    var arr = specificDayEntries
                                                    arr[i].type = newVal
                                                    specificDayEntries = arr
                                                }
                                            )) {
                                                ForEach(SpecificDayRuleType.allCases, id: \.self) { t in
                                                    Text(t.rawValue).tag(t)
                                                }
                                            }
                                            .pickerStyle(.menu)
                                            .labelsHidden()
                                            .tint(accent)
                                            .fixedSize(horizontal: true, vertical: false)
                                            IntegerPadTextField(
                                                text: Binding(
                                                    get: { specificDayEntries[i].value },
                                                    set: { newVal in
                                                        var arr = specificDayEntries
                                                        arr[i].value = newVal
                                                        specificDayEntries = arr
                                                    }
                                                ),
                                                placeholder: specificDayEntries[i].type == .monthDay ? "1〜31" : "0〜9",
                                                maxDigits: 2,
                                                font: .preferredFont(forTextStyle: .body),
                                                textColor: UIColor(t.mainTextColor),
                                                accentColor: UIColor(accent)
                                            )
                                            .multilineTextAlignment(.center)
                                            .frame(width: 48)
                                            if !displayLabel(for: i).isEmpty {
                                                Text(displayLabel(for: i))
                                                    .font(AppTypography.annotation)
                                                    .foregroundColor(t.subTextColor.opacity(0.88))
                                                    .lineLimit(1)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        .padding(16)
                        .padding(.bottom, 100)
                    }
                    .opacity(isShopBrowserExpanded ? 0 : 1)
                    .allowsHitTesting(!isShopBrowserExpanded)
                    .animation(isShopBrowserExpanded ? nil : .easeInOut(duration: 0.25), value: isShopBrowserExpanded)

                    if let url = shopResearchGoogleURL {
                        InAppWebView(url: url)
                            .id(url.absoluteString)
                            .background(AppGlassStyle.background)
                            .opacity(isShopBrowserExpanded ? 1 : 0)
                            .allowsHitTesting(isShopBrowserExpanded)
                            .animation(isShopBrowserExpanded ? nil : .easeInOut(duration: 0.25), value: isShopBrowserExpanded)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .animation(isShopBrowserExpanded ? nil : .spring(response: 0.35, dampingFraction: 0.82), value: isShopBrowserExpanded)

                shopBrowserSwipeBar
            }
            .ignoresSafeArea(edges: .bottom)
            .navigationTitle(isNew ? "新規店舗登録" : "店舗を編集")
            .navigationBarTitleDisplayMode(.inline)
            .keyboardDismissToolbar()
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarBackground(t.navigationBarBackdropColor, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .preferredColorScheme(.dark)
            .tint(accent)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss(); onDismiss() }
                        .foregroundColor(accent)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isNew ? "登録" : "保存") {
                        let n = name.trimmingCharacters(in: .whitespaces)
                        if n.isEmpty {
                            errorMessage = "店舗名を入力してください"
                            showErrorAlert = true
                            return
                        }
                        if (Int(ballsPerCashUnitStr) ?? 125) <= 0 {
                            errorMessage = "貸玉数は1以上にしてください"
                            showErrorAlert = true
                            return
                        }
                        guard let rate = effectiveExchangeRate, rate > 0 else {
                            errorMessage = exchangeRatePreset == .other ? "その他の場合は玉/100ptかpt交換を入力してください" : "交換率を選んでください"
                            showErrorAlert = true
                            return
                        }
                        saveShop()
                    }
                    .fontWeight(.semibold)
                    .foregroundColor(accent)
                }
            }
            .alert("入力エラー", isPresented: $showErrorAlert) {
                Button("閉じる", role: .cancel) { }
            } message: {
                Text(errorMessage)
            }
            .onAppear {
                if shop == nil {
                    placeSearchService.requestLocation()
                }
                if let s = shop {
                    name = s.name
                    address = s.address
                    placeID = s.placeID
                    ballsPerCashUnitStr = "\(s.ballsPerCashUnit)"
                    holdingsBallsPerButtonStr = s.holdingsBallsPerButton > 0
                        ? "\(s.holdingsBallsPerButton)"
                        : "\(s.ballsPerCashUnit)"
                    applyExchangeRateToPreset(s.payoutCoefficient)
                    loadSpecificDayEntries(from: s)
                    supportsChodamaService = s.supportsChodamaService
                    chodamaBalanceStr = "\(s.chodamaBalanceBalls)"
                } else {
                    address = ""
                    placeID = nil
                    let defaultRate = Double(UserDefaults.standard.string(for: .defaultExchangeRate) ?? "4.0") ?? 4.0
                    applyExchangeRateToPreset(defaultRate)
                    let defaultBalls = Int(UserDefaults.standard.string(for: .defaultBallsPerCash) ?? "125") ?? 125
                    ballsPerCashUnitStr = "\(defaultBalls)"
                    holdingsBallsPerButtonStr = "\(defaultBalls)"
                    supportsChodamaService = false
                    chodamaBalanceStr = "0"
                }
                isShopBrowserExpanded = false
            }
            .onChange(of: ballsPerCashUnitStr) { oldVal, newVal in
                syncHoldingsFieldWithLendingIfMirrored(oldLending: oldVal, newLending: newVal)
            }
            .onChange(of: placeSearchService.lastUserFacingMessage) { _, new in
                guard let m = new, !m.isEmpty else { return }
                placesToastText = m
                showPlacesToast = true
                placeSearchService.clearLastUserFacingMessage()
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                    showPlacesToast = false
                }
            }
            .appToast(isPresented: $showPlacesToast, text: placesToastText, systemImage: "wifi.exclamationmark")
        }
    }

    /// 最下部に常時表示。左端＝登録フォームへ、右端＝Google（店名＋交換率）アプリ内ブラウザ。（機種編集の DMM バーと同一レイアウト）
    @ViewBuilder
    private var shopBrowserSwipeBar: some View {
        let barHeight: CGFloat = 72
        let edgeInset: CGFloat = 8
        GeometryReader { geo in
            let w = geo.size.width
            let edgeW = max(92, min(124, w * 0.255))
            let stripCorner: CGFloat = 10

            ZStack {
                HStack(spacing: 0) {
                    shopBrowserRegisterEdge(width: edgeW, stripCorner: stripCorner)
                        .padding(.leading, edgeInset)
                    Spacer(minLength: 0)
                    shopBrowserWebEdge(width: edgeW, stripCorner: stripCorner)
                        .padding(.trailing, edgeInset)
                }

                VStack(spacing: 3) {
                    Text(isShopBrowserExpanded ? "Google 検索 表示中" : "ブラウザ切替")
                        .font(AppTypography.annotationSemibold)
                        .foregroundStyle(t.mainTextColor.opacity(0.95))
                    Text("左端・右端をタップ")
                        .font(AppTypography.annotationSmallMedium)
                        .foregroundStyle(t.subTextColor.opacity(0.9))
                }
                .multilineTextAlignment(.center)
                .frame(maxWidth: max(120, w - edgeW * 2 - 20))
                .allowsHitTesting(false)
            }
            .frame(width: w, height: barHeight)
        }
        .frame(height: barHeight)
        .padding(.horizontal, 8)
        .contentShape(Rectangle())
        .pstatsChromeSheetBarStyle(borderStyle: .topEdgeOnly)
    }

    /// 左端：登録画面へ戻る（機種編集の DMM 左端と同一）
    private func shopBrowserRegisterEdge(width: CGFloat, stripCorner: CGFloat) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                isShopBrowserExpanded = false
            }
        } label: {
            let active = !isShopBrowserExpanded
            VStack(alignment: .center, spacing: 4) {
                HStack(spacing: 3) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .bold))
                    Image(systemName: "doc.text.fill")
                        .font(.system(size: 14, weight: .semibold))
                }
                .foregroundStyle(t.mainTextColor.opacity(active ? 1.0 : 0.78))
                Text("登録画面")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(t.mainTextColor)
                Text(active ? "いま表示中" : "端をタップで戻る")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(t.subTextColor.opacity(0.88))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.85)
            }
            .frame(width: width)
            .frame(maxHeight: .infinity)
            .padding(.vertical, 6)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: stripCorner, style: .continuous)
                        .fill(active ? accent.opacity(0.22) : t.formCanvasMutedBackground)
                    RoundedRectangle(cornerRadius: stripCorner, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    t.chromeSheetBorderColor.opacity(active ? 1.0 : 0.55),
                                    accent.opacity(active ? 0.35 : 0.12)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: active ? 1.25 : 0.85
                        )
                }
            )
            .contentShape(RoundedRectangle(cornerRadius: stripCorner, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("登録画面に戻る")
        .accessibilityHint("タップで店舗編集画面を表示します。")
    }

    /// 右端：Google アプリ内ブラウザ（機種編集の DMM 右端と同一）
    @ViewBuilder
    private func shopBrowserWebEdge(width: CGFloat, stripCorner: CGFloat) -> some View {
        let urlReady = shopResearchGoogleURL != nil
        Button {
            guard urlReady else { return }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                isShopBrowserExpanded = true
            }
        } label: {
            let active = urlReady && isShopBrowserExpanded
            VStack(alignment: .center, spacing: 4) {
                HStack(spacing: 3) {
                    Image(systemName: "safari")
                        .font(.system(size: 14, weight: .semibold))
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .bold))
                }
                .foregroundStyle(t.mainTextColor.opacity(urlReady ? (isShopBrowserExpanded ? 1.0 : 0.9) : 0.42))
                Text("Google")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(t.mainTextColor.opacity(urlReady ? 1.0 : 0.5))
                Text(
                    urlReady
                        ? (isShopBrowserExpanded ? "いま表示中" : "端をタップで開く")
                        : "先に店名を入力"
                )
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(t.subTextColor.opacity(urlReady ? 0.88 : 0.72))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.85)
            }
            .frame(width: width)
            .frame(maxHeight: .infinity)
            .padding(.vertical, 6)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: stripCorner, style: .continuous)
                        .fill(
                            active
                                ? accent.opacity(0.2)
                                : (urlReady ? t.formCanvasMidBackground : t.formCanvasDeepBackground)
                        )
                    RoundedRectangle(cornerRadius: stripCorner, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    accent.opacity(active ? 0.5 : 0.2),
                                    t.chromeSheetBorderColor.opacity(urlReady ? 0.85 : 0.4)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: active ? 1.25 : 0.85
                        )
                }
            )
            .contentShape(RoundedRectangle(cornerRadius: stripCorner, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!urlReady)
        .opacity(urlReady ? 1.0 : 0.72)
        .accessibilityLabel("Google検索をアプリ内ブラウザで開く")
        .accessibilityHint(
            urlReady
                ? "タップで店名と交換率の検索結果を表示します。"
                : "店名を入力すると利用できます。"
        )
    }

    private func applyExchangeRateToPreset(_ rate: Double) {
        let tol = 0.01
        if let p = ExchangeRatePreset.allCases.first(where: { $0.yenPerBall != nil && abs(($0.yenPerBall ?? 0) - rate) < tol }) {
            exchangeRatePreset = p
            customBallsPer100YenStr = ""
            customYenPerBallStr = ""
        } else {
            exchangeRatePreset = .other
            customYenPerBallStr = rate.displayFormat("%.2f")
            if rate.isValidForNumericDisplay, abs(rate) > 1e-9 {
                customBallsPer100YenStr = (100.0 / rate).displayFormat("%.1f")
            } else {
                customBallsPer100YenStr = ""
            }
        }
    }

    /// 持ち玉欄が空、または変更前の貸玉数と同じときだけ貸玉入力に追従する。
    private func syncHoldingsFieldWithLendingIfMirrored(oldLending: String, newLending: String) {
        let newBalls = Int(newLending.trimmingCharacters(in: .whitespaces))
        guard let nb = newBalls, nb > 0 else { return }
        let hTrim = holdingsBallsPerButtonStr.trimmingCharacters(in: .whitespaces)
        if hTrim.isEmpty {
            holdingsBallsPerButtonStr = "\(nb)"
            return
        }
        guard let oldBalls = Int(oldLending.trimmingCharacters(in: .whitespaces)),
              let hi = Int(hTrim),
              hi == oldBalls
        else { return }
        holdingsBallsPerButtonStr = "\(nb)"
    }

    private func loadSpecificDayEntries(from s: Shop) {
        if !s.specificDayRulesStorage.isEmpty {
            let parts = s.specificDayRulesStorage.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }
            for (i, part) in parts.prefix(4).enumerated() {
                guard part.count >= 2, let num = Int(part.dropFirst()) else { continue }
                if part.hasPrefix("M") {
                    specificDayEntries[i] = (.monthDay, "\(num)")
                } else if part.hasPrefix("L") {
                    specificDayEntries[i] = (.lastDigit, "\(num)")
                }
            }
        } else {
            let dm = s.specificDayOfMonthStorage.split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }.filter { (1...31).contains($0) }
            let ld = s.specificLastDigitsStorage.split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }.filter { (0...9).contains($0) }
            var idx = 0
            for n in dm {
                if idx < 4 { specificDayEntries[idx] = (.monthDay, "\(n)"); idx += 1 }
            }
            for n in ld {
                if idx < 4 { specificDayEntries[idx] = (.lastDigit, "\(n)"); idx += 1 }
            }
        }
    }

    private func saveShop() {
        let n = name.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty else {
            errorMessage = "店舗名を入力してください"
            showErrorAlert = true
            return
        }
        let balls = Int(ballsPerCashUnitStr) ?? 125
        guard let rate = effectiveExchangeRate, rate > 0 else {
            errorMessage = "交換率を選ぶか、その他の場合は玉/100ptかpt交換を入力してください"
            showErrorAlert = true
            return
        }
        if balls <= 0 {
            errorMessage = "貸玉数は1以上にしてください"
            showErrorAlert = true
            return
        }
        
        let rulesStorage = specificDayEntries
            .compactMap { e -> String? in
                let v = e.value.trimmingCharacters(in: .whitespaces)
                guard !v.isEmpty else { return nil }
                switch e.type {
                case .monthDay: if let num = Int(v), (1...31).contains(num) { return "M\(num)" }; return nil
                case .lastDigit: if let num = Int(v), (0...9).contains(num) { return "L\(num)" }; return nil
                }
            }
            .joined(separator: ",")
        
        let chodamaBal = max(0, Int(chodamaBalanceStr.trimmingCharacters(in: .whitespaces)) ?? 0)
        let holdTap = Int(holdingsBallsPerButtonStr.trimmingCharacters(in: .whitespaces)) ?? 0
        let holdTapClamped = holdTap > 0 ? holdTap : 0
        if let existing = shop {
            existing.name = n
            existing.address = address.trimmingCharacters(in: .whitespaces)
            existing.placeID = placeID
            existing.ballsPerCashUnit = balls
            existing.payoutCoefficient = rate
            existing.holdingsBallsPerButton = holdTapClamped
            existing.specificDayRulesStorage = rulesStorage
            existing.supportsChodamaService = supportsChodamaService
            existing.chodamaBalanceBalls = chodamaBal
        } else {
            let newShop = Shop(
                name: n,
                ballsPerCashUnit: balls,
                payoutCoefficient: rate,
                placeID: placeID,
                address: address.trimmingCharacters(in: .whitespaces),
                holdingsBallsPerButton: holdTapClamped
            )
            newShop.specificDayRulesStorage = rulesStorage
            newShop.supportsChodamaService = supportsChodamaService
            newShop.chodamaBalanceBalls = chodamaBal
            modelContext.insert(newShop)
            onNewShopSaved?(newShop)
        }
        dismiss()
        onDismiss()
    }
}

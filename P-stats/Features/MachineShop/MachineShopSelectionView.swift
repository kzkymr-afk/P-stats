import SwiftUI
import SwiftData
import UIKit

/// 遊戯開始ゲート用：店舗・機種が未選択のときは遊戯開始できない
struct MachineShopSelectionView: View {
    @Bindable var log: GameLog
    /// true のとき「遊戯開始」「キャンセル」を表示し、決定時は onGateStart / onGateCancel を呼ぶ
    var gateMode: Bool = false
    var onGateStart: (() -> Void)? = nil
    var onGateCancel: (() -> Void)? = nil
    /// 実戦画面のシートから開いたとき true（左上に「実戦へ戻る」）
    var presentedFromPlaySession: Bool = false

    @Environment(\.dismiss) var dismiss
    @Environment(\.modelContext) private var modelContext

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
    /// 新規開始時：貯玉で開始する場合の持ち玉数（ゲート時のみ使用）
    @State private var initialHoldingsText = ""
    @AppStorage("startWithZeroHoldings") private var startWithZeroHoldings = false

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
                    log.selectedShop = Shop(name: "未選択", ballsPerCashUnit: 125, payoutCoefficient: 4.0)
                }
            }
        )
    }

    private var accent: Color { AppGlassStyle.accent }
    private var cardBackground: Color { AppGlassStyle.cardBackground }

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
            .foregroundColor(.white.opacity(0.95))
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
                    .foregroundColor(.white)
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
            .background(isSelected ? accent.opacity(0.18) : Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(isSelected ? accent.opacity(0.5) : Color.white.opacity(0.12), lineWidth: isSelected ? 1.5 : 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: - ゲートモード（新規遊技）：機種 → 店舗 → 回転数 → 持ち玉 → 遊戯開始（外側はスクロールなし・高さは比率配分）
    private var gateModeContent: some View {
        GeometryReader { outerGeo in
            let h = outerGeo.size.height
            let topPad: CGFloat = 8
            let bottomPad: CGFloat = 8
            let gapCount: CGFloat = 4
            let gap = max(6, min(12, h * 0.012))
            let gapTotal = gap * gapCount
            let contentH = max(120, h - topPad - bottomPad - gapTotal)
            let mH = contentH * 0.35
            let sH = contentH * 0.30
            let rH = contentH * 0.10
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
            if startWithZeroHoldings { initialHoldingsText = "0" }
        }
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
                            .foregroundColor(.white.opacity(0.9))
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
                            .foregroundColor(.white.opacity(0.9))
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
        HStack(alignment: .center, spacing: 6) {
            Button {
                rotationFieldFocusTrigger += 1
            } label: {
                HStack(spacing: 6) {
                    Text("開始時の回転数")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.white.opacity(0.95))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    Text("（必須）")
                        .font(.caption.weight(.bold))
                        .foregroundColor(.red)
                        .fixedSize()
                }
            }
            .buttonStyle(.plain)
            Spacer(minLength: 4)
                .frame(minHeight: 36)
                .contentShape(Rectangle())
                .onTapGesture { rotationFieldFocusTrigger += 1 }
            NumberPadTextField(
                text: $initialRotationText,
                placeholder: "",
                maxDigits: 4,
                font: .monospacedSystemFont(ofSize: 17, weight: .semibold),
                textColor: .white,
                accentColor: UIColor(accent),
                doneTitle: "完了",
                focusTrigger: rotationFieldFocusTrigger
            )
            .frame(minWidth: 72, maxWidth: .infinity, alignment: .trailing)
            InfoIconView(explanation: "遊戯開始時点のデータランプに表示された回転数を入力してください。見出し・余白をタップしてもテンキーを開けます。", tint: accent.opacity(0.6))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .frame(minHeight: max(height, 52))
        .background(AppGlassStyle.rowBackground, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(accent.opacity(0.2), lineWidth: 1))
    }

    private func gateHoldingsSection(height: CGFloat) -> some View {
        HStack(alignment: .center, spacing: 6) {
            Text("開始時の持ち玉")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.white.opacity(0.95))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .layoutPriority(1)
            Spacer(minLength: 4)
            NumberPadTextField(
                text: $initialHoldingsText,
                placeholder: "",
                maxDigits: 5,
                font: .monospacedSystemFont(ofSize: 17, weight: .semibold),
                textColor: .white,
                accentColor: UIColor(accent),
                doneTitle: "完了"
            )
            .frame(width: 88, alignment: .trailing)
            InfoIconView(explanation: "貯玉で始める場合は玉数を入力。未入力・0のときは持ち玉なしで開始。", tint: accent.opacity(0.6))
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
        return Button {
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
            onGateStart?()
        } label: {
            Text("遊戯開始")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundColor(.white)
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
                                    Color.white.opacity(canStart ? 0.4 : 0.2),
                                    accent.opacity(canStart ? 0.3 : 0.15),
                                    Color.white.opacity(0.06)
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
        .frame(height: height)
        .alert(isPresented: $showErrorAlert) {
            Alert(title: Text("エラー"), message: Text(errorMessage), dismissButton: .default(Text("OK")))
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
                    .foregroundColor(.white)
                }
                .listRowBackground(AppGlassStyle.rowBackground)
                .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
            } header: {
                Text("機種")
                    .font(AppTypography.panelHeading)
                    .foregroundColor(.white.opacity(0.95))
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
                    .foregroundColor(.white)
                }
                .listRowBackground(AppGlassStyle.rowBackground)
                .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
            } header: {
                Text("店舗")
                    .font(AppTypography.panelHeading)
                    .foregroundColor(.white.opacity(0.95))
            }

            Section {
                Button("この設定で開始") { dismiss() }
                    .frame(maxWidth: .infinity)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
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
                        .foregroundColor(accent)
                    }
                } else if presentedFromPlaySession {
                    ToolbarItem(placement: .cancellationAction) {
                        Button {
                            dismiss()
                        } label: {
                            Text("＜　実戦へ戻る")
                        }
                        .foregroundColor(accent)
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
                MachineEditView(editing: nil)
                    .equatable()
                    .presentationDetents([.large])
            }
            .sheet(item: $shopToEdit, onDismiss: { shopToEdit = nil }) { shop in
                ShopEditView(shop: shop) {
                    shopToEdit = nil
                }
                .presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $showNewShopSheet) {
                ShopEditView(shop: nil) {
                    showNewShopSheet = false
                }
                .presentationDetents([.medium, .large])
            }
            .onAppear {
                if gateMode, !savedMachines.isEmpty || !savedShops.isEmpty {
                    let defaultMachineName = UserDefaults.standard.string(forKey: "defaultMachineName")
                    let defaultShopName = UserDefaults.standard.string(forKey: "defaultShopName")
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

// MARK: - 登録済み機種一覧（タップで選択、スワイプで編集）
struct MyListMachinesView: View {
    @Bindable var log: GameLog
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
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
            List {
                ForEach(sortedMachinesForList) { m in
                    HStack(spacing: 12) {
                        Button {
                            log.selectedMachine = m
                            dismiss()
                        } label: {
                            HStack {
                                Text(m.name)
                                    .foregroundColor(.white)
                                if log.selectedMachine.persistentModelID == m.persistentModelID {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.subheadline)
                                        .foregroundStyle(AppGlassStyle.accent)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        Spacer(minLength: 8)
                        Button {
                            machineToEdit = m
                        } label: {
                            Image(systemName: "pencil.circle.fill")
                                .font(.title3)
                                .foregroundStyle(accent)
                        }
                        .buttonStyle(.plain)
                    }
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
        .navigationTitle("登録済み機種")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .preferredColorScheme(.dark)
        .sheet(item: $machineToEdit, onDismiss: { machineToEdit = nil }) { m in
            MachineEditView(editing: m)
                .equatable()
                .presentationDetents([.large])
        }
        .sheet(isPresented: $showNewSheet) {
            MachineEditView(editing: nil)
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
            List {
                ForEach(sortedShopsForList) { s in
                    HStack(spacing: 12) {
                        Button(s.name) {
                            log.selectedShop = s
                            dismiss()
                        }
                        .foregroundColor(.white)
                        .buttonStyle(.plain)
                        Spacer(minLength: 8)
                        Button {
                            shopToEdit = s
                        } label: {
                            Image(systemName: "pencil.circle.fill")
                                .font(.title3)
                                .foregroundStyle(accent)
                        }
                        .buttonStyle(.plain)
                    }
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
        .navigationTitle("登録済み店舗")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .preferredColorScheme(.dark)
        .sheet(item: $shopToEdit, onDismiss: { shopToEdit = nil }) { s in
            ShopEditView(shop: s) { shopToEdit = nil }
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showNewSheet) {
            ShopEditView(shop: nil) { showNewSheet = false }
                .presentationDetents([.medium, .large])
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

// MARK: - 店舗の新規登録・編集（貸玉料金・払出係数を実戦基準値算出に利用）
struct ShopEditView: View {
    /// 編集時は既存の店舗を渡す。nil のときは新規登録。
    let shop: Shop?
    let onDismiss: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var name: String = ""
    @State private var address: String = ""
    @State private var placeID: String?
    @State private var ballsPerCashUnitStr: String = "125"
    @State private var exchangeRatePreset: ExchangeRatePreset = .rate25
    @State private var customBallsPer100YenStr: String = ""
    @State private var customYenPerBallStr: String = ""
    @State private var isSyncingCustomRate = false
    /// 特定日ルール最大4件。追加順に 特定日① 毎月13日, 特定日② 5のつく日 のように表示
    @State private var specificDayEntries: [(type: SpecificDayRuleType, value: String)] = Array(repeating: (.lastDigit, ""), count: 4)

    @State private var showErrorAlert = false
    @State private var errorMessage = ""
    @StateObject private var placeSearchService = PlaceSearchService()

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
    /// 保存用の交換率（円/玉）。プリセットまたはその他入力から算出。
    private var effectiveExchangeRate: Double? {
        if exchangeRatePreset != .other, let rate = exchangeRatePreset.yenPerBall { return rate }
        if exchangeRatePreset == .other {
            if let y = Double(customYenPerBallStr.trimmingCharacters(in: .whitespaces)), y > 0 { return y }
            return customYenPerBallFromBalls
        }
        return nil
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
                        .foregroundColor(.white)
                    if !candidate.address.isEmpty {
                        Text(candidate.address)
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.7))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if let distLabel = candidate.distanceLabel {
                    Text(distLabel)
                        .font(.caption.weight(.medium))
                        .foregroundColor(accent.opacity(0.9))
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
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
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.white.opacity(0.95))
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(AppGlassStyle.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(AppGlassStyle.strokeGradient, lineWidth: 1))
    }

    private func shopEditPanel<Trailing: View, Content: View>(title: String, @ViewBuilder trailing: () -> Trailing, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white.opacity(0.95))
                Spacer(minLength: 8)
                trailing()
            }
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(AppGlassStyle.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(AppGlassStyle.strokeGradient, lineWidth: 1))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppGlassStyle.background.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 16) {
                        shopEditPanel(title: "店舗", trailing: { InfoIconView(explanation: "店名・チェーン名で検索するか、「現在地周辺から探す」で近くのホールを表示します。候補をタップすると店舗名と住所が自動で入ります。", tint: .white.opacity(0.7)) }) {
                            TextField("店名・チェーン名で検索", text: $name)
                                .textContentType(.none)
                                .foregroundColor(.white)
                                .onChange(of: name) { _, newValue in
                                    placeSearchService.searchText = newValue
                                }
                            if !placeSearchService.isApiKeyConfigured {
                                HStack(spacing: 8) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundColor(.orange.opacity(0.9))
                                    Text("Google Places APIキーが未設定です。Info.plist の GooglePlacesAPIKey にキーを設定すると実際の店舗検索が利用できます。")
                                        .font(.caption)
                                        .foregroundColor(.white.opacity(0.8))
                                }
                            }
                            if placeSearchService.isLocationDenied {
                                HStack(spacing: 8) {
                                    Image(systemName: "location.slash")
                                        .foregroundColor(.orange.opacity(0.9))
                                    Text("設定から位置情報をオンにすると、現在地周辺のホールを表示できます。")
                                        .font(.caption)
                                        .foregroundColor(.white.opacity(0.7))
                                }
                            } else if name.trimmingCharacters(in: .whitespaces).isEmpty && placeSearchService.canUseLocation {
                                Button {
                                    placeSearchService.fetchNearbyPachinkoIfNeeded()
                                } label: {
                                    HStack(spacing: 8) {
                                        Image(systemName: "location.circle.fill")
                                            .foregroundColor(accent)
                                        Text("現在地周辺から探す")
                                            .font(.subheadline.weight(.medium))
                                            .foregroundColor(accent)
                                        if placeSearchService.isFetchingNearby {
                                            Spacer()
                                            ProgressView()
                                                .scaleEffect(0.8)
                                                .tint(accent)
                                        }
                                    }
                                    .padding(.vertical, 8)
                                }
                            }
                            if !placeSearchService.nearbyCandidates.isEmpty && name.trimmingCharacters(in: .whitespaces).isEmpty {
                                Text("現在地周辺のホール")
                                    .font(.caption.weight(.semibold))
                                    .foregroundColor(accent.opacity(0.9))
                                VStack(spacing: 8) {
                                    ForEach(placeSearchService.nearbyCandidates) { candidate in
                                        placeCandidateRow(candidate)
                                    }
                                }
                            }
                            if !placeSearchService.candidates.isEmpty {
                                Text("検索結果")
                                    .font(.caption.weight(.semibold))
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
                                        .font(.caption)
                                        .foregroundColor(.white.opacity(0.7))
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
                        shopEditPanel(title: "貸玉料金・払出係数（実戦基準値算出に使用）", trailing: { InfoIconView(explanation: "貸玉数: 500ptで何玉借りられるか（等価125玉）。払出係数: 1玉何ptで換金か。玉/100ptかpt交換のどちらかを入力するともう片方も自動計算されます。", tint: .white.opacity(0.7)) }) {
                            HStack {
                                Text("貸玉数（500ptあたり）")
                                    .foregroundColor(.white.opacity(0.9))
                                    .fixedSize(horizontal: true, vertical: false)
                                Spacer()
                                TextField("125", text: $ballsPerCashUnitStr)
                                    .keyboardType(.numberPad)
                                    .multilineTextAlignment(.trailing)
                                    .foregroundColor(.white)
                            }
                            VStack(alignment: .leading, spacing: 10) {
                                Text("払出係数（pt/玉）")
                                    .foregroundColor(.white.opacity(0.9))
                                Picker("払出係数", selection: $exchangeRatePreset) {
                                    ForEach(ExchangeRatePreset.allCases, id: \.self) { preset in
                                        Text(preset.rawValue).tag(preset)
                                    }
                                }
                                .pickerStyle(.menu)
                                .tint(accent)
                                if exchangeRatePreset == .other {
                                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                                        Text("玉/100pt")
                                            .foregroundColor(.white.opacity(0.85))
                                        TextField("25.0", text: $customBallsPer100YenStr)
                                            .keyboardType(.decimalPad)
                                            .multilineTextAlignment(.trailing)
                                            .foregroundColor(.white)
                                            .onChange(of: customBallsPer100YenStr) { _, new in
                                                guard !isSyncingCustomRate, !new.isEmpty, let y = customYenPerBallFromBalls else { return }
                                                isSyncingCustomRate = true
                                                customYenPerBallStr = String(format: "%.2f", y)
                                                DispatchQueue.main.async { isSyncingCustomRate = false }
                                            }
                                        Text(customYenPerBallFromBalls.map { "→ \(String(format: "%.2f", $0))pt/玉" } ?? "→ — pt/玉")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                                        Text("pt交換")
                                            .foregroundColor(.white.opacity(0.85))
                                        TextField("4.00", text: $customYenPerBallStr)
                                            .keyboardType(.decimalPad)
                                            .multilineTextAlignment(.trailing)
                                            .foregroundColor(.white)
                                            .onChange(of: customYenPerBallStr) { _, new in
                                                guard !isSyncingCustomRate, !new.isEmpty, let b = customBallsPer100FromYen else { return }
                                                isSyncingCustomRate = true
                                                customBallsPer100YenStr = String(format: "%.1f", b)
                                                DispatchQueue.main.async { isSyncingCustomRate = false }
                                            }
                                        Text(customBallsPer100FromYen.map { "→ \(String(format: "%.1f", $0))玉/100pt" } ?? "→ — 玉/100pt")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                        shopEditPanel(title: "特定日ルール（分析で使用・最大4つ）", trailing: { InfoIconView(explanation: "種類で「毎月N日」か「Nのつく日」を選び、右のN欄に数字を入力。個別店舗分析の「特定日傾向」に追加順で表示されます。", tint: .white.opacity(0.7)) }) {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack(spacing: 6) {
                                    Text("種類")
                                        .font(.caption)
                                        .foregroundColor(.white.opacity(0.7))
                                        .frame(width: 36, alignment: .leading)
                                    Text("N")
                                        .font(.caption)
                                        .foregroundColor(.white.opacity(0.7))
                                        .frame(width: 28, alignment: .center)
                                }
                                .padding(.leading, 28)
                                ForEach(0..<4, id: \.self) { i in
                                    HStack(spacing: 8) {
                                        Text(["①", "②", "③", "④"][i])
                                            .font(.subheadline.weight(.medium))
                                            .foregroundColor(.white.opacity(0.9))
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
                                        TextField(specificDayEntries[i].type == .monthDay ? "1〜31" : "0〜9", text: Binding(
                                            get: { specificDayEntries[i].value },
                                            set: { newVal in
                                                var arr = specificDayEntries
                                                arr[i].value = newVal
                                                specificDayEntries = arr
                                            }
                                        ))
                                        .keyboardType(.numberPad)
                                        .multilineTextAlignment(.center)
                                        .foregroundColor(.white)
                                        .frame(width: 48)
                                        if !displayLabel(for: i).isEmpty {
                                            Text(displayLabel(for: i))
                                                .font(.caption)
                                                .foregroundColor(.white.opacity(0.7))
                                                .lineLimit(1)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .padding(16)
                    .padding(.bottom, 40)
                }
            }
            .navigationTitle(isNew ? "新規店舗登録" : "店舗を編集")
            .navigationBarTitleDisplayMode(.inline)
            .keyboardDismissToolbar()
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
                            errorMessage = exchangeRatePreset == .other ? "その他の場合は玉/100ptかpt交換を入力してください" : "払出係数を選択してください"
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
                Button("OK", role: .cancel) { }
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
                    applyExchangeRateToPreset(s.payoutCoefficient)
                    loadSpecificDayEntries(from: s)
                } else {
                    address = ""
                    placeID = nil
                    let defaultRate = Double(UserDefaults.standard.string(forKey: "defaultExchangeRate") ?? "4.0") ?? 4.0
                    applyExchangeRateToPreset(defaultRate)
                    let defaultBalls = Int(UserDefaults.standard.string(forKey: "defaultBallsPerCash") ?? "125") ?? 125
                    ballsPerCashUnitStr = "\(defaultBalls)"
                }
            }
        }
    }

    private func applyExchangeRateToPreset(_ rate: Double) {
        let tol = 0.01
        if let p = ExchangeRatePreset.allCases.first(where: { $0.yenPerBall != nil && abs(($0.yenPerBall ?? 0) - rate) < tol }) {
            exchangeRatePreset = p
            customBallsPer100YenStr = ""
            customYenPerBallStr = ""
        } else {
            exchangeRatePreset = .other
            customYenPerBallStr = String(format: "%.2f", rate)
            customBallsPer100YenStr = String(format: "%.1f", 100.0 / rate)
        }
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
            errorMessage = "払出係数を選択するか、その他の場合は玉/100ptかpt交換を入力してください"
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
        
        if let existing = shop {
            existing.name = n
            existing.address = address.trimmingCharacters(in: .whitespaces)
            existing.placeID = placeID
            existing.ballsPerCashUnit = balls
            existing.payoutCoefficient = rate
            existing.specificDayRulesStorage = rulesStorage
        } else {
            let newShop = Shop(
                name: n,
                ballsPerCashUnit: balls,
                payoutCoefficient: rate,
                placeID: placeID,
                address: address.trimmingCharacters(in: .whitespaces)
            )
            newShop.specificDayRulesStorage = rulesStorage
            modelContext.insert(newShop)
        }
        dismiss()
        onDismiss()
    }
}

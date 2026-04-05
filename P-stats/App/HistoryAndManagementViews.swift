import SwiftUI
import SwiftData
import UIKit

// MARK: - 機種管理（スワイプで編集・削除、並べ替え、右下FABで新規登録）

/// 機種・店舗管理リスト上部の控えめなスワイプ案内
private struct ManagementSwipeHintBar: View {
    @EnvironmentObject private var themeManager: ThemeManager
    let text: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "chevron.left")
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

private enum ManagementSessionStats {
    static func machinePlayStats(machineName: String, sessions: [GameSession]) -> (count: Int, winRatePercent: Int) {
        let filtered = sessions.filter { $0.machineName == machineName }
        let n = filtered.count
        guard n > 0 else { return (0, 0) }
        let wins = filtered.filter { $0.performance >= 0 }.count
        return (n, Int((Double(wins) / Double(n) * 100).rounded()))
    }

    static func shopPlayStats(shopName: String, sessions: [GameSession]) -> (count: Int, winRatePercent: Int) {
        let filtered = sessions.filter { $0.shopName == shopName }
        let n = filtered.count
        guard n > 0 else { return (0, 0) }
        let wins = filtered.filter { $0.performance >= 0 }.count
        return (n, Int((Double(wins) / Double(n) * 100).rounded()))
    }
}

/// 機種管理一覧用カード（`pstatsPanelStyle` でホーム・分析・履歴と同一パネル）
private struct MachineManagementCard: View {
    @EnvironmentObject private var themeManager: ThemeManager
    let machine: Machine
    let sessionCount: Int
    let winRatePercent: Int
    let isReorderMode: Bool

    private var skin: any ApplicationTheme { themeManager.currentTheme }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(machine.name)
                    .font(skin.themedFont(size: 17, weight: .semibold))
                    .foregroundColor(skin.mainTextColor)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                let maker = machine.manufacturer.trimmingCharacters(in: .whitespacesAndNewlines)
                Text(maker.isEmpty ? "メーカー未登録" : maker)
                    .font(skin.themedFont(size: 13, weight: .regular))
                    .foregroundColor(skin.subTextColor)
                    .lineLimit(1)
                Text("実戦 \(sessionCount)回　勝率 \(winRatePercent)%")
                    .font(skin.themedFont(size: 12, weight: .medium, monospaced: true))
                    .foregroundColor(skin.subTextColor)
            }
            Spacer(minLength: 0)
            if isReorderMode {
                Image(systemName: "line.3.horizontal")
                    .font(AppTypography.annotation)
                    .foregroundColor(skin.accentColor.opacity(DesignTokens.Surface.AccentTint.chromeTintMid))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .pstatsPanelStyle()
    }
}

/// 店舗管理一覧用カード（`pstatsPanelStyle` で他画面パネルと統一）
private struct ShopManagementCard: View {
    @EnvironmentObject private var themeManager: ThemeManager
    let shop: Shop
    let sessionCount: Int
    let winRatePercent: Int
    let isReorderMode: Bool

    private var skin: any ApplicationTheme { themeManager.currentTheme }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(shop.name)
                    .font(skin.themedFont(size: 17, weight: .semibold))
                    .foregroundColor(skin.mainTextColor)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                Text("実戦 \(sessionCount)回　勝率 \(winRatePercent)%")
                    .font(skin.themedFont(size: 12, weight: .medium, monospaced: true))
                    .foregroundColor(skin.subTextColor)
                if shop.supportsChodamaService || shop.chodamaBalanceBalls > 0 {
                    Text("貯玉　\(shop.chodamaBalanceBalls)玉")
                        .font(skin.themedFont(size: 11, weight: .regular))
                        .foregroundColor(skin.subTextColor)
                }
            }
            Spacer(minLength: 0)
            if isReorderMode {
                Image(systemName: "line.3.horizontal")
                    .font(AppTypography.annotation)
                    .foregroundColor(themeManager.currentTheme.accentColor.opacity(DesignTokens.Surface.AccentTint.chromeTintMid))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .pstatsPanelStyle()
    }
}

struct MachineManagementView: View {
    /// `HomeView` で非表示タブのまま `List` が生きているとネイティブが裏読み込みされるため、選択中タブのときだけ差し込む。
    var nativeAdsInListEnabled: Bool = true
    @EnvironmentObject private var themeManager: ThemeManager
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Machine.name) private var machines: [Machine]
    @Query(sort: \GameSession.date, order: .reverse) private var recentSessions: [GameSession]
    @AppStorage(UserDefaultsKey.machineDisplayOrder.rawValue) private var machineOrderStr = ""
    @State private var machineToEdit: Machine?
    @State private var showNewMachine = false
    @State private var isReorderMode = false
    @State private var pendingDeleteMachine: Machine?

    private var cyan: Color { AppGlassStyle.accent }
    /// 親 `HomeView` の VStack で広告・ドックぶんは既に除外済み。ここでさらに `safeAreaInset` すると余白が二重になり FAB が上に逃げる。
    private let fabVerticalPadding: CGFloat = 10
    private let fabTrailingPadding: CGFloat = 20
    /// スクロール末尾と FAB のかぶり防止
    private var listBottomContentMargin: CGFloat { 76 }

    /// 実戦履歴ベース：新しい順（未使用の機種は後ろへ）
    private var recencyOrderedMachines: [Machine] {
        let order = recentSessions.reduce(into: [String]()) { acc, s in
            let n = s.machineName.isEmpty ? "未設定" : s.machineName
            if !acc.contains(n) { acc.append(n) }
        }
        return machines.sorted { m1, m2 in
            let i1 = order.firstIndex(of: m1.name) ?? Int.max
            let i2 = order.firstIndex(of: m2.name) ?? Int.max
            if i1 != i2 { return i1 < i2 }
            return m1.name < m2.name
        }
    }

    private var orderedMachines: [Machine] {
        let order = machineOrderStr.split(separator: "|").map(String.init)
        return machines.sorted { m1, m2 in
            let i1 = order.firstIndex(of: m1.name) ?? Int.max
            let i2 = order.firstIndex(of: m2.name) ?? Int.max
            if i1 != i2 { return i1 < i2 }
            return m1.name < m2.name
        }
    }

    // 通常表示は最新遊技順。並べ替えモード時のみ手動順を反映。
    private var machinesForList: [Machine] {
        isReorderMode ? orderedMachines : recencyOrderedMachines
    }

    private func saveMachineOrder(_ list: [Machine]) {
        machineOrderStr = list.map(\.name).joined(separator: "|")
    }

    private var machineRowsWithAds: [NativeAdListInterleaving.MachineManagementRow] {
        NativeAdListInterleaving.machineManagementRows(machinesForList)
    }

    @ViewBuilder
    private func machineListRow(for m: Machine) -> some View {
        let st = ManagementSessionStats.machinePlayStats(machineName: m.name, sessions: recentSessions)
        MachineManagementCard(
            machine: m,
            sessionCount: st.count,
            winRatePercent: st.winRatePercent,
            isReorderMode: isReorderMode
        )
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
        .listRowSeparator(.hidden)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button {
                machineToEdit = m
            } label: { Label("編集", systemImage: "pencil") }
            .tint(cyan)
            Button(role: .destructive) {
                pendingDeleteMachine = m
            } label: { Label("削除", systemImage: "trash") }
        }
        .moveDisabled(!isReorderMode)
    }

    var body: some View {
        // bottomTrailing: フル画面の List がスクロール・スワイプを受け取る。FAB はドック直上の右下。
        // 行に listSelectionStyle() を付けない（DragGesture minimumDistance:0 が List の縦スクロール・swipeActions と競合するため）
        ZStack(alignment: .bottomTrailing) {
            StaticHomeBackgroundView()
            VStack(spacing: 0) {
                ManagementSwipeHintBar(text: "左にスワイプで編集・削除")
                List {
                    if isReorderMode {
                        ForEach(machinesForList) { m in
                            machineListRow(for: m)
                        }
                        .onMove { from, to in
                            var arr = orderedMachines
                            arr.move(fromOffsets: from, toOffset: to)
                            saveMachineOrder(arr)
                        }
                    } else if nativeAdsInListEnabled {
                        ForEach(machineRowsWithAds) { row in
                            switch row {
                            case .machine(let m):
                                machineListRow(for: m)
                            case .native(let placementKey):
                                OptionalNativeAdCardSlot(placementID: placementKey)
                                    .listRowBackground(Color.clear)
                                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                                    .listRowSeparator(.hidden)
                            }
                        }
                    } else {
                        ForEach(machinesForList) { m in
                            machineListRow(for: m)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .contentMargins(.bottom, listBottomContentMargin, for: .scrollContent)
                .environment(\.editMode, .constant(isReorderMode ? .active : .inactive))
            }

            Button {
                showNewMachine = true
            } label: {
                Label("新規機種を登録", systemImage: "plus.circle.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 14)
                    .background(cyan, in: Capsule())
            }
            .buttonStyle(.plain)
            .padding(.trailing, fabTrailingPadding)
            .padding(.bottom, fabVerticalPadding)
        }
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .preferredColorScheme(.dark)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(isReorderMode ? "完了" : "並べ替え") {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        if !isReorderMode {
                            saveMachineOrder(machinesForList)
                        }
                        isReorderMode.toggle()
                    }
                }
                .foregroundColor(cyan)
            }
        }
        .sheet(isPresented: Binding(
            get: { machineToEdit != nil },
            set: { if !$0 { machineToEdit = nil } }
            )) {
            if let m = machineToEdit {
                MachineEditView(editing: m)
                    .equatable()
                    .presentationDetents([.large])
            }
        }
        .sheet(isPresented: $showNewMachine) {
            MachineEditView(editing: nil)
                .equatable()
                .presentationDetents([.large])
        }
        .alert("機種を削除しますか？", isPresented: Binding(
            get: { pendingDeleteMachine != nil },
            set: { if !$0 { pendingDeleteMachine = nil } }
        )) {
            Button("削除", role: .destructive) {
                guard let m = pendingDeleteMachine else { return }
                modelContext.delete(m)
                let arr = orderedMachines.filter { $0.persistentModelID != m.persistentModelID }
                saveMachineOrder(arr)
                pendingDeleteMachine = nil
            }
            Button("キャンセル", role: .cancel) { pendingDeleteMachine = nil }
        } message: {
            Text("この機種自体は削除されますが、過去の実戦履歴（機種名の文字列）は残ります。集計の整合性に注意してください。")
        }
    }
}

// MARK: - 店舗管理（スワイプで編集・削除、右上並べ替え、右下FABで新規登録）
struct ShopManagementView: View {
    var nativeAdsInListEnabled: Bool = true
    @EnvironmentObject private var themeManager: ThemeManager
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Shop.name) private var shops: [Shop]
    @Query(sort: \GameSession.date, order: .reverse) private var allSessions: [GameSession]
    @AppStorage(UserDefaultsKey.shopDisplayOrder.rawValue) private var shopOrderStr = ""
    @State private var shopToEdit: Shop?
    @State private var showNewShop = false
    @State private var isReorderMode = false
    @State private var pendingDeleteShop: Shop?

    private var cyan: Color { AppGlassStyle.accent }
    private let fabVerticalPadding: CGFloat = 10
    private let fabTrailingPadding: CGFloat = 20
    private var listBottomContentMargin: CGFloat { 76 }
    private var orderedShops: [Shop] {
        let order = shopOrderStr.split(separator: "|").map(String.init)
        return shops.sorted { s1, s2 in
            let i1 = order.firstIndex(of: s1.name) ?? Int.max
            let i2 = order.firstIndex(of: s2.name) ?? Int.max
            if i1 != i2 { return i1 < i2 }
            return s1.name < s2.name
        }
    }
    private func saveShopOrder(_ list: [Shop]) {
        shopOrderStr = list.map(\.name).joined(separator: "|")
    }

    private var shopRowsWithAds: [NativeAdListInterleaving.ShopManagementRow] {
        NativeAdListInterleaving.shopManagementRows(orderedShops)
    }

    @ViewBuilder
    private func shopListRow(for s: Shop) -> some View {
        let st = ManagementSessionStats.shopPlayStats(shopName: s.name, sessions: allSessions)
        ShopManagementCard(
            shop: s,
            sessionCount: st.count,
            winRatePercent: st.winRatePercent,
            isReorderMode: isReorderMode
        )
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
        .listRowSeparator(.hidden)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                pendingDeleteShop = s
            } label: { Label("削除", systemImage: "trash") }
            Button {
                shopToEdit = s
            } label: { Label("編集", systemImage: "pencil") }
            .tint(cyan)
        }
        .moveDisabled(!isReorderMode)
    }

    var body: some View {
        // 行に listSelectionStyle() を付けない（機種管理と同様、List のスクロール・swipeActions と競合するため）
        ZStack(alignment: .bottomTrailing) {
            StaticHomeBackgroundView()
            VStack(spacing: 0) {
                ManagementSwipeHintBar(text: "左にスワイプで編集・削除")
                List {
                    if isReorderMode {
                        ForEach(orderedShops) { s in
                            shopListRow(for: s)
                        }
                        .onMove { from, to in
                            var arr = orderedShops
                            arr.move(fromOffsets: from, toOffset: to)
                            saveShopOrder(arr)
                        }
                    } else if nativeAdsInListEnabled {
                        ForEach(shopRowsWithAds) { row in
                            switch row {
                            case .shop(let s):
                                shopListRow(for: s)
                            case .native(let placementKey):
                                OptionalNativeAdCardSlot(placementID: placementKey)
                                    .listRowBackground(Color.clear)
                                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                                    .listRowSeparator(.hidden)
                            }
                        }
                    } else {
                        ForEach(orderedShops) { s in
                            shopListRow(for: s)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .contentMargins(.bottom, listBottomContentMargin, for: .scrollContent)
                .environment(\.editMode, .constant(isReorderMode ? .active : .inactive))
            }

            Button {
                showNewShop = true
            } label: {
                Label("新規店舗を登録", systemImage: "plus.circle.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 14)
                    .background(cyan, in: Capsule())
            }
            .buttonStyle(.plain)
            .padding(.trailing, fabTrailingPadding)
            .padding(.bottom, fabVerticalPadding)
        }
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .preferredColorScheme(.dark)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(isReorderMode ? "完了" : "並べ替え") {
                    withAnimation(.easeInOut(duration: 0.25)) { isReorderMode.toggle() }
                }
                .foregroundColor(cyan)
            }
        }
        .sheet(isPresented: Binding(
            get: { shopToEdit != nil },
            set: { if !$0 { shopToEdit = nil } }
            )) {
            if let s = shopToEdit {
                ShopEditView(shop: s) { shopToEdit = nil }
                    .presentationDetents([.large])
            }
        }
        .sheet(isPresented: $showNewShop) {
            ShopEditView(shop: nil) { showNewShop = false }
                .presentationDetents([.large])
        }
        .alert("店舗を削除しますか？", isPresented: Binding(
            get: { pendingDeleteShop != nil },
            set: { if !$0 { pendingDeleteShop = nil } }
        )) {
            Button("削除", role: .destructive) {
                guard let s = pendingDeleteShop else { return }
                modelContext.delete(s)
                let arr = orderedShops.filter { $0.persistentModelID != s.persistentModelID }
                saveShopOrder(arr)
                pendingDeleteShop = nil
            }
            Button("キャンセル", role: .cancel) { pendingDeleteShop = nil }
        } message: {
            Text("この店舗自体は削除されますが、過去の実戦履歴（店名の文字列）は残ります。店補正ボーダー等の再計算に影響する場合があります。")
        }
    }
}

// MARK: - 続きから：直近5件の履歴から選んで同じ機種・店舗で再開（復元不可時）
struct ContinuePlaySelectionView: View {
    @Bindable var log: GameLog
    var restoreFailed: Bool = false
    var onStart: () -> Void
    var onCancel: () -> Void

    @EnvironmentObject private var themeManager: ThemeManager
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \GameSession.date, order: .reverse) private var allSessions: [GameSession]
    @Query(sort: \Machine.name) private var machines: [Machine]
    @Query(sort: \Shop.name) private var shops: [Shop]

    @State private var alertMessage: String?
    @State private var showRestoreFailedAlert = false

    private var recentSessions: [GameSession] { Array(allSessions.prefix(5)) }

    var body: some View {
        NavigationStack {
            ZStack {
                StaticHomeBackgroundView()
                Group {
                    if recentSessions.isEmpty {
                        VStack(spacing: 16) {
                            Image(systemName: "tray")
                                .font(.system(size: 48))
                                .foregroundStyle(themeManager.currentTheme.subTextColor.opacity(0.55))
                            Text("遊技履歴がありません")
                                .font(AppTypography.panelHeading)
                                .foregroundColor(themeManager.currentTheme.mainTextColor)
                            Text("新規遊技スタートで遊技を開始してください")
                                .font(AppTypography.bodyRounded)
                                .foregroundStyle(themeManager.currentTheme.subTextColor.opacity(0.92))
                        }
                        .padding(.vertical, 28)
                        .padding(.horizontal, 24)
                        .frame(maxWidth: .infinity)
                        .pstatsPanelStyle()
                        .padding(.horizontal, 20)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        List {
                            Section {
                                Text("再開したい遊技を選んでください。同じ機種・店舗で遊技を開始します。")
                                    .font(AppTypography.annotation)
                                    .foregroundStyle(themeManager.currentTheme.subTextColor.opacity(0.88))
                                    .listRowBackground(themeManager.currentTheme.listRowBackground)
                            }
                            ForEach(recentSessions, id: \.id) { session in
                                Button {
                                    resume(session)
                                } label: {
                                    VStack(alignment: .leading, spacing: 6) {
                                        HStack {
                                            Text(session.machineName)
                                                .font(.body.weight(.semibold))
                                                .foregroundColor(themeManager.currentTheme.mainTextColor)
                                            Spacer()
                                            Text(JapaneseDateFormatters.yearMonthDay.string(from: session.date))
                                                .font(AppTypography.annotation)
                                                .foregroundColor(themeManager.currentTheme.subTextColor)
                                                .themeShadow(themeManager.currentTheme.compactLabelShadow)
                                        }
                                        Text(session.shopName)
                                            .font(.subheadline)
                                            .foregroundStyle(themeManager.currentTheme.subTextColor.opacity(0.92))
                                    }
                                    .padding(.vertical, 4)
                                }
                                .listRowBackground(themeManager.currentTheme.listRowBackground)
                                .listSelectionStyle()
                            }
                        }
                        .listStyle(.plain)
                        .scrollContentBackground(.hidden)
                    }
                }
            }
            .navigationTitle("続きから")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .preferredColorScheme(.dark)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { onCancel() }
                }
            }
            .alert("この履歴では再開できません", isPresented: Binding(
                get: { alertMessage != nil },
                set: { if !$0 { alertMessage = nil } }
            )) {
                Button("OK", role: .cancel) { alertMessage = nil }
            } message: {
                if let m = alertMessage { Text(m) }
            }
            .alert("前回の状態から復元できません", isPresented: $showRestoreFailedAlert) {
                Button("OK", role: .cancel) { showRestoreFailedAlert = false }
            } message: {
                Text("前回の機種・店舗がマイリストに登録されていません。履歴から選んで再開してください。")
            }
            .onAppear {
                if restoreFailed { showRestoreFailedAlert = true }
            }
        }
    }

    private func resume(_ session: GameSession) {
        let mach = machines.first { $0.name == session.machineName }
        let shop = shops.first { $0.name == session.shopName }
        if let m = mach, let s = shop {
            log.selectedMachine = m
            log.selectedShop = s
            onStart()
        } else {
            alertMessage = "この履歴の機種・店舗がマイリストに登録されていません。マイリストで同じ機種・店舗を登録してから再度お試しください。"
        }
    }
}

// --- 実戦ログ・期待値収支（日付でグループ化） — 表示・グループキーとも `JapaneseDateFormatters.yearMonthDay` を共有
struct HistoryListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \GameSession.date, order: .reverse) var sessions: [GameSession]
    @State private var sessionToEdit: GameSession?

    private var sessionsByDate: [(String, [GameSession])] {
        let grouped = Dictionary(grouping: sessions) { JapaneseDateFormatters.yearMonthDay.string(from: $0.date) }
        return grouped.sorted { $0.key > $1.key }.map { ($0.key, $0.value) }
    }

    var body: some View {
        ZStack {
            StaticHomeBackgroundView()
            ScrollView(showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(sessionsByDate, id: \.0) { item in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.0)
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(.white.opacity(0.95))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Color.black.opacity(DesignTokens.Surface.History.filterCapsuleFill), in: Capsule())
                                .overlay(
                                    Capsule().stroke(Color.white.opacity(DesignTokens.Surface.History.filterCapsuleStroke), lineWidth: DesignTokens.Thickness.hairline)
                                )
                                .padding(.horizontal, 4)
                            ForEach(NativeAdListInterleaving.rowsForSessionGroup(daySessions: item.1, placementPrefix: "hist-\(item.0)"), id: \.id) { row in
                                switch row {
                                case .session(let session):
                                    NavigationLink(destination: SessionDetailView(session: session)) {
                                        HistorySessionCard(session: session)
                                    }
                                    .buttonStyle(.plain)
                                    .contentShape(Rectangle())
                                    .contextMenu {
                                        Button {
                                            sessionToEdit = session
                                        } label: { Label("編集", systemImage: "pencil") }
                                        Button(role: .destructive) {
                                            modelContext.delete(session)
                                        } label: { Label("削除", systemImage: "trash") }
                                    }
                                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                        Button(role: .destructive) {
                                            modelContext.delete(session)
                                        } label: { Label("削除", systemImage: "trash") }
                                        Button {
                                            sessionToEdit = session
                                        } label: { Label("編集", systemImage: "pencil") }
                                            .tint(AppGlassStyle.accent)
                                    }
                                case .native(let placementKey):
                                    OptionalNativeAdCardSlot(placementID: placementKey)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
        }
        .navigationTitle("実戦履歴")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar) // 視認性優先でナビは従来どおり
        .sheet(item: $sessionToEdit) { s in
            NavigationStack {
                SessionEditView(session: s)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("閉じる") { sessionToEdit = nil }
                        }
                    }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(AppGlassStyle.background)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
    }
}

// MARK: - 履歴詳細（タップで表示）。各パネルは角丸・不透明度85％・ラベル可読性向上
struct SessionDetailView: View {
    let session: GameSession
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var themeManager: ThemeManager
    @State private var showEditSheet = false
    @State private var showShareSheet = false

    private var skin: any ApplicationTheme { themeManager.currentTheme }

    private var payoutCoefficient: Double {
        session.payoutCoefficient > 0 ? session.payoutCoefficient : PersistedDataSemantics.defaultPayoutCoefficientPtPerBall
    }
    /// 回収額（pt換算）
    private var totalRecoveryPt: Int { Int((Double(max(0, session.totalHoldings)) * payoutCoefficient).rounded()) }
    /// 総投資額（pt換算）
    private var totalInvestmentPt: Int { Int(max(0, session.totalRealCost).rounded()) }
    /// 実質回転率（回/1k）
    private var realRotationRateDisplay: String {
        guard let v = session.displayRealRotationRatePer1k, v.isValidForNumericDisplay else { return "—" }
        return v.displayFormat("%.1f 回/1k")
    }
    private var borderDiffDisplay: String {
        guard let d = session.sessionBorderDiffPer1k, d.isValidForNumericDisplay else { return "—" }
        return "\(d >= 0 ? "+" : "")\(d.displayFormat("%.1f")) 回/1k"
    }
    private var expectationDisplay: String {
        let pt = "\(session.theoreticalValue >= 0 ? "+" : "")\(session.theoreticalValue.formattedPtWithUnit)"
        let ratio = session.displayExpectationRatioAtSave
            .map { ($0 * 100).displayFormat("%.2f%%") } ?? "—"
        return "\(pt)（\(ratio)）"
    }

    private var playTimeDisplay: (start: String, end: String, duration: String, hourly: String) {
        let start = session.startedAt.map { JapaneseDateFormatters.timeShort.string(from: $0) } ?? "—"
        let end = session.endedAt.map { JapaneseDateFormatters.timeShort.string(from: $0) } ?? "—"
        let duration: String
        if let sec = session.playDurationSeconds {
            let m = Int((sec / 60).rounded())
            duration = "\(m)分"
        } else {
            duration = "—"
        }
        let hourly: String
        if let w = session.hourlyWagePt, w.isValidForNumericDisplay {
            hourly = w.displayFormat("%+.0f") + UnitDisplaySettings.currentSuffix()
        } else {
            hourly = "—"
        }
        return (start, end, duration, hourly)
    }

    var body: some View {
        ZStack {
            StaticHomeBackgroundView()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    SessionSlumpChartForSessionView(session: session, height: 180, strokeTint: themeManager.currentTheme.accentColor)

                    detailPanel(title: "機種・店舗") {
                        VStack(alignment: .leading, spacing: 8) {
                            detailRow(label: "機種", value: session.machineName)
                            detailRow(label: "店舗", value: session.shopName)
                            if !session.manufacturerName.isEmpty {
                                detailRow(label: "メーカー", value: session.manufacturerName)
                            }
                        }
                    }

                    detailPanel(title: "数値サマリ") {
                        VStack(alignment: .leading, spacing: 8) {
                            detailRow(label: "収支額", value: "\(session.performance >= 0 ? "+" : "")\(session.performance.formattedPtWithUnit)")
                            detailRow(label: "総回転数", value: "\(session.normalRotations)回")
                            detailRow(label: "大当たり回数", value: "RUSH：\(session.rushWinCount)回、通常：\(session.normalWinCount)回")
                            detailRow(label: "総投資額（pt換算）", value: totalInvestmentPt.formattedPtWithUnit)
                            detailRow(label: "総回収額（pt換算）", value: totalRecoveryPt.formattedPtWithUnit)
                            detailRow(label: "回収出玉", value: "\(session.totalHoldings) 玉")
                            detailRow(label: "期待値（期待値比）", value: expectationDisplay)
                            detailRow(label: "欠損・余剰", value: "\(session.deficitSurplus >= 0 ? "+" : "")\(session.deficitSurplus.formattedPtWithUnit)")
                            detailRow(label: "実質回転率", value: realRotationRateDisplay)
                            detailRow(label: "ボーダーとの差", value: borderDiffDisplay)
                            let t = playTimeDisplay
                            detailRow(label: "開始時刻", value: t.start)
                            detailRow(label: "終了時刻", value: t.end)
                            detailRow(label: "遊技時間", value: t.duration)
                            detailRow(label: "時給", value: t.hourly)
                        }
                    }

                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
        }
        .navigationTitle("履歴詳細")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar { }
        .sheet(isPresented: $showEditSheet) {
            NavigationStack {
                SessionEditView(session: session)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("閉じる") { showEditSheet = false }
                        }
                    }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(AppGlassStyle.background)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .sheet(isPresented: $showShareSheet) {
            SessionShareComposerSheet(snapshot: SessionShareSnapshot.from(session: session))
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            HStack(spacing: 12) {
                Button {
                    showEditSheet = true
                } label: {
                    Label("編集", systemImage: "pencil")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .foregroundColor(skin.mainTextColor)
                        .background(skin.panelSecondaryBackground)
                        .clipShape(RoundedRectangle(cornerRadius: max(12, skin.cornerRadius * 0.75), style: .continuous))
                }
                .buttonStyle(AppMicroInteractions.PressableButtonStyle())

                Button {
                    showShareSheet = true
                } label: {
                    Label("SNSで共有", systemImage: "square.and.arrow.up")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .foregroundColor(.black.opacity(0.88))
                        .background(skin.accentColor)
                        .clipShape(RoundedRectangle(cornerRadius: max(12, skin.cornerRadius * 0.75), style: .continuous))
                }
                .buttonStyle(AppMicroInteractions.PressableButtonStyle())
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 10)
            .background(Color.black.opacity(DesignTokens.Surface.History.panelScrim))
        }
    }

    private func detailPanel<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(AppTypography.panelHeading)
                .foregroundColor(skin.mainTextColor)
                .themeShadow(skin.compactLabelShadow)
            content()
                .foregroundColor(skin.mainTextColor)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .pstatsPanelStyle()
    }

    private func detailRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundColor(skin.subTextColor)
                .themeShadow(skin.compactLabelShadow)
            Spacer()
            Text(value)
                .font(.subheadline.monospacedDigit())
                .foregroundColor(skin.mainTextColor)
        }
    }
}

// MARK: - 実戦履歴カード（1記録＝1枚の角丸グラスパネル）
struct HistorySessionCard: View {
    let session: GameSession
    @EnvironmentObject private var themeManager: ThemeManager

    private var skin: any ApplicationTheme { themeManager.currentTheme }

    private var rotationPer1k: Double {
        guard session.totalRealCost > 0 else { return 0 }
        return (Double(session.normalRotations) / session.totalRealCost) * 1000
    }
    private var rotationRateValue: String {
        if session.excludesFromRotationExpectationAnalytics { return "—（帳簿）" }
        let displayRate = session.displayRealRotationRatePer1k ?? rotationPer1k
        if displayRate <= 0 || !displayRate.isValidForNumericDisplay { return "—" }
        return displayRate.displayFormat("%.1f 回/1k")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(session.machineName)
                .font(skin.themedFont(size: 16, weight: .semibold))
                .foregroundColor(skin.mainTextColor)
                .lineLimit(1)
            Text(session.shopName)
                .font(skin.themedFont(size: 15, weight: .regular))
                .foregroundColor(skin.subTextColor)
                .lineLimit(1)

            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("\(session.performance >= 0 ? "+" : "")\(session.performance.formattedPtWithUnit)")
                    .font(AppDesignSystem.EmphasisNumber.font(size: 26, weight: .heavy))
                    .foregroundStyle(session.performance >= 0 ? skin.accentColor : skin.cautionForegroundColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                Spacer(minLength: 0)
                Text("\(session.theoreticalValue >= 0 ? "+" : "")\(session.theoreticalValue.formattedPtWithUnit)")
                    .font(skin.themedFont(size: 14, weight: .semibold, monospaced: true))
                    .foregroundStyle(skin.subTextColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }

            HStack(alignment: .top, spacing: 16) {
                pairBlock(leftLabel: "総回転数", leftValue: "\(session.normalRotations)回", leftValueColor: skin.mainTextColor,
                          rightLabel: "実質回転率", rightValue: rotationRateValue, rightValueColor: skin.mainTextColor)
            }
            .font(AppTypography.annotation)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .pstatsPanelStyle()
    }

    private func pairBlock(
        leftLabel: String,
        leftValue: String,
        leftValueColor: Color,
        rightLabel: String,
        rightValue: String,
        rightValueColor: Color
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(leftLabel)
                    .foregroundColor(skin.subTextColor)
                Text(leftValue)
                    .font(AppTypography.annotationMonospacedDigitSemibold)
                    .foregroundColor(leftValueColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                Text(rightLabel)
                    .foregroundColor(skin.subTextColor)
                Text(rightValue)
                    .font(AppTypography.annotationMonospacedDigitSemibold)
                    .foregroundColor(rightValueColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - 実戦履歴の編集（マイリスト参照＋一覧にない場合は手入力）
struct SessionEditView: View {
    @Bindable var session: GameSession
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var themeManager: ThemeManager
    @Query(sort: \Machine.name) private var machines: [Machine]
    @Query(sort: \Shop.name) private var shops: [Shop]
    @State private var selectedMachine: Machine?
    @State private var selectedShop: Shop?

    var body: some View {
        ZStack {
            StaticHomeBackgroundView()
            List {
                Section("機種（マイリスト）") {
                if !machines.isEmpty {
                    Picker("機種を選択", selection: $selectedMachine) {
                        Text("手入力（一覧にない）").tag(nil as Machine?)
                        ForEach(machines) { m in
                            Text(m.name).tag(Optional(m))
                        }
                    }
                    .onChange(of: selectedMachine) { _, new in
                        if let m = new {
                            session.machineName = m.name
                            session.manufacturerName = m.manufacturer
                        }
                    }
                    .listRowBackground(themeManager.currentTheme.listRowBackground)
                }
                Text("一覧にない場合は下記で入力")
                    .font(AppTypography.annotation)
                    .foregroundStyle(.white.opacity(0.7))
                    .listRowBackground(themeManager.currentTheme.listRowBackground)
                TextField("機種名（手入力）", text: $session.machineName)
                    .onChange(of: session.machineName) { _, _ in selectedMachine = nil }
                    .listRowBackground(themeManager.currentTheme.listRowBackground)
                TextField("メーカー（分析用）", text: $session.manufacturerName)
                    .listRowBackground(themeManager.currentTheme.listRowBackground)
            }

            Section("店舗（マイリスト）") {
                if !shops.isEmpty {
                    Picker("店舗を選択", selection: $selectedShop) {
                        Text("手入力（一覧にない）").tag(nil as Shop?)
                        ForEach(shops) { s in
                            Text(s.name).tag(Optional(s))
                        }
                    }
                    .onChange(of: selectedShop) { _, new in
                        if let s = new {
                            session.shopName = s.name
                            session.payoutCoefficient = s.payoutCoefficient
                        }
                    }
                    .listRowBackground(themeManager.currentTheme.listRowBackground)
                }
                Text("一覧にない場合は下記で入力")
                    .font(AppTypography.annotation)
                    .foregroundStyle(.white.opacity(0.7))
                    .listRowBackground(themeManager.currentTheme.listRowBackground)
                TextField("店舗名（手入力）", text: $session.shopName)
                    .onChange(of: session.shopName) { _, _ in selectedShop = nil }
                    .listRowBackground(themeManager.currentTheme.listRowBackground)
            }

            Section("数値") {
                HStack {
                    Text("投資（pt）")
                    Spacer()
                    IntegerPadTextField(
                        text: Binding(
                            get: { "\(session.inputCash)" },
                            set: { session.inputCash = Int($0) ?? 0 }
                        ),
                        placeholder: "0",
                        maxDigits: 9,
                        font: .preferredFont(forTextStyle: .body),
                        textColor: UIColor.white,
                        accentColor: UIColor(themeManager.currentTheme.accentColor)
                    )
                    .frame(minWidth: 80, minHeight: 36)
                    .multilineTextAlignment(.trailing)
                }
                .listRowBackground(themeManager.currentTheme.listRowBackground)
                HStack {
                    Text("回収玉数")
                    Spacer()
                    IntegerPadTextField(
                        text: Binding(
                            get: { "\(session.totalHoldings)" },
                            set: { session.totalHoldings = Int($0) ?? 0 }
                        ),
                        placeholder: "0",
                        maxDigits: 8,
                        font: .preferredFont(forTextStyle: .body),
                        textColor: UIColor.white,
                        accentColor: UIColor(themeManager.currentTheme.accentColor)
                    )
                    .frame(minWidth: 80, minHeight: 36)
                    .multilineTextAlignment(.trailing)
                }
                .listRowBackground(themeManager.currentTheme.listRowBackground)
                HStack {
                    Text("総回転数")
                    Spacer()
                    IntegerPadTextField(
                        text: Binding(
                            get: { "\(session.normalRotations)" },
                            set: { session.normalRotations = Int($0) ?? 0 }
                        ),
                        placeholder: "0",
                        maxDigits: 7,
                        font: .preferredFont(forTextStyle: .body),
                        textColor: UIColor.white,
                        accentColor: UIColor(themeManager.currentTheme.accentColor)
                    )
                    .frame(minWidth: 80, minHeight: 36)
                    .multilineTextAlignment(.trailing)
                }
                .listRowBackground(themeManager.currentTheme.listRowBackground)
                HStack {
                    Text("RUSH当選回数")
                    Spacer()
                    IntegerPadTextField(
                        text: Binding(
                            get: { "\(session.rushWinCount)" },
                            set: { session.rushWinCount = Int($0) ?? 0 }
                        ),
                        placeholder: "0",
                        maxDigits: 5,
                        font: .preferredFont(forTextStyle: .body),
                        textColor: UIColor.white,
                        accentColor: UIColor(themeManager.currentTheme.accentColor)
                    )
                    .frame(minWidth: 80, minHeight: 36)
                    .multilineTextAlignment(.trailing)
                }
                .listRowBackground(themeManager.currentTheme.listRowBackground)
                HStack {
                    Text("通常当選回数")
                    Spacer()
                    IntegerPadTextField(
                        text: Binding(
                            get: { "\(session.normalWinCount)" },
                            set: { session.normalWinCount = Int($0) ?? 0 }
                        ),
                        placeholder: "0",
                        maxDigits: 5,
                        font: .preferredFont(forTextStyle: .body),
                        textColor: UIColor.white,
                        accentColor: UIColor(themeManager.currentTheme.accentColor)
                    )
                    .frame(minWidth: 80, minHeight: 36)
                    .multilineTextAlignment(.trailing)
                }
                .listRowBackground(themeManager.currentTheme.listRowBackground)
                HStack {
                    Text("交換率（pt/玉）")
                    Spacer()
                    DecimalPadTextField(
                        text: Binding(
                            get: { Self.decimalFieldString(session.payoutCoefficient) },
                            set: { session.payoutCoefficient = Double($0) ?? 0 }
                        ),
                        placeholder: "4.0",
                        maxIntegerDigits: 4,
                        maxFractionDigits: 4,
                        font: .preferredFont(forTextStyle: .body),
                        textColor: UIColor.white,
                        accentColor: UIColor(themeManager.currentTheme.accentColor)
                    )
                    .frame(minWidth: 80, minHeight: 36)
                    .multilineTextAlignment(.trailing)
                }
                .listRowBackground(themeManager.currentTheme.listRowBackground)
            }

            Section("計算用（変更時は期待値を再計算）") {
                HStack {
                    Text("実質投資（pt）")
                    Spacer()
                    DecimalPadTextField(
                        text: Binding(
                            get: { Self.decimalFieldString(session.totalRealCost) },
                            set: { session.totalRealCost = Double($0) ?? 0 }
                        ),
                        placeholder: "0",
                        maxIntegerDigits: 9,
                        maxFractionDigits: 2,
                        font: .preferredFont(forTextStyle: .body),
                        textColor: UIColor.white,
                        accentColor: UIColor(themeManager.currentTheme.accentColor)
                    )
                    .frame(minWidth: 80, minHeight: 36)
                    .multilineTextAlignment(.trailing)
                }
                .listRowBackground(themeManager.currentTheme.listRowBackground)
                HStack {
                    Text("ボーダー比（保存時）")
                    Spacer()
                    DecimalPadTextField(
                        text: Binding(
                            get: { Self.decimalFieldString(session.expectationRatioAtSave) },
                            set: { session.expectationRatioAtSave = Double($0) ?? 0 }
                        ),
                        placeholder: "1.0",
                        maxIntegerDigits: 2,
                        maxFractionDigits: 4,
                        font: .preferredFont(forTextStyle: .body),
                        textColor: UIColor.white,
                        accentColor: UIColor(themeManager.currentTheme.accentColor)
                    )
                    .frame(minWidth: 80, minHeight: 36)
                    .multilineTextAlignment(.trailing)
                }
                .listRowBackground(themeManager.currentTheme.listRowBackground)
                if session.expectationRatioAtSave == 0 || session.totalRealCost == 0 {
                    Text("期待値を出すには「実質投資」と「ボーダー比」を入力し、「期待値を再計算」をタップしてください。1.0＝基準、1.1＝10%上回り。")
                        .font(AppTypography.annotation)
                        .foregroundStyle(.white.opacity(0.7))
                        .listRowBackground(themeManager.currentTheme.listRowBackground)
                }
                Button("期待値を再計算") {
                    let ratio = session.expectationRatioAtSave > 0 ? session.expectationRatioAtSave : 1.0
                    let cost = session.totalRealCost > 0 ? session.totalRealCost : Double(session.inputCash)
                    session.theoreticalValue = PStatsCalculator.theoreticalValuePt(
                        totalRealCostPt: cost,
                        expectationRatio: ratio
                    )
                    if session.totalRealCost == 0 && session.inputCash > 0 {
                        session.totalRealCost = Double(session.inputCash)
                    }
                }
                .listRowBackground(themeManager.currentTheme.listRowBackground)
            }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("履歴を編集")
        .navigationBarTitleDisplayMode(.inline)
        .keyboardDismissToolbar()
        .toolbarColorScheme(.dark, for: .navigationBar)
        .preferredColorScheme(.dark)
        .onAppear {
            if selectedMachine == nil {
                selectedMachine = machines.first { $0.name == session.machineName }
            }
            if selectedShop == nil {
                selectedShop = shops.first { $0.name == session.shopName }
            }
            // 実質投資が未入力で総投資額がある場合は、現金投資を実質投資として補正（期待値計算のため）
            if session.totalRealCost == 0 && session.inputCash > 0 {
                session.totalRealCost = Double(session.inputCash)
            }
        }
    }

    private static func decimalFieldString(_ v: Double) -> String {
        if v == 0 { return "" }
        return String(v)
    }
}

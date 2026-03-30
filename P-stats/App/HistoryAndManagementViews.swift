import SwiftUI
import SwiftData
import UIKit

// MARK: - 機種管理（スワイプで編集・削除、並べ替え、右下FABで新規登録）
private let machineOrderKey = "machineDisplayOrder"
private let shopOrderKey = "shopDisplayOrder"

struct MachineManagementView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Machine.name) private var machines: [Machine]
    @Query(sort: \GameSession.date, order: .reverse) private var recentSessions: [GameSession]
    @AppStorage(machineOrderKey) private var machineOrderStr = ""
    @State private var machineToEdit: Machine?
    @State private var showNewMachine = false
    @State private var isReorderMode = false

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

    var body: some View {
        // bottomTrailing: フル画面の List がスクロール・スワイプを受け取る。FAB はドック直上の右下。
        // 行に listSelectionStyle() を付けない（DragGesture minimumDistance:0 が List の縦スクロール・swipeActions と競合するため）
        ZStack(alignment: .bottomTrailing) {
            StaticHomeBackgroundView()
            List {
                ForEach(machinesForList) { m in
                    Button {
                        guard !isReorderMode else { return }
                        machineToEdit = m
                    } label: {
                        HStack(alignment: .center) {
                            Text(m.name)
                                .foregroundColor(.white)
                            Spacer()
                            if !isReorderMode {
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundColor(cyan.opacity(0.8))
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                        .padding(.vertical, 12)
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(AppGlassStyle.rowBackground)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button {
                            machineToEdit = m
                        } label: { Label("編集", systemImage: "pencil") }
                        .tint(cyan)
                        Button(role: .destructive) {
                            modelContext.delete(m)
                            let arr = orderedMachines.filter { $0.persistentModelID != m.persistentModelID }
                            saveMachineOrder(arr)
                        } label: { Label("削除", systemImage: "trash") }
                    }
                    .moveDisabled(!isReorderMode)
                }
                .onMove { from, to in
                    guard isReorderMode else { return }
                    var arr = orderedMachines
                    arr.move(fromOffsets: from, toOffset: to)
                    saveMachineOrder(arr)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .contentMargins(.bottom, listBottomContentMargin, for: .scrollContent)
            .environment(\.editMode, .constant(isReorderMode ? .active : .inactive))

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
    }
}

// MARK: - 店舗管理（スワイプで編集・削除、右上並べ替え、右下FABで新規登録）
struct ShopManagementView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Shop.name) private var shops: [Shop]
    @AppStorage(shopOrderKey) private var shopOrderStr = ""
    @State private var shopToEdit: Shop?
    @State private var showNewShop = false
    @State private var isReorderMode = false

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

    var body: some View {
        // 行に listSelectionStyle() を付けない（機種管理と同様、List のスクロール・swipeActions と競合するため）
        ZStack(alignment: .bottomTrailing) {
            StaticHomeBackgroundView()
            List {
                ForEach(orderedShops) { s in
                    Button {
                        guard !isReorderMode else { return }
                        shopToEdit = s
                    } label: {
                        HStack(alignment: .center) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(s.name)
                                    .foregroundColor(.white)
                                if s.supportsChodamaService || s.chodamaBalanceBalls > 0 {
                                    Text("貯玉　\(s.chodamaBalanceBalls)玉")
                                        .font(.caption)
                                        .foregroundColor(.white.opacity(0.68))
                                }
                            }
                            Spacer()
                            if !isReorderMode {
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundColor(cyan.opacity(0.8))
                            }
                        }
                        .padding(.vertical, 12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .listRowBackground(AppGlassStyle.rowBackground)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            modelContext.delete(s)
                            let arr = orderedShops.filter { $0.persistentModelID != s.persistentModelID }
                            saveShopOrder(arr)
                        } label: { Label("削除", systemImage: "trash") }
                        Button {
                            shopToEdit = s
                        } label: { Label("編集", systemImage: "pencil") }
                        .tint(cyan)
                    }
                    .moveDisabled(!isReorderMode)
                }
                .onMove { from, to in
                    guard isReorderMode else { return }
                    var arr = orderedShops
                    arr.move(fromOffsets: from, toOffset: to)
                    saveShopOrder(arr)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .contentMargins(.bottom, listBottomContentMargin, for: .scrollContent)
            .environment(\.editMode, .constant(isReorderMode ? .active : .inactive))

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
                    .presentationDetents([.medium, .large])
            }
        }
        .sheet(isPresented: $showNewShop) {
            ShopEditView(shop: nil) { showNewShop = false }
                .presentationDetents([.medium, .large])
        }
    }
}

// MARK: - 続きから：直近5件の履歴から選んで同じ機種・店舗で再開（復元不可時）
struct ContinuePlaySelectionView: View {
    @Bindable var log: GameLog
    var restoreFailed: Bool = false
    var onStart: () -> Void
    var onCancel: () -> Void

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
                                .foregroundStyle(.white.opacity(0.5))
                            Text("遊戯履歴がありません")
                                .font(AppTypography.panelHeading)
                                .foregroundColor(.white)
                            Text("新規遊技スタートで遊戯を開始してください")
                                .font(AppTypography.bodyRounded)
                                .foregroundStyle(.white.opacity(0.85))
                        }
                        .padding(.vertical, 28)
                        .padding(.horizontal, 24)
                        .frame(maxWidth: .infinity)
                        .background(AppGlassStyle.cardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.panel))
                        .overlay(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.panel).stroke(AppGlassStyle.strokeGradient, lineWidth: 1))
                        .padding(.horizontal, 20)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        List {
                            Section {
                                Text("再開したい遊戯を選んでください。同じ機種・店舗で遊戯を開始します。")
                                    .font(.caption)
                                    .foregroundStyle(.white.opacity(0.7))
                                    .listRowBackground(AppGlassStyle.rowBackground)
                            }
                            ForEach(recentSessions, id: \.id) { session in
                                Button {
                                    resume(session)
                                } label: {
                                    VStack(alignment: .leading, spacing: 6) {
                                        HStack {
                                            Text(session.machineName)
                                                .font(.body.weight(.semibold))
                                                .foregroundColor(.white)
                                            Spacer()
                                            Text(JapaneseDateFormatters.yearMonthDay.string(from: session.date))
                                                .font(.caption)
                                                .foregroundColor(.white.opacity(0.95))
                                                .shadow(color: .black.opacity(0.7), radius: 2, x: 0, y: 1)
                                        }
                                        Text(session.shopName)
                                            .font(.subheadline)
                                            .foregroundStyle(.white.opacity(0.8))
                                    }
                                    .padding(.vertical, 4)
                                }
                                .listRowBackground(AppGlassStyle.rowBackground)
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
                                .shadow(color: .black.opacity(0.7), radius: 2, x: 0, y: 1)
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
        .toolbarColorScheme(.dark, for: .navigationBar)
        .preferredColorScheme(.dark)
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
            .preferredColorScheme(.dark)
        }
    }
}

// MARK: - 履歴詳細（タップで表示）。各パネルは角丸・不透明度85％・ラベル可読性向上
struct SessionDetailView: View {
    let session: GameSession
    @Environment(\.dismiss) private var dismiss
    @State private var showEditSheet = false

    private let panelBg = Color.black.opacity(0.85)
    private let labelColor = Color.white.opacity(0.95)
    private let labelShadow = (color: Color.black.opacity(0.7), radius: CGFloat(2), x: CGFloat(0), y: CGFloat(1))

    /// 回収額（pt換算）
    private var recoveryPt: Int { Int(Double(session.totalHoldings) * session.payoutCoefficient) }
    /// 実質回転率（回転/千pt）
    private var rotationPer1k: Double {
        guard session.inputCash > 0 else { return 0 }
        return Double(session.normalRotations) / (Double(session.inputCash) / 1000.0)
    }

    var body: some View {
        ZStack {
            StaticHomeBackgroundView()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    detailPanel(title: "記録日時") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(JapaneseDateFormatters.yearMonthDay.string(from: session.date))
                                .font(.body)
                                .foregroundColor(labelColor)
                                .shadow(color: labelShadow.color, radius: labelShadow.radius, x: labelShadow.x, y: labelShadow.y)
                        }
                    }

                    detailPanel(title: "機種・店舗") {
                        VStack(alignment: .leading, spacing: 8) {
                            detailRow(label: "機種", value: session.machineName)
                            detailRow(label: "店舗", value: session.shopName)
                            if !session.manufacturerName.isEmpty {
                                detailRow(label: "メーカー", value: session.manufacturerName)
                            }
                        }
                    }

                    detailPanel(title: "成績の推移") {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("投入（現金）")
                                        .font(.caption)
                                        .foregroundColor(labelColor)
                                        .shadow(color: labelShadow.color, radius: labelShadow.radius, x: labelShadow.x, y: labelShadow.y)
                                    Text(session.inputCash.formattedPtWithUnit)
                                        .font(.subheadline.monospacedDigit())
                                        .foregroundColor(.white)
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 4) {
                                    Text("回収（pt換算）")
                                        .font(.caption)
                                        .foregroundColor(labelColor)
                                        .shadow(color: labelShadow.color, radius: labelShadow.radius, x: labelShadow.x, y: labelShadow.y)
                                    Text(recoveryPt.formattedPtWithUnit)
                                        .font(.subheadline.monospacedDigit())
                                        .foregroundColor(.white)
                                }
                            }
                            GeometryReader { geo in
                                let w = geo.size.width
                                let total = max(session.inputCash + recoveryPt, 1)
                                let investW = w * CGFloat(session.inputCash) / CGFloat(total)
                                HStack(spacing: 0) {
                                    Rectangle()
                                        .fill(Color.orange.opacity(0.7))
                                        .frame(width: max(4, investW))
                                    Rectangle()
                                        .fill(Color.green.opacity(0.7))
                                        .frame(width: max(4, w - investW))
                                }
                            }
                            .frame(height: 24)
                        }
                    }

                    detailPanel(title: "数値サマリ") {
                        VStack(alignment: .leading, spacing: 8) {
                            detailRow(label: "総回転数", value: "\(session.normalRotations)")
                            detailRow(label: "総投入額（現金）", value: session.inputCash.formattedPtWithUnit)
                            detailRow(label: "回収出球", value: "\(session.totalHoldings) 玉")
                            detailRow(label: "回収額（pt換算）", value: recoveryPt.formattedPtWithUnit)
                            detailRow(label: "期待値", value: "\(session.theoreticalValue >= 0 ? "+" : "")\(session.theoreticalValue.formattedPtWithUnit)")
                            detailRow(label: "欠損・余剰", value: "\(session.deficitSurplus >= 0 ? "+" : "")\(session.deficitSurplus.formattedPtWithUnit)")
                            HStack {
                                Text("実成績")
                                    .font(.subheadline)
                                    .foregroundColor(labelColor)
                                    .shadow(color: labelShadow.color, radius: labelShadow.radius, x: labelShadow.x, y: labelShadow.y)
                                Spacer()
                                Text("\(session.performance >= 0 ? "+" : "")\(session.performance.formattedPtWithUnit)")
                                    .font(.body.weight(.semibold).monospacedDigit())
                                    .foregroundColor(session.performance >= 0 ? .green : .red)
                            }
                        }
                    }

                    detailPanel(title: "分析（入力データから算出）") {
                        VStack(alignment: .leading, spacing: 8) {
                            detailRow(label: "期待値比（保存時）", value: session.expectationRatioAtSave > 0 ? String(format: "%.2f%%", session.expectationRatioAtSave * 100) : "—")
                            detailRow(label: "実質回転率", value: String(format: "%.1f 回/1k", rotationPer1k))
                            detailRow(label: "RUSH当選", value: "\(session.rushWinCount) 回")
                            detailRow(label: "通常当選", value: "\(session.normalWinCount) 回")
                            detailRow(label: "LT当選", value: "\(session.ltWinCount) 回")
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
        .preferredColorScheme(.dark)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("編集") { showEditSheet = true }
            }
        }
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
            .preferredColorScheme(.dark)
        }
    }

    private func detailPanel<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(labelColor)
                .shadow(color: labelShadow.color, radius: labelShadow.radius, x: labelShadow.x, y: labelShadow.y)
            content()
                .foregroundColor(.white.opacity(0.9))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(panelBg)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(AppGlassStyle.strokeGradient, lineWidth: 1))
    }

    private func detailRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundColor(labelColor)
                .shadow(color: labelShadow.color, radius: labelShadow.radius, x: labelShadow.x, y: labelShadow.y)
            Spacer()
            Text(value)
                .font(.subheadline.monospacedDigit())
                .foregroundColor(.white)
        }
    }
}

// MARK: - 実戦履歴カード（1記録＝1枚の角丸グラスパネル）
struct HistorySessionCard: View {
    let session: GameSession

    private var rotationPer1k: Double {
        guard session.totalRealCost > 0 else { return 0 }
        return (Double(session.normalRotations) / session.totalRealCost) * 1000
    }
    private var rotationRateDisplay: String {
        if session.excludesFromRotationExpectationAnalytics { return "—（帳簿）" }
        if rotationPer1k <= 0 { return "—" }
        var s = String(format: "%.1f 回/1k", rotationPer1k)
        if session.formulaBorderPer1k > 0 {
            let diff = rotationPer1k - session.formulaBorderPer1k
            s += " (\(diff >= 0 ? "+" : "")\(String(format: "%.1f", diff)))"
        }
        return s
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(session.machineName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white)
                Spacer()
                Text(session.shopName)
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.8))
            }
            HStack(spacing: 16) {
                Text("実成績 \(session.performance >= 0 ? "+" : "")\(session.performance.formattedPtWithUnit)")
                    .font(.subheadline.monospacedDigit().weight(.medium))
                    .foregroundColor(session.performance >= 0 ? .green : .red)
                Text("当選 RUSH:\(session.rushWinCount) 通常:\(session.normalWinCount) LT:\(session.ltWinCount)")
                    .font(.subheadline.monospacedDigit())
                    .foregroundColor(.white.opacity(0.85))
            }
            HStack(spacing: 12) {
                labelValue("総回転", "\(session.normalRotations)")
                Text("・").foregroundColor(.white.opacity(0.5))
                labelValue("投入", session.inputCash.formattedPtWithUnit)
                Text("・").foregroundColor(.white.opacity(0.5))
                labelValue("回収玉", "\(session.totalHoldings)")
            }
            .font(.caption)
            .foregroundColor(.white.opacity(0.85))
            HStack(alignment: .top, spacing: 16) {
                miniblock("実戦回転率", value: rotationRateDisplay, valueColor: .white)
                miniblock("期待値", value: "\(session.theoreticalValue >= 0 ? "+" : "")\(session.theoreticalValue.formattedPtWithUnit)", valueColor: .white.opacity(0.9))
                deficitSurplusBlock
            }
            .font(.caption)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.black.opacity(0.85))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(AppGlassStyle.strokeGradient, lineWidth: 1)
        )
    }

    private var deficitSurplusBlock: some View {
        Group {
            if session.deficitSurplus > 0 {
                miniblock("余剰", value: "+\(session.deficitSurplus.formattedPtWithUnit)", valueColor: .green.opacity(0.9))
            } else if session.deficitSurplus < 0 {
                miniblock("欠損", value: session.deficitSurplus.formattedPtWithUnit, valueColor: .red.opacity(0.9))
            } else {
                miniblock("余剰・欠損", value: "0 pt", valueColor: .white.opacity(0.8))
            }
        }
    }

    private func miniblock(_ label: String, value: String, valueColor: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .foregroundColor(.white.opacity(0.65))
            Text(value)
                .font(.caption.monospacedDigit().weight(.medium))
                .foregroundColor(valueColor)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
    }

    private func labelValue(_ label: String, _ value: String) -> some View {
        HStack(spacing: 4) {
            Text(label + ":")
                .foregroundColor(.white.opacity(0.65))
            Text(value)
                .foregroundColor(.white)
        }
    }
}

// MARK: - 実戦履歴の編集（マイリスト参照＋一覧にない場合は手入力）
struct SessionEditView: View {
    @Bindable var session: GameSession
    @Environment(\.dismiss) private var dismiss
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
                    .listRowBackground(AppGlassStyle.rowBackground)
                }
                Text("一覧にない場合は下記で入力")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
                    .listRowBackground(AppGlassStyle.rowBackground)
                TextField("機種名（手入力）", text: $session.machineName)
                    .onChange(of: session.machineName) { _, _ in selectedMachine = nil }
                    .listRowBackground(AppGlassStyle.rowBackground)
                TextField("メーカー（分析用）", text: $session.manufacturerName)
                    .listRowBackground(AppGlassStyle.rowBackground)
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
                    .listRowBackground(AppGlassStyle.rowBackground)
                }
                Text("一覧にない場合は下記で入力")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
                    .listRowBackground(AppGlassStyle.rowBackground)
                TextField("店舗名（手入力）", text: $session.shopName)
                    .onChange(of: session.shopName) { _, _ in selectedShop = nil }
                    .listRowBackground(AppGlassStyle.rowBackground)
            }

            Section("数値") {
                HStack {
                    Text("投入（pt）")
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
                        accentColor: UIColor(AppGlassStyle.accent)
                    )
                    .frame(minWidth: 80, minHeight: 36)
                    .multilineTextAlignment(.trailing)
                }
                .listRowBackground(AppGlassStyle.rowBackground)
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
                        accentColor: UIColor(AppGlassStyle.accent)
                    )
                    .frame(minWidth: 80, minHeight: 36)
                    .multilineTextAlignment(.trailing)
                }
                .listRowBackground(AppGlassStyle.rowBackground)
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
                        accentColor: UIColor(AppGlassStyle.accent)
                    )
                    .frame(minWidth: 80, minHeight: 36)
                    .multilineTextAlignment(.trailing)
                }
                .listRowBackground(AppGlassStyle.rowBackground)
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
                        accentColor: UIColor(AppGlassStyle.accent)
                    )
                    .frame(minWidth: 80, minHeight: 36)
                    .multilineTextAlignment(.trailing)
                }
                .listRowBackground(AppGlassStyle.rowBackground)
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
                        accentColor: UIColor(AppGlassStyle.accent)
                    )
                    .frame(minWidth: 80, minHeight: 36)
                    .multilineTextAlignment(.trailing)
                }
                .listRowBackground(AppGlassStyle.rowBackground)
                HStack {
                    Text("LT当選回数")
                    Spacer()
                    IntegerPadTextField(
                        text: Binding(
                            get: { "\(session.ltWinCount)" },
                            set: { session.ltWinCount = Int($0) ?? 0 }
                        ),
                        placeholder: "0",
                        maxDigits: 5,
                        font: .preferredFont(forTextStyle: .body),
                        textColor: UIColor.white,
                        accentColor: UIColor(AppGlassStyle.accent)
                    )
                    .frame(minWidth: 80, minHeight: 36)
                    .multilineTextAlignment(.trailing)
                }
                .listRowBackground(AppGlassStyle.rowBackground)
                HStack {
                    Text("払出係数（pt/玉）")
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
                        accentColor: UIColor(AppGlassStyle.accent)
                    )
                    .frame(minWidth: 80, minHeight: 36)
                    .multilineTextAlignment(.trailing)
                }
                .listRowBackground(AppGlassStyle.rowBackground)
            }

            Section("計算用（変更時は期待値を再計算）") {
                HStack {
                    Text("実質投入（pt）")
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
                        accentColor: UIColor(AppGlassStyle.accent)
                    )
                    .frame(minWidth: 80, minHeight: 36)
                    .multilineTextAlignment(.trailing)
                }
                .listRowBackground(AppGlassStyle.rowBackground)
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
                        accentColor: UIColor(AppGlassStyle.accent)
                    )
                    .frame(minWidth: 80, minHeight: 36)
                    .multilineTextAlignment(.trailing)
                }
                .listRowBackground(AppGlassStyle.rowBackground)
                if session.expectationRatioAtSave == 0 || session.totalRealCost == 0 {
                    Text("期待値を出すには「実質投入」と「ボーダー比」を入力し、「期待値を再計算」をタップしてください。1.0＝基準、1.1＝10%上回り。")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.7))
                        .listRowBackground(AppGlassStyle.rowBackground)
                }
                Button("期待値を再計算") {
                    let ratio = session.expectationRatioAtSave > 0 ? session.expectationRatioAtSave : 1.0
                    let cost = session.totalRealCost > 0 ? session.totalRealCost : Double(session.inputCash)
                    session.theoreticalValue = Int(round(cost * (ratio - 1)))
                    if session.totalRealCost == 0 && session.inputCash > 0 {
                        session.totalRealCost = Double(session.inputCash)
                    }
                }
                .listRowBackground(AppGlassStyle.rowBackground)
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
            // 実質投入が未入力で総投入額がある場合は、現金投入を実質投入として補正（期待値計算のため）
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

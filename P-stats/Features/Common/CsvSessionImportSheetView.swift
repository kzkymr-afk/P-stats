import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// 実戦履歴（sessions）CSV の取り込み。プレミアム向け。
@MainActor
struct CsvSessionImportSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var themeManager: ThemeManager
    @Query(sort: \Machine.name) private var machines: [Machine]
    @Query(sort: \Shop.name) private var shops: [Shop]
    @Query(sort: \GameSession.date, order: .reverse) private var existingSessions: [GameSession]

    @State private var parsedRows: [CsvSessionImportService.ParsedSessionRow] = []
    @State private var machinePick: [UUID: PersistentIdentifier] = [:]
    @State private var shopPick: [UUID: PersistentIdentifier] = [:]
    @State private var showImporter = false
    @State private var parseErrorMessage: String?
    @State private var importErrorMessage: String?
    @State private var isImporting = false
    @State private var globalShopPick: PersistentIdentifier?
    @State private var skipLikelyDuplicates = true
    @State private var importResultMessage: String?

    private var cyan: Color { AppGlassStyle.accent }

    private var importableCount: Int {
        parsedRows.filter { r in
            r.canImport && machinePick[r.id] != nil && shopPick[r.id] != nil
        }.count
    }

    private var existingDuplicateKeys: Set<CsvSessionImportService.DuplicateKey> {
        Set(existingSessions.map(CsvSessionImportService.duplicateKey))
    }

    private func isLikelyDuplicate(_ row: CsvSessionImportService.ParsedSessionRow) -> Bool {
        guard row.canImport,
              let mid = machinePick[row.id],
              let sid = shopPick[row.id],
              let machine = machines.first(where: { $0.persistentModelID == mid }),
              let shop = shops.first(where: { $0.persistentModelID == sid })
        else { return false }
        guard let key = CsvSessionImportService.duplicateKey(
            for: row,
            selectedMachineName: machine.name,
            selectedShopName: shop.name,
            payoutCoefficientForShop: shop.interpretedPayoutCoefficientPtPerBall
        ) else { return false }
        return existingDuplicateKeys.contains(key)
    }

    var body: some View {
        ZStack {
            AppGlassStyle.background.ignoresSafeArea()
            if parsedRows.isEmpty {
                emptyState
            } else {
                reviewContent
            }
        }
        .navigationTitle("CSV から取り込み")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("閉じる") { dismiss() }
                    .foregroundColor(cyan)
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("取り込む") { runImport() }
                    .foregroundColor(cyan)
                    .disabled(importableCount == 0 || isImporting || machines.isEmpty || shops.isEmpty)
            }
        }
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [.commaSeparatedText, .plainText],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                let accessing = url.startAccessingSecurityScopedResource()
                defer {
                    if accessing { url.stopAccessingSecurityScopedResource() }
                }
                guard let data = try? Data(contentsOf: url) else {
                    parseErrorMessage = "ファイルを読み込めませんでした"
                    return
                }
                let body = RFC4180CSV.stripUTF8BOM(data)
                guard let text = String(data: body, encoding: .utf8) else {
                    parseErrorMessage = "UTF-8 として解釈できませんでした"
                    return
                }
                do {
                    let rows = try CsvSessionImportService.parseSessionsTable(text)
                    parsedRows = rows
                    applyDefaultPicks()
                } catch {
                    parseErrorMessage = error.localizedDescription
                }
            case .failure(let err):
                parseErrorMessage = err.localizedDescription
            }
        }
        .alert("読み込みエラー", isPresented: Binding(
            get: { parseErrorMessage != nil },
            set: { if !$0 { parseErrorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { parseErrorMessage = nil }
        } message: {
            Text(parseErrorMessage ?? "")
        }
        .alert("取り込みエラー", isPresented: Binding(
            get: { importErrorMessage != nil },
            set: { if !$0 { importErrorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { importErrorMessage = nil }
        } message: {
            Text(importErrorMessage ?? "")
        }
        .alert("CSV 取り込み", isPresented: Binding(
            get: { importResultMessage != nil },
            set: { if !$0 { importResultMessage = nil } }
        )) {
            Button("閉じる") {
                importResultMessage = nil
                dismiss()
            }
        } message: {
            Text(importResultMessage ?? "")
        }
        .preferredColorScheme(.dark)
    }

    private var emptyState: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                Text("このアプリで書き出した「sessions」CSV、または日時・投資・回収・機種・店名の列を含む表を読み込めます。機種名・店名は登録済みの一覧から行ごとに紐づけてください（CSV の表記ゆれに対応）。")
                    .font(AppTypography.bodyRounded)
                    .foregroundColor(.white.opacity(0.86))
                Text("最低限の列の例: date_iso8601（または date）、inputCash、totalHoldings または recovery_pt、machineName、shopName。当選回数は rushWinCount / normalWinCount、または winCount のみでも可です。")
                    .font(AppTypography.annotation)
                    .foregroundColor(.white.opacity(0.65))
                Button {
                    showImporter = true
                } label: {
                    Label("CSV ファイルを選ぶ", systemImage: "doc.badge.plus")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .foregroundColor(.black)
                        .background(cyan)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
            }
            .padding(20)
        }
    }

    private var reviewContent: some View {
        VStack(spacing: 0) {
            HStack {
                Text("\(parsedRows.count) 行（取り込み可能 \(importableCount) 件）")
                    .font(AppTypography.annotation)
                    .foregroundColor(.white.opacity(0.7))
                Spacer()
                Button {
                    showImporter = true
                } label: {
                    Text("別のファイル")
                        .font(AppTypography.annotationSemibold)
                        .foregroundColor(cyan)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Toggle(isOn: $skipLikelyDuplicates) {
                Text("既存データと重複しそうな行はスキップ")
                    .font(AppTypography.annotation)
                    .foregroundColor(.white.opacity(0.75))
            }
            .tint(cyan)
            .padding(.horizontal, 16)
            .padding(.bottom, 6)

            if !shops.isEmpty {
                HStack(spacing: 10) {
                    Text("全行の店舗")
                        .font(AppTypography.annotation)
                        .foregroundColor(.white.opacity(0.65))
                    Picker("", selection: $globalShopPick) {
                        Text("一括変更しない").tag(Optional<PersistentIdentifier>.none)
                        ForEach(shops) { s in
                            Text(s.name).tag(Optional(s.persistentModelID))
                        }
                    }
                    .tint(cyan)
                    .onChange(of: globalShopPick) { _, newVal in
                        guard let pid = newVal else { return }
                        for r in parsedRows where r.canImport {
                            shopPick[r.id] = pid
                        }
                    }
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }

            List {
                ForEach(parsedRows) { row in
                    rowCell(row)
                        .listRowBackground(Color.white.opacity(DesignTokens.Surface.WhiteOnDark.low))
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }

    @ViewBuilder
    private func rowCell(_ row: CsvSessionImportService.ParsedSessionRow) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("行 \(row.sourceLineNumber)")
                    .font(AppTypography.annotationSmallSemibold)
                    .foregroundColor(cyan.opacity(0.95))
                if row.isFullExportRow {
                    Text("フル書式")
                        .font(AppTypography.annotationSmall)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(cyan.opacity(0.2))
                        .foregroundColor(cyan)
                        .clipShape(Capsule())
                }
                if isLikelyDuplicate(row) {
                    Text("重複の可能性")
                        .font(AppTypography.annotationSmall)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(themeManager.currentTheme.cautionForegroundColor.opacity(DesignTokens.Surface.AccentTint.warningPanelBackground))
                        .foregroundColor(themeManager.currentTheme.cautionForegroundColor.opacity(0.95))
                        .clipShape(Capsule())
                }
                Spacer()
                if !row.canImport {
                    Text("要確認")
                        .font(AppTypography.annotationSmall)
                        .foregroundColor(themeManager.currentTheme.cautionForegroundColor)
                }
            }
            if !row.csvMachineName.isEmpty || !row.csvShopName.isEmpty {
                Text("CSV: \(row.csvMachineName) ／ \(row.csvShopName)")
                    .font(AppTypography.annotation)
                    .foregroundColor(Color.white.opacity(DesignTokens.Surface.WhiteOnDark.captionOnPanel))
            }
            if !row.issues.isEmpty {
                ForEach(row.issues, id: \.self) { iss in
                    Text(iss)
                        .font(AppTypography.annotationSmall)
                        .foregroundColor(themeManager.currentTheme.cautionForegroundColor.opacity(0.95))
                }
            }
            if row.canImport {
                Picker("機種", selection: machineBinding(for: row.id)) {
                    Text("選択してください").tag(Optional<PersistentIdentifier>.none)
                    ForEach(machines) { m in
                        Text(m.name).tag(Optional(m.persistentModelID))
                    }
                }
                .disabled(machines.isEmpty)
                Picker("店舗", selection: shopBinding(for: row.id)) {
                    Text("選択してください").tag(Optional<PersistentIdentifier>.none)
                    ForEach(shops) { s in
                        Text(s.name).tag(Optional(s.persistentModelID))
                    }
                }
                .disabled(shops.isEmpty)
            }
        }
        .padding(.vertical, 6)
    }

    private func machineBinding(for id: UUID) -> Binding<PersistentIdentifier?> {
        Binding(
            get: { machinePick[id] },
            set: { machinePick[id] = $0 }
        )
    }

    private func shopBinding(for id: UUID) -> Binding<PersistentIdentifier?> {
        Binding(
            get: { shopPick[id] },
            set: { shopPick[id] = $0 }
        )
    }

    private func applyDefaultPicks() {
        machinePick = [:]
        shopPick = [:]
        globalShopPick = nil
        for r in parsedRows {
            if r.canImport {
                machinePick[r.id] = CsvSessionImportService.bestMatchingMachine(csvName: r.csvMachineName, machines: machines)?.persistentModelID
                shopPick[r.id] = CsvSessionImportService.bestMatchingShop(csvName: r.csvShopName, shops: shops)?.persistentModelID
            }
        }
    }

    private func runImport() {
        guard importableCount > 0 else { return }
        isImporting = true
        defer { isImporting = false }
        var inserted = 0
        var skippedDup = 0
        for r in parsedRows {
            guard r.canImport,
                  let mid = machinePick[r.id],
                  let sid = shopPick[r.id],
                  let machine = machines.first(where: { $0.persistentModelID == mid }),
                  let shop = shops.first(where: { $0.persistentModelID == sid })
            else { continue }
            if skipLikelyDuplicates, isLikelyDuplicate(r) {
                skippedDup += 1
                continue
            }
            CsvSessionImportService.insertSession(from: r, machine: machine, shop: shop, modelContext: modelContext)
            inserted += 1
        }
        do {
            try modelContext.save()
            HapticUtil.impact(.medium)
            importResultMessage = "取り込み完了: \(inserted)件（重複スキップ: \(skippedDup)件）"
        } catch {
            importErrorMessage = error.localizedDescription
        }
    }
}

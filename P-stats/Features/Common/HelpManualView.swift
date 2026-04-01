import SwiftUI

// MARK: - Help / Manual UI

struct HelpManualView: View {
    @State private var query = ""
    private var cyan: Color { AppGlassStyle.accent }

    private var allItems: [(category: HelpCategory, item: HelpItem)] {
        HelpContent.categories.flatMap { cat in
            cat.items.map { (cat, $0) }
        }
    }

    private var filteredItems: [(category: HelpCategory, item: HelpItem)] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return allItems }
        let ql = q.lowercased()
        return allItems.filter { pair in
            let hay = [
                pair.category.title,
                pair.item.title,
                pair.item.bodyMarkdown,
                pair.item.tipMarkdown ?? "",
                pair.item.keywords.joined(separator: " ")
            ]
            .joined(separator: "\n")
            .lowercased()
            return hay.contains(ql)
        }
    }

    var body: some View {
        List {
            if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                ForEach(HelpContent.categories) { cat in
                    NavigationLink {
                        HelpCategoryDetailView(category: cat)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(cat.title)
                                    .foregroundStyle(.white.opacity(0.95))
                                Text("\(cat.items.count)件")
                                    .font(.caption)
                                    .foregroundStyle(AppGlassStyle.textSecondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(cyan.opacity(0.85))
                        }
                    }
                    .listRowBackground(AppGlassStyle.rowBackground)
                }
            } else {
                Section {
                    ForEach(filteredItems, id: \.item.id) { pair in
                        NavigationLink {
                            HelpItemDetailView(categoryTitle: pair.category.title, item: pair.item)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(pair.item.title)
                                    .foregroundStyle(AppGlassStyle.textPrimary)
                                Text(pair.category.title)
                                    .font(.caption)
                                    .foregroundStyle(AppGlassStyle.textSecondary)
                            }
                        }
                        .listRowBackground(AppGlassStyle.rowBackground)
                    }
                } header: {
                    Text("検索結果")
                        .foregroundStyle(AppGlassStyle.textSecondary)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppGlassStyle.background)
        .navigationTitle("マニュアル")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .automatic), prompt: "用語・機能を検索")
    }
}

private struct HelpCategoryDetailView: View {
    let category: HelpCategory
    private var cyan: Color { AppGlassStyle.accent }

    var body: some View {
        List {
            ForEach(category.items) { item in
                NavigationLink {
                    HelpItemDetailView(categoryTitle: category.title, item: item)
                } label: {
                    HStack {
                        Text(item.title)
                            .foregroundStyle(AppGlassStyle.textPrimary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(cyan.opacity(0.85))
                    }
                }
                .listRowBackground(AppGlassStyle.rowBackground)
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppGlassStyle.background)
        .navigationTitle(category.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct HelpItemDetailView: View {
    let categoryTitle: String
    let item: HelpItem
    private var cyan: Color { AppGlassStyle.accent }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 14) {
                Text(categoryTitle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(cyan.opacity(0.9))
                Text(item.title)
                    .font(AppTypography.panelHeading)
                    .foregroundStyle(AppGlassStyle.textPrimary)

                HelpMarkdownBlock(markdown: item.bodyMarkdown)

                if let tip = item.tipMarkdown, !tip.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    HelpTipBox(markdown: tip)
                }
            }
            .padding(18)
        }
        .background(AppGlassStyle.background)
        .navigationTitle("詳細")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct HelpTipBox: View {
    let markdown: String
    private var cyan: Color { AppGlassStyle.accent }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "lightbulb.fill")
                    .foregroundStyle(cyan)
                Text("補足")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppGlassStyle.textPrimary)
            }
            HelpMarkdownBlock(markdown: markdown)
        }
        .padding(12)
        .background(AppGlassStyle.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(cyan.opacity(0.25), lineWidth: 1)
        )
    }
}

private struct HelpMarkdownBlock: View {
    let markdown: String

    var body: some View {
        let md = markdown.trimmingCharacters(in: .whitespacesAndNewlines)
        if let attr = try? AttributedString(markdown: md, options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .full)) {
            Text(attr)
                .font(AppTypography.bodyRounded)
                .foregroundStyle(AppGlassStyle.textPrimary.opacity(0.92))
                .fixedSize(horizontal: false, vertical: true)
        } else {
            Text(md)
                .font(AppTypography.bodyRounded)
                .foregroundStyle(AppGlassStyle.textPrimary.opacity(0.92))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}


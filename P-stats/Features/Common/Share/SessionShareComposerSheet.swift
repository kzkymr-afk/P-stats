import SwiftUI

/// テンプレ選択→プレビュー→共有
@MainActor
struct SessionShareComposerSheet: View {
    let snapshot: SessionShareSnapshot
    @Environment(\.dismiss) private var dismiss
    @Environment(\.displayScale) private var displayScale
    @EnvironmentObject private var themeManager: ThemeManager

    @State private var template: SessionShareTemplate = .simple
    @State private var showShopName = true
    @State private var renderedImage: UIImage?
    @State private var isRendering = false
    @State private var shareItems: [Any] = []
    @State private var showShareSheet = false
    @State private var errorMessage: String?

    private var cyan: Color { themeManager.currentTheme.accentColor }

    var body: some View {
        NavigationStack {
            ZStack {
                AppGlassStyle.background.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 14) {
                        preview

                        VStack(alignment: .leading, spacing: 12) {
                            Text("テンプレート")
                                .font(AppTypography.panelHeading)
                                .foregroundStyle(.white)
                            Picker("", selection: $template) {
                                ForEach(SessionShareTemplate.allCases) { t in
                                    Text(t.displayName).tag(t)
                                }
                            }
                            .pickerStyle(.segmented)
                            .tint(cyan)

                            Toggle(isOn: $showShopName) {
                                Text("店舗名を表示する")
                                    .foregroundStyle(.white.opacity(0.9))
                            }
                            .tint(cyan)
                        }
                        .padding(14)
                        .pstatsPanelStyle()

                        Button {
                            openShareSheet()
                        } label: {
                            Label("共有する", systemImage: "square.and.arrow.up")
                                .fontWeight(.semibold)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .foregroundColor(.black)
                                .background(cyan)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                        .disabled(renderedImage == nil || isRendering)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 24)
                }
            }
            .navigationTitle("戦果をシェア")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                        .foregroundColor(cyan)
                }
            }
            .sheet(isPresented: $showShareSheet) {
                ActivityShareSheet(items: shareItems)
            }
            .alert("シェアの準備に失敗しました", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
            .preferredColorScheme(.dark)
            .onAppear { renderPreview() }
            .onChange(of: template) { _, _ in renderPreview() }
            .onChange(of: showShopName) { _, _ in renderPreview() }
        }
    }

    private var preview: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 18)
                    .fill(Color.black.opacity(DesignTokens.ShareCard.ComposerChrome.previewBackdrop))
                    .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.white.opacity(DesignTokens.ShareCard.ComposerChrome.previewStroke), lineWidth: DesignTokens.Thickness.hairline))

                if let img = renderedImage {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .padding(10)
                } else if isRendering {
                    ProgressView()
                        .tint(cyan)
                } else {
                    VStack(spacing: 10) {
                        Image(systemName: "photo")
                            .font(.system(size: 28, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.6))
                        Text("プレビューを生成します…")
                            .font(AppTypography.annotation)
                            .foregroundStyle(.white.opacity(0.6))
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 340)

            Text("生成された画像を確認してから共有できます。")
                .font(AppTypography.annotation)
                .foregroundStyle(.white.opacity(0.65))
        }
    }

    private func renderPreview() {
        isRendering = true
        defer { isRendering = false }
        do {
            let image = try ImageGenerator.render(
                size: CGSize(width: SessionShareCardView.cardWidth, height: SessionShareCardView.cardHeight),
                scale: displayScale
            ) {
                SessionShareCardView(snapshot: snapshot, showShopName: showShopName, template: template)
            }
            renderedImage = image
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func openShareSheet() {
        guard let image = renderedImage else { return }
        let hashtags = makeHashtags(machineName: snapshot.machineName, shopName: showShopName ? snapshot.shopName : nil)
        shareItems = [image, hashtags]
        showShareSheet = true
    }

    private func makeHashtags(machineName: String, shopName: String?) -> String {
        func normalizeTag(_ s: String) -> String {
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            if t.isEmpty { return "" }
            // X のハッシュタグとして極端に長いものや空白を軽く潰す（厳密変換はしない）
            return t.replacingOccurrences(of: " ", with: "")
                .replacingOccurrences(of: "　", with: "")
        }
        let m = normalizeTag(machineName)
        let s = shopName.map(normalizeTag) ?? ""
        var lines: [String] = []
        if !m.isEmpty { lines.append("#\(m)") }
        if !s.isEmpty { lines.append("#\(s)") }
        lines.append("#P-stats")
        return lines.joined(separator: "\n")
    }
}


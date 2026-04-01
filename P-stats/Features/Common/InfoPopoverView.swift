import SwiftUI

/// ⓘ アイコン。タップで注釈を表示（全画面にならない小さめのシート＋読みやすい文字サイズ）
struct InfoIconView: View {
    let explanation: String
    var tint: Color = .white.opacity(0.7)
    @State private var showExplanation = false

    var body: some View {
        Button {
            showExplanation = true
        } label: {
            Image(systemName: "info.circle")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(tint)
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showExplanation) {
            InfoExplanationSheet(explanation: explanation)
        }
    }
}

// MARK: - 説明シート（初期表示は画面の一部のみ。必要ならドラッグで中・大まで広げられる）
struct InfoExplanationSheet: View {
    let explanation: String
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.dismiss) private var dismiss

    /// 初回に選ぶデトント（1行でも全画面に見えないように低めにする）
    private var compactInitialDetent: PresentationDetent { .fraction(0.34) }
    private var regularInitialDetent: PresentationDetent { .fraction(0.42) }

    @State private var detent: PresentationDetent = .fraction(0.34)

    private static let sheetDetents: Set<PresentationDetent> = [
        .fraction(0.34),
        .fraction(0.42),
        .medium,
        .large
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(explanation)
                    .font(.body)
                    .fontWeight(.medium)
                    .lineSpacing(8)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 12)
                    .textSelection(.enabled)
            }
            .navigationTitle("説明")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("閉じる") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents(Self.sheetDetents, selection: $detent)
        .presentationDragIndicator(.visible)
        .onAppear {
            detent = horizontalSizeClass == .regular ? regularInitialDetent : compactInitialDetent
        }
    }
}

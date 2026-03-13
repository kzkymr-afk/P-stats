import SwiftUI

/// ⓘ アイコン。タップで注釈を小さく・フォント大きく、タップ位置付近にポップアップ表示
struct InfoIconView: View {
    let explanation: String
    var tint: Color = .white.opacity(0.7)
    @State private var showPopover = false

    var body: some View {
        Button {
            showPopover = true
        } label: {
            Image(systemName: "info.circle")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(tint)
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showPopover, attachmentAnchor: .point(.bottom)) {
            Text(explanation)
                .font(.subheadline)
                .foregroundColor(.primary)
                .padding(14)
                .frame(width: 200)
        }
        .presentationCompactAdaptation(.popover)
    }
}

/// ラベルとⓘを横に並べる。タイトル右に説明アイコンを置く用
struct LabelWithInfo: View {
    let title: String
    let explanation: String
    var tint: Color = .white.opacity(0.7)

    var body: some View {
        HStack(spacing: 4) {
            Text(title)
            InfoIconView(explanation: explanation, tint: tint)
        }
    }
}

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

import SwiftUI
import UIKit

/// 画像＋テキストの共有（X 等はここから）
struct ActivityShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let activity = UIActivityViewController(activityItems: items, applicationActivities: nil)
        return activity
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {
        // SwiftUI の sheet で「空の中間画面」を出さないため、UIActivityViewController を直接返す。
        // iPad のポップオーバー要件だけ満たす。
        if let pop = uiViewController.popoverPresentationController, pop.sourceView == nil {
            pop.sourceView = uiViewController.view
            pop.sourceRect = CGRect(x: uiViewController.view.bounds.midX, y: uiViewController.view.bounds.midY, width: 1, height: 1)
            pop.permittedArrowDirections = []
        }
    }
}


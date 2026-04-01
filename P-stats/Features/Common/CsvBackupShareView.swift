import SwiftUI
import UIKit

/// 共有シートを表示する軽量コンテナ。iPad では `popover` のアンカーを `view` に設定する。
final class CsvBackupShareContainerViewController: UIViewController {
    var fileURLs: [URL] = []
    var onComplete: (() -> Void)?

    private var didStartShare = false

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !didStartShare else { return }
        didStartShare = true

        let activity = UIActivityViewController(activityItems: fileURLs, applicationActivities: nil)
        if let pop = activity.popoverPresentationController {
            pop.sourceView = view
            pop.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 1, height: 1)
            pop.permittedArrowDirections = []
        }
        activity.completionWithItemsHandler = { [weak self] _, _, _, _ in
            guard let self else { return }
            CsvBackupExportService.removeTemporaryFiles(at: self.fileURLs)
            self.dismiss(animated: true) {
                self.onComplete?()
            }
        }
        present(activity, animated: true)
    }
}

/// 複数 CSV をシステムの共有シートで渡す（AirDrop・ファイルに保存など）
struct CsvBackupShareView: UIViewControllerRepresentable {
    let fileURLs: [URL]
    var onComplete: (() -> Void)?

    func makeUIViewController(context: Context) -> CsvBackupShareContainerViewController {
        let vc = CsvBackupShareContainerViewController()
        vc.fileURLs = fileURLs
        vc.onComplete = onComplete
        vc.view.backgroundColor = .clear
        return vc
    }

    func updateUIViewController(_ uiViewController: CsvBackupShareContainerViewController, context: Context) {}
}

import Foundation
import UIKit

// MARK: - 実戦画面用背景画像（ホームと別に設定可能）
enum PlayBackgroundStore {
    static let imageFileName = "PlayBackground.jpg"
    nonisolated static var documentsURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }
    nonisolated static func saveCustomImage(_ image: UIImage) -> String? {
        guard let data = image.jpegData(compressionQuality: 0.85) else { return nil }
        let name = "PlayBackground.jpg"
        let url = documentsURL.appendingPathComponent(name)
        try? data.write(to: url)
        return name
    }
    nonisolated static func loadCustomImage(fileName: String) -> UIImage? {
        guard !fileName.isEmpty else { return nil }
        let url = documentsURL.appendingPathComponent(fileName)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }
}

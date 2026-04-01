import Foundation
import UIKit

// MARK: - ホーム背景の保存・読み込み
enum HomeBackgroundStore {
    static let defaultStyle = "cyber"
    static let customImageFileName = "HomeBackground.jpg"

    nonisolated static var documentsURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
    }

    nonisolated static func saveCustomImage(_ image: UIImage) -> String? {
        let name = "HomeBackground.jpg"
        guard let data = image.jpegData(compressionQuality: 0.85) else { return nil }
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

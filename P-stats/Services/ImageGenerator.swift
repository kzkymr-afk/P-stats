import SwiftUI

// MARK: - SwiftUI → UIImage (iOS 16+)

@MainActor
enum ImageGenerator {
    struct RenderError: Error, LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    static func render<Content: View>(
        size: CGSize,
        scale: CGFloat,
        @ViewBuilder content: () -> Content
    ) throws -> UIImage {
        let renderer = ImageRenderer(content: content())
        renderer.scale = scale
        renderer.proposedSize = ProposedViewSize(size)
        if let ui = renderer.uiImage { return ui }
        throw RenderError(message: "画像の生成に失敗しました")
    }
}


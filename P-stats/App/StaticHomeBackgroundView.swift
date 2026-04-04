import SwiftUI
import UIKit

// MARK: - 共通背景（実戦履歴・分析で使用。トップと同じビジュアルだが静止）
struct StaticHomeBackgroundView: View {
    @AppStorage("homeBackgroundStyle") private var homeBackgroundStyle = HomeBackgroundStore.defaultStyle
    @AppStorage("homeBackgroundImagePath") private var homeBackgroundImagePath = ""
    @State private var loadedBackgroundImage: UIImage?

    private let cyan = AppGlassStyle.accent
    private var orbPrimary: Color {
        Color(
            red: DesignTokens.HomeBackground.orbPrimaryR,
            green: DesignTokens.HomeBackground.orbPrimaryG,
            blue: DesignTokens.HomeBackground.orbPrimaryB
        )
    }
    private var orbSecondary: Color {
        Color(
            red: DesignTokens.HomeBackground.orbSecondaryR,
            green: DesignTokens.HomeBackground.orbSecondaryG,
            blue: DesignTokens.HomeBackground.orbSecondaryB
        )
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                if homeBackgroundStyle == "custom", let uiImage = loadedBackgroundImage {
                    Image(uiImage: uiImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                } else {
                    AppDesignSystem.Background.base
                    orbViewStatic(color: cyan, x: 0.2, y: 0.15, geo: geo)
                    orbViewStatic(color: orbPrimary, x: 0.75, y: 0.3, geo: geo)
                    orbViewStatic(color: orbSecondary, x: 0.5, y: 0.75, geo: geo)
                    geometricLineStatic(geo: geo)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .onAppear {
            if homeBackgroundStyle == "custom", !homeBackgroundImagePath.isEmpty {
                let path = homeBackgroundImagePath
                Task.detached(priority: .userInitiated) { @Sendable () async in
                    let img = HomeBackgroundStore.loadCustomImage(fileName: path)
                    await MainActor.run { loadedBackgroundImage = img }
                }
            }
        }
        .onChange(of: homeBackgroundStyle) { _, new in
            if new == "custom", !homeBackgroundImagePath.isEmpty {
                let path = homeBackgroundImagePath
                Task.detached(priority: .userInitiated) { @Sendable () async in
                    let img = HomeBackgroundStore.loadCustomImage(fileName: path)
                    await MainActor.run { loadedBackgroundImage = img }
                }
            } else { loadedBackgroundImage = nil }
        }
        .onChange(of: homeBackgroundImagePath) { _, new in
            if homeBackgroundStyle == "custom", !new.isEmpty {
                Task.detached(priority: .userInitiated) { @Sendable () async in
                    let img = HomeBackgroundStore.loadCustomImage(fileName: new)
                    await MainActor.run { loadedBackgroundImage = img }
                }
            } else { loadedBackgroundImage = nil }
        }
    }

    private func orbViewStatic(color: Color, x: CGFloat, y: CGFloat, geo: GeometryProxy) -> some View {
        let size = geo.size.width * 0.6
        return Circle()
            .fill(color.opacity(0.25))
            .frame(width: size, height: size)
            .blur(radius: 80)
            .offset(x: (x - 0.5) * geo.size.width, y: (y - 0.5) * geo.size.height)
    }

    private func geometricLineStatic(geo: GeometryProxy) -> some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [.clear, cyan.opacity(0.04), .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .frame(width: geo.size.width, height: 2)
            .position(x: geo.size.width / 2, y: geo.size.height / 2)
    }
}

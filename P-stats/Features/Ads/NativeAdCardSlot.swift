import GoogleMobileAds
import SwiftUI
import UIKit

/// リスト用ネイティブ広告カード（`GADNativeAd`）。見た目は実戦カードに近いダークパネル。
struct NativeAdCardSlot: UIViewRepresentable {
    let placementID: String

    func makeCoordinator() -> Coordinator {
        Coordinator(placementID: placementID, adUnitID: AdMobConfig.nativeAdUnitID)
    }

    func makeUIView(context: Context) -> GADNativeAdView {
        context.coordinator.buildShellView()
    }

    func updateUIView(_ nativeAdView: GADNativeAdView, context: Context) {
        context.coordinator.attachIfNeeded(nativeAdView)
        nativeAdView.layer.cornerRadius = 14
        nativeAdView.clipsToBounds = true
    }

    @MainActor
    final class Coordinator: NSObject, GADNativeAdLoaderDelegate, GADNativeAdDelegate {
        let placementID: String
        let adUnitID: String
        private var loader: GADAdLoader?
        private weak var shell: GADNativeAdView?
        private var loadStarted = false

        init(placementID: String, adUnitID: String) {
            self.placementID = placementID
            self.adUnitID = adUnitID
        }

        func attachIfNeeded(_ view: GADNativeAdView) {
            shell = view
            startLoadIfNeeded()
        }

        func buildShellView() -> GADNativeAdView {
            let v = GADNativeAdView()
            v.backgroundColor = UIColor.pstatsSRGB(
                red: DesignTokens.Glass.dockBackgroundTopR,
                green: DesignTokens.Glass.dockBackgroundTopG,
                blue: DesignTokens.Glass.dockBackgroundTopB,
                alpha: 0.95
            )
            v.layer.cornerRadius = 14
            v.clipsToBounds = true

            let adMark = UILabel()
            adMark.text = "広告"
            adMark.font = .systemFont(ofSize: 10, weight: .semibold)
            adMark.textColor = UIColor.white.withAlphaComponent(0.45)
            adMark.translatesAutoresizingMaskIntoConstraints = false

            let iconView = UIImageView()
            iconView.contentMode = .scaleAspectFill
            iconView.clipsToBounds = true
            iconView.layer.cornerRadius = 8
            iconView.backgroundColor = UIColor.white.withAlphaComponent(0.08)
            iconView.translatesAutoresizingMaskIntoConstraints = false

            let headline = UILabel()
            headline.font = .systemFont(ofSize: 14, weight: .semibold)
            headline.textColor = .white
            headline.numberOfLines = 2
            headline.translatesAutoresizingMaskIntoConstraints = false

            let body = UILabel()
            body.font = .systemFont(ofSize: 12)
            body.textColor = UIColor.white.withAlphaComponent(0.82)
            body.numberOfLines = 2
            body.translatesAutoresizingMaskIntoConstraints = false

            let advertiser = UILabel()
            advertiser.font = .systemFont(ofSize: 10)
            advertiser.textColor = UIColor.white.withAlphaComponent(0.5)
            advertiser.numberOfLines = 1
            advertiser.translatesAutoresizingMaskIntoConstraints = false

            let cta = UIButton(type: .system)
            var ctaConfig = UIButton.Configuration.plain()
            ctaConfig.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 14, bottom: 8, trailing: 14)
            ctaConfig.baseForegroundColor = UIColor.pstatsSRGB(
                red: DesignTokens.NativeAd.ctaForegroundR,
                green: DesignTokens.NativeAd.ctaForegroundG,
                blue: DesignTokens.NativeAd.ctaForegroundB,
                alpha: 1
            )
            ctaConfig.background.backgroundColor = UIColor.white.withAlphaComponent(0.1)
            ctaConfig.background.cornerRadius = 8
            ctaConfig.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
                var out = incoming
                out.font = .systemFont(ofSize: 13, weight: .semibold)
                return out
            }
            cta.configuration = ctaConfig
            cta.translatesAutoresizingMaskIntoConstraints = false

            let media = GADMediaView()
            media.translatesAutoresizingMaskIntoConstraints = false

            v.addSubview(adMark)
            v.addSubview(iconView)
            v.addSubview(headline)
            v.addSubview(body)
            v.addSubview(advertiser)
            v.addSubview(cta)
            v.addSubview(media)

            v.iconView = iconView
            v.headlineView = headline
            v.bodyView = body
            v.advertiserView = advertiser
            v.callToActionView = cta
            v.mediaView = media

            NSLayoutConstraint.activate([
                adMark.topAnchor.constraint(equalTo: v.topAnchor, constant: 10),
                adMark.trailingAnchor.constraint(equalTo: v.trailingAnchor, constant: -12),

                iconView.leadingAnchor.constraint(equalTo: v.leadingAnchor, constant: 12),
                iconView.topAnchor.constraint(equalTo: v.topAnchor, constant: 12),
                iconView.widthAnchor.constraint(equalToConstant: 48),
                iconView.heightAnchor.constraint(equalToConstant: 48),

                headline.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 10),
                headline.trailingAnchor.constraint(equalTo: v.trailingAnchor, constant: -12),
                headline.topAnchor.constraint(equalTo: iconView.topAnchor),

                body.leadingAnchor.constraint(equalTo: headline.leadingAnchor),
                body.trailingAnchor.constraint(equalTo: headline.trailingAnchor),
                body.topAnchor.constraint(equalTo: headline.bottomAnchor, constant: 4),

                advertiser.leadingAnchor.constraint(equalTo: headline.leadingAnchor),
                advertiser.trailingAnchor.constraint(lessThanOrEqualTo: v.trailingAnchor, constant: -12),
                advertiser.topAnchor.constraint(equalTo: body.bottomAnchor, constant: 4),

                cta.leadingAnchor.constraint(equalTo: v.leadingAnchor, constant: 12),
                cta.trailingAnchor.constraint(equalTo: v.trailingAnchor, constant: -12),
                cta.topAnchor.constraint(equalTo: iconView.bottomAnchor, constant: 10),

                media.leadingAnchor.constraint(equalTo: v.leadingAnchor, constant: 12),
                media.trailingAnchor.constraint(equalTo: v.trailingAnchor, constant: -12),
                media.topAnchor.constraint(equalTo: cta.bottomAnchor, constant: 8),
                media.heightAnchor.constraint(equalToConstant: 120),
                media.bottomAnchor.constraint(equalTo: v.bottomAnchor, constant: -12),
            ])

            shell = v
            return v
        }

        private func startLoadIfNeeded() {
            guard !loadStarted else { return }
            loadStarted = true
            guard let root = Self.keyRootViewController() else { return }
            let options = GADNativeAdMediaAdLoaderOptions()
            options.mediaAspectRatio = .portrait
            let loader = GADAdLoader(
                adUnitID: adUnitID,
                rootViewController: root,
                adTypes: [.native],
                options: [options]
            )
            loader.delegate = self
            self.loader = loader
            loader.load(GADRequest())
        }

        func adLoader(_ adLoader: GADAdLoader, didReceive nativeAd: GADNativeAd) {
            guard let v = shell else { return }
            nativeAd.delegate = self
            (v.headlineView as? UILabel)?.text = nativeAd.headline
            (v.bodyView as? UILabel)?.text = nativeAd.body
            (v.advertiserView as? UILabel)?.text = nativeAd.advertiser
            (v.callToActionView as? UIButton)?.setTitle(nativeAd.callToAction, for: .normal)
            (v.iconView as? UIImageView)?.image = nativeAd.icon?.image
            v.mediaView?.mediaContent = nativeAd.mediaContent
            v.mediaView?.isHidden = !nativeAd.mediaContent.hasVideoContent && (nativeAd.mediaContent.aspectRatio <= 0)
            v.nativeAd = nativeAd
        }

        func adLoader(_ adLoader: GADAdLoader, didFailToReceiveAdWithError error: Error) {
            shell?.isHidden = true
        }

        fileprivate static func keyRootViewController() -> UIViewController? {
            let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            let scene = scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first
            return scene?.windows.first(where: \.isKeyWindow)?.rootViewController
        }
    }
}

/// `EntitlementsStore` により広告オフのときは描画しない。
struct OptionalNativeAdCardSlot: View {
    let placementID: String
    @ObservedObject private var adVisibility = AdVisibilityManager.shared

    var body: some View {
        if adVisibility.shouldShowBanner {
            NativeAdCardSlot(placementID: placementID)
                .frame(minHeight: 200)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

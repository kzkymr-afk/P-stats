import Foundation

// MARK: - AdMob 広告ユニット
//
// テスト広告の公式な方法（どちらか／併用）:
// 1. Google 提供のデモ広告ユニット ID を使う（アカウントに紐づかず無効トラフィックにならない）
// 2. AdMob コンソールまたは SDK で「テスト端末」を登録し、**本番の**広告ユニット ID で "Test mode" 表示にする
//
// https://developers.google.com/admob/ios/test-ads

/// AdMob のバナー設定。`Info.plist` の `GADApplicationIdentifier` はアプリ ID（~ の形式）。
enum AdMobConfig {
    // MARK: Google 公式デモ ID（テスト専用・無効トラフィック回避）

    /// Adaptive Banner 用デモ。`GADCurrentOrientationAnchoredAdaptiveBannerAdSizeWithWidth` 利用時はこちらを推奨。
    /// https://developers.google.com/admob/ios/test-ads#demo_ad_units
    static let googleDemoAdaptiveBannerAdUnitID = "ca-app-pub-3940256099942544/2435281174"

    /// Fixed Size Banner 用デモ（固定サイズ API 向け）。
    static let googleDemoFixedSizeBannerAdUnitID = "ca-app-pub-3940256099942544/2934735716"

    /// インタースティシャル用デモ
    static let googleDemoInterstitialAdUnitID = "ca-app-pub-3940256099942544/4411468910"

    /// アプリ起動広告用デモ
    static let googleDemoAppOpenAdUnitID = "ca-app-pub-3940256099942544/5575463023"

    /// ネイティブ（ネイティブ アドバンスド）用デモ
    /// https://developers.google.com/admob/ios/test-ads#demo_ad_units
    static let googleDemoNativeAdUnitID = "ca-app-pub-3940256099942544/3986624511"

    /// リワード用デモ
    static let googleDemoRewardedAdUnitID = "ca-app-pub-3940256099942544/1712485313"

    // MARK: 本番

    /// **リリース（Release）ビルド**で読み込む本番バナー広告ユニット ID。
    /// AdMob コンソールで作成した `ca-app-pub-…/…` に差し替えてください。空のままだと Release でもデモ ID にフォールバックします。
    static let productionBannerAdUnitID = "ca-app-pub-6247409434954317/1957626290"

    /// 本番インタースティシャル ID。空ならデモにフォールバック。
    static let productionInterstitialAdUnitID = "ca-app-pub-6247409434954317/8935969748"

    /// 本番アプリ起動広告 ID。空ならデモにフォールバック。
    static let productionAppOpenAdUnitID = "ca-app-pub-6247409434954317/7637328387"

    /// 本番ネイティブ広告 ID。空ならデモにフォールバック。
    static let productionNativeAdUnitID = "ca-app-pub-6247409434954317/8331462955"

    /// 本番リワード ID。空ならデモにフォールバック。
    static let productionRewardedAdUnitID = "ca-app-pub-6247409434954317/7698909695"

    /// アプリが実際にリクエストするバナー広告ユニット ID。
    static var bannerUnitID: String {
        #if DEBUG
        googleDemoAdaptiveBannerAdUnitID
        #else
        let trimmed = productionBannerAdUnitID.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? googleDemoAdaptiveBannerAdUnitID : trimmed
        #endif
    }

    static var interstitialUnitID: String {
        #if DEBUG
        googleDemoInterstitialAdUnitID
        #else
        let trimmed = productionInterstitialAdUnitID.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? googleDemoInterstitialAdUnitID : trimmed
        #endif
    }

    static var appOpenUnitID: String {
        #if DEBUG
        googleDemoAppOpenAdUnitID
        #else
        let trimmed = productionAppOpenAdUnitID.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? googleDemoAppOpenAdUnitID : trimmed
        #endif
    }

    static var nativeAdUnitID: String {
        #if DEBUG
        googleDemoNativeAdUnitID
        #else
        let trimmed = productionNativeAdUnitID.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? googleDemoNativeAdUnitID : trimmed
        #endif
    }

    static var rewardedAdUnitID: String {
        #if DEBUG
        googleDemoRewardedAdUnitID
        #else
        let trimmed = productionRewardedAdUnitID.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? googleDemoRewardedAdUnitID : trimmed
        #endif
    }
}

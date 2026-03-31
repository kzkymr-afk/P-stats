import GoogleMobileAds
import SwiftUI

@main
struct P_statsApp: App {
    init() {
        #if DEBUG
        // DEBUG では `AdMobConfig.bannerUnitID` が Google 公式デモ（Adaptive）を向く。
        // 本番ユニットで実機テストし「Test mode」ラベルを出したい場合: 広告1回ロード後に Xcode ログに出る
        // device ID をコピーし、次を有効化する。
        // GADMobileAds.sharedInstance().requestConfiguration.testDeviceIdentifiers = [ "……" ]
        // シミュレータは通常テスト端末扱い（公式ドキュメント参照）。
        #endif
        #if DEBUG
        if let raw = UserDefaults.standard.string(forKey: "GADTestDeviceIDs"), !raw.isEmpty {
            let ids = raw.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            if !ids.isEmpty {
                GADMobileAds.sharedInstance().requestConfiguration.testDeviceIdentifiers = ids
            }
        }
        #endif
        GADMobileAds.sharedInstance().start(completionHandler: nil)
        DispatchQueue.main.async {
            AppOpenAdPresenter.preload()
        }
        _ = EntitlementsStore.shared
    }

    var body: some Scene {
        WindowGroup {
            AppBootstrapView()
                .environment(\.locale, Locale(identifier: "ja_JP"))
        }
    }
}

import Foundation
import CoreLocation
import Combine

/// 現在地取得を担うマネージャー。CLLocationManager のラッパー。
final class LocationManager: NSObject, ObservableObject {
    private let manager = CLLocationManager()
    
    @Published private(set) var currentLocation: CLLocation?
    @Published private(set) var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published private(set) var isLoading = false
    
    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        manager.distanceFilter = 100
    }
    
    /// 位置情報の利用許諾をリクエスト（アプリ使用中のみ）
    func requestWhenInUseAuthorization() {
        manager.requestWhenInUseAuthorization()
    }
    
    /// 現在地を取得開始。許諾済みなら location が更新される
    func startUpdatingLocation() {
        authorizationStatus = manager.authorizationStatus
        guard authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways else {
            return
        }
        isLoading = true
        manager.startUpdatingLocation()
    }
    
    func stopUpdatingLocation() {
        manager.stopUpdatingLocation()
        isLoading = false
    }
    
    /// 現在地が利用可能か（許諾済みかつ緯度経度あり）
    var hasValidLocation: Bool {
        guard authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways else {
            return false
        }
        return currentLocation != nil
    }
    
    /// 緯度経度の文字列 "lat,lng"（API用）。取得できていなければ nil
    var locationStringForAPI: String? {
        guard let loc = currentLocation else { return nil }
        return "\(loc.coordinate.latitude),\(loc.coordinate.longitude)"
    }
}

extension LocationManager: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        currentLocation = locations.last
        isLoading = false
        manager.stopUpdatingLocation()
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        isLoading = false
        manager.stopUpdatingLocation()
    }
    
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
    }
}

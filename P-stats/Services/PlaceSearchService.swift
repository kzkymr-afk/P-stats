import Foundation
import Combine
import CoreLocation
import os

/// Places API の HTTP エラー（デバッグ用）
private enum PlacesAPIError: Error {
    case httpError(statusCode: Int)
}

/// 店舗検索候補1件（Google Places Text Search / Nearby 結果）
struct PlaceCandidate: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let address: String
    /// 現在地からの距離（メートル）。nil の場合は非表示
    let distanceMeters: Double?

    var distanceLabel: String? {
        guard let m = distanceMeters, m >= 0, m.isFinite, !m.isNaN else { return nil }
        if m < 1000 { return m.displayFormat("%.0fm") }
        return (m / 1000).displayFormat("%.1fkm")
    }

    nonisolated init(id: String, name: String, address: String, distanceMeters: Double? = nil) {
        self.id = id
        self.name = name
        self.address = address
        self.distanceMeters = distanceMeters
    }
}

/// 店舗検索用サービス。キーワード＝Text Search、周辺＝Nearby Search（ボタン押下時のみ）。
final class PlaceSearchService: ObservableObject {
    @Published var searchText: String = ""
    @Published private(set) var candidates: [PlaceCandidate] = []
    @Published private(set) var nearbyCandidates: [PlaceCandidate] = []
    @Published private(set) var isSearching: Bool = false
    @Published private(set) var isFetchingNearby: Bool = false
    @Published private(set) var hasNextPage: Bool = false
    @Published private(set) var isLoadingMore: Bool = false

    private let debounceInterval: TimeInterval
    private var searchTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()
    private let locationManager: LocationManager
    private var lastTextSearchPageToken: String?

    var apiKey: String? {
        Bundle.main.object(forInfoDictionaryKey: "GooglePlacesAPIKey") as? String
    }
    /// APIキーが未設定だと常にモックデータのみ表示される（本番検索が動かない）
    var isApiKeyConfigured: Bool {
        guard let k = apiKey else { return false }
        return !k.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var canUseLocation: Bool { locationManager.hasValidLocation }
    var isLocationDenied: Bool {
        let s = locationManager.authorizationStatus
        return s == .denied || s == .restricted
    }

    init(debounceInterval: TimeInterval = 0.4, locationManager: LocationManager = LocationManager()) {
        self.debounceInterval = debounceInterval
        self.locationManager = locationManager
        setupDebounce()
    }

    private func setupDebounce() {
        $searchText
            .debounce(for: .seconds(debounceInterval), scheduler: RunLoop.main)
            .removeDuplicates()
            .sink { [weak self] text in
                self?.performSearch(query: text)
            }
            .store(in: &cancellables)
    }

    /// 位置情報のリクエストと取得開始のみ。周辺検索は「現在地周辺から探す」ボタン押下時のみ実行。
    func requestLocation() {
        locationManager.requestWhenInUseAuthorization()
        locationManager.startUpdatingLocation()
    }

    private func performSearch(query: String) {
        searchTask?.cancel()
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            candidates = []
            hasNextPage = false
            lastTextSearchPageToken = nil
            isSearching = false
            return
        }
        isSearching = true
        lastTextSearchPageToken = nil
        let loc = locationManager.locationStringForAPI
        let queryWithPachinko = trimmed + " パチンコ店"
        searchTask = Task { @MainActor in
            do {
                var result: [PlaceCandidate]
                var nextToken: String?
                if let key = apiKey, !key.isEmpty {
                    (result, nextToken) = try await fetchTextSearch(query: queryWithPachinko, apiKey: key, location: loc, pageToken: nil)
                    if result.isEmpty, !trimmed.hasSuffix(" パチンコ") {
                        let fallback = try await fetchTextSearch(query: trimmed + " パチンコ", apiKey: key, location: loc, pageToken: nil)
                        result = fallback.0
                        nextToken = fallback.1
                    }
                } else {
                    result = mockCandidates(for: queryWithPachinko, location: loc)
                    nextToken = nil
                }
                result = result.filter { !PlaceSearchFilter.shouldExclude(name: $0.name) }
                if loc != nil {
                    result = result.sorted { ($0.distanceMeters ?? .infinity) < ($1.distanceMeters ?? .infinity) }
                }
                if !Task.isCancelled {
                    candidates = result
                    lastTextSearchPageToken = nextToken
                    hasNextPage = nextToken != nil
                    nearbyCandidates = []
                }
            } catch {
                if !Task.isCancelled { candidates = []; hasNextPage = false; nearbyCandidates = [] }
            }
            isSearching = false
        }
    }

    /// キーワード検索の次の20件を追加（next_page_token 使用）
    func loadMoreKeywordResults() {
        guard let token = lastTextSearchPageToken, !token.isEmpty, let key = apiKey, !key.isEmpty else { return }
        if isLoadingMore { return }
        isLoadingMore = true
        Task { @MainActor in
            do {
                try await Task.sleep(nanoseconds: 500_000_000) // 0.5秒（Google の token 有効化待ち）
                let (additional, nextToken) = try await fetchTextSearchPageToken(pagetoken: token, apiKey: key)
                let filtered = additional.filter { !PlaceSearchFilter.shouldExclude(name: $0.name) }
                if !Task.isCancelled {
                    candidates.append(contentsOf: filtered)
                    if locationManager.locationStringForAPI != nil {
                        candidates.sort { ($0.distanceMeters ?? .infinity) < ($1.distanceMeters ?? .infinity) }
                    }
                    lastTextSearchPageToken = nextToken
                    hasNextPage = nextToken != nil
                }
            } catch {
                if !Task.isCancelled { hasNextPage = false }
            }
            isLoadingMore = false
        }
    }

    /// 現在地周辺のパチンコ店を取得（「現在地周辺から探す」ボタン押下時のみ）。重い処理はメインスレッド外で実行。
    func fetchNearbyPachinkoIfNeeded() {
        guard canUseLocation, let locStr = locationManager.locationStringForAPI else {
            nearbyCandidates = []
            return
        }
        let userLoc = locationManager.currentLocation
        isFetchingNearby = true

        guard let apiKeyValue = apiKey?.trimmingCharacters(in: .whitespacesAndNewlines), !apiKeyValue.isEmpty else {
            let result = mockNearbyCandidates(location: locStr)
            let filtered = result.filter { !PlaceSearchFilter.shouldExclude(name: $0.name) }
            nearbyCandidates = filtered
            isFetchingNearby = false
            return
        }

        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            do {
                let result = try await self.fetchNearbySearch(apiKey: apiKeyValue, location: locStr, userLocation: userLoc)
                let filtered = result.filter { !PlaceSearchFilter.shouldExclude(name: $0.name) }
                await MainActor.run {
                    self.nearbyCandidates = filtered
                    self.isFetchingNearby = false
                }
            } catch {
                await MainActor.run {
                    self.nearbyCandidates = []
                    self.isFetchingNearby = false
                }
            }
        }
    }

    private static func performPlacesRequest(url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        if let bundleId = Bundle.main.bundleIdentifier {
            request.setValue(bundleId, forHTTPHeaderField: "X-Ios-Bundle-Identifier")
        }
        #if DEBUG
        AppLog.places.debug("Places request host=\(url.host ?? "nil", privacy: .public)")
        #endif
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
            AppLog.places.error("Places API HTTP error status=\(http.statusCode, privacy: .public)")
            #if DEBUG
            AppLog.places.debug("Places error response bytes=\(data.count, privacy: .public)")
            #endif
            throw PlacesAPIError.httpError(statusCode: http.statusCode)
        }
        #if DEBUG
        if let http = response as? HTTPURLResponse, http.statusCode == 200,
           let body = String(data: data, encoding: .utf8), body.contains("\"status\""),
           body.contains("\"REQUEST_DENIED\"") || body.contains("\"OVER_QUERY_LIMIT\"")
            || body.contains("\"INVALID_REQUEST\"") || body.contains("\"ZERO_RESULTS\"") {
            let snippet = String(body.prefix(200))
            AppLog.places.debug("Places API body status snippet: \(snippet, privacy: .public)")
        }
        #endif
        return data
    }

    // MARK: - Text Search（キーワード検索・広域。現在地があれば location+radius でバイアスのみ）

    private func fetchTextSearch(query: String, apiKey: String, location: String?, pageToken: String?) async throws -> ([PlaceCandidate], String?) {
        if let token = pageToken, !token.isEmpty {
            return try await fetchTextSearchPageToken(pagetoken: token, apiKey: apiKey)
        }
        var items: [URLQueryItem] = [
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "key", value: apiKey),
            URLQueryItem(name: "language", value: "ja"),
            URLQueryItem(name: "region", value: "jp")
        ]
        if let loc = location {
            items.append(URLQueryItem(name: "location", value: loc))
            items.append(URLQueryItem(name: "radius", value: "100000")) // 100km でバイアスのみ、絞り込みすぎない
        }
        var components = URLComponents(string: "https://maps.googleapis.com/maps/api/place/textsearch/json")
        components?.queryItems = items
        guard let url = components?.url else { return ([], nil) }
        let data = try await Self.performPlacesRequest(url: url)
        return try parseTextSearchResponse(data, userLocation: locationManager.currentLocation)
    }

    private func fetchTextSearchPageToken(pagetoken: String, apiKey: String) async throws -> ([PlaceCandidate], String?) {
        var components = URLComponents(string: "https://maps.googleapis.com/maps/api/place/textsearch/json")
        components?.queryItems = [
            URLQueryItem(name: "pagetoken", value: pagetoken),
            URLQueryItem(name: "key", value: apiKey)
        ]
        guard let url = components?.url else { return ([], nil) }
        let data = try await Self.performPlacesRequest(url: url)
        return try parseTextSearchResponse(data, userLocation: locationManager.currentLocation)
    }

    private func parseTextSearchResponse(_ data: Data, userLocation: CLLocation?) throws -> ([PlaceCandidate], String?) {
        struct Response: Decodable {
            struct Result: Decodable {
                let place_id: String?
                let name: String?
                let formatted_address: String?
                let geometry: Geometry?
                struct Geometry: Decodable {
                    let location: Location?
                    struct Location: Decodable {
                        let lat: Double?
                        let lng: Double?
                    }
                }
            }
            let results: [Result]?
            let next_page_token: String?
        }
        let res = try JSONDecoder().decode(Response.self, from: data)
        let userLoc = userLocation
        let list = (res.results ?? []).compactMap { r -> PlaceCandidate? in
            guard let id = r.place_id, !id.isEmpty else { return nil }
            let name = r.name ?? ""
            let address = r.formatted_address ?? ""
            var dist: Double? = nil
            if let ul = userLoc, let geo = r.geometry?.location, let lat = geo.lat, let lng = geo.lng {
                let place = CLLocation(latitude: lat, longitude: lng)
                dist = ul.distance(from: place)
            }
            return PlaceCandidate(id: id, name: name, address: address, distanceMeters: dist)
        }
        return (list, res.next_page_token)
    }

    // MARK: - Nearby Search（現在地周辺・距離順・ボタン押下時のみ）

    private nonisolated func fetchNearbySearch(apiKey: String, location: String, userLocation: CLLocation?) async throws -> [PlaceCandidate] {
        var components = URLComponents(string: "https://maps.googleapis.com/maps/api/place/nearbysearch/json")
        components?.queryItems = [
            URLQueryItem(name: "location", value: location),
            URLQueryItem(name: "rankby", value: "distance"),
            URLQueryItem(name: "keyword", value: "パチンコ"),
            URLQueryItem(name: "language", value: "ja"),
            URLQueryItem(name: "key", value: apiKey)
        ]
        guard let url = components?.url else { return [] }
        let data = try await Self.performPlacesRequest(url: url)
        return try parseNearbyResponse(data, userLocation: userLocation)
    }

    private nonisolated func parseNearbyResponse(_ data: Data, userLocation: CLLocation?) throws -> [PlaceCandidate] {
        struct Response: Decodable {
            struct Result: Decodable {
                let place_id: String?
                let name: String?
                let vicinity: String?
                let geometry: Geometry?
                struct Geometry: Decodable {
                    let location: Location?
                    struct Location: Decodable {
                        let lat: Double?
                        let lng: Double?
                    }
                }
            }
            let results: [Result]?
        }
        let res = try JSONDecoder().decode(Response.self, from: data)
        let userLoc = userLocation
        return (res.results ?? []).compactMap { r in
            guard let id = r.place_id, !id.isEmpty else { return nil }
            let name = r.name ?? ""
            let address = r.vicinity ?? ""
            var dist: Double? = nil
            if let ul = userLoc, let geo = r.geometry?.location, let lat = geo.lat, let lng = geo.lng {
                let place = CLLocation(latitude: lat, longitude: lng)
                dist = ul.distance(from: place)
            }
            return PlaceCandidate(id: id, name: name, address: address, distanceMeters: dist)
        }
    }

    // MARK: - モック

    private func mockCandidates(for query: String, location: String?) -> [PlaceCandidate] {
        let all: [PlaceCandidate] = [
            PlaceCandidate(id: "mock_maruhan_shinjuku", name: "マルハン新宿店", address: "東京都新宿区新宿3-17-5", distanceMeters: 1200),
            PlaceCandidate(id: "mock_maruhan_ikebukuro", name: "マルハン池袋店", address: "東京都豊島区東池袋1-12-8", distanceMeters: 3500),
            PlaceCandidate(id: "mock_espas", name: "エスパス新宿", address: "東京都新宿区", distanceMeters: 2800),
            PlaceCandidate(id: "mock_park", name: "Pアーク渋谷", address: "東京都渋谷区", distanceMeters: 2500),
        ]
        let filtered = query.isEmpty ? all : all.filter {
            $0.name.localizedCaseInsensitiveContains(query) || $0.address.localizedCaseInsensitiveContains(query)
        }
        return filtered.sorted { ($0.distanceMeters ?? .infinity) < ($1.distanceMeters ?? .infinity) }
    }

    private func mockNearbyCandidates(location: String) -> [PlaceCandidate] {
        mockCandidates(for: "", location: location)
    }

    func clearCandidates() {
        candidates = []
        hasNextPage = false
        lastTextSearchPageToken = nil
    }
}

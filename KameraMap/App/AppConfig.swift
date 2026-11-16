import Foundation

enum AppConfig {
    static let apiBaseURL: URL = {
        let raw = (Bundle.main.object(forInfoDictionaryKey: "KMAPIBaseURL") as? String) ?? ""
        if let url = URL(string: raw), url.scheme != nil {
            return url
        }
        return URL(string: "https://test.ismoiljon.me")!
    }()

    static let yandexMapKitKey: String = ((Bundle.main.object(forInfoDictionaryKey: "KMYandexMapKitKey") as? String) ?? "")
        .trimmingCharacters(in: .whitespacesAndNewlines)

    static let tashkent = Coordinate(lat: 41.3111, lng: 69.2797)
    static let startZoom: Float = 13
    static let minDataZoom: Float = 11
    static let placementZoom: Float = 15
    static let followZoom: Float = 16
    static let clusterListZoom: Float = 17
    static let reportsRefresh: Duration = .seconds(30)
    static let detailSheetFraction: CGFloat = 0.46

    static let yandexTermsURL = URL(string: "https://yandex.ru/legal/maps_termsofuse/")!

    static func adminCameraURL(_ id: Int) -> URL {
        apiBaseURL.appending(path: "admin/cameras/\(id)/edit")
    }

    static var appVersion: String {
        let version = (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "1.0"
        let build = (Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String) ?? "1"
        return "\(version) (\(build))"
    }
}

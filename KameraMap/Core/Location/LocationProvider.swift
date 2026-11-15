import CoreLocation
import Observation

enum LocationFailure: LocalizedError {
    case denied
    case unavailable

    var errorDescription: String? {
        switch self {
        case .denied:
            "Разрешите доступ к геопозиции в Настройках, чтобы показать, где вы."
        case .unavailable:
            "Не удалось определить, где вы. Попробуйте ещё раз."
        }
    }
}

@Observable
@MainActor
final class LocationProvider: NSObject, CLLocationManagerDelegate {
    private(set) var isAuthorized = false
    private(set) var isLocating = false

    @ObservationIgnored private let manager = CLLocationManager()
    @ObservationIgnored private var waiting: [CheckedContinuation<Coordinate, Error>] = []

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        isAuthorized = Self.allows(manager.authorizationStatus)
    }

    func current() async throws -> Coordinate {
        switch manager.authorizationStatus {
        case .denied, .restricted:
            throw LocationFailure.denied
        default:
            break
        }

        isLocating = true
        defer { isLocating = false }

        return try await withCheckedThrowingContinuation { continuation in
            waiting.append(continuation)
            if manager.authorizationStatus == .notDetermined {
                manager.requestWhenInUseAuthorization()
            } else {
                manager.requestLocation()
            }
        }
    }

    private func finish(_ result: Result<Coordinate, Error>) {
        let pending = waiting
        waiting.removeAll()
        for continuation in pending {
            continuation.resume(with: result)
        }
    }

    private static func allows(_ status: CLAuthorizationStatus) -> Bool {
        status == .authorizedWhenInUse || status == .authorizedAlways
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let last = locations.last else { return }
        let point = Coordinate(lat: last.coordinate.latitude, lng: last.coordinate.longitude)
        MainActor.assumeIsolated {
            finish(.success(point))
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        MainActor.assumeIsolated {
            finish(.failure(LocationFailure.unavailable))
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        MainActor.assumeIsolated {
            isAuthorized = Self.allows(status)
            switch status {
            case .authorizedWhenInUse, .authorizedAlways:
                if !waiting.isEmpty {
                    self.manager.requestLocation()
                }
            case .denied, .restricted:
                finish(.failure(LocationFailure.denied))
            default:
                break
            }
        }
    }
}

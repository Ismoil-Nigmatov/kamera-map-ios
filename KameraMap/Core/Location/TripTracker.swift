import CoreLocation
import Observation
import UIKit

struct TripPoint: Encodable, Hashable, Sendable {
    let lat: Double
    let lng: Double
    let accuracy: Double?
    let speed: Double?
    let heading: Double?
    let recordedAt: Date

    init(_ location: CLLocation) {
        lat = location.coordinate.latitude
        lng = location.coordinate.longitude
        accuracy = location.horizontalAccuracy >= 0 ? location.horizontalAccuracy : nil
        speed = location.speed >= 0 ? location.speed : nil
        heading = location.course >= 0 ? location.course : nil
        recordedAt = location.timestamp
    }

    init(lat: Double, lng: Double, accuracy: Double?, speed: Double?, heading: Double?, recordedAt: Date) {
        self.lat = lat
        self.lng = lng
        self.accuracy = accuracy
        self.speed = speed
        self.heading = heading
        self.recordedAt = recordedAt
    }
}

enum TripTexts {
    static let sharing = "Во время поездки на сервер отправляются ваше местоположение, скорость и направление. История поездок хранится 30 дней. Её видят администраторы сервиса и сотрудники МВД: они могут найти ваши поездки по номеру телефона."
    static let off = "Передачу можно выключить в любой момент — тогда вся история ваших поездок удаляется."
}

@Observable
@MainActor
final class TripTracker: NSObject, CLLocationManagerDelegate {
    private(set) var isActive = false
    private(set) var isSharing = false
    private(set) var location: Coordinate?
    private(set) var speedKmh: Int?
    private(set) var sent = 0
    private(set) var problem: String?

    let alerts = TripAlerts()

    @ObservationIgnored var onSharingRevoked: (@MainActor () -> Void)?
    @ObservationIgnored private var previous: TripPoint?
    @ObservationIgnored private let manager = CLLocationManager()
    @ObservationIgnored private var api: APIClient?
    @ObservationIgnored private var trip = UUID()
    @ObservationIgnored private var buffer: [TripPoint] = []
    @ObservationIgnored private var uploader: Task<Void, Never>?
    @ObservationIgnored private var isUploading = false

    private static let batchSize = 200
    private static let maxBuffered = 2_000
    private static let maxAccuracy = 100.0
    private static let deniedText = "Разрешите доступ к геопозиции в Настройках."

    override init() {
        super.init()
        manager.delegate = self
        manager.activityType = .automotiveNavigation
        manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        manager.distanceFilter = 10
        manager.pausesLocationUpdatesAutomatically = false
    }

    func start(api: APIClient, sharing: Bool) {
        guard !isActive else { return }
        self.api = api
        trip = UUID()
        buffer = []
        sent = 0
        problem = nil
        location = nil
        speedKmh = nil
        previous = nil
        alerts.reset()
        isSharing = sharing
        isActive = true

        manager.allowsBackgroundLocationUpdates = true
        manager.showsBackgroundLocationIndicator = true
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            problem = Self.deniedText
        default:
            manager.startUpdatingLocation()
        }
        UIApplication.shared.isIdleTimerDisabled = true

        uploader = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(10))
                guard !Task.isCancelled else { return }
                await self?.upload()
            }
        }
    }

    func stop() {
        guard isActive else { return }
        isActive = false
        manager.stopUpdatingLocation()
        manager.allowsBackgroundLocationUpdates = false
        uploader?.cancel()
        uploader = nil
        alerts.reset()
        UIApplication.shared.isIdleTimerDisabled = false
        Task { await upload() }
    }

    func enableSharing() {
        isSharing = true
    }

    func disableSharing() {
        isSharing = false
        buffer.removeAll()
    }

    private func record(_ raw: TripPoint) {
        guard isActive else { return }
        if problem == Self.deniedText {
            problem = nil
        }
        let point = derived(from: raw)
        previous = raw
        location = Coordinate(lat: point.lat, lng: point.lng)
        speedKmh = point.speed.map { Int(($0 * 3.6).rounded()) }

        if let api {
            alerts.process(point, api: api)
        }

        guard isSharing else { return }
        if let accuracy = point.accuracy, accuracy > Self.maxAccuracy {
            return
        }

        buffer.append(point)
        if buffer.count > Self.maxBuffered {
            buffer.removeFirst(buffer.count - Self.maxBuffered)
        }
    }

    private func derived(from point: TripPoint) -> TripPoint {
        guard point.speed == nil || point.heading == nil, let previous else { return point }
        let from = Coordinate(lat: previous.lat, lng: previous.lng)
        let to = Coordinate(lat: point.lat, lng: point.lng)
        let distance = Geo.meters(from, to)
        let seconds = point.recordedAt.timeIntervalSince(previous.recordedAt)
        guard seconds > 0.3, distance >= 3 else { return point }

        return TripPoint(
            lat: point.lat,
            lng: point.lng,
            accuracy: point.accuracy,
            speed: point.speed ?? distance / seconds,
            heading: point.heading ?? Geo.bearing(from, to),
            recordedAt: point.recordedAt
        )
    }

    private func upload() async {
        guard isSharing, !isUploading, !buffer.isEmpty, let api else { return }
        isUploading = true
        defer { isUploading = false }

        let batch = Array(buffer.prefix(Self.batchSize))
        do {
            let stored = try await api.uploadPositions(trip: trip, points: batch)
            buffer.removeFirst(min(batch.count, buffer.count))
            sent += stored
            problem = nil
        } catch let error as APIError where error.status == 409 {
            isSharing = false
            buffer.removeAll()
            onSharingRevoked?()
        } catch let error as APIError where error.status == 422 {
            buffer.removeFirst(min(batch.count, buffer.count))
            problem = error.message
        } catch {
            problem = "Нет связи — точки отправятся позже."
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let points = locations.map { TripPoint($0) }
        MainActor.assumeIsolated {
            for point in points {
                record(point)
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        let denied = (error as? CLError)?.code == .denied
        let status = manager.authorizationStatus
        MainActor.assumeIsolated {
            if denied, status == .denied || status == .restricted {
                problem = Self.deniedText
            }
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        MainActor.assumeIsolated {
            guard isActive else { return }
            switch status {
            case .authorizedWhenInUse, .authorizedAlways:
                if problem == Self.deniedText {
                    problem = nil
                }
                self.manager.startUpdatingLocation()
            case .denied, .restricted:
                problem = Self.deniedText
            default:
                break
            }
        }
    }
}

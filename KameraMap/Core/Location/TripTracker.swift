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
    static let sharing = "Пока передача включена, приложение отправляет на сервер ваше местоположение, скорость и направление всегда, когда вы в движении, даже если оно закрыто. История поездок хранится 30 дней. Её видят администраторы сервиса и сотрудники МВД: они могут найти ваши поездки по номеру телефона."
    static let off = "Передачу можно выключить в любой момент — тогда вся история ваших поездок удаляется."
    static let always = "Чтобы передача работала, когда приложение закрыто, разрешите доступ к геопозиции «Всегда»."
}

@Observable
@MainActor
final class TripTracker: NSObject, CLLocationManagerDelegate {
    private(set) var isActive = false
    private(set) var isAutomatic = false
    private(set) var isSharing = false
    private(set) var location: Coordinate?
    private(set) var speedKmh: Int?
    private(set) var sent = 0
    private(set) var problem: String?
    private(set) var authorization: CLAuthorizationStatus = .notDetermined

    let alerts = TripAlerts()

    @ObservationIgnored var onSharingRevoked: (@MainActor () -> Void)?
    @ObservationIgnored private let manager = CLLocationManager()
    @ObservationIgnored private var api: APIClient?
    @ObservationIgnored private var trip = UUID()
    @ObservationIgnored private var previous: TripPoint?
    @ObservationIgnored private var buffer: [Pending] = []
    @ObservationIgnored private var uploader: Task<Void, Never>?
    @ObservationIgnored private var isUploading = false
    @ObservationIgnored private var updatesPaused = false
    @ObservationIgnored private var backgroundTask = UIBackgroundTaskIdentifier.invalid

    private struct Pending {
        let trip: UUID
        let point: TripPoint
    }

    private static let consentKey = "km.locationSharing"
    private static let batchSize = 200
    private static let batchesPerUpload = 5
    private static let maxBuffered = 5_000
    private static let maxAccuracy = 100.0
    private static let tripGap: TimeInterval = 300
    private static let deniedText = "Нет доступа к геопозиции"

    override init() {
        super.init()
        manager.delegate = self
        manager.activityType = .automotiveNavigation
        manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        manager.distanceFilter = 10
        manager.pausesLocationUpdatesAutomatically = false
        authorization = manager.authorizationStatus
    }

    var isRecording: Bool {
        isActive || isAutomatic
    }

    var hasAlwaysAccess: Bool {
        authorization == .authorizedAlways
    }

    func resumeIfConsented(api: APIClient) {
        guard UserDefaults.standard.bool(forKey: Self.consentKey), api.token != nil else { return }
        startAutomatic(api: api)
    }

    func consentGranted(api: APIClient) {
        UserDefaults.standard.set(true, forKey: Self.consentKey)
        requestAlwaysAccess()
        startAutomatic(api: api)
    }

    func consentWithdrawn() {
        UserDefaults.standard.set(false, forKey: Self.consentKey)
        stopAutomatic()
    }

    func syncConsent(_ enabled: Bool, api: APIClient) {
        UserDefaults.standard.set(enabled, forKey: Self.consentKey)
        if enabled {
            startAutomatic(api: api)
        } else {
            stopAutomatic()
        }
    }

    func requestAlwaysAccess() {
        switch manager.authorizationStatus {
        case .notDetermined, .authorizedWhenInUse:
            manager.requestAlwaysAuthorization()
        default:
            break
        }
    }

    func start(api: APIClient, sharing: Bool) {
        guard !isActive else { return }
        self.api = api
        problem = nil
        alerts.reset()
        isSharing = sharing || isAutomatic
        isActive = true
        newTrip()
        configure()
        startUploader()
        UIApplication.shared.isIdleTimerDisabled = true
    }

    func stop() {
        guard isActive else { return }
        isActive = false
        UIApplication.shared.isIdleTimerDisabled = false
        alerts.reset()
        newTrip()
        if isAutomatic {
            configure()
        } else {
            manager.stopUpdatingLocation()
            manager.allowsBackgroundLocationUpdates = false
            stopUploader()
            flushInBackground()
        }
    }

    func endAll() {
        stop()
        consentWithdrawn()
    }

    private func startAutomatic(api: APIClient) {
        self.api = api
        isSharing = true
        isAutomatic = true
        configure()
        startUploader()
    }

    private func stopAutomatic() {
        guard isAutomatic || isSharing else { return }
        isAutomatic = false
        isSharing = false
        buffer.removeAll()
        manager.stopMonitoringSignificantLocationChanges()
        if !isActive {
            manager.stopUpdatingLocation()
            manager.allowsBackgroundLocationUpdates = false
            stopUploader()
        }
    }

    private func configure() {
        guard isRecording else { return }
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            manager.allowsBackgroundLocationUpdates = true
            manager.showsBackgroundLocationIndicator = true
            manager.pausesLocationUpdatesAutomatically = !isActive
            manager.startUpdatingLocation()
            updatesPaused = false
            if isAutomatic, manager.authorizationStatus == .authorizedAlways {
                manager.startMonitoringSignificantLocationChanges()
            }
        case .denied, .restricted:
            problem = Self.deniedText
        case .notDetermined:
            if isActive {
                manager.requestWhenInUseAuthorization()
            }
        @unknown default:
            break
        }
    }

    private func newTrip() {
        trip = UUID()
        previous = nil
    }

    private func record(_ raw: TripPoint) {
        guard isRecording else { return }
        if problem == Self.deniedText {
            problem = nil
        }
        if let previous, raw.recordedAt.timeIntervalSince(previous.recordedAt) > Self.tripGap {
            newTrip()
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

        buffer.append(Pending(trip: trip, point: point))
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

    private func startUploader() {
        guard uploader == nil else { return }
        uploader = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(10))
                guard !Task.isCancelled else { return }
                await self?.upload()
            }
        }
    }

    private func stopUploader() {
        uploader?.cancel()
        uploader = nil
    }

    private func flushInBackground() {
        if backgroundTask == .invalid {
            backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "km.positions") { [weak self] in
                MainActor.assumeIsolated {
                    self?.endBackgroundTask()
                }
            }
        }
        Task {
            await upload()
            endBackgroundTask()
        }
    }

    private func endBackgroundTask() {
        guard backgroundTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTask)
        backgroundTask = .invalid
    }

    private func upload() async {
        guard isSharing, !isUploading, let api, api.token != nil else { return }
        isUploading = true
        defer { isUploading = false }

        for _ in 0..<Self.batchesPerUpload {
            guard isSharing, let first = buffer.first else { return }
            let batch = Array(buffer.prefix(Self.batchSize).prefix { $0.trip == first.trip })
            do {
                let stored = try await api.uploadPositions(trip: first.trip, points: batch.map(\.point))
                buffer.removeFirst(min(batch.count, buffer.count))
                sent += stored
                problem = nil
            } catch let error as APIError where error.status == 409 {
                consentWithdrawn()
                onSharingRevoked?()
                return
            } catch let error as APIError where error.status == 422 {
                buffer.removeFirst(min(batch.count, buffer.count))
                problem = error.message
            } catch {
                problem = "Нет связи, отправим позже"
                return
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let points = locations.map { TripPoint($0) }
        MainActor.assumeIsolated {
            if updatesPaused, isRecording {
                updatesPaused = false
                self.manager.startUpdatingLocation()
            }
            for point in points {
                record(point)
            }
        }
    }

    nonisolated func locationManagerDidPauseLocationUpdates(_ manager: CLLocationManager) {
        MainActor.assumeIsolated {
            updatesPaused = true
            flushInBackground()
        }
    }

    nonisolated func locationManagerDidResumeLocationUpdates(_ manager: CLLocationManager) {
        MainActor.assumeIsolated {
            updatesPaused = false
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
            authorization = status
            guard isRecording else { return }
            if status == .denied || status == .restricted {
                problem = Self.deniedText
            } else if problem == Self.deniedText {
                problem = nil
            }
            configure()
        }
    }
}

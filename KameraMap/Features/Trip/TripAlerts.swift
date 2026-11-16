import AVFoundation
import Foundation
import Observation

enum HazardKind: Hashable, Sendable {
    case camera
    case radar
    case report(ReportType)

    var title: String {
        switch self {
        case .camera: "Камера"
        case .radar: "Радар"
        case .report(.police): "Пост ДПС"
        case .report(.tripod): "Тренога"
        case .report(.accident): "ДТП"
        case .report(.other): "Метка водителей"
        }
    }
}

struct Hazard: Hashable, Sendable {
    let key: String
    let kind: HazardKind
    let coordinate: Coordinate
    let heading: Int?
    let bidirectional: Bool
    let speedLimit: Int?
}

extension Hazard {
    init(camera: CameraMarker) {
        self.init(
            key: "camera-\(camera.id)",
            kind: camera.kind == .radar ? .radar : .camera,
            coordinate: camera.coordinate,
            heading: camera.heading,
            bidirectional: camera.bidirectional,
            speedLimit: camera.speedLimit
        )
    }

    init(report: Report) {
        self.init(
            key: "report-\(report.id)",
            kind: .report(report.type),
            coordinate: Coordinate(lat: report.lat, lng: report.lng),
            heading: nil,
            bidirectional: true,
            speedLimit: nil
        )
    }
}

struct TripAlert: Equatable, Sendable {
    let hazard: Hazard
    let distance: Double
    let isOverSpeed: Bool

    var distanceText: String {
        if distance >= 1000 {
            return String(format: "%.1f км", distance / 1000).replacingOccurrences(of: ".", with: ",")
        }
        return "\(Int((distance / 10).rounded()) * 10) м"
    }

    var phrase: String {
        let meters = max(100, Int((distance / 100).rounded()) * 100)
        var text = "\(hazard.kind.title) через \(meters) метров"
        if let limit = hazard.speedLimit {
            text += ", ограничение \(limit)"
        }
        return text
    }
}

enum Geo {
    static func meters(_ a: Coordinate, _ b: Coordinate) -> Double {
        let rad = Double.pi / 180
        let dLat = (b.lat - a.lat) * rad
        let dLng = (b.lng - a.lng) * rad
        let h = sin(dLat / 2) * sin(dLat / 2) + cos(a.lat * rad) * cos(b.lat * rad) * sin(dLng / 2) * sin(dLng / 2)
        return 2 * 6_371_000 * asin(min(1, sqrt(h)))
    }

    static func bearing(_ a: Coordinate, _ b: Coordinate) -> Double {
        let rad = Double.pi / 180
        let y = sin((b.lng - a.lng) * rad) * cos(b.lat * rad)
        let x = cos(a.lat * rad) * sin(b.lat * rad) - sin(a.lat * rad) * cos(b.lat * rad) * cos((b.lng - a.lng) * rad)
        let degrees = atan2(y, x) / rad
        return degrees < 0 ? degrees + 360 : degrees
    }

    static func angle(_ a: Double, _ b: Double) -> Double {
        let difference = abs(a - b).truncatingRemainder(dividingBy: 360)
        return difference > 180 ? 360 - difference : difference
    }
}

struct HazardFinder: Sendable {
    var lookAhead = 900.0
    var cone = 40.0
    var passRadius = 50.0
    var directionTolerance = 70.0

    func nearest(from position: Coordinate, course: Double, in hazards: [Hazard]) -> (hazard: Hazard, distance: Double)? {
        var best: (hazard: Hazard, distance: Double)?

        for hazard in hazards {
            let distance = Geo.meters(position, hazard.coordinate)
            guard distance <= lookAhead else { continue }
            if distance > passRadius, Geo.angle(Geo.bearing(position, hazard.coordinate), course) > cone {
                continue
            }
            if let heading = hazard.heading {
                let along = Geo.angle(course, Double(heading)) <= directionTolerance
                let against = hazard.bidirectional && Geo.angle(course, Double((heading + 180) % 360)) <= directionTolerance
                guard along || against else { continue }
            }
            if let current = best, current.distance <= distance {
                continue
            }
            best = (hazard, distance)
        }

        return best
    }
}

@Observable
@MainActor
final class TripAlerts {
    private(set) var current: TripAlert?
    private(set) var voiceEnabled: Bool

    @ObservationIgnored private var hazards: [Hazard] = []
    @ObservationIgnored private var fetchedAround: Coordinate?
    @ObservationIgnored private var fetchedAt = Date.distantPast
    @ObservationIgnored private var isFetching = false
    @ObservationIgnored private var lastCourse: (value: Double, time: Date)?
    @ObservationIgnored private var announced: [String: Date] = [:]
    @ObservationIgnored private var warnedSpeeding: [String: Date] = [:]
    @ObservationIgnored private let finder = HazardFinder()
    @ObservationIgnored private let speech = SpeechAnnouncer()

    private static let voiceKey = "km.tripVoice"
    private static let repeatAfter: TimeInterval = 300

    init() {
        voiceEnabled = UserDefaults.standard.object(forKey: Self.voiceKey) as? Bool ?? true
    }

    func toggleVoice() {
        voiceEnabled.toggle()
        UserDefaults.standard.set(voiceEnabled, forKey: Self.voiceKey)
        if !voiceEnabled {
            speech.stop()
        }
    }

    func reset() {
        current = nil
        hazards = []
        fetchedAround = nil
        fetchedAt = .distantPast
        lastCourse = nil
        announced = [:]
        warnedSpeeding = [:]
        speech.stop()
    }

    func process(_ point: TripPoint, api: APIClient) {
        let position = Coordinate(lat: point.lat, lng: point.lng)
        let now = point.recordedAt
        let speed = point.speed ?? 0

        if let course = point.heading, speed >= 1.5 {
            lastCourse = (course, now)
        }

        refreshHazards(around: position, api: api)

        guard let course = lastCourse, now.timeIntervalSince(course.time) < 20,
              let nearest = finder.nearest(from: position, course: course.value, in: hazards)
        else {
            current = nil
            return
        }

        let overSpeed = nearest.hazard.speedLimit.map { speed * 3.6 > Double($0) + 5 } ?? false
        let alert = TripAlert(hazard: nearest.hazard, distance: nearest.distance, isOverSpeed: overSpeed)
        current = alert
        announce(alert, speed: speed, now: now)
    }

    private func announce(_ alert: TripAlert, speed: Double, now: Date) {
        let key = alert.hazard.key
        let reach = speed > 19 ? 800.0 : 600.0

        if alert.distance <= reach, isDue(announced[key], now: now) {
            announced[key] = now
            Haptics.warning()
            say(alert.phrase)
        }

        if alert.isOverSpeed, alert.distance <= 350, isDue(warnedSpeeding[key], now: now) {
            warnedSpeeding[key] = now
            Haptics.warning()
            say("Снизьте скорость")
        }
    }

    private func isDue(_ last: Date?, now: Date) -> Bool {
        last.map { now.timeIntervalSince($0) > Self.repeatAfter } ?? true
    }

    private func say(_ text: String) {
        guard voiceEnabled else { return }
        speech.say(text)
    }

    private func refreshHazards(around position: Coordinate, api: APIClient) {
        let movedAway = fetchedAround.map { Geo.meters($0, position) > 1_200 } ?? true
        guard !isFetching, movedAway || Date().timeIntervalSince(fetchedAt) > 180 else { return }

        isFetching = true
        let box = BoundingBox(
            minLng: position.lng - 0.035,
            minLat: position.lat - 0.027,
            maxLng: position.lng + 0.035,
            maxLat: position.lat + 0.027
        )

        Task {
            defer { isFetching = false }
            async let cameras = api.cameras(in: box)
            async let reports = api.reports(in: box)
            guard let loaded = try? await (cameras, reports) else { return }
            hazards = loaded.0.filter { $0.status != .inactive }.map { Hazard(camera: $0) }
                + loaded.1.filter(\.isActive).map { Hazard(report: $0) }
            fetchedAround = position
            fetchedAt = Date()
        }
    }
}

@MainActor
final class SpeechAnnouncer: NSObject, AVSpeechSynthesizerDelegate {
    private let synthesizer = AVSpeechSynthesizer()
    private let voice = AVSpeechSynthesisVoice(language: "ru-RU")

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func say(_ text: String) {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .voicePrompt, options: [.duckOthers, .interruptSpokenAudioAndMixWithOthers])
        try? session.setActive(true)

        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice
        synthesizer.speak(utterance)
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        deactivate()
    }

    private func deactivate() {
        guard !synthesizer.isSpeaking else { return }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in
            self?.deactivate()
        }
    }
}

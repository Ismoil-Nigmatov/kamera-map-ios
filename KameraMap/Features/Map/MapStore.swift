import Foundation
import Observation

enum MapSheet: Identifiable, Hashable {
    case camera(Int)
    case report(Int)
    case cluster([Int])
    case newReport
    case suggest(Int)
    case login
    case profile

    var id: String {
        switch self {
        case .camera(let id): "camera-\(id)"
        case .report(let id): "report-\(id)"
        case .cluster(let ids): "cluster-\(ids.map(String.init).joined(separator: "-"))"
        case .newReport: "new-report"
        case .suggest(let id): "suggest-\(id)"
        case .login: "login"
        case .profile: "profile"
        }
    }

    var coversMapPartially: Bool {
        switch self {
        case .camera, .report, .cluster: true
        default: false
        }
    }
}

struct CameraTarget: Equatable {
    let coordinate: Coordinate
    let zoom: Float?
    let id = UUID()
}

struct MapRegion: Equatable, Sendable {
    let bbox: BoundingBox
    let zoom: Float
    let center: Coordinate
}

@Observable
@MainActor
final class MapStore {
    private(set) var cameras: [Int: CameraMarker] = [:]
    private(set) var reports: [Int: Report] = [:]
    private(set) var details: [Int: CameraDetails] = [:]
    private(set) var region: MapRegion?
    private(set) var loadFailed = false
    private(set) var isBusy = false
    var showCameras = true
    var showReports = true
    var sheet: MapSheet?
    var target: CameraTarget?
    var placing: ReportDraft?
    @ObservationIgnored private var afterLogin: MapSheet?

    @ObservationIgnored private let api: APIClient
    @ObservationIgnored private let toasts: ToastCenter
    @ObservationIgnored private var loadTask: Task<Void, Never>?

    init(api: APIClient, toasts: ToastCenter) {
        self.api = api
        self.toasts = toasts
    }

    var visibleCameras: [CameraMarker] {
        showCameras ? Array(cameras.values) : []
    }

    var visibleReports: [Report] {
        showReports ? reports.values.filter(\.isActive) : []
    }

    var zoomedInEnough: Bool {
        (region?.zoom ?? AppConfig.startZoom) >= AppConfig.minDataZoom
    }

    var canPlaceHere: Bool {
        (region?.zoom ?? 0) >= AppConfig.placementZoom
    }

    var selectedCameraID: Int? {
        switch sheet {
        case .camera(let id)?, .suggest(let id)?: id
        default: nil
        }
    }

    var selectedReportID: Int? {
        if case .report(let id)? = sheet {
            return id
        }
        return nil
    }

    func regionChanged(_ region: MapRegion) {
        self.region = region
        loadTask?.cancel()
        guard region.zoom >= AppConfig.minDataZoom else { return }
        loadTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled else { return }
            await self?.load(region.bbox)
        }
    }

    func refreshLoop() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: AppConfig.reportsRefresh)
            guard !Task.isCancelled, showReports, zoomedInEnough, let box = region?.bbox else { continue }
            if let fresh = try? await api.reports(in: box) {
                merge(reports: fresh, in: box)
            }
        }
    }

    private func load(_ box: BoundingBox) async {
        let api = self.api
        do {
            async let freshCameras = api.cameras(in: box)
            async let freshReports = api.reports(in: box)
            let (newCameras, newReports) = try await (freshCameras, freshReports)
            for camera in newCameras {
                cameras[camera.id] = camera
            }
            merge(reports: newReports, in: box)
            loadFailed = false
        } catch is CancellationError {
            return
        } catch {
            loadFailed = true
        }
    }

    private func merge(reports fresh: [Report], in box: BoundingBox) {
        let freshIDs = Set(fresh.map(\.id))
        for (id, report) in reports where box.contains(report.coordinate) && !freshIDs.contains(id) {
            reports[id] = nil
        }
        for report in fresh {
            reports[report.id] = report
        }
    }

    func openCamera(_ id: Int, focus: Bool = false) {
        sheet = .camera(id)
        if focus {
            Task { await loadDetails(id, focus: true) }
        }
    }

    func loadDetails(_ id: Int, focus: Bool = false) async {
        do {
            let camera = try await api.camera(id)
            details[id] = camera
            if focus {
                target = CameraTarget(coordinate: camera.coordinate, zoom: 16)
            }
        } catch is CancellationError {
            return
        } catch {
            toasts.show(error)
            if sheet == .camera(id) {
                sheet = nil
            }
        }
    }

    func openReport(_ id: Int) {
        sheet = .report(id)
    }

    func openCluster(ids: [Int], center: Coordinate, zoom: Float) {
        if zoom < AppConfig.clusterListZoom {
            target = CameraTarget(coordinate: center, zoom: min(zoom + 2, 19))
        } else {
            sheet = .cluster(ids)
        }
    }

    func mapTapped(at point: Coordinate) {
        if placing != nil {
            target = CameraTarget(coordinate: point, zoom: nil)
        } else if sheet != nil {
            sheet = nil
        }
    }

    func focus(on point: Coordinate, zoom: Float = 16) {
        target = CameraTarget(coordinate: point, zoom: zoom)
    }

    func present(_ next: MapSheet, signedIn: Bool) {
        if signedIn {
            sheet = next
        } else {
            afterLogin = next
            sheet = .login
        }
    }

    func requireLogin(returningTo next: MapSheet?) {
        afterLogin = next
        sheet = .login
    }

    func didSignIn() {
        sheet = afterLogin
        afterLogin = nil
    }

    func voteCamera(_ id: Int, _ value: VoteValue) async {
        await perform {
            self.details[id] = try await self.api.voteCamera(id, value)
            self.toasts.show("Спасибо, голос учтён.")
        }
    }

    func setStatus(_ id: Int, _ status: CameraStatus, label: String) async {
        await perform {
            let updated = try await self.api.setStatus(id, status)
            self.details[id] = updated
            if let marker = self.cameras[id] {
                self.cameras[id] = marker.with(status: updated.status)
            }
            self.toasts.show("Статус камеры: \(label.lowercased())")
        }
    }

    func suggestFix(_ id: Int, _ draft: SuggestionDraft) async -> Bool {
        var sent = false
        await perform {
            let result = try await self.api.suggestFix(id, draft)
            self.details[id] = result.camera
            self.toasts.show(result.merged
                ? "Такое предложение уже есть — ваш голос «за» учтён."
                : "Спасибо! Водители проголосуют, а администратор проверит.")
            Haptics.success()
            sent = true
        }
        return sent
    }

    func voteSuggestion(_ suggestion: CameraSuggestion, cameraID: Int, _ value: VoteValue) async {
        await perform {
            self.details[cameraID] = try await self.api.voteSuggestion(suggestion.id, value)
            self.toasts.show("Спасибо, голос учтён.")
        }
    }

    func startPlacing(_ draft: ReportDraft, near location: Coordinate?) {
        placing = draft
        sheet = nil
        let zoom = max(region?.zoom ?? 16, AppConfig.placementZoom + 1)
        if let location {
            target = CameraTarget(coordinate: location, zoom: zoom)
        } else if let region, region.zoom < AppConfig.placementZoom {
            target = CameraTarget(coordinate: region.center, zoom: zoom)
        }
    }

    func cancelPlacing() {
        placing = nil
    }

    func placeReport() async {
        guard let draft = placing, let center = region?.center else { return }
        await perform {
            let result = try await self.api.createReport(draft, at: center)
            self.reports[result.report.id] = result.report
            self.placing = nil
            self.showReports = true
            self.sheet = .report(result.report.id)
            self.toasts.show(result.merged ? "Рядом уже была такая метка — вы её подтвердили." : "Метка поставлена. Спасибо!")
            Haptics.success()
        }
    }

    func voteReport(_ id: Int, _ value: VoteValue) async {
        await perform {
            let updated = try await self.api.voteReport(id, value)
            if updated.isActive {
                self.reports[id] = updated
                self.toasts.show("Спасибо, голос учтён.")
            } else {
                self.reports[id] = nil
                self.sheet = nil
                self.toasts.show("Метка снята с карты.")
            }
        }
    }

    func openFromLaunchArguments() {
        let id = UserDefaults.standard.integer(forKey: "km.openCamera")
        if id > 0 {
            openCamera(id, focus: true)
        }
    }

    func handle(url: URL) {
        guard url.scheme == "kameramap" else { return }
        if url.host() == "camera", let id = Int(url.lastPathComponent) {
            openCamera(id, focus: true)
        }
    }

    private func perform(_ work: () async throws -> Void) async {
        isBusy = true
        defer { isBusy = false }
        do {
            try await work()
        } catch {
            toasts.show(error)
        }
    }
}

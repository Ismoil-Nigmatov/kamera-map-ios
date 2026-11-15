import SwiftUI
import UIKit
import YandexMapsMobile

struct YandexMapView: UIViewRepresentable {
    var cameras: [CameraMarker]
    var reports: [Report]
    var selectedCameraID: Int?
    var selectedReportID: Int?
    var target: CameraTarget?
    var logoBottomInset: CGFloat
    var showsUserLocation: Bool
    var onRegionChange: @MainActor (MapRegion) -> Void
    var onCameraTap: @MainActor (Int) -> Void
    var onClusterTap: @MainActor ([Int], Coordinate, Float) -> Void
    var onReportTap: @MainActor (Int) -> Void
    var onMapTap: @MainActor (Coordinate) -> Void
    var onUserGesture: @MainActor () -> Void

    @Environment(\.colorScheme) var colorScheme

    func makeCoordinator() -> MapCoordinator {
        MapCoordinator()
    }

    func makeUIView(context: Context) -> MapContainerView {
        let container = MapContainerView()
        context.coordinator.attach(to: container, initial: target)
        return container
    }

    func updateUIView(_ container: MapContainerView, context: Context) {
        context.coordinator.update(with: self, dark: colorScheme == .dark)
    }
}

final class MapContainerView: UIView {
    let mapView: YMKMapView
    var onResize: (@MainActor () -> Void)?
    private var laidOutSize: CGSize = .zero

    init() {
        mapView = YMKMapView(frame: .zero)
        super.init(frame: .zero)
        addSubview(mapView)
    }

    required init?(coder: NSCoder) {
        return nil
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        mapView.frame = bounds
        guard bounds.size != laidOutSize else { return }
        laidOutSize = bounds.size
        onResize?()
    }
}

final class MarkTag: NSObject {
    enum Kind {
        case camera
        case report
    }

    let kind: Kind
    let id: Int
    let status: CameraStatus

    init(kind: Kind, id: Int, status: CameraStatus = .unverified) {
        self.kind = kind
        self.id = id
        self.status = status
    }
}

@MainActor
final class MapCoordinator: NSObject, YMKMapCameraListener, YMKMapInputListener, YMKClusterListener, YMKClusterTapListener, YMKMapObjectTapListener {
    private struct Mark {
        let placemark: YMKPlacemarkMapObject
        var signature: String
    }

    private var parent: YandexMapView?
    private weak var view: YMKMapView?
    private var clusters: YMKClusterizedPlacemarkCollection?
    private var userLayer: YMKUserLocationLayer?
    private var cameraMarks: [Int: Mark] = [:]
    private var reportMarks: [Int: Mark] = [:]
    private var appliedTarget: UUID?
    private var isDark: Bool?
    private var logoInset: CGFloat?
    private var gestureActive = false

    private let centered: YMKIconStyle = {
        let style = YMKIconStyle()
        style.anchor = NSValue(cgPoint: CGPoint(x: 0.5, y: 0.5))
        return style
    }()

    func attach(to container: MapContainerView, initial: CameraTarget?) {
        let view = container.mapView
        self.view = view
        container.onResize = { [weak self] in
            self?.viewResized()
        }
        let map = view.mapWindow.map
        map.isRotateGesturesEnabled = false
        map.isTiltGesturesEnabled = false
        map.logo.setAlignmentWith(YMKLogoAlignment(horizontalAlignment: .left, verticalAlignment: .bottom))
        map.addCameraListener(with: self)
        map.addInputListener(with: self)
        clusters = map.mapObjects.addClusterizedPlacemarkCollection(with: self)

        let start = initial?.coordinate ?? AppConfig.tashkent
        map.move(with: YMKCameraPosition(
            target: YMKPoint(latitude: start.lat, longitude: start.lng),
            zoom: initial?.zoom ?? AppConfig.startZoom,
            azimuth: 0,
            tilt: 0
        ))
        appliedTarget = initial?.id
    }

    func update(with parent: YandexMapView, dark: Bool) {
        self.parent = parent
        guard let view else { return }
        let map = view.mapWindow.map

        if isDark != dark {
            map.isNightModeEnabled = dark
            isDark = dark
        }

        if logoInset != parent.logoBottomInset {
            logoInset = parent.logoBottomInset
            let scale = view.window?.screen.scale ?? view.traitCollection.displayScale
            map.logo.setPaddingWith(YMKLogoPadding(
                horizontalPadding: UInt(12 * scale),
                verticalPadding: UInt((parent.logoBottomInset + 10) * scale)
            ))
        }

        syncCameras(parent.cameras, selected: parent.selectedCameraID)
        syncReports(parent.reports, selected: parent.selectedReportID, root: map.mapObjects)

        if parent.showsUserLocation, userLayer == nil {
            let layer = YMKMapKit.sharedInstance().createUserLocationLayer(with: view.mapWindow)
            layer.setVisibleWithOn(true)
            userLayer = layer
        }

        if let target = parent.target, target.id != appliedTarget {
            appliedTarget = target.id
            let current = map.cameraPosition
            map.move(
                with: YMKCameraPosition(
                    target: YMKPoint(latitude: target.coordinate.lat, longitude: target.coordinate.lng),
                    zoom: target.zoom ?? current.zoom,
                    azimuth: 0,
                    tilt: 0
                ),
                animation: YMKAnimation(type: .smooth, duration: 0.5),
                cameraCallback: nil
            )
        }
    }

    private func syncCameras(_ cameras: [CameraMarker], selected: Int?) {
        guard let clusters else { return }
        var changed = false
        var seen = Set<Int>()

        for camera in cameras {
            seen.insert(camera.id)
            let isSelected = camera.id == selected
            let signature = "\(camera.lat),\(camera.lng)|\(camera.status.rawValue)|\(camera.kind.rawValue)|\(camera.speedLimit ?? -1)|\(camera.heading ?? -1)|\(camera.bidirectional)|\(isSelected)"

            if var mark = cameraMarks[camera.id] {
                guard mark.signature != signature else { continue }
                mark.placemark.geometry = YMKPoint(latitude: camera.lat, longitude: camera.lng)
                mark.placemark.setIconWith(MarkerRenderer.camera(camera, selected: isSelected), style: centered)
                mark.placemark.userData = MarkTag(kind: .camera, id: camera.id, status: camera.status)
                mark.placemark.zIndex = isSelected ? 10 : 0
                mark.signature = signature
                cameraMarks[camera.id] = mark
            } else {
                let placemark = clusters.addPlacemark()
                placemark.geometry = YMKPoint(latitude: camera.lat, longitude: camera.lng)
                placemark.setIconWith(MarkerRenderer.camera(camera, selected: isSelected), style: centered)
                placemark.userData = MarkTag(kind: .camera, id: camera.id, status: camera.status)
                placemark.zIndex = isSelected ? 10 : 0
                placemark.addTapListener(with: self)
                cameraMarks[camera.id] = Mark(placemark: placemark, signature: signature)
                changed = true
            }
        }

        for (id, mark) in cameraMarks where !seen.contains(id) {
            clusters.remove(with: mark.placemark)
            cameraMarks[id] = nil
            changed = true
        }

        if changed {
            clusters.clusterPlacemarks(withClusterRadius: 56, minZoom: 21)
        }
    }

    private func syncReports(_ reports: [Report], selected: Int?, root: YMKMapObjectCollection) {
        var seen = Set<Int>()

        for report in reports {
            seen.insert(report.id)
            let isSelected = report.id == selected
            let signature = "\(report.lat),\(report.lng)|\(report.type.rawValue)|\(isSelected)"

            if var mark = reportMarks[report.id] {
                guard mark.signature != signature else { continue }
                mark.placemark.geometry = YMKPoint(latitude: report.lat, longitude: report.lng)
                mark.placemark.setIconWith(MarkerRenderer.report(report.type, selected: isSelected), style: centered)
                mark.placemark.zIndex = isSelected ? 110 : 100
                mark.signature = signature
                reportMarks[report.id] = mark
            } else {
                let placemark = root.addPlacemark()
                placemark.geometry = YMKPoint(latitude: report.lat, longitude: report.lng)
                placemark.setIconWith(MarkerRenderer.report(report.type, selected: isSelected), style: centered)
                placemark.userData = MarkTag(kind: .report, id: report.id)
                placemark.zIndex = isSelected ? 110 : 100
                placemark.addTapListener(with: self)
                reportMarks[report.id] = Mark(placemark: placemark, signature: signature)
            }
        }

        for (id, mark) in reportMarks where !seen.contains(id) {
            root.remove(with: mark.placemark)
            reportMarks[id] = nil
        }
    }

    private func viewResized() {
        Task { @MainActor [weak self] in
            for _ in 0..<6 {
                guard let self else { return }
                if self.reportCurrentRegion() {
                    return
                }
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
    }

    @discardableResult
    private func reportCurrentRegion() -> Bool {
        guard let map = view?.mapWindow.map, let region = Self.region(of: map, at: map.cameraPosition) else {
            return false
        }
        parent?.onRegionChange(region)
        return true
    }

    nonisolated private static func region(of map: YMKMap, at position: YMKCameraPosition) -> MapRegion? {
        let visible = map.visibleRegion
        let corners = [visible.topLeft, visible.topRight, visible.bottomLeft, visible.bottomRight]
        let lats = corners.map(\.latitude)
        let lngs = corners.map(\.longitude)
        guard let minLat = lats.min(), let maxLat = lats.max(), let minLng = lngs.min(), let maxLng = lngs.max(),
              maxLat - minLat > 0.0001, maxLng - minLng > 0.0001
        else {
            return nil
        }
        return MapRegion(
            bbox: BoundingBox(minLng: minLng, minLat: minLat, maxLng: maxLng, maxLat: maxLat),
            zoom: position.zoom,
            center: Coordinate(lat: position.target.latitude, lng: position.target.longitude)
        )
    }

    private func beginGesture() {
        guard !gestureActive else { return }
        gestureActive = true
        parent?.onUserGesture()
    }

    private func clusterStatus(_ cluster: YMKCluster) -> CameraStatus {
        let statuses = cluster.placemarks.compactMap { ($0.userData as? MarkTag)?.status }
        if !statuses.isEmpty, statuses.allSatisfy({ $0 == .active }) {
            return .active
        }
        if !statuses.isEmpty, statuses.allSatisfy({ $0 == .inactive }) {
            return .inactive
        }
        return .unverified
    }

    nonisolated func onCameraPositionChanged(
        with map: YMKMap,
        cameraPosition: YMKCameraPosition,
        cameraUpdateReason: YMKCameraUpdateReason,
        finished: Bool
    ) {
        guard finished else {
            if cameraUpdateReason == .gestures {
                MainActor.assumeIsolated {
                    beginGesture()
                }
            }
            return
        }
        MainActor.assumeIsolated {
            gestureActive = false
        }
        guard let region = Self.region(of: map, at: cameraPosition) else { return }
        Task { @MainActor [weak self] in
            self?.parent?.onRegionChange(region)
        }
    }

    nonisolated func onMapTap(with map: YMKMap, point: YMKPoint) {
        let coordinate = Coordinate(lat: point.latitude, lng: point.longitude)
        Task { @MainActor [weak self] in
            self?.parent?.onMapTap(coordinate)
        }
    }

    nonisolated func onMapLongTap(with map: YMKMap, point: YMKPoint) {}

    nonisolated func onClusterAdded(with cluster: YMKCluster) {
        MainActor.assumeIsolated {
            let status = clusterStatus(cluster)
            cluster.appearance.setIconWith(MarkerRenderer.cluster(count: Int(cluster.size), status: status), style: centered)
            cluster.addClusterTapListener(with: self)
        }
    }

    nonisolated func onClusterTap(with cluster: YMKCluster) -> Bool {
        MainActor.assumeIsolated {
            let ids = cluster.placemarks.compactMap { ($0.userData as? MarkTag)?.id }
            let point = cluster.appearance.geometry
            let zoom = view?.mapWindow.map.cameraPosition.zoom ?? AppConfig.startZoom
            parent?.onClusterTap(ids, Coordinate(lat: point.latitude, lng: point.longitude), zoom)
            return true
        }
    }

    nonisolated func onMapObjectTap(with mapObject: YMKMapObject, point: YMKPoint) -> Bool {
        MainActor.assumeIsolated {
            guard let tag = mapObject.userData as? MarkTag else { return false }
            switch tag.kind {
            case .camera:
                parent?.onCameraTap(tag.id)
            case .report:
                parent?.onReportTap(tag.id)
            }
            return true
        }
    }
}

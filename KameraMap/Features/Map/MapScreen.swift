import SwiftUI

struct MapScreen: View {
    @Environment(MapStore.self) var store
    @Environment(SessionStore.self) var session
    @Environment(LocationProvider.self) var location
    @Environment(ToastCenter.self) var toasts
    @Environment(TripTracker.self) var trip
    @State private var placementCardHeight: CGFloat = 0
    @State private var tripPanelHeight: CGFloat = 0
    @State private var following = true

    private let placementBottomPadding: CGFloat = 30

    var body: some View {
        @Bindable var store = store

        GeometryReader { geometry in
            ZStack(alignment: .top) {
                mapLayer(
                    height: geometry.size.height + geometry.safeAreaInsets.top + geometry.safeAreaInsets.bottom,
                    safeBottom: geometry.safeAreaInsets.bottom
                )

                if let draft = store.placing {
                    PlacementPin(type: draft.type)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .ignoresSafeArea()
                        .allowsHitTesting(false)
                        .transition(.scale(scale: 0.6).combined(with: .opacity))
                }

                VStack(spacing: 10) {
                    TopBar()
                    MapHints()
                    Spacer(minLength: 0)
                    if let draft = store.placing {
                        PlacementCard(draft: draft)
                            .onGeometryChange(for: CGFloat.self) { proxy in
                                proxy.size.height
                            } action: { height in
                                placementCardHeight = height
                            }
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    } else if trip.isActive {
                        TripPanel(following: $following, onReport: startReport, onEnableSharing: enableSharing)
                            .onGeometryChange(for: CGFloat.self) { proxy in
                                proxy.size.height
                            } action: { height in
                                tripPanelHeight = height
                            }
                            .opacity(actionsHidden ? 0 : 1)
                            .allowsHitTesting(!actionsHidden)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    } else {
                        HStack {
                            Spacer()
                            MapActions(onLocate: locate, onTrip: startTrip, onReport: startReport)
                        }
                        .opacity(actionsHidden ? 0 : 1)
                        .allowsHitTesting(!actionsHidden)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 4)
                .padding(.bottom, store.placing == nil && !trip.isActive ? 12 : placementBottomPadding)

                ToastOverlay()
            }
        }
        .animation(.snappy(duration: 0.3), value: store.placing)
        .animation(.easeInOut(duration: 0.2), value: actionsHidden)
        .animation(.snappy(duration: 0.3), value: trip.isActive)
        .onChange(of: trip.isActive) { _, active in
            if active {
                following = true
            }
        }
        .onChange(of: trip.location) { _, point in
            follow(point)
        }
        .onChange(of: following) { _, on in
            if on {
                follow(trip.location)
            }
        }
        .sheet(item: $store.sheet) { sheet in
            SheetContent(sheet: sheet)
        }
        .task {
            await store.refreshLoop()
        }
        .task {
            store.openFromLaunchArguments()
        }
        .onOpenURL { url in
            store.handle(url: url)
        }
    }

    @ViewBuilder
    private func mapLayer(height: CGFloat, safeBottom: CGFloat) -> some View {
        if MapKitBootstrap.isConfigured {
            YandexMapView(
                cameras: store.visibleCameras,
                reports: store.visibleReports,
                selectedCameraID: store.selectedCameraID,
                selectedReportID: store.selectedReportID,
                target: store.target,
                logoBottomInset: logoInset(screenHeight: height, safeBottom: safeBottom),
                showsUserLocation: location.isAuthorized,
                onRegionChange: { store.regionChanged($0) },
                onCameraTap: { id in
                    Haptics.tap()
                    store.openCamera(id)
                },
                onClusterTap: { ids, center, zoom in
                    Haptics.tap()
                    store.openCluster(ids: ids, center: center, zoom: zoom)
                },
                onReportTap: { id in
                    Haptics.tap()
                    store.openReport(id)
                },
                onMapTap: { store.mapTapped(at: $0) },
                onUserGesture: { store.userMovedMap() }
            )
            .ignoresSafeArea()
        } else {
            MissingMapKeyView()
        }
    }

    private var actionsHidden: Bool {
        store.sheet?.coversMapPartially ?? false
    }

    private func logoInset(screenHeight: CGFloat, safeBottom: CGFloat) -> CGFloat {
        if store.placing != nil {
            return safeBottom + placementBottomPadding + max(placementCardHeight, 120) + 6
        }
        let base = trip.isActive ? safeBottom + placementBottomPadding + max(tripPanelHeight, 120) + 6 : 0
        if let sheet = store.sheet, sheet.coversMapPartially {
            return max(base, screenHeight * AppConfig.detailSheetFraction)
        }
        return base
    }

    private func follow(_ point: Coordinate?) {
        guard trip.isActive, following, let point else { return }
        let zoomedOut = (store.region?.zoom ?? 0) < AppConfig.followZoom - 1
        store.target = CameraTarget(coordinate: point, zoom: zoomedOut ? AppConfig.followZoom : nil)
    }

    private func startTrip() {
        Haptics.tap()
        guard session.isSignedIn else {
            store.requireLogin(returningTo: .tripConsent(true))
            return
        }
        if session.user?.isSharingLocation == true {
            trip.start(api: session.api, sharing: true)
        } else {
            store.sheet = .tripConsent(true)
        }
    }

    private func enableSharing() {
        store.sheet = .tripConsent(false)
    }

    private func locate() {
        Task {
            do {
                let point = try await location.current()
                store.focus(on: point, zoom: 16)
            } catch {
                toasts.show(error)
            }
        }
    }

    private func startReport() {
        Haptics.tap()
        store.present(.newReport, signedIn: session.isSignedIn)
    }
}

private struct SheetContent: View {
    let sheet: MapSheet

    var body: some View {
        switch sheet {
        case .camera(let id):
            CameraSheet(cameraID: id)
                .detailSheetPresentation()
        case .report(let id):
            ReportSheet(reportID: id)
                .detailSheetPresentation()
        case .cluster(let ids):
            CameraListSheet(cameraIDs: ids)
                .detailSheetPresentation()
        case .newReport:
            ReportTypeSheet()
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        case .suggest(let id):
            SuggestFixSheet(cameraID: id)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        case .login:
            LoginSheet()
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        case .profile:
            ProfileSheet()
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        case .tripConsent(let starting):
            TripConsentSheet(startingTrip: starting)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
    }
}

private extension View {
    func detailSheetPresentation() -> some View {
        presentationDetents([.fraction(AppConfig.detailSheetFraction), .large])
            .presentationBackgroundInteraction(.enabled(upThrough: .fraction(AppConfig.detailSheetFraction)))
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(24)
            .presentationContentInteraction(.resizes)
    }
}

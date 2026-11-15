import SwiftUI

struct MapScreen: View {
    @Environment(MapStore.self) var store
    @Environment(SessionStore.self) var session
    @Environment(LocationProvider.self) var location
    @Environment(ToastCenter.self) var toasts

    var body: some View {
        @Bindable var store = store

        GeometryReader { geometry in
            ZStack(alignment: .top) {
                mapLayer(height: geometry.size.height + geometry.safeAreaInsets.top + geometry.safeAreaInsets.bottom)

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
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    } else {
                        HStack {
                            Spacer()
                            MapActions(onLocate: locate, onReport: startReport)
                        }
                        .opacity(actionsHidden ? 0 : 1)
                        .allowsHitTesting(!actionsHidden)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 4)
                .padding(.bottom, store.placing == nil ? 12 : 30)

                ToastOverlay()
            }
        }
        .animation(.snappy(duration: 0.3), value: store.placing)
        .animation(.easeInOut(duration: 0.2), value: actionsHidden)
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
    private func mapLayer(height: CGFloat) -> some View {
        if MapKitBootstrap.isConfigured {
            YandexMapView(
                cameras: store.visibleCameras,
                reports: store.visibleReports,
                selectedCameraID: store.selectedCameraID,
                selectedReportID: store.selectedReportID,
                target: store.target,
                logoBottomInset: logoInset(screenHeight: height),
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

    private func logoInset(screenHeight: CGFloat) -> CGFloat {
        if store.placing != nil {
            return 150
        }
        if let sheet = store.sheet, sheet.coversMapPartially {
            return screenHeight * AppConfig.detailSheetFraction
        }
        return 0
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

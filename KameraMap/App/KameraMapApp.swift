import SwiftUI

@main
@MainActor
struct KameraMapApp: App {
    @State private var session: SessionStore
    @State private var meta = MetaStore()
    @State private var toasts: ToastCenter
    @State private var map: MapStore
    @State private var location = LocationProvider()
    @State private var trip: TripTracker
    @Environment(\.scenePhase) private var scenePhase

    init() {
        MapKitBootstrap.start()
        let session = SessionStore()
        let toasts = ToastCenter()
        let trip = TripTracker()
        _session = State(initialValue: session)
        _toasts = State(initialValue: toasts)
        _trip = State(initialValue: trip)
        _map = State(initialValue: MapStore(api: session.api, toasts: toasts))
        trip.onSharingRevoked = { [session, toasts] in
            toasts.show("Передача геопозиции выключена.")
            Task { await session.restore() }
        }
        trip.resumeIfConsented(api: session.api)
    }

    var body: some Scene {
        WindowGroup {
            MapScreen()
                .environment(session)
                .environment(meta)
                .environment(toasts)
                .environment(map)
                .environment(location)
                .environment(trip)
                .tint(Palette.brand)
                .task {
                    await session.restore()
                    await meta.load(using: session.api)
                }
        }
        .onChange(of: scenePhase) { _, phase in
            MapKitBootstrap.handle(phase)
        }
        .onChange(of: session.user?.isSharingLocation) { _, sharing in
            if let sharing {
                trip.syncConsent(sharing, api: session.api)
            }
        }
    }
}

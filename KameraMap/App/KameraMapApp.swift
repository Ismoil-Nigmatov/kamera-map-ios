import SwiftUI

@main
@MainActor
struct KameraMapApp: App {
    @State private var session: SessionStore
    @State private var meta = MetaStore()
    @State private var toasts: ToastCenter
    @State private var map: MapStore
    @State private var location = LocationProvider()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        MapKitBootstrap.start()
        let session = SessionStore()
        let toasts = ToastCenter()
        _session = State(initialValue: session)
        _toasts = State(initialValue: toasts)
        _map = State(initialValue: MapStore(api: session.api, toasts: toasts))
    }

    var body: some Scene {
        WindowGroup {
            MapScreen()
                .environment(session)
                .environment(meta)
                .environment(toasts)
                .environment(map)
                .environment(location)
                .tint(Palette.brand)
                .task {
                    await session.restore()
                    await meta.load(using: session.api)
                }
        }
        .onChange(of: scenePhase) { _, phase in
            MapKitBootstrap.handle(phase)
        }
    }
}

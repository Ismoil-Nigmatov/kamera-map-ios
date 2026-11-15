import SwiftUI
import YandexMapsMobile

@MainActor
enum MapKitBootstrap {
    private static var started = false

    static var isConfigured: Bool {
        !AppConfig.yandexMapKitKey.isEmpty
    }

    static func start() {
        guard !started, isConfigured else { return }
        started = true
        YMKMapKit.setApiKey(AppConfig.yandexMapKitKey)
        YMKMapKit.setLocale("ru_RU")
        YMKMapKit.sharedInstance().onStart()
    }

    static func handle(_ phase: ScenePhase) {
        guard started else { return }
        switch phase {
        case .active:
            YMKMapKit.sharedInstance().onStart()
        case .background:
            YMKMapKit.sharedInstance().onStop()
        default:
            break
        }
    }
}

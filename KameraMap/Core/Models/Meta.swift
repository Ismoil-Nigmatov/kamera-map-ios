import Foundation
import Observation

struct LabeledValue: Decodable, Hashable, Identifiable, Sendable {
    let value: String
    let label: String

    var id: String { value }
}

struct ReportTypeInfo: Decodable, Hashable, Identifiable, Sendable {
    let value: String
    let label: String
    let lifetimeMinutes: Int

    var id: String { value }

    var type: ReportType {
        ReportType(rawValue: value) ?? .other
    }
}

struct Meta: Decodable, Sendable {
    var violations: [LabeledValue]
    var statuses: [LabeledValue]
    var kinds: [LabeledValue]
    var sources: [LabeledValue]
    var reportTypes: [ReportTypeInfo]

    static let fallback = Meta(
        violations: [
            ("speed", "Скорость"),
            ("red_light", "Проезд на красный"),
            ("stop_line", "Стоп-линия"),
            ("lane", "Движение по полосам"),
            ("bus_lane", "Полоса для автобусов"),
            ("road_marking", "Сплошная и разметка"),
            ("oncoming", "Выезд на встречную"),
            ("no_stopping", "Остановка и стоянка"),
            ("pedestrian", "Пропуск пешеходов"),
            ("seatbelt", "Ремень безопасности"),
            ("road_signs", "Требования знаков"),
            ("other", "Другое"),
        ].map { LabeledValue(value: $0.0, label: $0.1) },
        statuses: [
            ("active", "Работает"),
            ("unverified", "Не проверена"),
            ("inactive", "Не работает"),
        ].map { LabeledValue(value: $0.0, label: $0.1) },
        kinds: [
            ("camera", "Камера"),
            ("radar", "Радар"),
        ].map { LabeledValue(value: $0.0, label: $0.1) },
        sources: [
            ("official", "Список МВД"),
            ("admin", "Модератор"),
            ("user", "Водитель"),
            ("demo", "Демо-данные"),
        ].map { LabeledValue(value: $0.0, label: $0.1) },
        reportTypes: [
            ReportTypeInfo(value: "tripod", label: "Тренога", lifetimeMinutes: 180),
            ReportTypeInfo(value: "police", label: "Пост ДПС", lifetimeMinutes: 90),
            ReportTypeInfo(value: "accident", label: "ДТП", lifetimeMinutes: 60),
            ReportTypeInfo(value: "other", label: "Другое", lifetimeMinutes: 30),
        ]
    )
}

@Observable
@MainActor
final class MetaStore {
    private(set) var meta = Meta.fallback

    func load(using api: APIClient) async {
        if let fresh = try? await api.meta() {
            meta = fresh
        }
    }

    func violation(_ value: String) -> String {
        label(value, in: meta.violations)
    }

    func status(_ status: CameraStatus) -> String {
        label(status.rawValue, in: meta.statuses)
    }

    func kind(_ kind: CameraKind) -> String {
        label(kind.rawValue, in: meta.kinds)
    }

    func source(_ value: String) -> String {
        label(value, in: meta.sources)
    }

    func report(_ type: ReportType) -> ReportTypeInfo {
        meta.reportTypes.first { $0.value == type.rawValue }
            ?? Meta.fallback.reportTypes.first { $0.value == type.rawValue }
            ?? ReportTypeInfo(value: type.rawValue, label: type.rawValue, lifetimeMinutes: 30)
    }

    private func label(_ value: String, in options: [LabeledValue]) -> String {
        options.first { $0.value == value }?.label ?? value
    }
}

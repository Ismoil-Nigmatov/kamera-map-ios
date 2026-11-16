import SwiftUI

struct TripPanel: View {
    @Environment(TripTracker.self) var trip
    @Binding var following: Bool
    let onReport: () -> Void
    let onEnableSharing: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let alert = trip.alerts.current {
                AlertRow(alert: alert)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            HStack(alignment: .center, spacing: 14) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(trip.speedKmh.map { "\($0)" } ?? "—")
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .animation(.snappy, value: trip.speedKmh)
                        .foregroundStyle(trip.alerts.current?.isOverSpeed == true ? Palette.brand : Color.primary)
                    Text("км/ч")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("В пути")
                        .font(.headline)
                    Text(statusLine)
                        .font(.footnote)
                        .foregroundStyle(trip.problem == nil ? Color.secondary : Palette.brand)
                        .lineLimit(2)
                        .accessibilityLabel(statusDescription)
                        .accessibilityIdentifier("tripStatus")
                }

                Spacer(minLength: 0)

                Button {
                    trip.alerts.toggleVoice()
                    Haptics.tap()
                } label: {
                    Image(systemName: trip.alerts.voiceEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .frame(width: 44, height: 44)
                        .background(Color(uiColor: .secondarySystemBackground), in: .circle)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(trip.alerts.voiceEnabled ? "Выключить голос" : "Включить голос")
                .accessibilityIdentifier("tripVoiceButton")

                Button {
                    following.toggle()
                    Haptics.tap()
                } label: {
                    Image(systemName: following ? "location.fill" : "location")
                        .font(.system(size: 17, weight: .semibold))
                        .frame(width: 44, height: 44)
                        .background(Color(uiColor: .secondarySystemBackground), in: .circle)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(following ? "Не следовать за мной" : "Следовать за мной")
            }

            HStack(spacing: 10) {
                if !trip.isSharing {
                    Button(action: onEnableSharing) {
                        Label("Передавать", systemImage: "antenna.radiowaves.left.and.right")
                    }
                    .buttonStyle(SoftButtonStyle())
                }

                Button(action: onReport) {
                    Label("Сообщить", systemImage: "megaphone.fill")
                }
                .buttonStyle(SoftButtonStyle())

                Button {
                    Haptics.tap()
                    trip.stop()
                } label: {
                    Label("Завершить", systemImage: "stop.fill")
                }
                .buttonStyle(ProminentButtonStyle())
                .accessibilityIdentifier("stopTripButton")
            }
        }
        .padding(14)
        .floatingSurface(.rect(cornerRadius: 22, style: .continuous))
        .animation(.snappy(duration: 0.25), value: trip.alerts.current?.hazard)
    }

    private var statusLine: String {
        if let problem = trip.problem {
            return problem
        }
        if trip.location == nil {
            return "Ищем вас…"
        }
        return trip.isSharing ? "Передача · \(trip.sent)" : "Без передачи"
    }

    private var statusDescription: String {
        if let problem = trip.problem {
            return problem
        }
        if trip.location == nil {
            return "Определяем, где вы"
        }
        return trip.isSharing ? "Передача включена, отправлено точек: \(trip.sent)" : "Передача геопозиции выключена"
    }
}

private struct AlertRow: View {
    let alert: TripAlert

    var body: some View {
        HStack(spacing: 12) {
            IconBadge(systemImage: symbol, color: color, size: 42)
            VStack(alignment: .leading, spacing: 2) {
                Text(alert.hazard.kind.title)
                    .font(.headline)
                Text("через \(alert.distanceText)")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if let limit = alert.hazard.speedLimit {
                SpeedLimitSign(limit: limit)
            }
        }
        .padding(10)
        .background(
            alert.isOverSpeed ? Palette.brand.opacity(0.18) : Color(uiColor: .secondarySystemBackground),
            in: .rect(cornerRadius: 16, style: .continuous)
        )
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("tripAlert")
    }

    private var symbol: String {
        switch alert.hazard.kind {
        case .camera: CameraKind.camera.symbol
        case .radar: CameraKind.radar.symbol
        case .report(let type): type.symbol
        }
    }

    private var color: Color {
        switch alert.hazard.kind {
        case .camera, .radar: Palette.brand
        case .report(let type): Palette.report(type)
        }
    }
}

private struct SpeedLimitSign: View {
    let limit: Int

    var body: some View {
        Text("\(limit)")
            .font(.system(size: 17, weight: .heavy, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(.black)
            .frame(width: 46, height: 46)
            .background(.white, in: .circle)
            .overlay(Circle().strokeBorder(Color.red, lineWidth: 5))
            .accessibilityLabel("Ограничение \(limit)")
    }
}

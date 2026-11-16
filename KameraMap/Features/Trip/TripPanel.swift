import SwiftUI

struct TripPanel: View {
    @Environment(TripTracker.self) var trip
    @Binding var following: Bool
    let onReport: () -> Void
    let onEnableSharing: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 14) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(trip.speedKmh.map { "\($0)" } ?? "—")
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .animation(.snappy, value: trip.speedKmh)
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
                        .accessibilityIdentifier("tripStatus")
                }

                Spacer(minLength: 0)

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
    }

    private var statusLine: String {
        if let problem = trip.problem {
            return problem
        }
        if trip.location == nil {
            return "Определяем, где вы…"
        }
        return trip.isSharing ? "Передача включена · отправлено точек: \(trip.sent)" : "Передача геопозиции выключена"
    }
}

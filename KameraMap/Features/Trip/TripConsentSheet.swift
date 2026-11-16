import SwiftUI

struct TripConsentSheet: View {
    @Environment(SessionStore.self) var session
    @Environment(MapStore.self) var store
    @Environment(TripTracker.self) var trip
    @Environment(ToastCenter.self) var toasts
    let startingTrip: Bool
    @State private var isWorking = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    IconBadge(systemImage: "location.fill", color: Palette.brand, size: 52)
                    Text("Передавать мою геопозицию?")
                        .font(.title2.weight(.bold))
                    Text(TripTexts.sharing)
                    Text(TripTexts.off)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(20)
            }
            .bottomActionBar {
                VStack(spacing: 10) {
                    Button {
                        choose(share: true)
                    } label: {
                        if isWorking {
                            ProgressView().tint(.white)
                        } else {
                            Text(startingTrip ? "Передавать и поехать" : "Включить передачу")
                        }
                    }
                    .buttonStyle(ProminentButtonStyle())
                    .accessibilityIdentifier("shareAndStartButton")

                    if startingTrip {
                        Button {
                            choose(share: false)
                        } label: {
                            Text("Поехать без передачи")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(SoftButtonStyle())
                        .accessibilityIdentifier("startWithoutSharingButton")
                    }
                }
                .disabled(isWorking)
            }
            .navigationTitle("Поездка")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") {
                        store.sheet = nil
                    }
                }
            }
        }
    }

    private func choose(share: Bool) {
        Task {
            if share {
                isWorking = true
                do {
                    try await session.setLocationSharing(true)
                } catch {
                    isWorking = false
                    toasts.show(error)
                    return
                }
                isWorking = false
            }
            store.sheet = nil
            if startingTrip {
                trip.start(api: session.api, sharing: share)
            } else if share {
                trip.enableSharing()
            }
        }
    }
}

import SwiftUI

struct TopBar: View {
    @Environment(MapStore.self) var store
    @Environment(SessionStore.self) var session

    var body: some View {
        @Bindable var store = store

        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 28, height: 28)
                        .background(Palette.brand, in: .rect(cornerRadius: 8, style: .continuous))
                    Text("Kamera Map")
                        .font(.headline)
                }
                HStack(spacing: 6) {
                    FilterToggle(title: "Камеры", isOn: $store.showCameras)
                    FilterToggle(title: "Метки", isOn: $store.showReports)
                }
                if store.showCameras {
                    Legend()
                }
            }
            .padding(10)
            .floatingSurface(.rect(cornerRadius: 18, style: .continuous))

            Spacer(minLength: 0)

            Button {
                Haptics.tap()
                store.sheet = session.isSignedIn ? .profile : .login
            } label: {
                if session.isSignedIn {
                    Text(session.user?.initials ?? "…")
                        .font(.subheadline.weight(.bold))
                        .frame(width: 44, height: 44)
                        .floatingSurface(.circle)
                } else {
                    Text("Войти")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 16)
                        .frame(height: 44)
                        .floatingSurface(.capsule)
                }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("accountButton")
            .accessibilityLabel(session.isSignedIn ? "Профиль" : "Войти")
        }
    }
}

private struct FilterToggle: View {
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            Text(title)
                .font(.footnote.weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isOn ? Color(uiColor: .label) : Color.clear, in: .capsule)
                .overlay(Capsule().strokeBorder(Color(uiColor: .label).opacity(isOn ? 0 : 0.2)))
                .foregroundStyle(isOn ? Color(uiColor: .systemBackground) : .secondary)
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: isOn)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

private struct Legend: View {
    @Environment(MetaStore.self) var meta

    var body: some View {
        HStack(spacing: 10) {
            ForEach(CameraStatus.allCases, id: \.self) { status in
                HStack(spacing: 4) {
                    Circle()
                        .fill(Palette.status(status))
                        .frame(width: 8, height: 8)
                    Text(meta.status(status).lowercased())
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

struct MapHints: View {
    @Environment(MapStore.self) var store

    var body: some View {
        VStack(spacing: 6) {
            if store.region != nil, !store.zoomedInEnough, store.placing == nil {
                hint("Приблизьте карту, чтобы увидеть камеры и метки", systemImage: "plus.magnifyingglass", color: .primary)
            }
            if store.loadFailed {
                hint("Не удалось обновить данные", systemImage: "wifi.exclamationmark", color: Palette.brand)
            }
        }
        .animation(.snappy, value: store.zoomedInEnough)
        .animation(.snappy, value: store.loadFailed)
    }

    private func hint(_ text: String, systemImage: String, color: Color) -> some View {
        Label(text, systemImage: systemImage)
            .font(.footnote.weight(.medium))
            .foregroundStyle(color)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .floatingSurface(.capsule)
            .transition(.move(edge: .top).combined(with: .opacity))
    }
}

struct MapActions: View {
    @Environment(LocationProvider.self) var location
    let onLocate: () -> Void
    let onTrip: () -> Void
    let onReport: () -> Void

    var body: some View {
        VStack(alignment: .trailing, spacing: 12) {
            Button(action: onLocate) {
                Group {
                    if location.isLocating {
                        ProgressView()
                    } else {
                        Image(systemName: "location.fill")
                            .font(.system(size: 18, weight: .semibold))
                    }
                }
                .frame(width: 52, height: 52)
                .floatingSurface(.circle)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("locateButton")
            .accessibilityLabel("Показать, где я")

            Button(action: onTrip) {
                Label("В путь", systemImage: "car.fill")
                    .font(.headline)
                    .padding(.horizontal, 20)
                    .frame(height: 50)
                    .floatingSurface(.capsule)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("tripButton")

            Button(action: onReport) {
                Label("Сообщить", systemImage: "megaphone.fill")
                    .font(.headline)
                    .padding(.horizontal, 22)
                    .frame(height: 56)
                    .background(Palette.brand, in: .capsule)
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .shadow(color: Palette.brand.opacity(0.4), radius: 12, y: 6)
            .accessibilityIdentifier("reportButton")
        }
    }
}

struct PlacementPin: View {
    let type: ReportType

    var body: some View {
        VStack(spacing: 0) {
            IconBadge(systemImage: type.symbol, color: Palette.report(type), size: 48)
                .overlay(Circle().strokeBorder(.white, lineWidth: 3))
                .shadow(color: .black.opacity(0.25), radius: 6, y: 3)
            Rectangle()
                .fill(Color.primary)
                .frame(width: 3, height: 18)
            Circle()
                .fill(Color.primary)
                .frame(width: 10, height: 10)
                .overlay(Circle().strokeBorder(.white, lineWidth: 2))
        }
        .offset(y: -38)
    }
}

struct PlacementCard: View {
    @Environment(MapStore.self) var store
    @Environment(MetaStore.self) var meta
    let draft: ReportDraft

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                IconBadge(systemImage: draft.type.symbol, color: Palette.report(draft.type), size: 32)
                Text(store.canPlaceHere
                    ? "Подвиньте карту, чтобы метка «\(meta.report(draft.type).label)» встала точно на место, или нажмите на нужную точку."
                    : "Приблизьте карту, чтобы поставить метку точно.")
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 10) {
                Button("Отмена") {
                    store.cancelPlacing()
                }
                .buttonStyle(SoftButtonStyle())
                .frame(maxWidth: 120)

                Button {
                    Task { await store.placeReport() }
                } label: {
                    if store.isBusy {
                        ProgressView().tint(.white)
                    } else {
                        Text("Поставить здесь")
                    }
                }
                .buttonStyle(ProminentButtonStyle())
                .disabled(!store.canPlaceHere || store.isBusy)
                .accessibilityIdentifier("placeHereButton")
            }
        }
        .padding(14)
        .floatingSurface(.rect(cornerRadius: 20, style: .continuous))
    }
}

struct ToastOverlay: View {
    @Environment(ToastCenter.self) var toasts

    var body: some View {
        VStack {
            if let toast = toasts.current {
                HStack(spacing: 10) {
                    Image(systemName: toast.isError ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                        .foregroundStyle(toast.isError ? Palette.brand : Palette.status(.active))
                    Text(toast.message)
                        .font(.subheadline.weight(.medium))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .floatingSurface(.capsule)
                .padding(.horizontal, 20)
                .transition(.move(edge: .top).combined(with: .opacity))
                .onTapGesture { toasts.dismiss() }
                .id(toast.id)
            }
            Spacer()
        }
        .padding(.top, 6)
        .animation(.spring(duration: 0.35), value: toasts.current)
    }
}

struct MissingMapKeyView: View {
    var body: some View {
        ContentUnavailableView {
            Label("Нет ключа Яндекс MapKit", systemImage: "map")
        } description: {
            Text("Добавьте ключ MapKit в секрет YANDEX_MAPKIT_KEY репозитория и пересоберите приложение.")
        }
        .background(Color(uiColor: .systemGroupedBackground))
    }
}

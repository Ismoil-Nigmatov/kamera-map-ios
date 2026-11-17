import SwiftUI

struct ProfileSheet: View {
    @Environment(SessionStore.self) var session
    @Environment(MapStore.self) var store
    @Environment(ToastCenter.self) var toasts
    @State var name = ""
    @State var isSaving = false
    @State var confirmDelete = false
    @State var isChangingSharing = false
    @State var confirmStopSharing = false
    @Environment(TripTracker.self) var trip
    @Environment(\.openURL) var openURL

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 14) {
                        Text(session.user?.initials ?? "…")
                            .font(.title3.weight(.bold))
                            .foregroundStyle(.white)
                            .frame(width: 56, height: 56)
                            .background(Palette.brand, in: .circle)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(session.user?.name ?? "Загружаем…")
                                .font(.headline)
                            if let phone = session.user?.phone {
                                Text(phone)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            if session.isAdmin {
                                Pill(text: "Администратор", color: Palette.brand)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section {
                    Toggle(isOn: sharingBinding) {
                        Label("Передавать геопозицию", systemImage: "location.fill")
                    }
                    .disabled(isChangingSharing || session.user == nil)
                    .accessibilityIdentifier("sharingToggle")
                    .confirmationDialog("Выключить передачу?", isPresented: $confirmStopSharing, titleVisibility: .visible) {
                        Button("Выключить и удалить историю", role: .destructive) {
                            Task { await changeSharing(false) }
                        }
                        Button("Отмена", role: .cancel) {}
                    } message: {
                        Text("История ваших поездок будет удалена.")
                    }

                    if session.user?.isSharingLocation == true, !trip.hasAlwaysAccess {
                        Button {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                openURL(url)
                            }
                        } label: {
                            Label("Разрешить доступ «Всегда»", systemImage: "location.circle")
                        }
                    }

                    Toggle(isOn: voiceBinding) {
                        Label("Голосовые предупреждения", systemImage: "speaker.wave.2.fill")
                    }
                } header: {
                    Text("Поездки")
                } footer: {
                    if session.user?.isSharingLocation == true, !trip.hasAlwaysAccess {
                        Text("\(TripTexts.always) \(TripTexts.sharing) \(TripTexts.off)")
                    } else {
                        Text("\(TripTexts.sharing) \(TripTexts.off)")
                    }
                }

                Section("Имя") {
                    TextField("Как вас зовут", text: $name)
                        .textContentType(.givenName)
                    Button {
                        Task { await save() }
                    } label: {
                        if isSaving {
                            ProgressView()
                        } else {
                            Text("Сохранить")
                        }
                    }
                    .disabled(isSaving || trimmedName.isEmpty || trimmedName == session.user?.name)
                }

                Section {
                    Button {
                        Task {
                            trip.endAll()
                            await session.signOut()
                            store.sheet = nil
                            toasts.show("Вы вышли из аккаунта.")
                        }
                    } label: {
                        Label("Выйти", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                    Button(role: .destructive) {
                        confirmDelete = true
                    } label: {
                        Label("Удалить аккаунт", systemImage: "trash")
                    }
                    .accessibilityIdentifier("deleteAccountButton")
                } footer: {
                    Text("Удаление необратимо: аккаунт и ваши голоса исчезнут, метки и правки останутся без автора.")
                }

                Section("О приложении") {
                    LabeledContent("Версия", value: AppConfig.appVersion)
                    Link(destination: AppConfig.yandexTermsURL) {
                        Label("Условия использования Яндекс Карт", systemImage: "doc.text")
                    }
                    Text("Камеры — из официального списка МВД Узбекистана и от водителей. Данные могут быть неточными: всегда соблюдайте ПДД.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Профиль")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") {
                        store.sheet = nil
                    }
                }
            }
            .confirmationDialog("Удалить аккаунт?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Удалить аккаунт", role: .destructive) {
                    Task { await deleteAccount() }
                }
                Button("Отмена", role: .cancel) {}
            } message: {
                Text("Это нельзя отменить.")
            }
        }
        .onAppear {
            name = session.user?.name ?? ""
        }
        .task {
            await session.restore()
            if name.isEmpty {
                name = session.user?.name ?? ""
            }
        }
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        do {
            try await session.rename(trimmedName)
            Haptics.success()
            toasts.show("Имя сохранено.")
        } catch {
            toasts.show(error)
        }
    }

    private var sharingBinding: Binding<Bool> {
        Binding(
            get: { session.user?.isSharingLocation ?? false },
            set: { enabled in
                if enabled {
                    Task { await changeSharing(true) }
                } else {
                    confirmStopSharing = true
                }
            }
        )
    }

    private var voiceBinding: Binding<Bool> {
        Binding(
            get: { trip.alerts.voiceEnabled },
            set: { enabled in
                if enabled != trip.alerts.voiceEnabled {
                    trip.alerts.toggleVoice()
                }
            }
        )
    }

    private func changeSharing(_ enabled: Bool) async {
        isChangingSharing = true
        defer { isChangingSharing = false }
        do {
            try await session.setLocationSharing(enabled)
            if enabled {
                trip.consentGranted(api: session.api)
            } else {
                trip.consentWithdrawn()
            }
            toasts.show(enabled ? "Передача геопозиции включена." : "Передача выключена, история поездок удалена.")
        } catch {
            toasts.show(error)
        }
    }

    private func deleteAccount() async {
        do {
            trip.endAll()
            try await session.deleteAccount()
            store.sheet = nil
            toasts.show("Аккаунт удалён.")
        } catch {
            toasts.show(error)
        }
    }
}

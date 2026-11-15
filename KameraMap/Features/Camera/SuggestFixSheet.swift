import SwiftUI

struct SuggestFixSheet: View {
    let cameraID: Int

    @Environment(MapStore.self) var store
    @Environment(MetaStore.self) var meta
    @State var action: SuggestionAction = .remove
    @State var violation: String?
    @State var comment = ""
    @FocusState var commentFocused: Bool

    private var camera: CameraDetails? {
        store.details[cameraID]
    }

    private var fixed: Set<String> {
        Set(camera?.fixedViolations ?? [])
    }

    private var options: [LabeledValue] {
        meta.meta.violations.filter { fixed.contains($0.value) == (action == .remove) }
    }

    private var chosen: String? {
        guard let violation, options.contains(where: { $0.value == violation }) else { return nil }
        return violation
    }

    private var needsComment: Bool {
        chosen == "other"
    }

    private var canSend: Bool {
        chosen != nil && (!needsComment || !comment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) && !store.isBusy
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Text("Другие водители проголосуют за ваше предложение, а администратор проверит его и поправит камеру.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Picker("Что не так", selection: $action) {
                        Text("Не фиксирует").tag(SuggestionAction.remove)
                        Text("Фиксирует ещё").tag(SuggestionAction.add)
                    }
                    .pickerStyle(.segmented)
                    .disabled(fixed.isEmpty)

                    VStack(alignment: .leading, spacing: 10) {
                        Text(action == .remove ? "Что камера на самом деле не фиксирует?" : "Что ещё фиксирует камера?")
                            .font(.headline)
                        FlowLayout(spacing: 8) {
                            ForEach(options) { option in
                                ChoiceChip(title: option.label, isSelected: chosen == option.value) {
                                    violation = option.value
                                }
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text(needsComment ? "Что именно? (обязательно)" : "Комментарий (необязательно)")
                            .font(.headline)
                        TextField(placeholder, text: $comment, axis: .vertical)
                            .lineLimit(2...4)
                            .padding(12)
                            .background(Color(uiColor: .secondarySystemBackground), in: .rect(cornerRadius: 12, style: .continuous))
                            .focused($commentFocused)
                            .onChange(of: comment) { _, value in
                                if value.count > 255 {
                                    comment = String(value.prefix(255))
                                }
                            }
                        if needsComment, comment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Text("Для «Другое» напишите, о чём речь.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(20)
            }
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom) {
                Button {
                    send()
                } label: {
                    if store.isBusy {
                        ProgressView().tint(.white)
                    } else {
                        Label("Отправить", systemImage: "paperplane.fill")
                    }
                }
                .buttonStyle(ProminentButtonStyle())
                .disabled(!canSend)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(.bar)
                .accessibilityIdentifier("sendSuggestionButton")
            }
            .navigationTitle("Что не так с камерой?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Назад") {
                        store.sheet = .camera(cameraID)
                    }
                }
            }
        }
        .onAppear {
            if fixed.isEmpty {
                action = .add
            }
        }
    }

    private var placeholder: String {
        if needsComment {
            return "Опишите, о каком нарушении речь"
        }
        return action == .remove ? "Например: на правой полосе не снимает" : "Например: снимает и на третьей полосе"
    }

    private func send() {
        guard let chosen else { return }
        let text = comment.trimmingCharacters(in: .whitespacesAndNewlines)
        let draft = SuggestionDraft(action: action, violation: chosen, comment: text.isEmpty ? nil : text)
        Task {
            if await store.suggestFix(cameraID, draft) {
                store.sheet = .camera(cameraID)
            }
        }
    }
}

import SwiftUI

struct ReportTypeSheet: View {
    @Environment(MapStore.self) var store
    @Environment(MetaStore.self) var meta
    @Environment(LocationProvider.self) var location
    @State var type: ReportType?
    @State var comment = ""

    private var needsComment: Bool {
        type == .other
    }

    private var canContinue: Bool {
        type != nil && (!needsComment || !comment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Text("Выберите, что видите, а затем укажите точное место на карте. Другие водители смогут подтвердить метку или опровергнуть её.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                        ForEach(meta.meta.reportTypes) { info in
                            TypeTile(info: info, isSelected: type == info.type) {
                                type = info.type
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text(needsComment ? "Что именно? (обязательно)" : "Комментарий (необязательно)")
                            .font(.headline)
                        TextField(
                            needsComment ? "Например: яма на дороге, сломан светофор" : "Например: за мостом, в сторону центра",
                            text: $comment,
                            axis: .vertical
                        )
                        .lineLimit(1...3)
                        .padding(12)
                        .background(Color(uiColor: .secondarySystemBackground), in: .rect(cornerRadius: 12, style: .continuous))
                        .onChange(of: comment) { _, value in
                            if value.count > 200 {
                                comment = String(value.prefix(200))
                            }
                        }
                        if needsComment, comment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Text("Напишите, что вы видите, — без этого метку «Другое» не поставить.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(20)
            }
            .scrollDismissesKeyboard(.interactively)
            .bottomActionBar {
                Button {
                    chooseLocation()
                } label: {
                    Label("Указать место на карте", systemImage: "mappin.and.ellipse")
                }
                .buttonStyle(ProminentButtonStyle())
                .disabled(!canContinue)
                .accessibilityIdentifier("chooseLocationButton")
            }
            .navigationTitle("Что вы видите?")
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

    private func chooseLocation() {
        guard let type else { return }
        let draft = ReportDraft(type: type, comment: comment.trimmingCharacters(in: .whitespacesAndNewlines))
        store.startPlacing(draft, near: location.lastKnown)
        Task {
            if let point = try? await location.current() {
                store.refinePlacement(draft, near: point)
            }
        }
    }
}

private struct TypeTile: View {
    let info: ReportTypeInfo
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 10) {
                IconBadge(systemImage: info.type.symbol, color: Palette.report(info.type), size: 48)
                Text(info.label)
                    .font(.subheadline.weight(.semibold))
                Text("на \(Format.lifetime(minutes: info.lifetimeMinutes))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background(
                isSelected ? Palette.report(info.type).opacity(0.12) : Color(uiColor: .secondarySystemBackground),
                in: .rect(cornerRadius: 18, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(isSelected ? Palette.report(info.type) : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: isSelected)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

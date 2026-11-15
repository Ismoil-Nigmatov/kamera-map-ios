import SwiftUI

struct SuggestionsSection: View {
    let camera: CameraDetails

    @Environment(MapStore.self) var store
    @Environment(SessionStore.self) var session
    @Environment(MetaStore.self) var meta

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(camera.suggestions.isEmpty ? "Камера фиксирует не то?" : "Водители предлагают поправить")
                .font(.headline)

            ForEach(camera.suggestions) { suggestion in
                SuggestionRow(
                    suggestion: suggestion,
                    title: meta.violation(suggestion.violation),
                    canVote: session.isSignedIn,
                    isBusy: store.isBusy,
                    onVote: { value in
                        Task { await store.voteSuggestion(suggestion, cameraID: camera.id, value) }
                    }
                )
            }

            if session.isSignedIn {
                Button {
                    store.sheet = .suggest(camera.id)
                } label: {
                    Label("Предложить правку", systemImage: "pencil.line")
                }
                .buttonStyle(SoftButtonStyle())
                .accessibilityIdentifier("suggestFixButton")
            } else {
                Button {
                    store.requireLogin(returningTo: .camera(camera.id))
                } label: {
                    Label("Войдите, чтобы предложить правку", systemImage: "person.crop.circle")
                }
                .buttonStyle(SoftButtonStyle())
            }
        }
    }
}

private struct SuggestionRow: View {
    let suggestion: CameraSuggestion
    let title: String
    let canVote: Bool
    let isBusy: Bool
    let onVote: (VoteValue) -> Void

    private var removing: Bool {
        suggestion.action == .remove
    }

    var body: some View {
        Card {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: removing ? "minus.circle.fill" : "plus.circle.fill")
                    .foregroundStyle(removing ? Palette.brand : Palette.status(.active))
                (Text(removing ? "Не фиксирует: " : "Фиксирует ещё: ") + Text(title).bold())
                    .font(.subheadline)
            }
            if let comment = suggestion.comment {
                Text("«\(comment)»")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if canVote {
                HStack(spacing: 8) {
                    VoteButton(title: "За", count: suggestion.agree, systemImage: "hand.thumbsup", isActive: suggestion.myVote == .confirm, tint: Palette.status(.active)) {
                        onVote(.confirm)
                    }
                    VoteButton(title: "Против", count: suggestion.disagree, systemImage: "hand.thumbsdown", isActive: suggestion.myVote == .deny, tint: Palette.brand) {
                        onVote(.deny)
                    }
                }
                .disabled(isBusy)
                if suggestion.isMine {
                    Text("Ваше предложение")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("За — \(suggestion.agree), против — \(suggestion.disagree)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

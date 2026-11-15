import SwiftUI

struct CameraSheet: View {
    let cameraID: Int

    @Environment(MapStore.self) var store
    @Environment(SessionStore.self) var session
    @Environment(MetaStore.self) var meta
    @Environment(\.openURL) var openURL

    var body: some View {
        Group {
            if let camera = store.details[cameraID] {
                content(camera)
            } else {
                loading
            }
        }
        .task(id: cameraID) {
            await store.loadDetails(cameraID)
        }
    }

    private var loading: some View {
        VStack(spacing: 14) {
            ProgressView()
            Text("Загружаем камеру…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 40)
    }

    private func content(_ camera: CameraDetails) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                SheetHeader(
                    title: camera.address ?? "\(meta.kind(camera.kind)) №\(camera.id)",
                    subtitle: nil,
                    leading: {
                        IconBadge(systemImage: camera.kind.symbol, color: Palette.status(camera.status))
                    },
                    onClose: { store.sheet = nil }
                )

                badges(camera)
                rules(camera)

                if let description = camera.description, !description.isEmpty {
                    Text(description)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Text(sourceLine(camera))
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Divider()

                SuggestionsSection(camera: camera)

                Divider()

                VoteSection(
                    question: "Камера на месте?",
                    confirmTitle: "На месте",
                    denyTitle: "Её нет",
                    confirms: camera.votes.confirm,
                    denies: camera.votes.deny,
                    myVote: camera.myVote,
                    canVote: session.isSignedIn,
                    isBusy: store.isBusy,
                    onVote: { value in Task { await store.voteCamera(camera.id, value) } },
                    onLogin: { store.requireLogin(returningTo: .camera(camera.id)) }
                )

                if session.isAdmin {
                    Divider()
                    adminSection(camera)
                }
            }
            .padding(20)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    private func badges(_ camera: CameraDetails) -> some View {
        FlowLayout(spacing: 6) {
            Pill(text: meta.status(camera.status), color: Palette.status(camera.status), filled: true)
            Pill(text: meta.kind(camera.kind))
            if let heading = camera.heading {
                Pill(text: camera.bidirectional ? "Снимает оба направления" : "Снимает едущих на \(Format.compass(heading))")
            }
        }
    }

    @ViewBuilder
    private func rules(_ camera: CameraDetails) -> some View {
        if camera.rules.isEmpty {
            Text("Пока неизвестно, что фиксирует эта камера.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(camera.detailedRules) { rule in
                    RuleCard(rule: rule, title: meta.violation(rule.violation), laneCount: camera.laneCount)
                }
                if !camera.generalRules.isEmpty {
                    Text(camera.detailedRules.isEmpty ? "Фиксирует" : "Также фиксирует")
                        .font(.subheadline.weight(.semibold))
                    FlowLayout(spacing: 6) {
                        ForEach(camera.generalRules) { rule in
                            Pill(text: meta.violation(rule.violation), color: .primary)
                        }
                    }
                    if camera.detailedRules.isEmpty {
                        Text("Полосы и лимит скорости пока не уточнены.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func sourceLine(_ camera: CameraDetails) -> String {
        var line = "Источник: \(meta.source(camera.source))"
        if let verified = camera.verifiedAt {
            line += " · проверена \(Format.day(verified))"
        }
        return line
    }

    private func adminSection(_ camera: CameraDetails) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Админ · камера №\(camera.id)")
                .font(.headline)
            HStack(spacing: 8) {
                ForEach(CameraStatus.allCases, id: \.self) { status in
                    Button {
                        Task { await store.setStatus(camera.id, status, label: meta.status(status)) }
                    } label: {
                        Text(meta.status(status))
                            .font(.footnote.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 36)
                            .background(
                                camera.status == status ? Palette.status(status) : Color(uiColor: .secondarySystemBackground),
                                in: .rect(cornerRadius: 10, style: .continuous)
                            )
                            .foregroundStyle(camera.status == status ? Color.white : .primary)
                    }
                    .buttonStyle(.plain)
                    .disabled(camera.status == status || store.isBusy)
                }
            }
            Button {
                openURL(AppConfig.adminCameraURL(camera.id))
            } label: {
                Label("Открыть в админке: направление, полосы, лимит", systemImage: "arrow.up.right.square")
                    .font(.footnote)
            }
        }
    }
}

private struct RuleCard: View {
    let rule: CameraRule
    let title: String
    let laneCount: Int?

    var body: some View {
        Card {
            HStack(alignment: .center) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if let limit = rule.speedLimit {
                    SpeedSign(limit: limit)
                }
            }
            if let schedule = rule.schedule {
                Label(schedule, systemImage: "clock")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if rule.lanes == nil, laneCount == nil {
                Text("На всех полосах")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                LaneDiagram(laneCount: laneCount, lanes: rule.lanes)
            }
            if let note = rule.note {
                Text(note)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct SpeedSign: View {
    let limit: Int

    var body: some View {
        Text("\(limit)")
            .font(.system(size: 14, weight: .heavy))
            .foregroundStyle(.black)
            .frame(width: 38, height: 38)
            .background(Circle().fill(.white))
            .overlay(Circle().strokeBorder(Palette.brand, lineWidth: 4))
    }
}

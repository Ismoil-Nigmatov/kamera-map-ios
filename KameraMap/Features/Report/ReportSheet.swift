import SwiftUI

struct ReportSheet: View {
    let reportID: Int

    @Environment(MapStore.self) var store
    @Environment(SessionStore.self) var session
    @Environment(MetaStore.self) var meta

    var body: some View {
        ScrollView {
            if let report = store.reports[reportID] {
                content(report)
            } else {
                ContentUnavailableView("Метки уже нет", systemImage: "mappin.slash", description: Text("Её сняли или истёк срок."))
                    .padding(.top, 30)
            }
        }
    }

    private func content(_ report: Report) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            SheetHeader(
                title: meta.report(report.type).label,
                subtitle: nil,
                leading: { IconBadge(systemImage: report.type.symbol, color: Palette.report(report.type)) },
                onClose: { store.sheet = nil }
            )

            if let comment = report.comment {
                Text("«\(comment)»")
                    .font(.body)
            }

            TimelineView(.periodic(from: .now, by: 30)) { context in
                Text(timing(report, now: context.date))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Divider()

            if report.isMine {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Это ваша метка.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Button(role: .destructive) {
                        Task { await store.voteReport(report.id, .deny) }
                    } label: {
                        Label("Снять метку", systemImage: "trash")
                    }
                    .buttonStyle(SoftButtonStyle())
                    .disabled(store.isBusy)
                }
            } else {
                VoteSection(
                    question: "Ещё там?",
                    confirmTitle: "Ещё там",
                    denyTitle: "Уже нет",
                    confirms: report.confirmations,
                    denies: report.rejections,
                    myVote: report.myVote,
                    canVote: session.isSignedIn,
                    isBusy: store.isBusy,
                    onVote: { value in Task { await store.voteReport(report.id, value) } },
                    onLogin: { store.requireLogin(returningTo: .report(report.id)) }
                )
            }
        }
        .padding(20)
    }

    private func timing(_ report: Report, now: Date) -> String {
        var parts: [String] = []
        if let created = report.createdAt {
            parts.append("Отметили \(Format.relative(created, now: now)).")
        }
        parts.append("Исчезнет \(Format.relative(report.expiresAt, now: now)), если её не подтвердят.")
        return parts.joined(separator: " ")
    }
}

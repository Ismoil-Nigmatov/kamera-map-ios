import SwiftUI

struct CameraListSheet: View {
    let cameraIDs: [Int]

    @Environment(MapStore.self) var store
    @Environment(MetaStore.self) var meta

    private var cameras: [CameraMarker] {
        cameraIDs.compactMap { store.cameras[$0] }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                SheetHeader(
                    title: "Камеры в этой точке: \(cameras.count)",
                    subtitle: "Выберите камеру, чтобы посмотреть, что она фиксирует.",
                    leading: { IconBadge(systemImage: "square.stack.3d.up.fill", color: Palette.status(.unverified)) },
                    onClose: { store.sheet = nil }
                )

                ForEach(cameras) { camera in
                    Button {
                        Haptics.tap()
                        store.openCamera(camera.id)
                    } label: {
                        row(camera)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(20)
        }
    }

    private func row(_ camera: CameraMarker) -> some View {
        HStack(spacing: 12) {
            IconBadge(systemImage: camera.kind.symbol, color: Palette.status(camera.status), size: 36)
            VStack(alignment: .leading, spacing: 3) {
                Text("\(meta.kind(camera.kind)) №\(camera.id)")
                    .font(.subheadline.weight(.semibold))
                Text(camera.violations.isEmpty
                    ? "Нарушения не указаны"
                    : camera.violations.map { meta.violation($0) }.joined(separator: ", "))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer()
            if let limit = camera.speedLimit {
                SpeedSign(limit: limit)
            }
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(12)
        .background(Color(uiColor: .secondarySystemBackground), in: .rect(cornerRadius: 14, style: .continuous))
    }
}

import SwiftUI

struct LaneDiagram: View {
    let laneCount: Int?
    let lanes: [Int]?

    private var total: Int {
        max(laneCount ?? 0, lanes?.max() ?? 0, 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                ForEach(1...total, id: \.self) { lane in
                    let active = lanes?.contains(lane) ?? true
                    Text("\(lane)")
                        .font(.caption.weight(.bold))
                        .frame(maxWidth: .infinity, minHeight: 30)
                        .background(
                            active ? Palette.brand.opacity(0.16) : Color(uiColor: .tertiarySystemFill),
                            in: .rect(cornerRadius: 7, style: .continuous)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .strokeBorder(active ? Palette.brand.opacity(0.7) : Color.clear, lineWidth: 1.5)
                        )
                        .foregroundStyle(active ? Palette.brand : .secondary)
                        .accessibilityLabel(active ? "Полоса \(lane), снимает" : "Полоса \(lane)")
                }
            }
            HStack {
                Text("← левая")
                Spacer()
                Text("правая →")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
    }
}

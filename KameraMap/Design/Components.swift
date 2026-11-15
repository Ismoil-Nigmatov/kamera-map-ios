import SwiftUI

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let height = rows.last.map { $0.y + $0.height } ?? 0
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: bounds.minY + row.y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
        }
    }

    private struct Row {
        var indices: [Int] = []
        var y: CGFloat = 0
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = []
        var current = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            if needed > width, !current.indices.isEmpty {
                rows.append(current)
                current = Row(y: current.y + current.height + spacing)
            }
            current.width = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            current.height = max(current.height, size.height)
            current.indices.append(index)
        }
        if !current.indices.isEmpty {
            rows.append(current)
        }
        return rows
    }
}

struct ProminentButtonStyle: ButtonStyle {
    var tint: Color = Palette.brand

    func makeBody(configuration: Configuration) -> some View {
        ProminentButtonBody(configuration: configuration, tint: tint)
    }
}

private struct ProminentButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let tint: Color
    @Environment(\.isEnabled) var isEnabled

    var body: some View {
        configuration.label
            .font(.body.weight(.semibold))
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(tint.opacity(isEnabled ? 1 : 0.4), in: .rect(cornerRadius: 14, style: .continuous))
            .foregroundStyle(.white)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.snappy(duration: 0.18), value: configuration.isPressed)
    }
}

struct SoftButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 14)
            .frame(minHeight: 40)
            .background(Color(uiColor: .secondarySystemBackground), in: .rect(cornerRadius: 12, style: .continuous))
            .foregroundStyle(.primary)
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

struct Pill: View {
    let text: String
    var color: Color = .secondary
    var filled = false

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(filled ? color : color.opacity(0.14), in: .capsule)
            .foregroundStyle(filled ? Color.white : color)
    }
}

struct ChoiceChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(
                    isSelected ? Color(uiColor: .label) : Color(uiColor: .secondarySystemBackground),
                    in: .capsule
                )
                .foregroundStyle(isSelected ? Color(uiColor: .systemBackground) : .primary)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .sensoryFeedback(.selection, trigger: isSelected)
    }
}

struct VoteButton: View {
    let title: String
    let count: Int
    let systemImage: String
    let isActive: Bool
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: isActive ? "\(systemImage).fill" : systemImage)
                Text(title)
                Text("\(count)")
                    .monospacedDigit()
                    .opacity(0.7)
            }
            .font(.subheadline.weight(.semibold))
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(
                isActive ? tint : Color(uiColor: .secondarySystemBackground),
                in: .rect(cornerRadius: 12, style: .continuous)
            )
            .foregroundStyle(isActive ? Color.white : .primary)
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.impact(weight: .light), trigger: isActive)
    }
}

struct VoteSection: View {
    let question: String
    let confirmTitle: String
    let denyTitle: String
    let confirms: Int
    let denies: Int
    let myVote: VoteValue?
    let canVote: Bool
    let isBusy: Bool
    let onVote: (VoteValue) -> Void
    let onLogin: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(question)
                .font(.headline)
            if canVote {
                HStack(spacing: 10) {
                    VoteButton(title: confirmTitle, count: confirms, systemImage: "hand.thumbsup", isActive: myVote == .confirm, tint: Palette.status(.active)) {
                        onVote(.confirm)
                    }
                    VoteButton(title: denyTitle, count: denies, systemImage: "hand.thumbsdown", isActive: myVote == .deny, tint: Palette.brand) {
                        onVote(.deny)
                    }
                }
                .disabled(isBusy)
            } else {
                Button(action: onLogin) {
                    Label("Войдите, чтобы ответить", systemImage: "person.crop.circle")
                }
                .buttonStyle(SoftButtonStyle())
                Text("Сейчас: да — \(confirms), нет — \(denies)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct SheetHeader<Leading: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder var leading: Leading
    let onClose: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            leading
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(title.count > 32 ? .headline : .title3.weight(.bold))
                    .lineLimit(4)
                    .fixedSize(horizontal: false, vertical: true)
                if let subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 30, height: 30)
                    .background(Color(uiColor: .tertiarySystemFill), in: .circle)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Закрыть")
        }
    }
}

struct IconBadge: View {
    let systemImage: String
    let color: Color
    var size: CGFloat = 40

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(color, in: .circle)
    }
}

struct Card<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            content
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemBackground), in: .rect(cornerRadius: 16, style: .continuous))
    }
}

extension View {
    @ViewBuilder
    func floatingSurface<S: Shape>(_ shape: S) -> some View {
        if #available(iOS 26.0, *) {
            glassEffect(.regular, in: shape)
                .contentShape(shape)
        } else {
            background(.regularMaterial, in: shape)
                .contentShape(shape)
                .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
        }
    }

    func bottomActionBar<Bar: View>(@ViewBuilder _ bar: () -> Bar) -> some View {
        modifier(BottomActionBar(bar: bar()))
    }
}

private struct BottomActionBar<Bar: View>: ViewModifier {
    let bar: Bar

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.safeAreaBar(edge: .bottom) {
                bar
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
            }
        } else {
            content.safeAreaInset(edge: .bottom) {
                bar
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(.bar)
            }
        }
    }
}

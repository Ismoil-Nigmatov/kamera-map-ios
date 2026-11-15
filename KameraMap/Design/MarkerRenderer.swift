import UIKit

@MainActor
enum MarkerRenderer {
    private static var cache: [String: UIImage] = [:]

    static func camera(_ camera: CameraMarker, selected: Bool) -> UIImage {
        let headings: [Int] = camera.heading.map { camera.bidirectional ? [$0, ($0 + 180) % 360] : [$0] } ?? []
        let key = [
            "camera",
            camera.status.rawValue,
            camera.kind.rawValue,
            String(camera.speedLimit ?? -1),
            headings.map(String.init).joined(separator: "-"),
            selected ? "selected" : "",
        ].joined(separator: "|")

        return cached(key) {
            render(side: 60) { context, center in
                let color = Palette.statusUI(camera.status)
                let radius: CGFloat = selected ? 19 : 17

                if selected {
                    fill(context, center: center, radius: radius + 7, color: color.withAlphaComponent(0.25))
                }
                for heading in headings {
                    arrow(context, center: center, distance: radius + 4, heading: CGFloat(heading), color: color)
                }

                shadow(context)
                fill(context, center: center, radius: radius, color: .white)
                context.setShadow(offset: .zero, blur: 0, color: nil)

                if let limit = camera.speedLimit {
                    ring(context, center: center, radius: radius - 3, width: 5, color: color)
                    text("\(limit)", center: center, size: limit >= 100 ? 12 : 14, color: .black)
                } else {
                    fill(context, center: center, radius: radius - 2, color: color)
                    symbol(camera.kind.symbol, center: center, size: 15, color: .white)
                }
            }
        }
    }

    static func cluster(count: Int, status: CameraStatus) -> UIImage {
        let diameter: CGFloat = count < 10 ? 38 : count < 100 ? 44 : 50
        return cached("cluster|\(count)|\(status.rawValue)") {
            render(side: diameter + 8) { context, center in
                shadow(context)
                fill(context, center: center, radius: diameter / 2, color: .white)
                context.setShadow(offset: .zero, blur: 0, color: nil)
                fill(context, center: center, radius: diameter / 2 - 3, color: Palette.statusUI(status))
                text("\(count)", center: center, size: count < 100 ? 15 : 14, color: .white)
            }
        }
    }

    static func report(_ type: ReportType, selected: Bool) -> UIImage {
        cached("report|\(type.rawValue)|\(selected)") {
            render(side: 52) { context, center in
                let color = Palette.reportUI(type)
                if selected {
                    fill(context, center: center, radius: 24, color: color.withAlphaComponent(0.25))
                }
                shadow(context)
                fill(context, center: center, radius: 17, color: .white)
                context.setShadow(offset: .zero, blur: 0, color: nil)
                fill(context, center: center, radius: 15, color: color)
                symbol(type.symbol, center: center, size: 14, color: .white)
            }
        }
    }

    private static func cached(_ key: String, make: () -> UIImage) -> UIImage {
        if let image = cache[key] {
            return image
        }
        let image = make()
        cache[key] = image
        return image
    }

    private static func render(side: CGFloat, draw: (CGContext, CGPoint) -> Void) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: side, height: side))
        return renderer.image { context in
            draw(context.cgContext, CGPoint(x: side / 2, y: side / 2))
        }
    }

    private static func shadow(_ context: CGContext) {
        context.setShadow(offset: CGSize(width: 0, height: 1.5), blur: 4, color: UIColor.black.withAlphaComponent(0.3).cgColor)
    }

    private static func fill(_ context: CGContext, center: CGPoint, radius: CGFloat, color: UIColor) {
        context.setFillColor(color.cgColor)
        context.fillEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
    }

    private static func ring(_ context: CGContext, center: CGPoint, radius: CGFloat, width: CGFloat, color: UIColor) {
        context.setStrokeColor(color.cgColor)
        context.setLineWidth(width)
        context.strokeEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
    }

    private static func arrow(_ context: CGContext, center: CGPoint, distance: CGFloat, heading: CGFloat, color: UIColor) {
        context.saveGState()
        context.translateBy(x: center.x, y: center.y)
        context.rotate(by: heading * .pi / 180)
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 0, y: -distance - 9))
        path.addLine(to: CGPoint(x: 7, y: -distance + 1))
        path.addLine(to: CGPoint(x: -7, y: -distance + 1))
        path.closeSubpath()
        context.addPath(path)
        context.setFillColor(color.cgColor)
        context.fillPath()
        context.restoreGState()
    }

    private static func text(_ value: String, center: CGPoint, size: CGFloat, color: UIColor) {
        let font = UIFont.systemFont(ofSize: size, weight: .heavy)
        let string = NSAttributedString(string: value, attributes: [.font: font, .foregroundColor: color])
        let bounds = string.size()
        string.draw(at: CGPoint(x: center.x - bounds.width / 2, y: center.y - bounds.height / 2))
    }

    private static func symbol(_ name: String, center: CGPoint, size: CGFloat, color: UIColor) {
        let configuration = UIImage.SymbolConfiguration(pointSize: size, weight: .semibold)
        guard let image = UIImage(systemName: name, withConfiguration: configuration)?
            .withTintColor(color, renderingMode: .alwaysOriginal)
        else {
            return
        }
        let imageSize = image.size
        image.draw(in: CGRect(
            x: center.x - imageSize.width / 2,
            y: center.y - imageSize.height / 2,
            width: imageSize.width,
            height: imageSize.height
        ))
    }
}

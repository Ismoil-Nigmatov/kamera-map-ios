import SwiftUI
import UIKit

enum Palette {
    static let brand = Color(uiColor: brandUI)
    static let brandUI = UIColor(red: 220 / 255, green: 38 / 255, blue: 38 / 255, alpha: 1)

    static func status(_ status: CameraStatus) -> Color {
        Color(uiColor: statusUI(status))
    }

    static func statusUI(_ status: CameraStatus) -> UIColor {
        switch status {
        case .active:
            UIColor(red: 22 / 255, green: 163 / 255, blue: 74 / 255, alpha: 1)
        case .unverified:
            UIColor(red: 245 / 255, green: 158 / 255, blue: 11 / 255, alpha: 1)
        case .inactive:
            UIColor(red: 163 / 255, green: 163 / 255, blue: 163 / 255, alpha: 1)
        }
    }

    static func report(_ type: ReportType) -> Color {
        Color(uiColor: reportUI(type))
    }

    static func reportUI(_ type: ReportType) -> UIColor {
        switch type {
        case .tripod:
            UIColor(red: 124 / 255, green: 58 / 255, blue: 237 / 255, alpha: 1)
        case .police:
            UIColor(red: 37 / 255, green: 99 / 255, blue: 235 / 255, alpha: 1)
        case .accident:
            UIColor(red: 249 / 255, green: 115 / 255, blue: 22 / 255, alpha: 1)
        case .other:
            UIColor(red: 100 / 255, green: 116 / 255, blue: 139 / 255, alpha: 1)
        }
    }
}

extension ReportType {
    var symbol: String {
        switch self {
        case .tripod: "dot.radiowaves.left.and.right"
        case .police: "light.beacon.max.fill"
        case .accident: "car.side.rear.and.collision.and.car.side.front"
        case .other: "exclamationmark.triangle.fill"
        }
    }
}

extension CameraKind {
    var symbol: String {
        switch self {
        case .camera: "camera.fill"
        case .radar: "gauge.with.dots.needle.67percent"
        }
    }
}

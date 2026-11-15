import UIKit
import XCTest
@testable import KameraMap

final class FormatTests: XCTestCase {
    func testPhoneDigitsAndGrouping() {
        XCTAssertEqual(Format.nationalDigits("+998 (90) 123-45-67"), "901234567")
        XCTAssertEqual(Format.nationalDigits("90 123 45 67 89"), "901234567")
        XCTAssertEqual(Format.nationalPhone("901234567"), "90 123 45 67")
        XCTAssertEqual(Format.nationalPhone("9012"), "90 12")
        XCTAssertEqual(Format.nationalPhone(""), "")
    }

    func testLifetime() {
        XCTAssertEqual(Format.lifetime(minutes: 30), "30 мин")
        XCTAssertEqual(Format.lifetime(minutes: 90), "1 ч 30 мин")
        XCTAssertEqual(Format.lifetime(minutes: 180), "3 ч")
    }

    func testCompass() {
        XCTAssertEqual(Format.compass(0), "север")
        XCTAssertEqual(Format.compass(90), "восток")
        XCTAssertEqual(Format.compass(350), "север")
        XCTAssertEqual(Format.compass(225), "юго-запад")
    }

    func testBoundingBoxQueryAndContains() {
        let box = BoundingBox(minLng: 69.2, minLat: 41.25, maxLng: 69.35, maxLat: 41.35)
        XCTAssertEqual(box.query, "69.20000,41.25000,69.35000,41.35000")
        XCTAssertTrue(box.contains(Coordinate(lat: 41.3, lng: 69.28)))
        XCTAssertFalse(box.contains(Coordinate(lat: 40.1, lng: 67.8)))
    }

    @MainActor
    func testMarkersRenderAndCache() {
        let marker = CameraMarker(id: 1, lat: 41.3, lng: 69.2, heading: 90, bidirectional: true, kind: .camera, status: .active, violations: ["speed"], speedLimit: 60)
        let first = MarkerRenderer.camera(marker, selected: false)
        let again = MarkerRenderer.camera(marker, selected: false)
        let selected = MarkerRenderer.camera(marker, selected: true)

        XCTAssertEqual(first.size, CGSize(width: 60, height: 60))
        XCTAssertTrue(first === again)
        XCTAssertFalse(first === selected)
        XCTAssertEqual(MarkerRenderer.cluster(count: 120, status: .unverified).size.width, 58)
    }
}

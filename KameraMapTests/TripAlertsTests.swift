import XCTest
@testable import KameraMap

final class TripAlertsTests: XCTestCase {
    private let driver = Coordinate(lat: 41.3300, lng: 69.2200)

    private func hazard(_ key: String, north meters: Double, east eastMeters: Double = 0, heading: Int? = nil, bidirectional: Bool = false, limit: Int? = nil) -> Hazard {
        Hazard(
            key: key,
            kind: .camera,
            coordinate: Coordinate(
                lat: driver.lat + meters / 111_320,
                lng: driver.lng + eastMeters / (111_320 * cos(driver.lat * .pi / 180))
            ),
            heading: heading,
            bidirectional: bidirectional,
            speedLimit: limit
        )
    }

    func testPicksTheNearestCameraAhead() throws {
        let hazards = [hazard("far", north: 700), hazard("near", north: 400), hazard("behind", north: -100)]

        let nearest = try XCTUnwrap(HazardFinder().nearest(from: driver, course: 0, in: hazards))

        XCTAssertEqual(nearest.hazard.key, "near")
        XCTAssertEqual(nearest.distance, 400, accuracy: 2)
    }

    func testIgnoresCamerasBehindToTheSideAndTooFar() {
        let hazards = [hazard("behind", north: -300), hazard("side", north: 100, east: 400), hazard("far", north: 1_500)]

        XCTAssertNil(HazardFinder().nearest(from: driver, course: 0, in: hazards))
    }

    func testRespectsTheDirectionTheCameraWatches() {
        let oneWaySouth = hazard("south", north: 300, heading: 180)
        let bothWays = hazard("both", north: 500, heading: 180, bidirectional: true)

        let nearest = HazardFinder().nearest(from: driver, course: 0, in: [oneWaySouth, bothWays])

        XCTAssertEqual(nearest?.hazard.key, "both")
    }

    func testKeepsACameraThatIsBeingPassed() {
        let alongside = hazard("alongside", north: 10, east: 30)

        XCTAssertEqual(HazardFinder().nearest(from: driver, course: 0, in: [alongside])?.hazard.key, "alongside")
    }

    func testPhrasesAndDistances() {
        let camera = hazard("cam", north: 0, limit: 60)
        let alert = TripAlert(hazard: camera, distance: 463, isOverSpeed: false)

        XCTAssertEqual(alert.phrase, "Камера через 500 метров, ограничение 60")
        XCTAssertEqual(alert.distanceText, "460 м")
        XCTAssertEqual(TripAlert(hazard: camera, distance: 1_240, isOverSpeed: false).distanceText, "1,2 км")

        let police = Hazard(key: "p", kind: .report(.police), coordinate: driver, heading: nil, bidirectional: true, speedLimit: nil)
        XCTAssertEqual(TripAlert(hazard: police, distance: 40, isOverSpeed: false).phrase, "Пост ДПС через 100 метров")
    }

    func testGeometryHelpers() {
        let north = Coordinate(lat: driver.lat + 0.01, lng: driver.lng)
        XCTAssertEqual(Geo.bearing(driver, north), 0, accuracy: 0.5)
        XCTAssertEqual(Geo.meters(driver, north), 1_112, accuracy: 2)
        XCTAssertEqual(Geo.angle(350, 10), 20, accuracy: 0.001)
        XCTAssertEqual(Geo.angle(90, 270), 180, accuracy: 0.001)
    }
}

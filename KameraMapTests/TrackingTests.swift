import XCTest
@testable import KameraMap

final class TrackingTests: XCTestCase {
    func testUserDecodesLocationSharing() throws {
        let decoder = APIClient.makeDecoder()
        let sharing = try decoder.decode(User.self, from: Data("""
        {"id":7,"name":"Тест","phone":"+998 90 000-00-02","is_admin":false,
         "location_sharing":true,"location_sharing_since":"2026-11-16T08:00:00+00:00"}
        """.utf8))
        XCTAssertTrue(sharing.isSharingLocation)
        XCTAssertEqual(sharing.locationSharingSince, Date(timeIntervalSince1970: 1_794_816_000))

        let older = try decoder.decode(User.self, from: Data("""
        {"id":7,"name":"Тест","phone":null,"is_admin":false}
        """.utf8))
        XCTAssertFalse(older.isSharingLocation)
        XCTAssertNil(older.locationSharingSince)
    }

    func testTripPointEncodesSnakeCaseAndIsoDates() throws {
        let point = TripPoint(lat: 41.3, lng: 69.2, accuracy: 5, speed: nil, heading: 90, recordedAt: Date(timeIntervalSince1970: 1_794_816_000))
        let data = try APIClient.makeEncoder().encode(point)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(json["recorded_at"] as? String, "2026-11-16T08:00:00Z")
        XCTAssertEqual(json["lat"] as? Double, 41.3)
        XCTAssertEqual(json["heading"] as? Double, 90)
        XCTAssertNil(json["speed"])
    }

    func testPaddedBoxCoversTheViewAndStaysUnderTheServerLimit() {
        let box = BoundingBox(minLng: 69.0, minLat: 41.0, maxLng: 70.2, maxLat: 41.5)
        let padded = box.padded(by: 0.5)

        XCTAssertTrue(padded.contains(box))
        XCTAssertFalse(box.contains(padded))
        XCTAssertEqual(padded.maxLng - padded.minLng, 1.9, accuracy: 1e-9)
        XCTAssertEqual(padded.maxLat - padded.minLat, 1.0, accuracy: 1e-9)
    }
}

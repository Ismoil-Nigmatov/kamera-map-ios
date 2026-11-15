import XCTest
@testable import KameraMap

final class DecodingTests: XCTestCase {
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try APIClient.makeDecoder().decode(T.self, from: Data(json.utf8))
    }

    func testCameraDetailsDecodeRulesAndSuggestions() throws {
        let camera = try decode(CameraDetails.self, """
        {"id":13,"lat":41.33,"lng":69.21,"heading":90,"bidirectional":false,"lane_count":3,"kind":"camera",
         "address":"Тестовая улица","description":null,"status":"active","source":"official",
         "verified_at":"2026-11-14T19:26:54+00:00",
         "rules":[
           {"id":1,"violation":"speed","lanes":[1,2],"speed_limit":60,"active_from":"06:00","active_to":null,"note":null},
           {"id":2,"violation":"red_light","lanes":null,"speed_limit":null,"active_from":null,"active_to":null,"note":null},
           {"id":3,"violation":"speed","lanes":[3],"speed_limit":50,"active_from":null,"active_to":null,"note":null}
         ],
         "votes":{"confirm":2,"deny":1},
         "suggestions":[{"id":5,"action":"remove","violation":"lane","comment":"На правой не снимает","agree":3,"disagree":1,"is_mine":true,"my_vote":"confirm","created_at":"2026-11-14T15:11:00+00:00"}]}
        """)

        XCTAssertEqual(camera.laneCount, 3)
        XCTAssertEqual(camera.status, .active)
        XCTAssertEqual(camera.detailedRules.map(\.violation), ["speed", "speed"])
        XCTAssertEqual(camera.generalRules.map(\.violation), ["red_light"])
        XCTAssertEqual(camera.fixedViolations, ["speed", "red_light"])
        XCTAssertEqual(camera.rules.first?.schedule, "Действует с 06:00")
        XCTAssertEqual(camera.suggestions.first?.action, .remove)
        XCTAssertEqual(camera.suggestions.first?.myVote, .confirm)
        XCTAssertNil(camera.myVote)
        XCTAssertNotNil(camera.verifiedAt)
    }

    func testCameraDetailsToleratesMissingCollections() throws {
        let camera = try decode(CameraDetails.self, """
        {"id":1,"lat":41.3,"lng":69.2,"kind":"radar","status":"inactive"}
        """)

        XCTAssertEqual(camera.kind, .radar)
        XCTAssertTrue(camera.rules.isEmpty)
        XCTAssertTrue(camera.suggestions.isEmpty)
        XCTAssertEqual(camera.votes.confirm, 0)
    }

    func testUnknownValuesFallBackSafely() throws {
        let marker = try decode(CameraMarker.self, """
        {"id":1,"lat":41.3,"lng":69.2,"heading":null,"bidirectional":false,"kind":"drone","status":"broken","violations":["speed"],"speed_limit":null}
        """)

        XCTAssertEqual(marker.status, .unverified)
        XCTAssertEqual(marker.kind, .camera)
    }

    func testReportDecodesDatesAndOptionalVote() throws {
        let report = try decode(Report.self, """
        {"id":7,"type":"police","lat":41.3,"lng":69.2,"heading":null,"comment":null,"confirmations":0,"rejections":0,
         "expires_at":"2026-11-15T12:00:00+00:00","created_at":"2026-11-15T10:30:00+00:00","is_active":true,"is_mine":false}
        """)

        let created = try XCTUnwrap(report.createdAt)
        XCTAssertEqual(report.type, .police)
        XCTAssertNil(report.myVote)
        XCTAssertEqual(report.expiresAt.timeIntervalSince(created), 5400)
    }

    func testMetaAndLoginDecode() throws {
        let meta = try decode(Meta.self, """
        {"violations":[{"value":"speed","label":"Скорость"}],"statuses":[],"kinds":[],"sources":[],
         "report_types":[{"value":"tripod","label":"Тренога","lifetime_minutes":180}],"region":{"min_lng":55.9}}
        """)
        XCTAssertEqual(meta.reportTypes.first?.lifetimeMinutes, 180)
        XCTAssertEqual(meta.reportTypes.first?.type, .tripod)

        let login = try decode(LoginCode.self, """
        {"phone":"+998 90 123-45-67","is_new_user":true,"resend_in":60,"code":"123456"}
        """)
        XCTAssertTrue(login.isNewUser)
        XCTAssertEqual(login.code, "123456")
    }

    func testFallbackMetaMatchesServerDictionaries() {
        XCTAssertEqual(Meta.fallback.violations.count, 12)
        XCTAssertEqual(Meta.fallback.violations.first?.value, "speed")
        XCTAssertEqual(Meta.fallback.reportTypes.map(\.lifetimeMinutes), [180, 90, 60, 30])
    }
}

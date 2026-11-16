import Foundation

private struct VoteBody: Encodable {
    let value: VoteValue
}

private struct StatusBody: Encodable {
    let status: CameraStatus
}

private struct PhoneBody: Encodable {
    let phone: String
}

private struct TokenBody: Encodable {
    let phone: String
    let code: String
    let name: String?
    let deviceName: String
}

private struct NameBody: Encodable {
    let name: String
}

private struct SharingBody: Encodable {
    let enabled: Bool
}

private struct PositionsBody: Encodable {
    let trip: String
    let points: [TripPoint]
}

private struct StoredPositions: Decodable {
    let stored: Int
}

private struct ReportBody: Encodable {
    let type: ReportType
    let lat: Double
    let lng: Double
    let comment: String?
}

extension APIClient {
    func meta() async throws -> Meta {
        try await send("GET", "meta", as: Meta.self).value
    }

    func cameras(in box: BoundingBox) async throws -> [CameraMarker] {
        try await send("GET", "cameras", query: [URLQueryItem(name: "bbox", value: box.query)], as: [CameraMarker].self).value
    }

    func reports(in box: BoundingBox) async throws -> [Report] {
        try await send("GET", "reports", query: [URLQueryItem(name: "bbox", value: box.query)], as: [Report].self).value
    }

    func camera(_ id: Int) async throws -> CameraDetails {
        try await send("GET", "cameras/\(id)", as: CameraDetails.self).value
    }

    func voteCamera(_ id: Int, _ value: VoteValue) async throws -> CameraDetails {
        try await send("POST", "cameras/\(id)/votes", body: VoteBody(value: value), as: CameraDetails.self).value
    }

    func setStatus(_ id: Int, _ status: CameraStatus) async throws -> CameraDetails {
        try await send("PATCH", "cameras/\(id)", body: StatusBody(status: status), as: CameraDetails.self).value
    }

    func suggestFix(_ id: Int, _ draft: SuggestionDraft) async throws -> (camera: CameraDetails, merged: Bool) {
        let result = try await send("POST", "cameras/\(id)/suggestions", body: draft, as: CameraDetails.self)
        return (result.value, result.status == 200)
    }

    func voteSuggestion(_ id: Int, _ value: VoteValue) async throws -> CameraDetails {
        try await send("POST", "suggestions/\(id)/votes", body: VoteBody(value: value), as: CameraDetails.self).value
    }

    func createReport(_ draft: ReportDraft, at point: Coordinate) async throws -> (report: Report, merged: Bool) {
        let comment = draft.comment.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = ReportBody(type: draft.type, lat: point.lat, lng: point.lng, comment: comment.isEmpty ? nil : comment)
        let result = try await send("POST", "reports", body: body, as: Report.self)
        return (result.value, result.status == 200)
    }

    func voteReport(_ id: Int, _ value: VoteValue) async throws -> Report {
        try await send("POST", "reports/\(id)/votes", body: VoteBody(value: value), as: Report.self).value
    }

    func requestCode(phone: String) async throws -> LoginCode {
        try await send("POST", "auth/code", body: PhoneBody(phone: phone), as: LoginCode.self).value
    }

    func issueToken(phone: String, code: String, name: String?, deviceName: String) async throws -> IssuedToken {
        let body = TokenBody(phone: phone, code: code, name: name, deviceName: deviceName)
        return try await send("POST", "auth/token", body: body, as: IssuedToken.self).value
    }

    func logout() async throws {
        _ = try await send("DELETE", "auth/token", as: EmptyResponse.self)
    }

    func me() async throws -> User {
        try await send("GET", "me", as: User.self).value
    }

    func rename(_ name: String) async throws -> User {
        try await send("PATCH", "me", body: NameBody(name: name), as: User.self).value
    }

    func deleteAccount() async throws {
        _ = try await send("DELETE", "me", as: EmptyResponse.self)
    }

    func setLocationSharing(_ enabled: Bool) async throws -> User {
        try await send("PUT", "me/location-sharing", body: SharingBody(enabled: enabled), as: User.self).value
    }

    func uploadPositions(trip: UUID, points: [TripPoint]) async throws -> Int {
        let body = PositionsBody(trip: trip.uuidString.lowercased(), points: points)
        return try await send("POST", "me/positions", body: body, as: StoredPositions.self).value.stored
    }
}

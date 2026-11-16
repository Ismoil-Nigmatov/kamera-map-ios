import Foundation

struct Coordinate: Hashable, Sendable {
    var lat: Double
    var lng: Double
}

struct BoundingBox: Hashable, Sendable {
    var minLng: Double
    var minLat: Double
    var maxLng: Double
    var maxLat: Double

    var query: String {
        [minLng, minLat, maxLng, maxLat]
            .map { String(format: "%.5f", $0) }
            .joined(separator: ",")
    }

    func contains(_ point: Coordinate) -> Bool {
        point.lat >= minLat && point.lat <= maxLat && point.lng >= minLng && point.lng <= maxLng
    }

    func contains(_ box: BoundingBox) -> Bool {
        box.minLat >= minLat && box.maxLat <= maxLat && box.minLng >= minLng && box.maxLng <= maxLng
    }

    func padded(by fraction: Double, maxSpan: Double = 1.9) -> BoundingBox {
        let lngSpan = maxLng - minLng
        let latSpan = maxLat - minLat
        let lngPad = min(lngSpan * fraction, max(0, (maxSpan - lngSpan) / 2))
        let latPad = min(latSpan * fraction, max(0, (maxSpan - latSpan) / 2))
        return BoundingBox(minLng: minLng - lngPad, minLat: minLat - latPad, maxLng: maxLng + lngPad, maxLat: maxLat + latPad)
    }
}

enum CameraStatus: String, CaseIterable, Hashable, Sendable, Codable {
    case active
    case unverified
    case inactive

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = CameraStatus(rawValue: raw) ?? .unverified
    }
}

enum CameraKind: String, Hashable, Sendable, Codable {
    case camera
    case radar

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = CameraKind(rawValue: raw) ?? .camera
    }
}

enum ReportType: String, CaseIterable, Hashable, Sendable, Codable {
    case tripod
    case police
    case accident
    case other

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = ReportType(rawValue: raw) ?? .other
    }
}

enum VoteValue: String, Hashable, Sendable, Codable {
    case confirm
    case deny
}

enum SuggestionAction: String, CaseIterable, Hashable, Sendable, Codable {
    case remove
    case add
}

struct CameraMarker: Decodable, Identifiable, Hashable, Sendable {
    let id: Int
    let lat: Double
    let lng: Double
    let heading: Int?
    let bidirectional: Bool
    let kind: CameraKind
    let status: CameraStatus
    let violations: [String]
    let speedLimit: Int?

    var coordinate: Coordinate {
        Coordinate(lat: lat, lng: lng)
    }

    func with(status newStatus: CameraStatus) -> CameraMarker {
        CameraMarker(
            id: id,
            lat: lat,
            lng: lng,
            heading: heading,
            bidirectional: bidirectional,
            kind: kind,
            status: newStatus,
            violations: violations,
            speedLimit: speedLimit
        )
    }
}

struct CameraRule: Decodable, Identifiable, Hashable, Sendable {
    let id: Int
    let violation: String
    let lanes: [Int]?
    let speedLimit: Int?
    let activeFrom: String?
    let activeTo: String?
    let note: String?

    var isDetailed: Bool {
        lanes != nil || speedLimit != nil || activeFrom != nil || activeTo != nil || note != nil
    }

    var schedule: String? {
        guard activeFrom != nil || activeTo != nil else { return nil }
        var parts = ["Действует"]
        if let activeFrom { parts.append("с \(activeFrom)") }
        if let activeTo { parts.append("до \(activeTo)") }
        return parts.joined(separator: " ")
    }
}

struct VoteCounts: Decodable, Hashable, Sendable {
    let confirm: Int
    let deny: Int
}

struct CameraSuggestion: Decodable, Identifiable, Hashable, Sendable {
    let id: Int
    let action: SuggestionAction
    let violation: String
    let comment: String?
    let agree: Int
    let disagree: Int
    let isMine: Bool
    let myVote: VoteValue?
}

struct CameraDetails: Decodable, Identifiable, Hashable, Sendable {
    let id: Int
    let lat: Double
    let lng: Double
    let heading: Int?
    let bidirectional: Bool
    let laneCount: Int?
    let kind: CameraKind
    let address: String?
    let description: String?
    let status: CameraStatus
    let source: String
    let verifiedAt: Date?
    let rules: [CameraRule]
    let votes: VoteCounts
    let suggestions: [CameraSuggestion]
    let myVote: VoteValue?

    private enum CodingKeys: String, CodingKey {
        case id, lat, lng, heading, bidirectional, laneCount, kind, address, description, status, source
        case verifiedAt, rules, votes, suggestions, myVote
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        lat = try container.decode(Double.self, forKey: .lat)
        lng = try container.decode(Double.self, forKey: .lng)
        heading = try container.decodeIfPresent(Int.self, forKey: .heading)
        bidirectional = try container.decodeIfPresent(Bool.self, forKey: .bidirectional) ?? false
        laneCount = try container.decodeIfPresent(Int.self, forKey: .laneCount)
        kind = try container.decode(CameraKind.self, forKey: .kind)
        address = try container.decodeIfPresent(String.self, forKey: .address)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        status = try container.decode(CameraStatus.self, forKey: .status)
        source = try container.decodeIfPresent(String.self, forKey: .source) ?? "official"
        verifiedAt = try container.decodeIfPresent(Date.self, forKey: .verifiedAt)
        rules = try container.decodeIfPresent([CameraRule].self, forKey: .rules) ?? []
        votes = try container.decodeIfPresent(VoteCounts.self, forKey: .votes) ?? VoteCounts(confirm: 0, deny: 0)
        suggestions = try container.decodeIfPresent([CameraSuggestion].self, forKey: .suggestions) ?? []
        myVote = try container.decodeIfPresent(VoteValue.self, forKey: .myVote)
    }

    var coordinate: Coordinate {
        Coordinate(lat: lat, lng: lng)
    }

    var detailedRules: [CameraRule] {
        rules.filter(\.isDetailed)
    }

    var generalRules: [CameraRule] {
        rules.filter { !$0.isDetailed }
    }

    var fixedViolations: [String] {
        var seen = Set<String>()
        return rules.map(\.violation).filter { seen.insert($0).inserted }
    }
}

struct Report: Decodable, Identifiable, Hashable, Sendable {
    let id: Int
    let type: ReportType
    let lat: Double
    let lng: Double
    let heading: Int?
    let comment: String?
    let confirmations: Int
    let rejections: Int
    let expiresAt: Date
    let createdAt: Date?
    let isActive: Bool
    let isMine: Bool
    let myVote: VoteValue?

    var coordinate: Coordinate {
        Coordinate(lat: lat, lng: lng)
    }
}

struct User: Decodable, Hashable, Sendable {
    let id: Int
    let name: String
    let phone: String?
    let isAdmin: Bool
    let locationSharing: Bool?
    let locationSharingSince: Date?

    var isSharingLocation: Bool {
        locationSharing ?? false
    }

    var initials: String {
        let letters = name.split(separator: " ").prefix(2).compactMap(\.first)
        return letters.isEmpty ? "?" : String(letters).uppercased()
    }
}

struct LoginCode: Decodable, Hashable, Sendable {
    let phone: String
    let isNewUser: Bool
    let resendIn: Int
    let code: String?
}

struct IssuedToken: Decodable, Sendable {
    let token: String
    let user: User
}

struct ReportDraft: Hashable, Sendable {
    var type: ReportType
    var comment: String
}

struct SuggestionDraft: Encodable, Hashable, Sendable {
    var action: SuggestionAction
    var violation: String
    var comment: String?
}

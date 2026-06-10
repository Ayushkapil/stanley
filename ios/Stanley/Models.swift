import Foundation

// Codable mirrors of the server payloads (server/stanley/serialize.py).
// Snake-case keys are converted by the decoder in APIClient.

struct UserBrief: Codable, Hashable {
    let id: String?
    let displayName: String
}

struct PhotoURLs: Codable, Hashable {
    let image: String
    let thumb: String
}

struct Comment: Codable, Identifiable, Hashable {
    let id: String
    let author: UserBrief
    let body: String
    let createdAt: Date
}

struct Photo: Codable, Identifiable, Hashable {
    let id: String
    let owner: UserBrief
    let takenAt: Date
    let caption: String?
    let state: String
    let decayProgress: Double
    let stateDeadline: Date?
    let urls: PhotoURLs?
    let comments: [Comment]
    let anchoredByMe: Bool
    let myAnchorNote: String?
}

struct FeedResponse: Codable {
    let photos: [Photo]
}

/// A memory thread item: either a full artifact or an honest tombstone
/// ("a memory was here"). The server sends different shapes; everything that
/// can be absent is optional here.
struct Memory: Codable, Identifiable, Hashable {
    let tombstone: Bool
    // tombstone shape
    let photoId: String?
    let date: String?
    // full-artifact shape (photo payload fields)
    let photoPayloadId: String?
    let takenAt: Date?
    let caption: String?
    let urls: PhotoURLs?
    let comments: [Comment]?
    // both
    let note: String?
    let anchoredAt: Date?

    var id: String { photoId ?? photoPayloadId ?? UUID().uuidString }

    enum CodingKeys: String, CodingKey {
        case tombstone, photoId, date, takenAt, caption, urls, comments, note, anchoredAt
        case photoPayloadId = "id"
    }
}

struct MemoryThread: Codable, Identifiable, Hashable {
    let friend: UserBrief
    let memories: [Memory]
    var id: String { friend.id ?? friend.displayName }
}

struct MemoriesResponse: Codable {
    let threads: [MemoryThread]
}

struct ReturnedItem: Codable, Hashable {
    let source: String
    let photo: Memory
}

struct ReturnedResponse: Codable {
    let item: ReturnedItem?
}

struct CircleMember: Codable, Identifiable, Hashable {
    let id: String
    let displayName: String?
    let joinedAt: Date
}

struct CircleInfo: Codable {
    let id: String
    let name: String
    let inviteToken: String?
    let members: [CircleMember]?
}

struct AuthResponse: Codable {
    struct AuthedUser: Codable {
        let id: String
        let displayName: String
    }

    let token: String
    let user: AuthedUser
}

struct MeSettings: Codable {
    let lastLightNoticeEnabled: Bool
}

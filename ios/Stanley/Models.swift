import Foundation

// Codable mirrors of the server payloads (server/stanley/serialize.py).
// Snake-case keys are converted by the decoder in APIClient.

struct UserBrief: Codable, Hashable {
    let id: String?
    let displayName: String
    let avatarUrl: String?

    // A person reduced to a face and a name — never a number.
    // Not Identifiable (its id is optional); iterate with ForEach(_, id: \.id).
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
    let location: String?
    let state: String
    let decayProgress: Double
    let stateDeadline: Date?
    let urls: PhotoURLs?
    let comments: [Comment]
    let anchoredByMe: Bool
    let myAnchorNote: String?
    // The caller's own like state only — never a count, never who else (Part 1).
    let likedByMe: Bool
}

/// One short shared line for the circle (Part 4). A sticky note the day erases
/// — not a chat: there are no replies or reactions to decode.
struct CommunityNote: Codable, Hashable {
    let text: String
    let author: UserBrief
    let setAt: Date?
}

/// A Today entry: either a standalone photo or a shared moment (Part 3).
struct FeedItem: Codable, Identifiable {
    let kind: String
    let photo: Photo?
    // moment fields
    let location: String?
    let members: [UserBrief]?
    let photos: [Photo]?

    var isMoment: Bool { kind == "moment" }
    var id: String {
        if isMoment { return "moment:\(location ?? "")|\(photos?.first?.id ?? "")" }
        return photo?.id ?? UUID().uuidString
    }
}

struct TodayResponse: Codable {
    let note: CommunityNote?
    let items: [FeedItem]
}

/// A memory thread item: either a full artifact or an honest tombstone
/// ("a memory was here"). The server sends different shapes; everything that
/// can be absent is optional here.
struct Memory: Codable, Identifiable, Hashable {
    // Absent in the Returned "rescue" payload (a raw photo), so optional.
    let tombstone: Bool?
    var isTombstone: Bool { tombstone ?? false }
    // tombstone shape
    let photoId: String?
    let date: String?
    // full-artifact shape (photo payload fields)
    let photoPayloadId: String?
    let takenAt: Date?
    let caption: String?
    let location: String?
    let urls: PhotoURLs?
    let comments: [Comment]?
    // both
    let note: String?
    let anchoredAt: Date?

    var id: String { photoId ?? photoPayloadId ?? UUID().uuidString }

    enum CodingKeys: String, CodingKey {
        case tombstone, photoId, date, takenAt, caption, location, urls, comments, note, anchoredAt
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
    let avatarUrl: String?
    let joinedAt: Date
    let isCreator: Bool?
}

struct CircleInfo: Codable {
    let id: String
    let name: String
    let inviteToken: String?
    let isCreator: Bool?
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

/// Own profile (GET /me, PATCH /me/profile). Identity only — the API has no
/// counts to decode, and neither does this struct.
struct MyProfile: Codable {
    let id: String
    let displayName: String?
    let username: String?
    let bio: String?
    let avatarUrl: String?
    let createdAt: Date?
    let lastLightNoticeEnabled: Bool?
}

/// Another circle member's profile: their face, name and words, nothing else.
struct MemberProfile: Codable {
    let id: String
    let displayName: String?
    let username: String?
    let bio: String?
    let avatarUrl: String?
}

struct AvatarResponse: Codable {
    let avatarUrl: String?
}

struct InviteResponse: Codable {
    let inviteToken: String
}

/// Owner-only faces of who liked a photo — never a count (Part 1).
struct LikesResponse: Codable {
    let faces: [UserBrief]
}

/// Owner-only entry of who held a photo. Faces, not numbers (A2).
struct HeldByEntry: Codable, Identifiable, Hashable {
    let user: UserBrief
    let createdAt: Date
    let note: String?
    var id: String { user.id ?? UUID().uuidString }
}

struct HeldByResponse: Codable {
    let anchors: [HeldByEntry]
}

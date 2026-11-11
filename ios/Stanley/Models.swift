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
    /// The capture filter's name, or nil. Display only: the look is baked
    /// into the image, and it can't be changed after posting.
    let filter: String?
    let state: String
    let decayProgress: Double
    let stateDeadline: Date?
    let urls: PhotoURLs?
    let comments: [Comment]
    let anchoredByMe: Bool
    let myAnchorNote: String?
    // The caller's own like state only — never a count, never who else (Part 1).
    let likedByMe: Bool
    // 'Who was there' — a memory detail, faces not mentions (Part 3).
    let tagged: [UserBrief]
    /// Yours only (build 18): whether deleting this photo gives you the day
    /// back — today's photo, with the day's one redo unspent. Nil on anyone
    /// else's photo, and from a server older than build 18.
    let retakeOnDelete: Bool?
    /// Yours only (build 26): whether you've written a journal entry on it,
    /// for the small book on your print. Never the words, which are fetched
    /// only when you open it. Nil on anyone else's photo, and from an older
    /// server.
    let hasJournal: Bool?
}

/// A sticky note on the circle's board (Part 4; one each since build 27). The
/// day erases it — not a chat: there are no replies or reactions to decode,
/// and nothing counts the notes.
struct CommunityNote: Codable, Hashable {
    /// Nil from a server before the board, whose one note had none.
    let id: String?
    let text: String
    let author: UserBrief
    let setAt: Date?
    let updatedAt: Date?

    /// Its place on the board: its id, or for an older server's one note,
    /// whose it is.
    var boardId: String { id ?? author.id ?? text }
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
    /// When it was taken: a moment's newest photo, as the server orders it.
    var takenAt: Date? { photo?.takenAt ?? photos?.first?.takenAt }
    var id: String {
        if isMoment { return "moment:\(location ?? "")|\(photos?.first?.id ?? "")" }
        return photo?.id ?? UUID().uuidString
    }
}

/// The weekly mosaic (Part 2): ephemeral, view-only, no interactions.
struct MosaicTile: Codable, Hashable {
    let thumb: String
    let image: String?
    let caption: String?
    let owner: UserBrief
}

struct Mosaic: Codable, Hashable {
    let weekStart: String
    let weekEnd: String
    let tiles: [MosaicTile]
}

struct TodayResponse: Codable {
    let mosaic: Mosaic?
    /// The board (build 27): everyone's note today, newest first. Nil from a
    /// server before the board, which sends only `note`.
    let notes: [CommunityNote]?
    let note: CommunityNote?
    let items: [FeedItem]
    /// Where the next page starts, or nil at the end (and from a server
    /// before paging, which sends everything at once).
    let nextCursor: String?
}

/// One headline in The World Today. Text only, and there is nothing to do to
/// it but read it: no like, no save, no share, no comment.
struct NewsArticle: Codable, Identifiable, Hashable {
    let title: String
    let source: String
    let summary: String?
    let publishedAt: Date?
    let url: String

    enum CodingKeys: String, CodingKey {
        case title, source, publishedAt, url
        case summary = "description"
    }

    var id: String { url }

    /// http(s) only. Those are the only links an in-app Safari sheet will
    /// open (it crashes on anything else), and the server sends no others.
    var link: URL? {
        guard let link = URL(string: url),
              let scheme = link.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else { return nil }
        return link
    }
}

/// A quiet, private milestone (Part 4) — a reflection, never a score.
struct Milestone: Codable, Identifiable, Hashable {
    let id: Int
    let kind: String
    let title: String
    let body: String?
    let faces: [UserBrief]?
    let photos: [String]?
}

struct MilestonesResponse: Codable {
    let milestones: [Milestone]
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
    let tagged: [UserBrief]?
    // both
    let note: String?
    let anchoredAt: Date?
    /// Which circle it's from. Held gathers every circle (build 17). Absent
    /// from a server before that, and from Returned's rescue payload.
    let circleName: String?
    /// The journal entry you wrote on your own held photo (build 26), there
    /// beneath it in the album. Only ever on your own photos, for you.
    let journal: String?

    var id: String { photoId ?? photoPayloadId ?? UUID().uuidString }

    enum CodingKeys: String, CodingKey {
        case tombstone, photoId, date, takenAt, caption, location, urls, comments, tagged, note, anchoredAt
        case circleName, journal
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

/// The Rested view's data: memories set never to resurface, still browsable.
struct RestedResponse: Codable {
    let memories: [Memory]
}

struct CircleMember: Codable, Identifiable, Hashable {
    let id: String
    let displayName: String?
    let avatarUrl: String?
    let joinedAt: Date
    let isCreator: Bool?
}

/// One of the circles a person is in, for the switcher atop Today. A name,
/// and nothing that ranks one circle above another.
struct CircleSummary: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let isCreator: Bool
}

struct CirclesResponse: Codable {
    let circles: [CircleSummary]
}

struct CircleInfo: Codable {
    let id: String
    let name: String
    let inviteToken: String?
    let isCreator: Bool?
    let members: [CircleMember]?
    /// Build 35: something this one circle is counting toward, nil for every
    /// other circle.
    let countdown: Countdown?
}

extension CircleInfo {
    /// A countdown that won't decode is dropped, never allowed to take the
    /// circle down with it: a circle that fails to load is a trouble page.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        inviteToken = try c.decodeIfPresent(String.self, forKey: .inviteToken)
        isCreator = try c.decodeIfPresent(Bool.self, forKey: .isCreator)
        members = try c.decodeIfPresent([CircleMember].self, forKey: .members)
        countdown = try? c.decodeIfPresent(Countdown.self, forKey: .countdown)
    }
}

struct AuthResponse: Codable {
    struct AuthedUser: Codable {
        let id: String
        // Nullable, unlike every other name on the wire. The auth routes build
        // this dict inline from User.display_name instead of going through
        // serialize.py's user_brief, which is the one place that substitutes
        // DEPARTED for a missing name — so a first Apple sign-in by someone who
        // declined to share their name arrives here as null. Decoding that into
        // a non-optional String threw valueNotFound, which the app surfaced as
        // "The data couldn't be read because it is missing."
        let displayName: String?
    }

    let token: String
    let user: AuthedUser
    /// True when this sign-in made the account, so setup comes next. Absent
    /// from a server before build 16, which reads as false.
    let newAccount: Bool?
}

struct MeSettings: Codable {
    let lastLightNoticeEnabled: Bool
    /// The evening note (build 18). Absent from an older server.
    let digestEnabled: Bool?
    /// "{name} shared a moment" (build 37). Absent from an older server.
    let circlePostsEnabled: Bool?
    /// The two reminders (build 39), and the hour of the day each is set
    /// for. Nil from a server before them, which then offers neither.
    let noteReminderEnabled: Bool?
    let noteReminderHour: Int?
    let photoReminderEnabled: Bool?
    let photoReminderHour: Int?
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
    /// How many moments you've shared, ever (build 19). Yours alone: only
    /// `/me` carries it, for one quiet line on your own You tab.
    let momentsShared: Int?
}

/// Another circle member's profile: their face, name and words, nothing else.
struct MemberProfile: Codable {
    let id: String
    let displayName: String?
    let username: String?
    let bio: String?
    let avatarUrl: String?
    /// Since build 19: when they joined the circle on screen (or the first
    /// one you share), whether they started it, and their own photos still
    /// in the light. Nil from an older server. Never a count of anything.
    let memberSince: Date?
    let isOrganizer: Bool?
    let photos: [Photo]?
}

struct AvatarResponse: Codable {
    let avatarUrl: String?
}

/// GET /me/username_check — the edit sheet's real-time availability answer.
struct UsernameCheck: Codable {
    let valid: Bool
    let available: Bool
}

struct InviteResponse: Codable {
    let inviteToken: String
}

/// Owner-only faces of who liked a photo — never a count (Part 1).
struct LikesResponse: Codable {
    let faces: [UserBrief]
}

/// The people you've blocked (build 18), so you can unblock them. Never
/// who has blocked you.
struct BlockedPeople: Codable {
    let people: [UserBrief]
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

// MARK: - Writing things down (build 26)

/// What you wrote about your own photo: "Anything else about today?" Yours
/// alone. The server answers only your own request for it, never a feed.
struct JournalEntry: Codable, Hashable {
    let photoId: String
    let body: String
    let updatedAt: Date?
}

/// One of your own photos from a week, for its reflection: still in Today
/// and fading as it does there, or held by you and at full light. The rest
/// of the week has faded, and a reflection doesn't bring it back.
struct WeekPhoto: Codable, Identifiable, Hashable {
    let id: String
    let takenAt: Date
    let thumb: String
    let image: String?
    let caption: String?
    let held: Bool
    let decayProgress: Double
}

/// How your week was, in your words. Read by no one else, and it doesn't fade.
struct Reflection: Codable, Identifiable, Hashable {
    let id: String
    /// The week's Monday and Sunday, as days ("2026-11-02").
    let weekStart: String
    let weekEnd: String
    let body: String
    let createdAt: Date
    let photos: [WeekPhoto]
}

struct ReflectionsPage: Codable {
    let reflections: [Reflection]
    let nextCursor: String?
}

/// The week a reflection written now would be about: its days, your photos
/// from it, and the reflection once it's written.
struct ThisWeek: Codable, Hashable {
    let weekStart: String
    let weekEnd: String
    let photos: [WeekPhoto]
    let reflection: Reflection?
}

/// The circle's question of the week. Answers open together at `revealsAt`
/// (Saturday, 00:00 UTC).
struct Question: Codable, Identifiable, Hashable {
    let id: String
    let text: String
    let weekStart: String
    let weekEnd: String
    let revealsAt: Date
}

/// Someone's answer to it: a face and a name, and their words. No count of
/// anything goes with it.
struct Answer: Codable, Identifiable, Hashable {
    let id: String
    let author: UserBrief
    let body: String
    let createdAt: Date
}

/// This week's question for the circle on screen, your own answer if you've
/// given it, and whether everyone's are open yet.
struct WeekQuestion: Codable, Hashable {
    let prompt: Question
    let response: Answer?
    let revealed: Bool
}

struct QuestionAnswers: Codable {
    let prompt: Question
    let responses: [Answer]
}

/// A week in the circle journal: its question and what everyone said.
struct PastQuestion: Codable, Identifiable, Hashable {
    let id: String
    let text: String
    let weekStart: String
    let weekEnd: String
    let revealsAt: Date
    let responses: [Answer]

    var question: Question {
        Question(id: id, text: text, weekStart: weekStart, weekEnd: weekEnd, revealsAt: revealsAt)
    }
}

struct CircleJournalPage: Codable {
    let prompts: [PastQuestion]
    let nextCursor: String?
}

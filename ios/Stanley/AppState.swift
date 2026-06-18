import Foundation
import Observation

@Observable
final class AppState {
    let api = APIClient()

    var signedIn: Bool
    var circle: CircleInfo?
    var feedItems: [FeedItem] = []
    var communityNote: CommunityNote?
    var returned: ReturnedItem?
    var threads: [MemoryThread] = []
    var profile: MyProfile?
    var myId: String?
    var errorMessage: String?
    var checkedCircle = false

    init() {
        signedIn = api.token != nil
    }

    func surface(_ error: Error) {
        errorMessage = error.localizedDescription
    }

    // MARK: auth & circle

    func devSignIn(name: String) async {
        do {
            let auth: AuthResponse = try await api.send(
                "POST", "/auth/dev", json: ["display_name": name]
            )
            api.token = auth.token
            myId = auth.user.id
            signedIn = true
            await loadCircle()
        } catch {
            surface(error)
        }
    }

    func signOut() {
        api.token = nil
        signedIn = false
        circle = nil
        checkedCircle = false
        feedItems = []
        communityNote = nil
        returned = nil
        threads = []
        profile = nil
        myId = nil
    }

    func loadCircle() async {
        defer { checkedCircle = true }
        do {
            circle = try await api.send("GET", "/circles/mine") as CircleInfo
        } catch APIError.server(code: "no_circle", status: _) {
            circle = nil
        } catch {
            surface(error)
        }
    }

    func createCircle(name: String) async {
        do {
            _ = try await api.send("POST", "/circles", json: ["name": name]) as CircleInfo
            await loadCircle()  // pull the full shape: invite token, roster, creator
        } catch {
            surface(error)
        }
    }

    /// Invite codes are `circleId.inviteToken` — one string to paste or QR.
    func joinCircle(code: String) async {
        let parts = code.split(separator: ".", maxSplits: 1).map(String.init)
        guard parts.count == 2 else {
            errorMessage = "That invite code doesn't look right."
            return
        }
        do {
            _ = try await api.send(
                "POST", "/circles/\(parts[0])/join", json: ["invite_token": parts[1]]
            ) as CircleInfo
            await loadCircle()  // pull the full shape: roster + creator flag
        } catch {
            surface(error)
        }
    }

    var inviteCode: String? {
        guard let circle, let token = circle.inviteToken else { return nil }
        return "\(circle.id).\(token)"
    }

    // MARK: surfaces

    func refreshToday() async {
        do {
            let response: TodayResponse = try await api.send("GET", "/feed/today")
            feedItems = response.items
            communityNote = response.note
            let returnedResponse: ReturnedResponse = try await api.send(
                "GET", "/feed/returned", query: ["tz": TimeZone.current.identifier]
            )
            returned = returnedResponse.item
        } catch {
            surface(error)
        }
    }

    func setNote(_ text: String) async {
        guard let circle else { return }
        do {
            let _: CommunityNote = try await api.send(
                "PUT", "/circles/\(circle.id)/note", json: ["text": text]
            )
            await refreshToday()
        } catch {
            surface(error)
        }
    }

    func refreshMemories() async {
        do {
            let response: MemoriesResponse = try await api.send("GET", "/me/anchored")
            threads = response.threads
        } catch {
            surface(error)
        }
    }

    // MARK: profile

    func loadProfile() async {
        do {
            profile = try await api.send("GET", "/me") as MyProfile
            myId = profile?.id
        } catch {
            surface(error)
        }
    }

    func uploadAvatar(jpeg: Data) async {
        do {
            _ = try await api.uploadAvatar(jpeg: jpeg)
            await loadProfile()
            await loadCircle()  // so the roster cluster shows the new face
        } catch {
            surface(error)
        }
    }

    func updateProfile(displayName: String, username: String, bio: String) async -> Bool {
        var body: [String: Any?] = ["display_name": displayName, "bio": bio]
        if !username.isEmpty {
            body["username"] = username
        }
        do {
            profile = try await api.send("PATCH", "/me/profile", json: body) as MyProfile
            return true
        } catch {
            surface(error)
            return false
        }
    }

    func loadMember(_ memberId: String) async throws -> MemberProfile {
        try await api.send("GET", "/members/\(memberId)")
    }

    // MARK: gestures

    func capture(jpeg: Data, caption: String?, location: String?) async throws {
        _ = try await api.uploadPhoto(jpeg: jpeg, caption: caption, location: location)
        await refreshToday()
    }

    func toggleAnchor(_ photo: Photo) async {
        do {
            if photo.anchoredByMe {
                let _: Empty = try await api.send("DELETE", "/photos/\(photo.id)/anchor")
            } else {
                let _: Empty = try await api.send(
                    "POST", "/photos/\(photo.id)/anchor", json: ["note": nil]
                )
            }
            await refreshToday()
        } catch {
            surface(error)
        }
    }

    /// Press-and-hold commit: hold a photo into Held. Idempotent — holding an
    /// already-held photo keeps it held (the icon-tap path does the un-hold).
    func hold(_ photo: Photo) async {
        if photo.anchoredByMe { return }
        do {
            let _: Empty = try await api.send(
                "POST", "/photos/\(photo.id)/anchor", json: ["note": nil]
            )
            await refreshToday()
        } catch {
            surface(error)
        }
    }

    /// The like — double-tap toggles (Part 1). Ephemeral, owner-private, no count.
    func toggleLike(_ photo: Photo) async {
        do {
            if photo.likedByMe {
                let _: Empty = try await api.send("DELETE", "/photos/\(photo.id)/like")
            } else {
                let _: Empty = try await api.send("POST", "/photos/\(photo.id)/like")
            }
            await refreshToday()
        } catch {
            surface(error)
        }
    }

    /// Owner-only: who liked this photo, as faces. Never a count.
    func likeFaces(_ photoId: String) async -> [UserBrief] {
        do {
            return (try await api.send("GET", "/photos/\(photoId)/likes") as LikesResponse).faces
        } catch {
            surface(error)
            return []
        }
    }

    /// Owner-only: who held this photo, as faces. Never a count (A2).
    func heldByFaces(_ photoId: String) async -> [HeldByEntry] {
        do {
            return (try await api.send("GET", "/photos/\(photoId)/anchors") as HeldByResponse).anchors
        } catch {
            surface(error)
            return []
        }
    }

    func comment(on photo: Photo, body: String) async {
        do {
            let _: Empty = try await api.send(
                "POST", "/photos/\(photo.id)/comments", json: ["body": body]
            )
            await refreshToday()
        } catch {
            surface(error)
        }
    }

    func restMemory(photoId: String) async {
        do {
            let _: Empty = try await api.send("POST", "/memories/\(photoId)/rest")
            returned = nil  // gone quietly; no confirmation, no reason prompt (§14)
        } catch {
            surface(error)
        }
    }

    // MARK: circle admin & account

    func rotateInvite() async {
        guard let circle else { return }
        do {
            let _: InviteResponse = try await api.send("POST", "/circles/\(circle.id)/rotate_invite")
            await loadCircle()  // reload to surface the new token in the UI
        } catch {
            surface(error)
        }
    }

    func removeMember(_ memberId: String) async {
        guard let circle else { return }
        do {
            let _: Empty = try await api.send("DELETE", "/circles/\(circle.id)/members/\(memberId)")
            await loadCircle()
        } catch {
            surface(error)
        }
    }

    func leaveCircle() async {
        guard let circle else { return }
        do {
            let _: Empty = try await api.send("POST", "/circles/\(circle.id)/leave")
            await loadCircle()  // -> no_circle -> back to the circle gate
        } catch {
            surface(error)
        }
    }

    func deleteAccount() async {
        do {
            let _: Empty = try await api.send("DELETE", "/me")
            signOut()
        } catch {
            surface(error)
        }
    }

    func exportMemories() async -> Data? {
        do {
            return try await api.fetchData("/me/export")
        } catch {
            surface(error)
            return nil
        }
    }
}

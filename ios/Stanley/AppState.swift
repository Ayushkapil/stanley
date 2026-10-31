import AuthenticationServices
import Foundation
import Observation

/// Everything the screens show. Main-actor isolated: every observed
/// property is written on the main thread, where SwiftUI reads it. The
/// network calls still run off it (`APIClient.send` is its own `async`), so
/// requests and JSON decoding never block the UI. Only the assignments
/// come back here. Without this, Swift 5 ran these `async` methods on a
/// background executor, and `feedItems` and the rest were written off the
/// main thread while SwiftUI read them on it: a data race.
@MainActor
@Observable
final class AppState {
    let api = APIClient()
    /// Captures taken before the network was there. Claims the day locally.
    let queue = OfflineQueue()

    var signedIn: Bool
    var circle: CircleInfo?
    var feedItems: [FeedItem] = []
    var communityNote: CommunityNote?
    var mosaic: Mosaic?
    var returned: ReturnedItem?
    var news: [NewsArticle] = []
    var threads: [MemoryThread] = []
    var profile: MyProfile?
    var myId: String?
    var errorMessage: String?
    var flash: String?  // gentle, transient confirmation (e.g. after resting)
    var checkedCircle = false

    init() {
        signedIn = api.token != nil
        api.onTokenRejected { [weak self] token in
            Task { @MainActor in self?.tokenRejected(token) }
        }
    }

    /// The server turned down our sign-in, so nothing will work until the
    /// person signs in again. Sign out now and say so once, wherever they
    /// are, rather than answer every request with an error they can't act
    /// on. On the name and circle gates there is no Settings to sign out
    /// from. Only the token we still hold counts: a late answer to a request
    /// sent before a fresh sign-in mustn't undo it.
    private func tokenRejected(_ token: String) {
        guard signedIn, api.token == token else { return }
        signOut()
        errorMessage = APIError.signedOut.errorDescription
    }

    /// Show an error — unless the "error" is the person changing their mind.
    ///
    /// A cancellation is not a failure. `URLError.cancelled` in particular
    /// localizes to the bare word "cancelled", which is how a raw lowercase
    /// alert was reaching the screen whenever a sheet was dismissed mid-request
    /// or a `.task` was torn down on disappear. Nothing to tell anyone.
    func surface(_ error: Error) {
        guard !AppState.isCancellation(error) else { return }
        // `tokenRejected` has already signed out and said why, once. The
        // other requests that fail the same way have nothing to add, and
        // neither does one that left after the sign-out with no token at all.
        if case APIError.signedOut = error { return }
        if case APIError.status(401) = error, !signedIn { return }
        errorMessage = AppState.words(for: error)
    }

    /// Every error in Stanley's voice. The system's own descriptions ("The
    /// Internet connection appears to be offline.", "The data couldn't be
    /// read because it isn't in the correct format.") never reach the screen.
    nonisolated static func words(for error: Error) -> String {
        switch error {
        case let api as APIError: return api.errorDescription ?? APIError.words(forStatus: 0)
        case is URLError: return APIError.unreachable
        case is DecodingError: return "Something didn't load right. Try again in a moment."
        case is ASAuthorizationError: return APIError.appleSignInFailed
        default: return "Something went wrong. Try again in a moment."
        }
    }

    /// True for every flavour of "the user backed out" we can be handed.
    nonisolated static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        if let urlError = error as? URLError, urlError.code == .cancelled { return true }
        if let authError = error as? ASAuthorizationError, authError.code == .canceled { return true }
        let ns = error as NSError
        switch (ns.domain, ns.code) {
        // Sheets, pickers and share sheets dismissed by the person.
        case (NSCocoaErrorDomain, NSUserCancelledError): return true
        // PHPhotosError.userCancelled, and the Photos picker's own cancel.
        case ("PHPhotosErrorDomain", 3072): return true
        case (ASAuthorizationError.errorDomain, ASAuthorizationError.canceled.rawValue): return true
        case (NSURLErrorDomain, NSURLErrorCancelled): return true
        default: return false
        }
    }

    /// Apple hands over a name only on the very first authorization, and only
    /// if the person agrees to share it. Decline, and we genuinely do not know
    /// what to call them — so ask, once, before the circle gate.
    var needsName: Bool {
        guard let profile else { return false }
        return (profile.displayName ?? "").trimmingCharacters(in: .whitespaces).isEmpty
    }

    // MARK: auth & circle

    /// Sign in with Apple: exchange Apple's identity token for a Stanley JWT.
    func appleSignIn(identityToken: String, name: String?) async {
        do {
            var body: [String: Any?] = ["identity_token": identityToken]
            if let name, !name.isEmpty { body["name"] = name }
            let auth: AuthResponse = try await api.send("POST", "/auth/apple", json: body)
            api.token = auth.token
            myId = auth.user.id
            signedIn = true
            await loadCircle()
        } catch {
            surface(error)
        }
    }

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
        mosaic = nil
        returned = nil
        news = []
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

    func joinCircle(code: String) async {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            errorMessage = "That invite code doesn't look right."
            return
        }
        do {
            _ = try await api.send("POST", "/circles/join", json: ["code": trimmed]) as CircleInfo
            await loadCircle()
        } catch APIError.status(404) {
            // No circle has this code — mistyped, or rotated since it was shared.
            errorMessage = "That invite code doesn't look right."
        } catch {
            surface(error)
        }
    }

    var inviteCode: String? {
        guard let circle, let token = circle.inviteToken else { return nil }
        return token
    }

    // MARK: surfaces

    func refreshToday() async {
        do {
            let response: TodayResponse = try await api.send("GET", "/feed/today")
            feedItems = response.items
            communityNote = response.note
            mosaic = response.mosaic
            let returnedResponse: ReturnedResponse = try await api.send(
                "GET", "/feed/returned", query: ["tz": TimeZone.current.identifier]
            )
            returned = returnedResponse.item
        } catch {
            surface(error)
        }
    }

    /// The World Today. A failure here is never surfaced, because the news
    /// is a convenience, not part of the circle. This loads when the World
    /// tab appears and on pull, so headlines don't shift under someone
    /// reading them.
    func loadNews() async {
        do {
            news = try await api.send("GET", "/news/today")
        } catch {
            // Keep whatever was showing.
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

    /// Real-time username availability for the edit sheet. Nil on network
    /// trouble — the caller treats that as "unknown", never as a block; the
    /// server re-validates on save regardless.
    func checkUsername(_ candidate: String) async -> UsernameCheck? {
        // As a query item, not part of the path: `send` builds the path with
        // `appending(path:)`, which encoded a "?u=" into the path itself, so
        // the server answered 404 and this check never ran.
        try? await api.send("GET", "/me/username_check", query: ["u": candidate])
    }

    // MARK: gestures

    func capture(
        jpeg: Data, caption: String?, location: String?, tagged: [String], filter: String? = nil
    ) async throws {
        // The day is already spoken for by something waiting to go up. The
        // law holds offline too, so this is refused here, not at the server.
        if queue.isHoldingTheDay {
            throw APIError.message("Your photo for today is still waiting to upload.")
        }
        do {
            _ = try await api.uploadPhoto(
                jpeg: jpeg, caption: caption, location: location, tagged: tagged, filter: filter
            )
            await refreshToday()
        } catch {
            guard isOffline(error) else {
                // The server answered and failed (it rolls the request back,
                // so the day is untouched). A refusal with a reason keeps it.
                if let api = error as? APIError, case .status(let status) = api, status >= 500 {
                    throw APIError.message(APIError.photoNotPosted)
                }
                throw error
            }
            // No signal: keep the moment, claim the day, send it later.
            queue.enqueue(jpeg: jpeg, caption: caption, location: location, tagged: tagged, filter: filter)
            flash = "Saved. It'll go up when you're back online."
        }
    }

    /// Try the waiting capture again. Safe to call often — it no-ops unless
    /// something is actually pending and still sendable.
    func flushPendingCapture() async {
        guard let item = queue.pending, item.rejection == nil, let jpeg = queue.jpeg() else { return }
        do {
            _ = try await api.uploadPhoto(
                jpeg: jpeg, caption: item.caption, location: item.location, tagged: item.tagged,
                filter: item.filter
            )
            queue.clear()
            flash = "Your photo went up."
            await refreshToday()
        } catch let error as APIError {
            // The server refused the slot - another device got there first.
            // Strand it honestly rather than retrying forever.
            if case .server(let code, _) = error, code == "slot_used" || code == "too_soon" {
                queue.markRejected("Today's photo was already posted from another device.")
            }
        } catch {
            // Still offline. Keep waiting; nothing to tell the user.
        }
    }

    // MARK: milestones (Part 4)

    func loadMilestones() async -> [Milestone] {
        do {
            return (try await api.send("GET", "/me/milestones") as MilestonesResponse).milestones
        } catch {
            surface(error)
            return []
        }
    }

    func dismissMilestone(_ id: Int) async {
        do {
            let _: Empty = try await api.send("DELETE", "/me/milestones/\(id)")
        } catch {
            surface(error)
        }
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

    /// Rest a memory — one tap, no confirmation (§14). Works from a Returned
    /// card or any held row. Gentle, unexplaining confirmation after.
    func rest(photoId: String) async {
        do {
            let _: Empty = try await api.send("POST", "/memories/\(photoId)/rest")
            flash = "Rested. It won't come back on its own."
        } catch {
            surface(error)
        }
    }

    /// "Let it return" — undo a rest from the Rested view.
    func unrest(photoId: String) async {
        do {
            let _: Empty = try await api.send("DELETE", "/memories/\(photoId)/rest")
        } catch {
            surface(error)
        }
    }

    func loadRested() async -> [Memory] {
        do {
            return (try await api.send("GET", "/memories/rested") as RestedResponse).memories
        } catch {
            surface(error)
            return []
        }
    }

    // MARK: Returned card actions

    /// Rest from the Returned card: stop it ever resurfacing, clear the card.
    func restReturned(photoId: String) async {
        await rest(photoId: photoId)
        returned = nil
    }

    /// Keep (rescue): anchor the photo so it survives, then refresh — the card
    /// clears because a kept photo no longer needs rescuing.
    func keepReturned(photoId: String) async {
        do {
            let _: Empty = try await api.send("POST", "/photos/\(photoId)/anchor", json: ["note": nil])
            flash = "Kept. It's yours now."
            await refreshToday()
        } catch {
            surface(error)
        }
    }

    /// Dismiss = "not now": clear today's card without resting it.
    func dismissReturned() async {
        do {
            let _: Empty = try await api.send(
                "POST", "/feed/returned/dismiss", query: ["tz": TimeZone.current.identifier]
            )
            returned = nil
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
            // The places this person named live only on this phone. The
            // account is gone, so they go too.
            if let myId { PlaceBook.erase(userId: myId) }
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

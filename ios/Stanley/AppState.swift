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
    /// Where the phone is, as names, with permission: a photo's place and
    /// the town for the news.
    let whereabouts = Whereabouts()

    var signedIn: Bool
    /// The circle on screen, in full: its roster, its invite code.
    var circle: CircleInfo?
    /// Every circle this person is in, in the order they joined. Up to five
    /// (build 17); Today shows one at a time.
    var circles: [CircleSummary] = []
    var feedItems: [FeedItem] = []
    var communityNote: CommunityNote?
    var mosaic: Mosaic?
    var returned: ReturnedItem?
    var news: [NewsArticle] = []
    /// Headlines from the town the phone is in, and that town's name. Empty
    /// without location permission.
    var nearby: [NewsArticle] = []
    var nearbyTown: String?
    var threads: [MemoryThread] = []
    var profile: MyProfile?
    var myId: String?
    var errorMessage: String?
    var flash: String?  // gentle, transient confirmation (e.g. after resting)
    var checkedCircle = false
    /// A new avatar is on its way up.
    var avatarUploading = false
    /// This account hasn't been through setup yet (`SetupView`). Kept on the
    /// phone per account, so someone who quits halfway is brought back to it.
    var setupPending = false

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

    /// Setup comes before the circle gate for a new account, and for anyone
    /// we have no name for. Apple hands over a name only on the very first
    /// authorization, and only if the person agrees to share it. Decline,
    /// and we genuinely do not know what to call them.
    var needsSetup: Bool {
        if setupPending { return true }
        guard let profile else { return false }
        return (profile.displayName ?? "").trimmingCharacters(in: .whitespaces).isEmpty
    }

    private static func setupKey(_ userId: String) -> String { "stanley.setupPending.\(userId)" }
    /// The circle last on screen, per account, so the app opens where it was.
    private static func circleKey(_ userId: String) -> String { "stanley.activeCircle.\(userId)" }

    /// Setup is done, or was finished from its last step.
    func finishSetup() {
        if let myId { UserDefaults.standard.removeObject(forKey: Self.setupKey(myId)) }
        setupPending = false
    }

    // MARK: auth & circle

    /// Sign in with Apple: exchange Apple's identity token for a Stanley JWT.
    func appleSignIn(identityToken: String, name: String?) async {
        do {
            var body: [String: Any?] = ["identity_token": identityToken]
            if let name, !name.isEmpty { body["name"] = name }
            let auth: AuthResponse = try await api.send("POST", "/auth/apple", json: body)
            await startSession(auth)
        } catch {
            surface(error)
        }
    }

    func devSignIn(name: String) async {
        do {
            let auth: AuthResponse = try await api.send(
                "POST", "/auth/dev", json: ["display_name": name]
            )
            await startSession(auth)
        } catch {
            surface(error)
        }
    }

    /// A new account is marked for setup before anything else happens, so
    /// quitting right after signing in still brings setup back. The profile
    /// loads before the circle, because setup reads the name.
    private func startSession(_ auth: AuthResponse) async {
        if auth.newAccount == true {
            UserDefaults.standard.set(true, forKey: Self.setupKey(auth.user.id))
        }
        api.token = auth.token
        myId = auth.user.id
        setupPending = UserDefaults.standard.bool(forKey: Self.setupKey(auth.user.id))
        signedIn = true
        await loadProfile()
        await loadCircle()
        // If this phone already allows notifications, its token now belongs
        // to this account.
        await Push.shared.refresh()
    }

    func signOut() {
        // This phone stops hearing from this account: the token goes, under
        // the sign-in that registered it, before that sign-in is dropped.
        if let push = Push.shared.token, let auth = api.token {
            let api = self.api
            Task.detached {
                let _: Empty? = try? await api.send(
                    "DELETE", "/me/push-token", json: ["token": push],
                    headers: ["Authorization": "Bearer \(auth)"]
                )
            }
        }
        api.token = nil
        api.circleId = nil
        signedIn = false
        setupPending = false
        avatarUploading = false
        circle = nil
        circles = []
        checkedCircle = false
        feedItems = []
        communityNote = nil
        mosaic = nil
        returned = nil
        news = []
        nearby = []
        nearbyTown = nil
        threads = []
        profile = nil
        myId = nil
    }

    /// Which circles this person is in, and the one on screen in full. The
    /// one on screen is the one they last chose, while they're still in it,
    /// else the first they joined.
    func loadCircle() async {
        defer { checkedCircle = true }
        do {
            let list: CirclesResponse
            do {
                list = try await api.send("GET", "/circles")
            } catch APIError.status(404) {
                // A server from before multiple circles: the one it knows.
                api.circleId = nil
                let only: CircleInfo = try await api.send("GET", "/circles/mine")
                circle = only
                circles = [CircleSummary(id: only.id, name: only.name, isCreator: only.isCreator ?? false)]
                return
            }
            circles = list.circles
            guard let first = circles.first else {
                circle = nil
                api.circleId = nil
                return
            }
            queue.adopt(into: first.id)
            let chosen = myId.flatMap { UserDefaults.standard.string(forKey: Self.circleKey($0)) }
            api.circleId = (circles.first { $0.id == chosen } ?? first).id
            circle = try await api.send("GET", "/circles/mine") as CircleInfo
        } catch APIError.server(code: "no_circle", status: _) {
            circle = nil
            circles = []
            api.circleId = nil
        } catch {
            surface(error)
        }
    }

    /// This phone's APNs token, for the notices this person has turned on.
    /// Sent on every launch that has one; the server keeps one row per token.
    func sendPushToken(_ token: String) async {
        guard signedIn else { return }
        let _: Empty? = try? await api.send(
            "POST", "/me/push-token", json: ["token": token, "environment": Push.environment]
        )
    }

    /// The organizer renames the circle on screen.
    func renameCircle(_ name: String) async -> Bool {
        guard let circle else { return false }
        do {
            let _: Empty = try await api.send("PATCH", "/circles/\(circle.id)", json: ["name": name])
            await loadCircle()
            return true
        } catch {
            surface(error)
            return false
        }
    }

    /// Show another of this person's circles. Today empties at once, so the
    /// last circle's photos never sit under the new circle's name.
    func switchCircle(to id: String) async {
        if let myId { UserDefaults.standard.set(id, forKey: Self.circleKey(myId)) }
        guard id != circle?.id else { return }
        api.circleId = id
        feedItems = []
        communityNote = nil
        mosaic = nil
        await loadCircle()
        await refreshToday()
    }

    /// The circle on screen is gone (left, or removed, on another phone).
    /// Back to one they're in, or the gate if there's none.
    private func lostCircle() async {
        if let myId { UserDefaults.standard.removeObject(forKey: Self.circleKey(myId)) }
        feedItems = []
        communityNote = nil
        mosaic = nil
        await loadCircle()
    }

    /// Start a circle, and show it.
    func createCircle(name: String) async -> Bool {
        do {
            let made: CircleInfo = try await api.send("POST", "/circles", json: ["name": name])
            await switchCircle(to: made.id)
            return true
        } catch {
            surface(error)
            return false
        }
    }

    /// Join a circle by its code, and show it.
    func joinCircle(code: String) async -> Bool {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            errorMessage = "That invite code doesn't look right."
            return false
        }
        do {
            let joined: CircleInfo = try await api.send("POST", "/circles/join", json: ["code": trimmed])
            await switchCircle(to: joined.id)
            return true
        } catch APIError.status(404) {
            // No circle has this code — mistyped, or rotated since it was shared.
            errorMessage = "That invite code doesn't look right."
        } catch {
            surface(error)
        }
        return false
    }

    var inviteCode: String? {
        guard let circle, let token = circle.inviteToken else { return nil }
        return token
    }

    // MARK: surfaces

    func refreshToday() async {
        let asked = api.circleId
        do {
            let response: TodayResponse = try await api.send("GET", "/feed/today")
            // Switched circles while this was on its way: it's the old one's.
            guard api.circleId == asked else { return }
            feedItems = response.items
            communityNote = response.note
            mosaic = response.mosaic
            let returnedResponse: ReturnedResponse = try await api.send(
                "GET", "/feed/returned", query: ["tz": TimeZone.current.identifier]
            )
            returned = returnedResponse.item
        } catch APIError.server(code: "not_in_circle", status: _) {
            await lostCircle()
            if circle != nil { await refreshToday() }
        } catch {
            surface(error)
        }
    }

    /// The World Today. A failure here is never surfaced, because the news
    /// is a convenience, not part of the circle. This loads when the World
    /// tab appears and on pull, so headlines don't shift under someone
    /// reading them. The national stories don't wait for a location fix:
    /// they load for the country the phone was last found in, and again only
    /// if this fix finds it somewhere else.
    func loadNews() async {
        let assumed = whereabouts.foundCountry
        async let national: Void = loadNational(country: assumed)
        async let local: Void = loadNearby()
        _ = await (national, local)
        if let found = whereabouts.foundCountry, found != (assumed ?? "US") {
            await loadNational(country: found)
        }
    }

    /// PBS for a phone in the US, BBC World elsewhere. Without a country (no
    /// location permission, or no fix yet) the server assumes the US, where
    /// the pilot is.
    private func loadNational(country: String?) async {
        var headers: [String: String] = [:]
        if let country { headers["X-Stanley-Country"] = country }
        do {
            news = try await api.send("GET", "/news/today", headers: headers)
        } catch {
            // Keep whatever was showing.
        }
    }

    /// The town's headlines. Only the town's name and country go to the
    /// server, in headers so they never reach an access log, and the town is
    /// percent-encoded because a header is ASCII and a town may not be.
    private func loadNearby() async {
        guard whereabouts.allowed else {
            nearby = []
            nearbyTown = nil
            return
        }
        guard let here = await whereabouts.here(), let town = here.town else { return }
        let ascii = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
        var headers = ["X-Stanley-Town": town.addingPercentEncoding(withAllowedCharacters: ascii) ?? ""]
        if let country = here.country { headers["X-Stanley-Country"] = country }
        do {
            nearby = try await api.send("GET", "/news/nearby", headers: headers)
            nearbyTown = here.townName
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
            if let myId {
                setupPending = UserDefaults.standard.bool(forKey: Self.setupKey(myId))
            }
        } catch {
            surface(error)
        }
    }

    func uploadAvatar(jpeg: Data) async {
        avatarUploading = true
        defer { avatarUploading = false }
        do {
            _ = try await api.uploadAvatar(jpeg: jpeg)
            await loadProfile()
            await loadCircle()  // so the roster shows the new face
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

    /// Change only the fields given; the server leaves the rest as they are.
    /// Setup saves one step at a time this way.
    func patchProfile(_ fields: [String: Any?]) async -> Bool {
        do {
            profile = try await api.send("PATCH", "/me/profile", json: fields) as MyProfile
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

    /// The capture waiting for signal in the circle on screen.
    var pendingHere: PendingCapture? { queue.pending(in: circle?.id) }

    /// The circle on screen has a capture waiting: its day is spoken for.
    var holdsTheDay: Bool { pendingHere != nil }

    /// Who the people a story mentions are, in the circle on screen, and
    /// their tones (`Mentions.swift`).
    var mentions: MentionDirectory { MentionDirectory(circle: circle) }
    /// The people a story being written could mention, shown above the
    /// keyboard by whatever screen holds the story's field.
    let mentionOffer = MentionOffer()

    func capture(
        jpeg: Data, caption: String?, location: String?, tagged: [String], filter: String? = nil
    ) async throws {
        let circleId = circle?.id
        // The day is already spoken for by something waiting to go up. The
        // law holds offline too, so this is refused here, not at the server.
        if queue.isHoldingTheDay(in: circleId) {
            throw APIError.message("Your photo for today is still waiting to upload.")
        }
        do {
            _ = try await api.uploadPhoto(
                jpeg: jpeg, caption: caption, location: location, tagged: tagged, filter: filter,
                circleId: circleId
            )
            await refreshToday()
        } catch APIError.server(code: "not_in_circle", status: let status) {
            await lostCircle()
            throw APIError.server(code: "not_in_circle", status: status)
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
            queue.enqueue(
                jpeg: jpeg, caption: caption, location: location, tagged: tagged, filter: filter,
                circleId: circleId
            )
            flash = "Saved. It'll go up when you're back online."
        }
    }

    /// Try the waiting captures again, each to the circle it was taken for.
    /// Safe to call often — it no-ops unless something is actually pending
    /// and still sendable.
    func flushPendingCapture() async {
        var sent = false
        for item in queue.items where item.rejection == nil {
            guard let jpeg = queue.jpeg(item) else { continue }
            do {
                _ = try await api.uploadPhoto(
                    jpeg: jpeg, caption: item.caption, location: item.location, tagged: item.tagged,
                    filter: item.filter, circleId: item.circleId
                )
                queue.clear(item)
                sent = true
            } catch let error as APIError {
                // The server refused the slot - another device got there
                // first, or the circle is gone. Strand it honestly rather than
                // retrying forever.
                if case .server(let code, _) = error {
                    switch code {
                    case "slot_used", "too_soon":
                        queue.markRejected(item, "Today's photo was already posted from another device.")
                    case "not_in_circle":
                        queue.markRejected(item, "You're no longer in the circle this was for.")
                    default:
                        break
                    }
                }
            } catch {
                // Still offline. Keep waiting; nothing to tell the user.
                break
            }
        }
        if sent {
            flash = "Your photo went up."
            await refreshToday()
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

    /// Add a story to a photo. Returns the story as posted, so a thread can
    /// show it even when it's drawn from a copy of the photo that Today's
    /// refresh never reaches (a profile's prints). Nil if it didn't go, with
    /// the reason already said.
    func comment(on photo: Photo, body: String) async -> Comment? {
        struct Posted: Decodable { let id: String }
        do {
            let posted: Posted = try await api.send(
                "POST", "/photos/\(photo.id)/comments", json: ["body": body]
            )
            await refreshToday()
            let me = UserBrief(
                id: myId, displayName: profile?.displayName ?? "New member", avatarUrl: profile?.avatarUrl
            )
            return Comment(id: posted.id, author: me, body: body, createdAt: .now)
        } catch {
            surface(error)
            return nil
        }
    }

    // MARK: - Safety (build 18): report, block, delete, untag
    //
    // The server has had all of these since the first pilot builds; the app
    // reaches them through each photo's menu, a story's menu, a member's
    // profile and Settings → Privacy & Security → Blocked.

    /// A report about a photo or a story, with the reason in words. Read by a
    /// person within a day (Terms §5). True once it's in.
    func report(photo: Photo? = nil, comment: Comment? = nil, reason: String) async -> Bool {
        do {
            let _: Empty = try await api.send(
                "POST", "/reports",
                json: ["photo_id": photo?.id, "comment_id": comment?.id, "reason": reason]
            )
            return true
        } catch {
            surface(error)
            return false
        }
    }

    /// Block someone: neither of you sees the other's photos or stories, in
    /// any circle you share. They aren't told. True once it's done.
    ///
    /// Doesn't refresh Today: blocking happens in a sheet, often one that a
    /// card of theirs presented, and refreshing would remove that card and
    /// tear the sheet down mid-flight. The caller refreshes once its sheet
    /// has gone (`onDisappear`).
    func block(_ person: UserBrief) async -> Bool {
        guard let id = person.id else { return false }
        do {
            let _: Empty = try await api.send("POST", "/blocks", json: ["user_id": id])
            return true
        } catch {
            surface(error)
            return false
        }
    }

    func unblock(_ person: UserBrief) async -> Bool {
        guard let id = person.id else { return false }
        do {
            let _: Empty = try await api.send("DELETE", "/blocks/\(id)")
            await refreshToday()
            return true
        } catch {
            surface(error)
            return false
        }
    }

    func blockedPeople() async throws -> [UserBrief] {
        (try await api.send("GET", "/blocks") as BlockedPeople).people
    }

    /// Delete one of your own photos: removed everywhere at once, from the
    /// people who held it too, who keep a note that a memory was here. Today's
    /// photo gives the day back once (the redo, §8.4); the server decides.
    func deletePhoto(_ photo: Photo) async {
        do {
            let _: Empty = try await api.send("DELETE", "/photos/\(photo.id)")
            await refreshToday()
            flash = photo.retakeOnDelete == true
                ? "Deleted. You can take today's photo again."
                : "Deleted."
        } catch {
            surface(error)
        }
    }

    /// Take your own face off a photo someone tagged you in.
    func untagMe(from photo: Photo) async {
        do {
            let _: Empty = try await api.send("DELETE", "/photos/\(photo.id)/tags/me")
            await refreshToday()
            flash = "You're no longer on that photo."
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

    /// Leave the circle on screen. Another circle, if there is one, comes
    /// up in its place; with none left, the circle gate.
    func leaveCircle() async {
        guard let circle else { return }
        do {
            let _: Empty = try await api.send("POST", "/circles/\(circle.id)/leave")
            await lostCircle()
            if self.circle != nil { await refreshToday() }
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

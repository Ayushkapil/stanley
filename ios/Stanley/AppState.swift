import AuthenticationServices
import Foundation
import Network
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
    /// Where Today's next page starts, or nil when everything is here
    /// (the production audit: twenty entries at a time, newest first).
    var todayCursor: String?
    /// Today has been fetched for the circle on screen. Until then an empty
    /// feed means "not here yet", not "nothing posted", so the empty page
    /// doesn't flash up at every launch and circle switch.
    var todayLoaded = false
    /// The circle's board today (build 27): everyone's note, newest first.
    var notes: [CommunityNote] = []
    var mosaic: Mosaic?
    var returned: ReturnedItem?
    /// The circle on screen's question of the week, and your answer to it
    /// (build 26). Nil before it's loaded, and from an older server.
    var question: WeekQuestion?
    /// Today's photo, just posted: the one the quiet "Anything else about
    /// today?" slip sits under, until something's written or it's put away.
    /// Doing nothing is skipping it, and it's gone at the next launch.
    var journalOffer: String?
    /// The week a reflection written now would be about, with your photos
    /// from it: loaded on Sunday evenings, when the You tab asks.
    var thisWeek: ThisWeek?
    /// Your reflections, newest first, and where the next page starts.
    var reflections: [Reflection] = []
    var reflectionsCursor: String?
    var news: [NewsArticle] = []
    /// Headlines from the town the phone is in, and that town's name. Empty
    /// without location permission.
    var nearby: [NewsArticle] = []
    var nearbyTown: String?
    var threads: [MemoryThread] = []
    /// Held has been fetched once, so an empty album is really empty.
    var memoriesLoaded = false
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
    /// Stanley can't be reached: no signal, or no answer. Said once, quietly,
    /// under each page's masthead (`OfflineLine`), never as an alert for
    /// something the person didn't ask for. What was on screen stays.
    var offline = false
    /// Bumped whenever what's on screen should be fetched again without
    /// anyone pulling: Stanley answers again after it couldn't be reached,
    /// or a photo's signed link ran out before it was shown. Views that keep
    /// their own copy of something (a member's page, Rested, milestones)
    /// load again on it; what this state holds is loaded here.
    var reloads = 0

    private let path = NWPathMonitor()
    /// Asks whether Stanley answers again, every few seconds, only while it
    /// doesn't.
    private var retrying: Task<Void, Never>?
    /// When signed links last ran out, so a screenful of failed photos asks
    /// for fresh ones once, not once each.
    private var lastRenewal = Date.distantPast
    /// A queued capture is on its way up. Reconnecting and Today's own pass
    /// both send what's waiting; two sends at once would post one and then
    /// strand the other as "already posted".
    private var flushing = false
    /// The next page of Today is on its way.
    private var loadingMoreToday = false
    /// The next page of reflections is on its way.
    private var loadingMoreReflections = false
    /// Today's first page, and each page after it.
    static let todayPage = 20
    /// When the sign-in was last renewed (`refreshSignInIfDue`).
    private static let signInRenewedKey = "stanley.signInRenewedAt"

    init() {
        signedIn = api.token != nil
        api.onTokenRejected { [weak self] token in
            Task { @MainActor in self?.tokenRejected(token) }
        }
        // No network at all is known before any request fails, and its
        // return is the moment to try again.
        path.pathUpdateHandler = { [weak self] path in
            let up = path.status == .satisfied
            Task { @MainActor in
                if up { await self?.checkConnection() } else { self?.lostConnection() }
            }
        }
        path.start(queue: DispatchQueue(label: "stanley.path"))
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
        if isOffline(error) { lostConnection() }
        errorMessage = AppState.words(for: error)
    }

    /// A page couldn't load. Without a connection that isn't news to tell
    /// anyone in an alert, once per request, on every tab: it's said under
    /// the masthead, what was showing stays, and it all loads again by itself
    /// when Stanley answers (`checkConnection`). Anything else is said as
    /// usual. Something the person did (a story, a like) still says it
    /// didn't go through, through `surface`.
    func missed(_ error: Error) {
        if isOffline(error) {
            lostConnection()
        } else {
            surface(error)
        }
    }

    /// Stanley is out of reach. Ask again every few seconds until it
    /// answers; that also covers a network that's up while the server
    /// isn't, which no path change would announce.
    func lostConnection() {
        guard !offline else { return }
        offline = true
        Trail.note(.wentOffline)
        guard retrying == nil else { return }
        // Never cancelled from outside: the pass that finds Stanley again
        // runs inside this task, and cancelling it would cancel the very
        // requests that reload the page. It ends by itself once answered.
        retrying = Task { [weak self] in
            repeat {
                try? await Task.sleep(for: .seconds(8))
                await self?.checkConnection()
            } while self?.offline == true
            self?.retrying = nil
        }
    }

    /// Does Stanley answer? If it does after it didn't, everything on
    /// screen loads again and anything waiting goes up, with nothing to
    /// pull or tap. Also asked when the network comes back and when the app
    /// comes to the front.
    func checkConnection() async {
        guard offline else { return }
        do {
            let _: Empty = try await api.send("GET", "/health")
        } catch {
            return
        }
        guard offline else { return }
        offline = false
        Trail.note(.cameBack)
        // Before the circle is known, the launch's own pass does it all
        // (`RootView`), as soon as this is false.
        guard signedIn, checkedCircle else { return }
        await reloadEverything()
        if news.isEmpty { await loadNews() }
        await flushPendingCapture()
    }

    /// A photo's signed link ran out before the photo was shown: links last
    /// fifteen minutes (§9), and a page left open longer still holds the
    /// old ones. Fetch everything this state holds again, which signs every
    /// link afresh, at most once every half minute however many photos ask.
    func linksExpired() {
        guard signedIn, checkedCircle, !offline,
              Date.now.timeIntervalSince(lastRenewal) > 30 else { return }
        lastRenewal = .now
        Trail.note(.renewedLinks)
        Task { await reloadEverything() }
    }

    /// Today, the circle's faces, Held and the profile, fetched again; then
    /// everything that keeps its own copy is told to.
    private func reloadEverything() async {
        await loadCircle()
        await refreshToday()
        await loadQuestion()
        await refreshMemories()
        await loadProfile()
        reloads += 1
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
        UserDefaults.standard.set(Date.now, forKey: Self.signInRenewedKey)
        myId = auth.user.id
        setupPending = UserDefaults.standard.bool(forKey: Self.setupKey(auth.user.id))
        signedIn = true
        Trail.note(.signedIn)
        await loadProfile()
        await loadCircle()
        // If this phone already allows notifications, its token now belongs
        // to this account.
        await Push.shared.refresh()
    }

    /// Keep a sign-in that's in use from running out (the production audit).
    /// A token lasts thirty days; once a day, while the app is open and
    /// Stanley answers, it's traded for a fresh one, so someone who opens
    /// Stanley at least once a month is never signed out by the calendar.
    /// A phone left unopened for a month still is, and signs in again. A
    /// token the server refuses signs out as any refused request does
    /// (`tokenRejected`); any other failure waits for tomorrow.
    func refreshSignInIfDue() async {
        guard signedIn, !offline, api.token != nil else { return }
        let last = UserDefaults.standard.object(forKey: Self.signInRenewedKey) as? Date ?? .distantPast
        guard Date.now.timeIntervalSince(last) > 24 * 60 * 60 else { return }
        struct Renewed: Decodable { let token: String }
        do {
            let renewed: Renewed = try await api.send("POST", "/auth/refresh")
            guard signedIn else { return }
            api.token = renewed.token
            UserDefaults.standard.set(Date.now, forKey: Self.signInRenewedKey)
            Trail.note(.refreshedSignIn)
        } catch {
            // Refused: already signed out by `tokenRejected`. Otherwise,
            // tomorrow's open tries again.
        }
    }

    func signOut() {
        Trail.note(.signedOut)
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
        todayCursor = nil
        todayLoaded = false
        notes = []
        mosaic = nil
        returned = nil
        question = nil
        journalOffer = nil
        thisWeek = nil
        reflections = []
        reflectionsCursor = nil
        news = []
        nearby = []
        nearbyTown = nil
        threads = []
        memoriesLoaded = false
        profile = nil
        myId = nil
    }

    /// Which circles this person is in, and the one on screen in full. The
    /// one on screen is the one they last chose, while they're still in it,
    /// else the first they joined.
    func loadCircle() async {
        // Unanswered isn't answered: without a connection, nobody has been
        // told they have no circle, and the gate is for people who don't.
        // Launched offline, the app waits for Stanley instead (`RootView`).
        var answered = true
        defer { if answered { checkedCircle = true } }
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
        } catch let error where isOffline(error) || AppState.isCancellation(error) {
            // A launch pass cut short (its view gave way to the offline
            // page) hasn't heard either.
            answered = false
            if isOffline(error) { lostConnection() }
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
        Trail.note(.switchedCircle)
        feedItems = []
        todayCursor = nil
        todayLoaded = false
        notes = []
        mosaic = nil
        question = nil
        journalOffer = nil
        await loadCircle()
        await refreshToday()
        await loadQuestion()
    }

    /// The circle on screen is gone (left, or removed, on another phone).
    /// Back to one they're in, or the gate if there's none.
    private func lostCircle() async {
        if let myId { UserDefaults.standard.removeObject(forKey: Self.circleKey(myId)) }
        feedItems = []
        todayCursor = nil
        todayLoaded = false
        notes = []
        mosaic = nil
        question = nil
        journalOffer = nil
        await loadCircle()
    }

    /// Start a circle, and show it.
    func createCircle(name: String) async -> Bool {
        do {
            let made: CircleInfo = try await api.send("POST", "/circles", json: ["name": name])
            Trail.note(.startedCircle)
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
            Trail.note(.joinedCircle)
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

    /// Today, fetched again. Asks for everything already showing in one
    /// request (at least a page, at most the server's 200), so a like or a
    /// story deep in an evening's scrolling refreshes the page it's on
    /// instead of folding Today back to its first twenty.
    func refreshToday() async {
        let asked = api.circleId
        let wanted = min(max(Self.todayPage, feedItems.count), 200)
        do {
            let response: TodayResponse = try await api.send(
                "GET", "/feed/today", query: ["limit": String(wanted)]
            )
            // Switched circles while this was on its way: it's the old one's.
            guard api.circleId == asked else { return }
            feedItems = response.items
            todayCursor = response.nextCursor
            todayLoaded = true
            notes = response.notes ?? response.note.map { [$0] } ?? []
            mosaic = response.mosaic
            let returnedResponse: ReturnedResponse = try await api.send(
                "GET", "/feed/returned", query: ["tz": TimeZone.current.identifier]
            )
            returned = returnedResponse.item
        } catch APIError.server(code: "not_in_circle", status: _) {
            await lostCircle()
            if circle != nil { await refreshToday() }
        } catch {
            missed(error)
        }
    }

    /// The next page of Today, when the end of what's showing comes into
    /// view. Only ever one on its way; an answer that arrives after a
    /// refresh or a circle switch has replaced the pages is dropped.
    func loadMoreToday() async {
        guard let cursor = todayCursor, !loadingMoreToday else { return }
        loadingMoreToday = true
        defer { loadingMoreToday = false }
        let asked = api.circleId
        do {
            let response: TodayResponse = try await api.send(
                "GET", "/feed/today", query: ["limit": String(Self.todayPage), "cursor": cursor]
            )
            guard api.circleId == asked, todayCursor == cursor else { return }
            let showing = Set(feedItems.map(\.id))
            feedItems += response.items.filter { !showing.contains($0.id) }
            todayCursor = response.nextCursor
            Trail.note(.loadedMoreToday)
        } catch {
            missed(error)
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

    /// Your note on the board today, if you've written one.
    var myNote: CommunityNote? { notes.first(where: isMine) }

    func isMine(_ note: CommunityNote) -> Bool { myId != nil && note.author.id == myId }

    /// Pin your note to the board, or change it. True once it's up.
    @discardableResult
    func setNote(_ text: String) async -> Bool {
        guard let circle else { return false }
        do {
            do {
                let _: CommunityNote = try await api.send(
                    "PUT", "/circles/\(circle.id)/notes/mine", json: ["text": text]
                )
            } catch APIError.status(404) {
                // A server from before the board: its one note.
                let _: CommunityNote = try await api.send(
                    "PUT", "/circles/\(circle.id)/note", json: ["text": text]
                )
            }
            Trail.note(.leftNote)
            await loadNotes()
            return true
        } catch {
            surface(error)
            return false
        }
    }

    /// Take your note off the board.
    func deleteNote() async {
        guard let circle else { return }
        do {
            let _: Empty = try await api.send("DELETE", "/circles/\(circle.id)/notes/mine")
            notes.removeAll(where: isMine)
        } catch {
            surface(error)
        }
    }

    /// The board again, on its own: after writing, and when every note is
    /// opened to read. A server before the board has no such list, and
    /// Today's own refresh brings its one note instead.
    func loadNotes() async {
        guard let circleId = circle?.id else { return }
        struct Board: Decodable { let notes: [CommunityNote] }
        do {
            let board: Board = try await api.send("GET", "/circles/\(circleId)/notes")
            guard circle?.id == circleId else { return }
            notes = board.notes
        } catch APIError.status(404) {
            await refreshToday()
        } catch {
            missed(error)
        }
    }

    func refreshMemories() async {
        do {
            let response: MemoriesResponse = try await api.send("GET", "/me/anchored")
            threads = response.threads
            memoriesLoaded = true
        } catch {
            missed(error)
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
            missed(error)
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

    /// Today's photo in the circle on screen, when it's already posted: the
    /// day is spent, and the capture sheet says so before anyone frames a
    /// photo the server would refuse. Only a photo still in Today counts, so
    /// one deleted with its redo unspent leaves the day open, as it is. (A
    /// redo already spent can't be seen from here; the server's refusal
    /// says the same words.)
    var sharedToday: Photo? {
        guard let myId else { return nil }
        let photos = feedItems.flatMap { item in item.photo.map { [$0] } ?? item.photos ?? [] }
        return photos.first { $0.owner.id == myId && Calendar.current.isDateInToday($0.takenAt) }
    }

    /// Who the people a story mentions are, in the circle on screen, and
    /// their tones (`Mentions.swift`).
    var mentions: MentionDirectory { MentionDirectory(circle: circle) }
    /// The people a story being written could mention, shown above the
    /// keyboard by whatever screen holds the story's field.
    let mentionOffer = MentionOffer()
    /// Taps on the tab already showing, for its page to scroll to its top or
    /// refresh (`TabTaps.swift`).
    let tabTaps = TabTaps()
    /// Bumped when the home screen widget asks for Today (build 40).
    var todayAsked = 0

    /// Post today's photo. True when it's up; false when there was no signal
    /// and it's kept on the phone to go up later.
    @discardableResult
    func capture(
        jpeg: Data, caption: String?, location: String?, tagged: [String], filter: String? = nil
    ) async throws -> Bool {
        let circleId = circle?.id
        // The day is already spoken for by something waiting to go up. The
        // law holds offline too, so this is refused here, not at the server.
        if queue.isHoldingTheDay(in: circleId) {
            throw APIError.message("Your photo for today is still waiting to upload.")
        }
        do {
            let posted = try await api.uploadPhoto(
                jpeg: jpeg, caption: caption, location: location, tagged: tagged, filter: filter,
                circleId: circleId
            )
            Trail.note(.postedPhoto)
            // Only a photo posted now, never one sent later from the queue:
            // by then the moment to ask has passed.
            journalOffer = posted.id
            await refreshToday()
            return true
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
            Trail.note(.keptPhotoForLater)
            flash = "Saved. It'll go up when you're back online."
            return false
        }
    }

    /// Try the waiting captures again, each to the circle it was taken for.
    /// Safe to call often — it no-ops unless something is actually pending
    /// and still sendable.
    func flushPendingCapture() async {
        guard !flushing else { return }
        flushing = true
        defer { flushing = false }
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
                    case "words_not_allowed":
                        // Its caption or place won't ever go up as written.
                        queue.markRejected(item, APIError.wordsNotAllowed)
                    default:
                        // A pause (slow_down) or a passing failure: it
                        // waits for the next try.
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

    // MARK: writing things down (build 26)
    //
    // Three kinds, none counted and none notified: a private entry on your
    // own photo, your reflection on the week, and the circle's question of
    // the week, sealed until Saturday and then read together.

    /// The circle on screen's question this week. Loaded when Today is
    /// (not on every refresh: it changes once a week, and opens once).
    func loadQuestion() async {
        guard let circleId = circle?.id else {
            question = nil
            return
        }
        do {
            let loaded: WeekQuestion = try await api.send("GET", "/circles/\(circleId)/prompt")
            guard circle?.id == circleId else { return }
            question = loaded
        } catch APIError.status(404) {
            // A server from before the question existed.
            question = nil
        } catch {
            // Keep what was showing; Today says if it's offline.
        }
    }

    /// Answer this week's question, once. True when it's in; the words stay
    /// in the field otherwise, with the reason said.
    func answerQuestion(_ text: String) async -> Bool {
        guard let circleId = circle?.id else { return false }
        do {
            let answered: WeekQuestion = try await api.send(
                "POST", "/circles/\(circleId)/prompt/respond", json: ["body": text]
            )
            Trail.note(.answeredQuestion)
            if circle?.id == circleId { question = answered }
            return true
        } catch {
            surface(error)
            // Already answered (on another phone), or closed: show it as it is.
            if case APIError.server = error { await loadQuestion() }
            return false
        }
    }

    /// Everyone's answers to this week's question, once they're out.
    func questionAnswers() async -> QuestionAnswers? {
        guard let circleId = circle?.id else { return nil }
        do {
            return try await api.send("GET", "/circles/\(circleId)/prompt/responses")
        } catch {
            missed(error)
            return nil
        }
    }

    /// A page of the circle journal: past weeks' questions and answers.
    func circleJournal(cursor: String?) async throws -> CircleJournalPage {
        guard let circleId = circle?.id else { return CircleJournalPage(prompts: [], nextCursor: nil) }
        var query: [String: String] = [:]
        if let cursor { query["cursor"] = cursor }
        return try await api.send("GET", "/circles/\(circleId)/prompts", query: query)
    }

    /// Your entry on your own photo, or nil when there isn't one.
    func journalEntry(_ photoId: String) async throws -> JournalEntry? {
        do {
            return try await api.send("GET", "/photos/\(photoId)/journal")
        } catch APIError.status(404) {
            return nil
        }
    }

    /// Write or rewrite your entry. True when it's kept; Today's book and
    /// Held's words follow.
    func writeJournal(_ photoId: String, _ body: String) async -> Bool {
        do {
            let _: JournalEntry = try await api.send("PUT", "/photos/\(photoId)/journal", json: ["body": body])
            Trail.note(.wroteJournal)
            if journalOffer == photoId { journalOffer = nil }
            await refreshToday()
            if memoriesLoaded { await refreshMemories() }
            return true
        } catch {
            surface(error)
            return false
        }
    }

    func deleteJournal(_ photoId: String) async -> Bool {
        do {
            let _: Empty = try await api.send("DELETE", "/photos/\(photoId)/journal")
            await refreshToday()
            if memoriesLoaded { await refreshMemories() }
            return true
        } catch {
            surface(error)
            return false
        }
    }

    /// The week a reflection would be about, asked for only while the
    /// evening for writing one is open (`ReflectionWindow`).
    func loadThisWeek() async {
        guard ReflectionWindow.isOpen() else {
            thisWeek = nil
            return
        }
        do {
            thisWeek = try await api.send(
                "GET", "/me/reflections/this-week", query: ["tz": TimeZone.current.identifier]
            )
        } catch APIError.status(404) {
            thisWeek = nil
        } catch {
            missed(error)
        }
    }

    /// Your reflections, from the newest.
    func loadReflections() async {
        do {
            let page: ReflectionsPage = try await api.send("GET", "/me/reflections")
            reflections = page.reflections
            reflectionsCursor = page.nextCursor
        } catch APIError.status(404) {
            reflections = []
            reflectionsCursor = nil
        } catch {
            missed(error)
        }
    }

    func loadMoreReflections() async {
        guard let cursor = reflectionsCursor, !loadingMoreReflections else { return }
        loadingMoreReflections = true
        defer { loadingMoreReflections = false }
        do {
            let page: ReflectionsPage = try await api.send("GET", "/me/reflections", query: ["cursor": cursor])
            guard reflectionsCursor == cursor else { return }
            let showing = Set(reflections.map(\.id))
            reflections += page.reflections.filter { !showing.contains($0.id) }
            reflectionsCursor = page.nextCursor
        } catch {
            missed(error)
        }
    }

    /// This week's reflection. True once it's in your journal.
    func writeReflection(_ body: String) async -> Bool {
        do {
            let _: Reflection = try await api.send(
                "POST", "/me/reflections", json: ["body": body, "tz": TimeZone.current.identifier]
            )
            Trail.note(.wroteReflection)
            await loadThisWeek()
            await loadReflections()
            return true
        } catch {
            surface(error)
            if case APIError.server(code: "already_reflected", status: _) = error {
                await loadThisWeek()
                await loadReflections()
            }
            return false
        }
    }

    func deleteReflection(_ reflection: Reflection) async {
        do {
            let _: Empty = try await api.send("DELETE", "/me/reflections/\(reflection.id)")
            reflections.removeAll { $0.id == reflection.id }
            if thisWeek?.reflection?.id == reflection.id { await loadThisWeek() }
        } catch {
            surface(error)
        }
    }

    // MARK: milestones (Part 4)

    func loadMilestones() async -> [Milestone] {
        do {
            return (try await api.send("GET", "/me/milestones") as MilestonesResponse).milestones
        } catch {
            missed(error)
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
                Trail.note(.letGo)
            } else {
                let _: Empty = try await api.send(
                    "POST", "/photos/\(photo.id)/anchor", json: ["note": nil]
                )
                Trail.note(.held)
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
            Trail.note(.held)
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
                Trail.note(.unliked)
            } else {
                let _: Empty = try await api.send("POST", "/photos/\(photo.id)/like")
                Trail.note(.liked)
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
            missed(error)
            return []
        }
    }

    /// Owner-only: who held this photo, as faces. Never a count (A2).
    func heldByFaces(_ photoId: String) async -> [HeldByEntry] {
        do {
            return (try await api.send("GET", "/photos/\(photoId)/anchors") as HeldByResponse).anchors
        } catch {
            missed(error)
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
            Trail.note(.addedStory)
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
    func report(
        photo: Photo? = nil, comment: Comment? = nil, answer: Answer? = nil, note: CommunityNote? = nil,
        reason: String
    ) async -> Bool {
        do {
            let _: Empty = try await api.send(
                "POST", "/reports",
                json: [
                    "photo_id": photo?.id, "comment_id": comment?.id, "response_id": answer?.id,
                    "note_id": note?.id, "reason": reason,
                ]
            )
            Trail.note(.reported)
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
            Trail.note(.blocked)
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
            Trail.note(.deletedPhoto)
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
            missed(error)
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
            Trail.note(.leftCircle)
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

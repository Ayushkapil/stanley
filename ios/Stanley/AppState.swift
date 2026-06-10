import Foundation
import Observation

@Observable
final class AppState {
    let api = APIClient()

    var signedIn: Bool
    var circle: CircleInfo?
    var feed: [Photo] = []
    var returned: ReturnedItem?
    var threads: [MemoryThread] = []
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
        feed = []
        returned = nil
        threads = []
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
            circle = try await api.send("POST", "/circles", json: ["name": name]) as CircleInfo
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
            circle = try await api.send(
                "POST", "/circles/\(parts[0])/join", json: ["invite_token": parts[1]]
            ) as CircleInfo
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
            let response: FeedResponse = try await api.send("GET", "/feed/today")
            feed = response.photos
            let returnedResponse: ReturnedResponse = try await api.send(
                "GET", "/feed/returned", query: ["tz": TimeZone.current.identifier]
            )
            returned = returnedResponse.item
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

    // MARK: gestures

    func capture(jpeg: Data, caption: String?) async throws {
        _ = try await api.uploadPhoto(jpeg: jpeg, caption: caption)
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
}

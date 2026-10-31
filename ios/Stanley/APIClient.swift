import Foundation
import os

enum APIError: LocalizedError {
    /// The server said no, and said why.
    case server(code: String, status: Int)
    /// The server said no without a code: a bare status, or a detail written
    /// for developers ("not found", "invalid token"). Never shown as sent.
    case status(Int)
    /// Our own words, already in Stanley's voice.
    case message(String)
    /// The server turned down the sign-in this request carried: it expired
    /// (thirty days), the server's secret changed, or the account is gone.
    /// Nothing works with that token again, so the app signs out on its own
    /// (`APIClient.onTokenRejected`) and says this once. It never asks
    /// anyone to find a Settings tab, which the gates before Today don't have.
    case signedOut

    var errorDescription: String? {
        switch self {
        case .server(let code, let status):
            // The product never shouts. Error copy stays gentle, and no code
            // or status number ever reaches the screen.
            switch code {
            case "slot_used": return "Today's photo is already given."
            case "too_soon": return "A little too soon — the day needs room to breathe."
            case "circle_full": return "This circle is full."
            case "already_in_circle": return "You're already part of a circle."
            case "no_circle": return "Join a circle first."
            case "faded": return "This moment has already faded."
            case "username_taken": return "That username is taken."
            case "bad_username": return "Usernames are 3–30 characters: lowercase letters, numbers, dots and underscores, and can't start with a number."
            case "bad_display_name": return "A name can't be empty."
            case "location_too_long": return "Keep the place name short."
            case "caption_too_long": return "That caption is longer than a photo can carry. Try it shorter."
            case "too_large": return "That photo is too large to send."
            case "bad_image": return "That photo couldn't be read. Try taking it again."
            case "upload_failed": return Self.photoNotPosted
            case "creator_only": return "Only the person who started the circle can do that."
            case "use_leave": return "To step away yourself, use Leave circle."
            case "empty_note": return "A note needs a few words."
            case "invalid_apple_token": return Self.appleSignInFailed
            case "apple_auth_unconfigured": return "Signing in isn't available right now. Try again a little later."
            default: return Self.words(forStatus: status)
            }
        case .status(let status):
            return Self.words(forStatus: status)
        case .message(let text):
            return text
        case .signedOut:
            return "Your sign-in has expired, so you've been signed out. Sign in again to carry on."
        }
    }

    /// When a server-side failure costs nothing: the server rolls the whole
    /// request back, so the day was never spent. Weak or no signal never lands
    /// here — that capture is kept on the phone and sent later.
    static let photoNotPosted = "That photo couldn't be posted, and today is still open. Try again in a moment."
    static let appleSignInFailed = "Sign in with Apple didn't go through. Try again."
    static let unreachable = "Couldn't reach Stanley. Check your connection and try again."

    /// What a bare status means to the person holding the phone.
    static func words(forStatus status: Int) -> String {
        switch status {
        // A 401 with a token becomes `.signedOut`. This is the rest: a request
        // that went out with no sign-in at all.
        case 401: return "You're signed out. Sign in again to carry on."
        case 403: return "That isn't yours to change."
        case 404: return "That's no longer here."
        case 410: return "This moment has already faded."
        case 413: return "That's too large to send."
        case 400, 422: return "That didn't go through. Check what you wrote and try again."
        default: return "Stanley is having trouble right now. Try again in a moment."
        }
    }
}

struct Empty: Codable {}

/// Safe to call from any thread. `AppState` sets the token on the main actor
/// while requests read it from whatever thread they run on, so the token
/// sits behind a lock. The base URL never changes after launch.
final class APIClient: Sendable {
    let baseURL: URL
    private let storedToken: OSAllocatedUnfairLock<String?>
    private let rejectedHandler = OSAllocatedUnfairLock<(@Sendable (String) -> Void)?>(initialState: nil)

    var token: String? {
        get { storedToken.withLock { $0 } }
        set {
            storedToken.withLock { $0 = newValue }
            if let newValue { KeychainToken.save(newValue) } else { KeychainToken.delete() }
        }
    }

    init() {
        self.baseURL = APIClient.resolveBaseURL()
        self.storedToken = OSAllocatedUnfairLock(initialState: KeychainToken.load())
    }

    /// Called, from whatever thread the request ran on, with the token the
    /// server just refused. It's the token the request carried, not the
    /// current one, so a late answer to a request sent before a fresh
    /// sign-in can be told apart and ignored.
    func onTokenRejected(_ handler: @escaping @Sendable (String) -> Void) {
        rejectedHandler.withLock { $0 = handler }
    }

    /// Base URL precedence: STANLEY_API env (debug runs) → Info.plist
    /// STANLEY_API_BASE (set per build config: release reads from the plist) →
    /// localhost as a debug-only fallback.
    private static func resolveBaseURL() -> URL {
        if let env = ProcessInfo.processInfo.environment["STANLEY_API"], let u = URL(string: env) {
            return u
        }
        if let s = Bundle.main.object(forInfoDictionaryKey: "STANLEY_API_BASE") as? String,
           !s.isEmpty, let u = URL(string: s) {
            return u
        }
        return URL(string: "http://127.0.0.1:8000")!
    }

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        decoder.dateDecodingStrategy = .custom { d in
            let s = try d.singleValueContainer().decode(String.self)
            if let date = fractional.date(from: s) ?? plain.date(from: s) { return date }
            throw DecodingError.dataCorrupted(
                .init(codingPath: d.codingPath, debugDescription: "bad date: \(s)")
            )
        }
        return decoder
    }()

    func absoluteURL(_ path: String) -> URL? {
        URL(string: path, relativeTo: baseURL)
    }

    @discardableResult
    func send<T: Decodable>(
        _ method: String,
        _ path: String,
        json: [String: Any?]? = nil,
        query: [String: String] = [:],
        headers: [String: String] = [:]
    ) async throws -> T {
        var components = URLComponents(
            url: baseURL.appending(path: path), resolvingAgainstBaseURL: false
        )!
        if !query.isEmpty {
            components.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        var request = URLRequest(url: components.url!)
        request.httpMethod = method
        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        for (name, value) in headers {
            request.setValue(value, forHTTPHeaderField: name)
        }
        if let json {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(
                withJSONObject: json.compactMapValues { $0 }
            )
        }
        return try await perform(request)
    }

    /// Capture upload (§8.4): multipart, in-app camera bytes only. Location is
    /// a typed place label — never GPS, which the server strips anyway.
    func uploadPhoto(
        jpeg: Data, caption: String?, location: String?, tagged: [String] = [], filter: String? = nil
    ) async throws -> Photo {
        let boundary = "stanley-\(UUID().uuidString)"
        var request = URLRequest(url: baseURL.appending(path: "/photos"))
        request.httpMethod = "POST"
        request.setValue(
            "multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type"
        )
        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        var body = Data()
        func append(_ s: String) { body.append(Data(s.utf8)) }
        func field(_ name: String, _ value: String) {
            append("--\(boundary)\r\n")
            append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n")
        }
        field("tz", TimeZone.current.identifier)
        field("taken_at_claim", ISO8601DateFormatter().string(from: Date()))
        if let caption, !caption.isEmpty { field("caption", caption) }
        if let location, !location.isEmpty { field("location", location) }
        for uid in tagged { field("tagged", uid) }  // repeated form fields
        // The filter's name only: the look is already in the JPEG below.
        if let filter { field("filter", filter) }
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"file\"; filename=\"photo.jpg\"\r\n")
        append("Content-Type: image/jpeg\r\n\r\n")
        body.append(jpeg)
        append("\r\n--\(boundary)--\r\n")
        request.httpBody = body
        return try await perform(request)
    }

    /// Avatar upload (Part 6): identity, not content. Multipart, like capture.
    func uploadAvatar(jpeg: Data) async throws -> AvatarResponse {
        let boundary = "stanley-\(UUID().uuidString)"
        var request = URLRequest(url: baseURL.appending(path: "/me/avatar"))
        request.httpMethod = "POST"
        request.setValue(
            "multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type"
        )
        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        var body = Data()
        body.append(Data("--\(boundary)\r\n".utf8))
        body.append(Data("Content-Disposition: form-data; name=\"file\"; filename=\"avatar.jpg\"\r\n".utf8))
        body.append(Data("Content-Type: image/jpeg\r\n\r\n".utf8))
        body.append(jpeg)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        request.httpBody = body
        return try await perform(request)
    }

    /// Raw authed GET, for the export zip (not JSON).
    func fetchData(_ path: String) async throws -> Data {
        var request = URLRequest(url: baseURL.appending(path: path))
        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            throw failure(for: request, data: data, status: status)
        }
        return data
    }

    private func perform<T: Decodable>(_ request: URLRequest) async throws -> T {
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            throw failure(for: request, data: data, status: status)
        }
        if T.self == Empty.self, data.isEmpty {
            return Empty() as! T
        }
        return try Self.decoder.decode(T.self, from: data)
    }

    /// What a failed request throws. A bare 401 on a request that carried a
    /// token means the server no longer accepts that token. Sign in with
    /// Apple's own refusal comes with a code, and a request sent with no token
    /// has nothing to reject, so neither counts.
    private func failure(for request: URLRequest, data: Data, status: Int) -> APIError {
        let error = Self.errorFrom(data: data, status: status)
        guard case .status(401) = error,
              let header = request.value(forHTTPHeaderField: "Authorization"),
              header.hasPrefix("Bearer ")
        else { return error }
        let sent = String(header.dropFirst("Bearer ".count))
        rejectedHandler.withLock { $0 }?(sent)
        return .signedOut
    }

    private static func errorFrom(data: Data, status: Int) -> APIError {
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let detail = obj["detail"] as? [String: Any], let code = detail["code"] as? String {
                return .server(code: code, status: status)
            }
        }
        return .status(status)
    }
}

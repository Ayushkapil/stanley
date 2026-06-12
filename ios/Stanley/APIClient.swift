import Foundation

enum APIError: LocalizedError {
    case server(code: String, status: Int)
    case message(String)

    var errorDescription: String? {
        switch self {
        case .server(let code, _):
            // The product never shouts. Error copy stays gentle.
            switch code {
            case "slot_used": return "Today's photo is already given."
            case "too_soon": return "A little too soon — the day needs room to breathe."
            case "circle_full": return "This circle is full."
            case "already_in_circle": return "You're already part of a circle."
            case "no_circle": return "Join a circle first."
            case "faded": return "This moment has already faded."
            case "username_taken": return "That username is taken."
            case "bad_username": return "Usernames are 3–30 characters: lowercase letters, numbers, dots, dashes."
            case "bad_display_name": return "A name can't be empty."
            case "location_too_long": return "Keep the place name short."
            default: return "Something went wrong (\(code))."
            }
        case .message(let text):
            return text
        }
    }
}

struct Empty: Codable {}

final class APIClient {
    let baseURL: URL
    var token: String? {
        didSet { UserDefaults.standard.set(token, forKey: "stanley.token") }
    }

    // TODO(pilot→release): move the token to the Keychain.
    init() {
        let env = ProcessInfo.processInfo.environment["STANLEY_API"]
        self.baseURL = URL(string: env ?? "http://127.0.0.1:8000")!
        self.token = UserDefaults.standard.string(forKey: "stanley.token")
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
        query: [String: String] = [:]
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
    func uploadPhoto(jpeg: Data, caption: String?, location: String?) async throws -> Photo {
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
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"file\"; filename=\"photo.jpg\"\r\n")
        append("Content-Type: image/jpeg\r\n\r\n")
        body.append(jpeg)
        append("\r\n--\(boundary)--\r\n")
        request.httpBody = body
        return try await perform(request)
    }

    private func perform<T: Decodable>(_ request: URLRequest) async throws -> T {
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            throw Self.errorFrom(data: data, status: status)
        }
        if T.self == Empty.self, data.isEmpty {
            return Empty() as! T
        }
        return try Self.decoder.decode(T.self, from: data)
    }

    private static func errorFrom(data: Data, status: Int) -> APIError {
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let detail = obj["detail"] as? [String: Any], let code = detail["code"] as? String {
                return .server(code: code, status: status)
            }
            if let detail = obj["detail"] as? String {
                return .message(detail)
            }
        }
        return .message("The server couldn't be reached (\(status)).")
    }
}

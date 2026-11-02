import SwiftUI
import UIKit

/// A picture behind one of Stanley's signed links (§9): every photo and every
/// face. It stands where `AsyncImage` stood, with two differences.
///
/// A link lasts fifteen minutes. A page left open longer than that holds
/// links that have run out, and a photo first scrolled to after that was
/// refused (403) and stayed a gray block for good. Now a refused link asks
/// for fresh ones (`AppState.linksExpired`), and the photo loads from the new
/// link the page is handed. A photo that failed for want of a connection
/// tries again when Stanley answers (`AppState.reloads`).
///
/// And a photo, once loaded, is kept in memory by what it is, its blob's
/// path, not by its link, which changes every time a page is fetched. So
/// fresh links don't send every photo on screen back to gray to download
/// again. A face isn't kept that way, because its path stays the same when
/// someone changes their photo; a face being re-fetched keeps showing until
/// the new one is in.
struct SignedImage<Content: View, Placeholder: View>: View {
    @Environment(AppState.self) private var state
    private let url: URL?
    private let content: (Image) -> Content
    private let placeholder: () -> Placeholder
    /// What's showing, and the path it came from.
    @State private var shown: (path: String, image: UIImage)?
    /// Fresh links asked for on this picture's behalf. A link that's
    /// refused again once renewed isn't running out; asking forever would
    /// only fetch every page every half minute.
    @State private var renewals = 0

    init(
        url: URL?,
        @ViewBuilder content: @escaping (Image) -> Content,
        @ViewBuilder placeholder: @escaping () -> Placeholder
    ) {
        self.url = url
        self.content = content
        self.placeholder = placeholder
    }

    var body: some View {
        Group {
            if let shown, shown.path == url?.path {
                content(Image(uiImage: shown.image))
            } else {
                placeholder()
            }
        }
        // A new link, or Stanley reachable again, is another try.
        .task(id: Attempt(url: url, reloads: state.reloads)) { await load() }
    }

    private struct Attempt: Equatable {
        let url: URL?
        let reloads: Int
    }

    private func load() async {
        guard let url else { return }
        if let kept = PhotoMemory.image(for: url) {
            shown = (url.path, kept)
            return
        }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if status == 403 {
                // The link ran out. Fresh ones are on their way; the page
                // hands this view one and it tries again.
                if renewals < 2 {
                    renewals += 1
                    state.linksExpired()
                }
                return
            }
            guard (200..<300).contains(status),
                  let image = await UIImage(data: data)?.byPreparingForDisplay()
            else { return }
            PhotoMemory.keep(image, for: url)
            shown = (url.path, image)
        } catch {
            if isOffline(error) { state.lostConnection() }
        }
    }
}

/// Photos already seen this session, by blob path, so a photo is downloaded
/// once however often its link is renewed. Faces are left out (see
/// `SignedImage`). An `NSCache`, so memory pressure empties it.
enum PhotoMemory {
    private static let cache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.totalCostLimit = 120 * 1024 * 1024
        return cache
    }()

    private static func key(_ url: URL) -> NSString? {
        url.path.contains("/avatars/") ? nil : url.path as NSString
    }

    static func image(for url: URL) -> UIImage? {
        key(url).flatMap { cache.object(forKey: $0) }
    }

    static func keep(_ image: UIImage, for url: URL) {
        guard let key = key(url) else { return }
        let pixels = image.size.width * image.size.height * image.scale * image.scale
        cache.setObject(image, forKey: key, cost: Int(pixels) * 4)
    }
}

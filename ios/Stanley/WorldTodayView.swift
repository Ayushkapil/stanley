import SafariServices
import SwiftUI
import UIKit

/// The World Today: twelve headlines at the very foot of Today, below every
/// photo and the note. Meant to be a morning paper on the counter, not a feed.
///
/// It is quieter than anything the circle made: smaller type, a card at half
/// the weight, and no images, so the eye lands on the photos first. There is
/// nothing to do to a headline but read it. There is no like, save, share or
/// comment, by construction, and news never reaches Held, Returned or a
/// notification. With nothing to show (no key on the server, a failed fetch,
/// a stale set), the section isn't drawn at all. No empty state, no error.
struct WorldTodaySection: View {
    let articles: [NewsArticle]
    @State private var reading: NewsArticle?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider()
                .padding(.bottom, 6)
            VStack(alignment: .leading, spacing: 2) {
                Text("The World Today")
                    .font(.headline)
                Text("What's happening nearby")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 4)
            .padding(.bottom, 2)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            ForEach(articles) { article in
                NewsCard(article: article) { reading = article }
            }
        }
        .sheet(item: $reading) { article in
            if let link = article.link {
                SafariSheet(url: link) { reading = nil }
                    .ignoresSafeArea()
            }
        }
    }
}

/// One headline: the headline itself, where it's from and when, and the
/// short summary. Tapping it opens the source.
private struct NewsCard: View {
    @Environment(\.horizontalSizeClass) private var hSizeClass
    private var density: Density { Density(hSizeClass) }
    let article: NewsArticle
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            VStack(alignment: .leading, spacing: 4) {
                Text(article.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Text(byline)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if let summary = article.summary {
                    Text(summary)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .padding(.top, 2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(density.cardPadding)
            .cardSurface(corner: density.cardCorner - 4, muted: true)
            .contentShape(RoundedRectangle(cornerRadius: density.cardCorner - 4))
        }
        .buttonStyle(.plain)
        .disabled(article.link == nil)
        .accessibilityHint("Opens the article")
    }

    /// "Outlet · 2 hr. ago". This is a time, never a tally. It is formatted
    /// once and doesn't tick, because a live clock would read as a countdown.
    private var byline: String {
        guard let published = article.publishedAt else { return article.source }
        let ago = min(published, Date())
            .formatted(.relative(presentation: .named, unitsStyle: .abbreviated))
        return "\(article.source) · \(ago)"
    }
}

/// An in-app Safari sheet in the atmosphere's accent. Stanley never learns
/// which article was opened.
struct SafariSheet: UIViewControllerRepresentable {
    @AppStorage("stanley.atmosphere") private var raw = "auto"
    let url: URL
    let onDone: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onDone: onDone) }

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let safari = SFSafariViewController(url: url)
        safari.dismissButtonStyle = .close
        safari.preferredControlTintColor = UIColor(Atmosphere.resolve(raw).palette.accent)
        safari.delegate = context.coordinator
        return safari
    }

    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}

    /// Safari's own Close button dismisses from inside UIKit. Clearing the
    /// binding here as well lets SwiftUI know the sheet is gone, so the next
    /// tap opens a new one.
    final class Coordinator: NSObject, SFSafariViewControllerDelegate {
        let onDone: () -> Void
        init(onDone: @escaping () -> Void) { self.onDone = onDone }
        func safariViewControllerDidFinish(_ controller: SFSafariViewController) { onDone() }
    }
}

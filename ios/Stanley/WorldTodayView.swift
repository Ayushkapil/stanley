import SafariServices
import SwiftUI
import UIKit

/// The World Today, as it sits in Today: one quiet card at the very foot,
/// below every photo and the note. It's an invitation, not a module. The
/// stories themselves live a tap away, in their own sheet, so the circle's
/// day is all that Today shows.
///
/// The card is quieter than anything the circle made: a half-weight card,
/// small type and no images, so the eye lands on the photos first. With
/// nothing to show (no key on the server, a failed fetch, a stale set), the
/// card isn't drawn at all. No empty state, no error.
struct WorldTodayCard: View {
    @Environment(\.horizontalSizeClass) private var hSizeClass
    private var density: Density { Density(hSizeClass) }
    let articles: [NewsArticle]
    @State private var showingAll = false

    var body: some View {
        Button { showingAll = true } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    Image(systemName: "newspaper")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("The World Today")
                            .font(.subheadline.weight(.semibold))
                        Text("What's happening nearby")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                if let first = articles.first {
                    Text(first.title)
                        .font(.footnote)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                HStack(spacing: 4) {
                    Text(WorldToday.seeAll(articles.count))
                    Image(systemName: "chevron.right")
                        .imageScale(.small)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(density.cardPadding)
            .cardSurface(corner: density.cardCorner, muted: true)
            .contentShape(RoundedRectangle(cornerRadius: density.cardCorner))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens today's stories")
        .sheet(isPresented: $showingAll) {
            WorldTodaySheet(articles: articles)
        }
    }
}

/// All of today's stories, and the end of them: a finite list with no
/// "load more", no pagination, and nothing to do to a story but read it.
/// There is no like, save, share or comment, by construction, and news never
/// reaches Held, Returned or a notification.
struct WorldTodaySheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var hSizeClass
    private var density: Density { Density(hSizeClass) }
    let articles: [NewsArticle]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    Text(WorldToday.subtitle(articles.count))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                        .padding(.bottom, 4)
                    ForEach(articles) { article in
                        NewsCard(article: article)
                    }
                }
                .padding()
                .readableWidth(density)
            }
            .atmosphereWash()
            .navigationTitle("The World Today")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

/// The two lines that name the set. The number is the edition's size, the
/// actual one, so it's never "12" when fewer came back. It isn't a tally of
/// anyone's activity.
enum WorldToday {
    static func seeAll(_ count: Int) -> String {
        count == 1 ? "Read the story" : "See all \(count) stories"
    }

    static func subtitle(_ count: Int) -> String {
        "\(count) \(count == 1 ? "story" : "stories"), refreshed every half hour"
    }
}

/// One story in the sheet: the headline, where it's from and when, and the
/// short summary. Tapping it opens the source.
private struct NewsCard: View {
    @Environment(\.horizontalSizeClass) private var hSizeClass
    private var density: Density { Density(hSizeClass) }
    let article: NewsArticle

    var body: some View {
        Button {
            if let link = article.link { StoryReader.open(link) }
        } label: {
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
            .cardSurface(corner: density.cardCorner - 4)
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

/// Opens a story in Safari, tinted with the atmosphere's accent. Stanley never
/// learns which story was opened.
///
/// UIKit presents it, over whatever is on top, instead of a SwiftUI sheet.
/// Safari's Close button dismisses from inside UIKit. As a SwiftUI sheet, the
/// binding needed a second dismissal to stay in step, and inside the stories
/// sheet that second dismissal closed the stories as well. Presented this way,
/// Close only ever closes Safari.
@MainActor
enum StoryReader {
    static func open(_ url: URL) {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        guard var top = scene?.keyWindow?.rootViewController else { return }
        while let presented = top.presentedViewController { top = presented }
        let raw = UserDefaults.standard.string(forKey: "stanley.atmosphere") ?? "auto"
        let safari = SFSafariViewController(url: url)
        safari.dismissButtonStyle = .close
        safari.preferredControlTintColor = UIColor(Atmosphere.resolve(raw).palette.accent)
        safari.modalPresentationStyle = .pageSheet
        top.present(safari, animated: true)
    }
}

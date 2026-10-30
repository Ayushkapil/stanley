import SafariServices
import SwiftUI
import UIKit

/// The World tab: all of today's stories, and the end of them. A finite list
/// with no "load more", no pagination, and nothing to do to a story but read
/// it. There is no like, save, share or comment, by construction, and news
/// never reaches Today, Held, Returned or a notification.
///
/// It loads when the tab appears and on pull, never on a timer, so headlines
/// don't shift under someone reading them. With nothing to show (no key on
/// the server, a failed fetch, a stale set) it says so in one quiet line.
struct WorldTodayView: View {
    @Environment(AppState.self) private var state
    @Environment(\.horizontalSizeClass) private var hSizeClass
    private var density: Density { Density(hSizeClass) }
    /// Whether the first answer is in, so the empty line doesn't flash up
    /// before the stories arrive.
    @State private var asked = false

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    if !state.news.isEmpty {
                        Text(subtitle)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 4)
                            .padding(.bottom, 4)
                        ForEach(state.news) { article in
                            NewsCard(article: article)
                        }
                    } else if asked {
                        Text("No stories right now.")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 80)
                    }
                }
                .padding()
                .readableWidth(density)
            }
            .atmosphereWash()
            .navigationTitle("The World Today")
            .refreshable { await state.loadNews() }
            .task {
                await state.loadNews()
                asked = true
            }
        }
    }

    /// The number is the edition's size, the actual one, so it's never "12"
    /// when fewer came back. It isn't a tally of anyone's activity.
    private var subtitle: String {
        let count = state.news.count
        return "\(count) \(count == 1 ? "story" : "stories"), refreshed every half hour"
    }
}

/// One story: the headline, where it's from and when, and the short summary.
/// Tapping it opens the source.
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
/// Safari's Close button dismisses from inside UIKit, and a sheet's binding
/// then needed a second dismissal to stay in step, which closed whatever sat
/// beneath Safari as well. Presented this way, Close only ever closes Safari.
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

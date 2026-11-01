import SafariServices
import SwiftUI
import UIKit

/// The World tab: today's stories, and the end of them. A finite list with
/// no "load more", no pagination, and nothing to do to a story but read it.
/// There is no like, save, share or comment, by construction, and news never
/// reaches Today, Held, Returned or a notification.
///
/// Two editions. With location allowed, the town's own headlines come first
/// ("Near Bloomington"), then the national stories, each with the summary it
/// was published with. The two look different on purpose (build 18): a story
/// with a summary has it beneath the headline, to read right there, and a
/// link to the whole piece; a local story has only a headline (its feed
/// carries no summary), so it's the headline, the source and "Read more",
/// with no empty space where a summary would be.
///
/// It loads when the tab appears and on pull, never on a timer, so stories
/// don't shift under someone reading them. With nothing to show (news off on
/// the server, a failed fetch, a stale set) it says so in one quiet line.
struct WorldTodayView: View {
    @Environment(AppState.self) private var state
    @Environment(\.horizontalSizeClass) private var hSizeClass
    private var density: Density { Density(hSizeClass) }
    /// Whether the first answer is in, so the empty line doesn't flash up
    /// before the stories arrive.
    @State private var asked = false
    @AppStorage("stanley.nearbyNews.notNow") private var notNow = false

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    if state.whereabouts.undecided && !notNow {
                        NearbyInvitation(notNow: $notNow) {
                            Task {
                                await state.whereabouts.ask()
                                await state.loadNews()
                            }
                        }
                        .padding(.bottom, 14)
                    }
                    if !state.nearby.isEmpty {
                        header(
                            "Near \(state.nearbyTown ?? "you")",
                            "Local headlines, refreshed every half hour"
                        )
                        stories(state.nearby)
                    }
                    if !state.news.isEmpty {
                        header(state.nearby.isEmpty ? nil : "The day's news", subtitle)
                            .padding(.top, state.nearby.isEmpty ? 0 : 18)
                        stories(state.news)
                    } else if asked && state.nearby.isEmpty {
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
            .refreshable {
                // Its own task: SwiftUI cancels a refresh's task as soon as
                // the state it refreshes changes.
                await Task { await state.loadNews() }.value
            }
            .task {
                await state.loadNews()
                asked = true
            }
        }
    }

    private func header(_ title: String?, _ line: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            if let title {
                Text(title).font(.title3.weight(.semibold))
            }
            Text(line)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 4)
        .padding(.bottom, 4)
    }

    private func stories(_ articles: [NewsArticle]) -> some View {
        ForEach(articles) { article in
            NewsCard(article: article)
        }
    }

    /// The number is the edition's size, the actual one, so it's never "12"
    /// when fewer came back. It isn't a tally of anyone's activity. The
    /// outlet is named when one outlet wrote them all, as PBS does.
    private var subtitle: String {
        let count = state.news.count
        let stories = "\(count) \(count == 1 ? "story" : "stories")"
        let outlets = Set(state.news.map(\.source))
        let from = outlets.count == 1 ? " from \(outlets.first!)" : ""
        return "\(stories)\(from), refreshed every half hour"
    }
}

/// One story. With a summary: the headline, where it's from and when, the
/// summary beneath it, and "Read full article". Without one: the headline,
/// the source line, and "Read more", and the whole card opens the story.
/// Either way the full piece opens in Safari, in Stanley.
private struct NewsCard: View {
    @Environment(\.horizontalSizeClass) private var hSizeClass
    private var density: Density { Density(hSizeClass) }
    let article: NewsArticle

    private var summary: String? {
        article.summary?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }

    var body: some View {
        Group {
            if summary == nil, let link = article.link {
                // Headline only: the card is the link.
                Button { StoryReader.open(link) } label: { content }
                    .buttonStyle(.plain)
                    .accessibilityHint("Opens the story in Safari")
            } else {
                content
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(density.cardPadding)
        .cardSurface(corner: density.cardCorner - 4)
        .clipShape(RoundedRectangle(cornerRadius: density.cardCorner - 4))
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(article.title)
                .font(.subheadline.weight(.semibold))
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            Text(byline)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .padding(.top, 4)
            if let summary {
                Text(summary)
                    .font(.callout)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 10)
            }
            if let link = article.link {
                Button {
                    StoryReader.open(link)
                } label: {
                    Label(summary == nil ? "Read more" : "Read full article", systemImage: "arrow.up.right")
                        .labelStyle(TrailingIcon())
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Opens in Safari")
                .padding(.top, 10)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
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

/// "Read full article ↗": the word first, the arrow after it.
private struct TrailingIcon: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.title
            configuration.icon.imageScale(.small)
        }
    }
}

/// Asked once, at the top of the World tab, before the system's own sheet:
/// what location is for and what leaves the phone. "Not now" puts it away
/// for good; capture asks again in its own moment, after the shutter.
private struct NearbyInvitation: View {
    @Environment(\.horizontalSizeClass) private var hSizeClass
    private var density: Density { Density(hSizeClass) }
    @AppStorage("stanley.atmosphere") private var raw = "auto"
    @Binding var notNow: Bool
    let allow: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("News from near you", systemImage: "location")
                .font(.subheadline.weight(.semibold))
            Text("Allow location and the headlines from the town you're in appear here too. Stanley only ever sends the town's name.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 16) {
                Button(action: allow) {
                    Text("Allow location")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Atmosphere.resolve(raw).palette.ink)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Atmosphere.resolve(raw).palette.accent, in: Capsule())
                }
                .buttonStyle(.plain)
                Button("Not now") {
                    withAnimation { notNow = true }
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
                .buttonStyle(.plain)
            }
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(density.cardPadding)
        .cardSurface(corner: density.cardCorner - 4)
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

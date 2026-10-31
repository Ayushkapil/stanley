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
/// was published with. A story opens in place: tap it and the summary is
/// there to read without leaving Stanley, with a link to the full piece for
/// anyone who wants it.
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
    /// The stories opened to their summaries. Several can be open at once.
    @State private var open: Set<String> = []
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
            NewsCard(article: article, open: Binding(
                get: { open.contains(article.id) },
                set: { if $0 { open.insert(article.id) } else { open.remove(article.id) } }
            ))
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

/// One story. Closed, it's the headline, where it's from and when. Open, the
/// headline in full, the summary, and a quiet link to the whole piece in
/// Safari. A local headline has no summary (its feed carries none), so open
/// it is the headline and the link.
private struct NewsCard: View {
    @Environment(\.horizontalSizeClass) private var hSizeClass
    private var density: Density { Density(hSizeClass) }
    let article: NewsArticle
    @Binding var open: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.25)) { open.toggle() }
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(article.title)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(open ? nil : 2)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: open)
                        Text(byline)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(open ? 180 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(open ? "Hides the summary" : "Shows the summary")

            if open {
                VStack(alignment: .leading, spacing: 12) {
                    if let summary = article.summary {
                        Text(summary)
                            .font(.callout)
                            .lineSpacing(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let link = article.link {
                        Button {
                            StoryReader.open(link)
                        } label: {
                            Label("Read full article", systemImage: "arrow.up.right")
                                .labelStyle(TrailingIcon())
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(Color.accentColor)
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Opens in Safari")
                    }
                }
                .padding(.top, 12)
                .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(density.cardPadding)
        .cardSurface(corner: density.cardCorner - 4)
        .clipShape(RoundedRectangle(cornerRadius: density.cardCorner - 4))
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

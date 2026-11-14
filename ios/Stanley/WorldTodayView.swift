import SafariServices
import SwiftUI
import UIKit

/// The World tab: the morning paper (build 19). A finite page with no "load
/// more", no pagination, and nothing to do to a story but read it. There is
/// no like, save, share or comment, by construction, and news never reaches
/// Today, Held, Returned or a notification.
///
/// It's laid out as a newspaper page, not a list of cards: a serif masthead
/// with the day's dateline between rules, the lead story across the full
/// width, then the rest in columns divided by thin rules, and the town's own
/// headlines under their own head ("Near Bloomington"). No card backgrounds,
/// just ink on the page. This is the one place in Stanley set in a serif
/// (New York, the system's): it marks the paper as apart from the journal.
///
/// A story with a summary (PBS, the BBC) has it beneath its headline, to read
/// right there, and "Read full article"; a local story has only a headline
/// (its feed carries no summary), so it's the headline, the source and "Read
/// more", with no space left for a summary. Tapping a story opens it in
/// Safari, in Stanley.
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
          ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Masthead(edition: edition)
                        .id("masthead")
                    if state.whereabouts.undecided && !notNow {
                        NearbyInvitation(notNow: $notNow) {
                            Task {
                                await state.whereabouts.ask()
                                await state.loadNews()
                            }
                        }
                        .padding(.top, 18)
                    }
                    if let lead = state.news.first {
                        LeadStory(article: lead)
                            .padding(.top, 22)
                        if state.news.count > 1 {
                            Rule(weight: 0.5)
                                .padding(.vertical, 20)
                            NewsColumns(articles: Array(state.news.dropFirst()))
                        }
                    }
                    if !state.nearby.isEmpty {
                        SectionHead(title: "Near \(state.nearbyTown ?? "you")")
                            .padding(.top, state.news.isEmpty ? 22 : 34)
                            .padding(.bottom, 16)
                        NewsColumns(articles: state.nearby)
                    }
                    if asked && state.news.isEmpty && state.nearby.isEmpty {
                        Text(state.offline ? "The paper comes when you're back online." : "No stories right now.")
                            .font(.system(.body, design: .serif).italic())
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 80)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 6)
                // The same room above the tab bar as every page.
                .padding(.bottom, Spacing.chapter)
                .readableWidth(density)
            }
            // A tap on the World tab: back to the top, or at the top the
            // pull's own refresh (`TabTaps`).
            .onTabTap(state.tabTaps.world, scroll: proxy, to: "masthead") {
                await state.loadNews()
            }
            // The paper, no navigation bar, and a strip of the page under the
            // status bar so the paper slides beneath the clock (`Journal.swift`).
            // The paper keeps its grain (the one page that does, build 44:
            // the newspaper stays as it was), under the page's own floor.
            .background { PaperGrainView(strength: 0.45).ignoresSafeArea() }
            .journalPage()
            .sunRefreshable {
                Haptics.refreshed()
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
    }

    /// Who the paper is from, for the right of the dateline: the outlet when
    /// one wrote it all, as PBS does, else simply today's edition.
    private var edition: String {
        let outlets = Set(state.news.map(\.source))
        return outlets.count == 1 ? outlets.first! : "Today's edition"
    }
}

/// "The World Today" in a heavy serif, its publisher's line in small italic
/// under it ("By Stanley", build 22), then the day's date and the outlet in
/// small capitals between rules, the way a front page opens.
private struct Masthead: View {
    let edition: String
    // The paper's small type follows Dynamic Type (the HCI audit, build 32).
    @ScaledMetric(relativeTo: .caption2) private var dateline: CGFloat = 10
    @ScaledMetric(relativeTo: .caption) private var publisher: CGFloat = 12

    var body: some View {
        VStack(spacing: 7) {
            Text("The World Today")
                .font(.system(size: 38, weight: .black, design: .serif))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(maxWidth: .infinity)
                .accessibilityAddTraits(.isHeader)
            Text("By Stanley")
                .font(.system(size: publisher, design: .serif).italic())
                .foregroundStyle(.secondary)
                .padding(.top, -3)
            VStack(spacing: 2) {
                Rule(weight: 1.5)
                Rule(weight: 0.5)
            }
            HStack {
                Text(Date.now.formatted(.dateTime.weekday(.wide).month(.wide).day().year()))
                Spacer(minLength: 12)
                Text(edition)
            }
            .font(.system(size: dateline, weight: .semibold))
            .tracking(1.1)
            .textCase(.uppercase)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .foregroundStyle(.secondary)
            OfflineLine()
                .frame(maxWidth: .infinity, alignment: .leading)
            Rule(weight: 0.5)
        }
        .padding(.top, 8)
        // Room under the rule before the page begins (build 22).
        .padding(.bottom, 10)
    }
}

/// A section's head: its name in italic between rules.
private struct SectionHead: View {
    let title: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Rule(weight: 1.5)
            Text(title)
                .font(.system(.title3, design: .serif).italic())
                .accessibilityAddTraits(.isHeader)
            Rule(weight: 0.5)
        }
    }
}

/// The front-page story: the first of the day's, across the full width, its
/// headline large, then where it's from, then its summary to read right there.
private struct LeadStory: View {
    let article: NewsArticle

    var body: some View {
        StoryBlock(article: article) {
            VStack(alignment: .leading, spacing: 10) {
                Text(article.title)
                    .font(.system(.title, design: .serif, weight: .bold))
                    .fixedSize(horizontal: false, vertical: true)
                Byline(article: article)
                if let summary = article.trimmedSummary {
                    Text(summary)
                        .font(.system(.body, design: .serif))
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                }
                ReadOn(article: article)
            }
        }
    }
}

/// The rest of the stories in columns, the way a page runs: down the first
/// column, then down the next, each split where the page is about half
/// full, so the columns end near each other. Two on a phone, three on the
/// Duo's inner display. Thin rules between stories and between columns.
private struct NewsColumns: View {
    @Environment(\.horizontalSizeClass) private var hSizeClass
    let articles: [NewsArticle]

    private static let gutter: CGFloat = 24

    var body: some View {
        let count = Density(hSizeClass).isRoom ? 3 : 2
        let columns = Self.split(articles, into: min(count, max(1, articles.count)))
        HStack(alignment: .top, spacing: Self.gutter) {
            ForEach(columns.indices, id: \.self) { index in
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(columns[index].enumerated()), id: \.element.id) { position, article in
                        if position > 0 {
                            Rule(weight: 0.5).padding(.vertical, 14)
                        }
                        ColumnStory(article: article)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
        // The rules between columns run the height of the tallest one.
        .background {
            GeometryReader { geo in
                let n = CGFloat(columns.count)
                let width = (geo.size.width - Self.gutter * (n - 1)) / n
                ForEach(1..<max(columns.count, 1), id: \.self) { i in
                    Rectangle()
                        .fill(DarkRoom.line(0.3))
                        .frame(width: 0.5, height: geo.size.height)
                        .position(x: (width + Self.gutter) * CGFloat(i) - Self.gutter / 2, y: geo.size.height / 2)
                }
            }
        }
    }

    /// In reading order, a new column begins once the page so far holds its
    /// share of the words. Rough by design: a story's length is its
    /// headline, its summary and a little for its byline.
    static func split(_ articles: [NewsArticle], into count: Int) -> [[NewsArticle]] {
        guard count > 1 else { return [articles] }
        func weight(_ a: NewsArticle) -> Double {
            60 + Double(a.title.count) * 1.6 + Double(a.trimmedSummary?.count ?? 0)
        }
        let total = articles.map(weight).reduce(0, +)
        var columns = Array(repeating: [NewsArticle](), count: count)
        var sofar = 0.0
        var column = 0
        for article in articles {
            if column < count - 1, !columns[column].isEmpty, sofar >= total * Double(column + 1) / Double(count) {
                column += 1
            }
            columns[column].append(article)
            sofar += weight(article)
        }
        return columns.filter { !$0.isEmpty }
    }
}

/// One story in a column: the headline in bold serif, where it's from, and
/// the summary when there is one.
private struct ColumnStory: View {
    let article: NewsArticle

    var body: some View {
        StoryBlock(article: article) {
            VStack(alignment: .leading, spacing: 6) {
                Text(article.title)
                    .font(.system(.subheadline, design: .serif, weight: .bold))
                    .fixedSize(horizontal: false, vertical: true)
                Byline(article: article)
                if let summary = article.trimmedSummary {
                    Text(summary)
                        .font(.system(.footnote, design: .serif))
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 2)
                }
                ReadOn(article: article)
            }
        }
    }
}

/// A story is tappable as a whole when it has a link, and opens in Safari.
private struct StoryBlock<Content: View>: View {
    let article: NewsArticle
    @ViewBuilder let content: () -> Content

    var body: some View {
        if let link = article.link {
            Button { StoryReader.open(link) } label: {
                content()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens the story in Safari")
        } else {
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// "PBS NEWS HOUR · 2 HR. AGO", in small capitals. This is a time, never a
/// tally. It is formatted once and doesn't tick, because a live clock would
/// read as a countdown.
private struct Byline: View {
    let article: NewsArticle
    @ScaledMetric(relativeTo: .caption2) private var size: CGFloat = 10

    var body: some View {
        Text(line)
            .font(.system(size: size, weight: .semibold))
            .tracking(0.8)
            .textCase(.uppercase)
            .foregroundStyle(.secondary)
            .lineLimit(2)
    }

    private var line: String {
        guard let published = article.publishedAt else { return article.source }
        let ago = min(published, Date())
            .formatted(.relative(presentation: .named, unitsStyle: .abbreviated))
        return "\(article.source) · \(ago)"
    }
}

/// "Read full article ↗" under a story with a summary, "Read more ↗" under a
/// headline alone, in a small italic.
private struct ReadOn: View {
    let article: NewsArticle

    var body: some View {
        if article.link != nil {
            Text("\(article.trimmedSummary == nil ? "Read more" : "Read full article") \(Image(systemName: "arrow.up.right"))")
                .font(.system(.footnote, design: .serif).italic())
                .foregroundStyle(Color.accentColor)
                .padding(.top, 2)
        }
    }
}

private extension NewsArticle {
    var trimmedSummary: String? {
        summary?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }
}

/// Asked once, at the top of the World tab, before the system's own sheet:
/// what location is for and what leaves the phone. "Not now" puts it away
/// for good; capture asks again in its own moment, after the shutter.
private struct NearbyInvitation: View {
    @AppStorage("stanley.atmosphere") private var raw = "auto"
    @Binding var notNow: Bool
    let allow: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("News from near you")
                .font(.system(.subheadline, design: .serif, weight: .bold))
            Text("Allow location and the headlines from the town you're in appear here too. Stanley only ever sends the town's name.")
                .font(.system(.footnote, design: .serif))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 16) {
                Button(action: allow) {
                    Text("Allow location")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Atmosphere.resolve(raw).palette.ink)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
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
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        // A notice to readers, boxed in a rule, not a card.
        .overlay(Rectangle().strokeBorder(DarkRoom.line(0.3), lineWidth: 0.5))
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

import Photos
import SwiftUI
import UIKit

/// Today, as a shared journal rather than a feed (build 17). The circle's
/// name is the journal's, atop the page, and opens the others; the note is a
/// sticky note on the first page; each day is a page with its own mark; and
/// each photo is a print, the poster's name written small in its corner,
/// with the words beneath it. Still reverse-chronological and nothing else.
struct TodayFeedView: View {
    @Environment(AppState.self) private var state
    /// The capture sheet is up.
    @Binding var capturing: Bool
    /// The tab bar's dock, when it stands down the side of the screen (the
    /// iPhone Duo's cover display). Nil on an ordinary iPhone. Read here,
    /// inside the tab bar controller, for `HomeView`.
    @Binding var sideDock: CGRect?
    @State private var joiningAnother = false
    @State private var readingCircleJournal = false
    @Environment(\.horizontalSizeClass) private var hSizeClass
    private var density: Density { Density(hSizeClass) }
    /// The entry at the top of the viewport, by id. Folding or unfolding
    /// changes every photo's height, so a raw content offset would land on a
    /// different entry after the reflow; anchoring to the entry itself means
    /// the thing you were looking at is still the thing you are looking at.
    /// No `scrollTargetBehavior`, so scrolling itself feels exactly as before.
    @State private var anchor: String?

    var body: some View {
        NavigationStack {
          ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                  // Each entry is its own scroll target, full width, with the
                  // page's margins inside it (the Group gives every child the
                  // same padding and column). With the margins outside,
                  // restoring the place (keyboard up for a story, Today
                  // refreshing under a sheet) lined an entry's leading edge up
                  // with the screen's and slid the page 20pt sideways.
                  Group {
                    // The journal's cover line, the way the paper opens: the
                    // circle's name (which opens the others), a double rule
                    // and the day in small capitals.
                    TodayMasthead(
                        onJoinAnother: { joiningAnother = true },
                        onCircleJournal: { readingCircleJournal = true },
                        onCapture: { capturing = true }
                    )
                    .padding(.bottom, Spacing.section)
                    .id("masthead")
                    // The board is the circle talking to itself, so it goes
                    // first, above even the mosaic: everyone's sticky note
                    // for the day, pinned to the first page (build 27).
                    NoteBoard()
                        .padding(.bottom, Spacing.section)
                        .id("note")
                    // The circle's question of the week (build 26): a slip
                    // under the note, above the photos.
                    if let question = state.question {
                        QuestionSlip(question: question)
                            .padding(.bottom, Spacing.section)
                            .id("question")
                    }
                    // Letters to the circle (build 42), in the question's
                    // place on the page: last month's while they're open,
                    // and this month's to write.
                    if let letters = state.circleLetters, letters.revealed != nil || letters.open {
                        CircleLetterCards(letters: letters)
                            .padding(.bottom, Spacing.section)
                            .id("letters")
                    }
                    // The weekly mosaic sits above the days themselves
                    // (Part 2), Sun/Mon only.
                    if let mosaic = state.mosaic {
                        MosaicCard(mosaic: mosaic)
                            .padding(.bottom, Spacing.section)
                            .id("mosaic")
                    }
                    // Returned sits above the circle's own pages, set apart.
                    if let item = state.returned {
                        ReturnedCard(item: item)
                            .padding(.bottom, Spacing.section)
                            .id("returned")
                    }
                    if let pending = state.pendingHere {
                        PendingCaptureCard(pending: pending)
                            .padding(.bottom, Spacing.section)
                            .id("pending")
                    }
                    // Nothing posted in this circle in six days, or ever: a
                    // note tucked into the page and the camera under it. Only
                    // once Today has answered, so it doesn't flash up while
                    // the photos are on their way, and not while a capture
                    // waits to go up, which has its own card.
                    if state.todayLoaded && state.feedItems.isEmpty && state.pendingHere == nil {
                        TodayEmptyPage { capturing = true }
                            .id("empty")
                    }
                    // Before Today's first answer: the shapes of the page,
                    // shimmering, where its prints will be (build 39).
                    if !state.todayLoaded && state.feedItems.isEmpty && !state.offline {
                        TodaySkeleton()
                            .id("skeleton")
                            .transition(.opacity)
                    }
                    ForEach(Array(JournalDay.group(state.feedItems).enumerated()), id: \.element.id) { index, day in
                        DayMark(date: day.date)
                            .padding(.top, index == 0 ? 0 : Spacing.chapter)
                            .padding(.bottom, Spacing.section)
                            .id("day:\(day.id.timeIntervalSince1970)")
                        // Entries carry their FeedItem id (a String, like the
                        // ids above), so one binding anchors to any of them.
                        // A day's entries are divided by room, not a rule
                        // (build 44): the photos do the dividing.
                        ForEach(Array(day.items.enumerated()), id: \.element.id) { position, item in
                            VStack(alignment: .leading, spacing: 0) {
                                if position > 0 {
                                    Color.clear.frame(height: Spacing.chapter - 4)
                                }
                                if item.isMoment {
                                    MomentCard(item: item)
                                } else if let photo = item.photo {
                                    PhotoCard(photo: photo)
                                }
                                // Just posted: a quiet question under it,
                                // for your eyes only (build 26).
                                if let offered = journalOffered(in: item) {
                                    JournalOfferSlip(photo: offered)
                                        .padding(.top, Spacing.section)
                                }
                            }
                            // Each entry arrives as it's scrolled to (build 24).
                            .entrance()
                        }
                    }
                    // The end of what's here, with more to come: the next
                    // page is asked for as this comes into view, and again
                    // whenever the page it brought ends on screen too.
                    if state.todayCursor != nil {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, Spacing.chapter)
                            .task(id: state.todayCursor) { await state.loadMoreToday() }
                            .id("more")
                    }
                  }
                  .padding(.horizontal, 20)
                  .frame(maxWidth: density.journalWidth)
                  .frame(maxWidth: .infinity)
                }
                .scrollTargetLayout()
                // The same room above the tab bar as every page.
                .padding(.bottom, Spacing.chapter)
                .foldAnimated(hSizeClass)
            }
            .scrollPosition(id: $anchor)
            // A tap on the Today tab: back to the top, or at the top the
            // pull's own refresh (`TabTaps`).
            .onTabTap(state.tabTaps.today, scroll: proxy, to: "masthead", position: $anchor) {
                await state.loadCircle()
                await state.refreshToday()
                await state.loadQuestion()
                await state.loadCircleLetters()
                await state.flushPendingCapture()
            }
            .background(SideDockReader(dock: $sideDock))
            // While a story's @ is being typed: who it could be, right above
            // the keyboard.
            .safeAreaInset(edge: .bottom) { MentionBar() }
            // Paper, no navigation bar: the masthead is the page's own.
            .journalPage()
            .navigationTitle("Today")
            .sheet(isPresented: $capturing) { CaptureView() }
            .sheet(isPresented: $joiningAnother) { CircleGateView(another: true) }
            .sheet(isPresented: $readingCircleJournal) {
                NavigationStack {
                    CircleJournalView()
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done") { readingCircleJournal = false }
                            }
                        }
                }
            }
            .sunRefreshable {
                Haptics.refreshed()
                // SwiftUI cancels a pull's own task as soon as the state it is
                // refreshing changes, which cut the pass short after the first
                // response: Returned and the queued upload never ran. The
                // pass runs as its own task and the pull waits on it.
                await Task {
                    // The circle too: who's in it (Members, mention tones)
                    // and which circles you're in had no other way to catch
                    // up until a relaunch (the QA audit, build 30).
                    await state.loadCircle()
                    await state.refreshToday()
                    await state.loadQuestion()
                    await state.loadCircleLetters()
                    await state.flushPendingCapture()
                }.value
            }
            .task {
                await state.refreshToday()
                await state.loadQuestion()
                await state.loadCircleLetters()
                await state.flushPendingCapture()
            }
          }
        }
    }

    /// Your photo in this entry, if it's the one just posted and nothing's
    /// written on it yet.
    private func journalOffered(in item: FeedItem) -> Photo? {
        guard let offer = state.journalOffer else { return nil }
        let photos = item.photo.map { [$0] } ?? item.photos ?? []
        return photos.first { $0.id == offer && $0.hasJournal != true && $0.owner.id == state.myId }
    }
}

/// Today with nothing on it: a note tucked into the journal, written by hand,
/// and the camera large beneath it, because the day's photo is the one thing
/// to do here. The floating camera stays where it always is.
struct TodayEmptyPage: View {
    @Environment(AppState.self) private var state
    let onCapture: () -> Void

    /// The camera is inside the sheet (the QA audit, build 30): below it,
    /// under the board and the question, a 90pt ring fell behind the tab bar
    /// on a phone, half hidden, exactly where it was meant to be the page's
    /// one thing to do. Since build 31 the sheet is short enough to sit
    /// whole above the tab bar with the board and a three-line question
    /// above it: the camera and its words on one line, the rule of six days
    /// as its small print, and room beneath before the tab bar.
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Nothing here yet.")
                .font(.sectionTitle)
            Button(action: onCapture) {
                HStack(spacing: 12) {
                    CaptureButton(disabled: state.holdsTheDay, diameter: 44, action: onCapture)
                        .allowsHitTesting(false)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Take today's photo")
                            .font(.system(.body, design: .rounded).weight(.medium))
                            .foregroundStyle(.primary)
                        Text("Your circle's first moment is waiting.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
                .frame(minHeight: 48)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(state.holdsTheDay)
            .opacity(state.holdsTheDay ? 0.45 : 1)
            .padding(.top, Spacing.tight)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Take today's photo")
            .accessibilityHint("Your circle's first moment is waiting.")
            Text("Photos live for six days, then they're gone.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.top, 12)
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(h: 20, v: 16)
        .padding(.top, 6)
        // Breathing room under the sheet, so its foot clears the tab bar
        // with the page's own margin to spare once scrolled to the end.
        .padding(.bottom, Spacing.chapter)
    }
}

/// One day's page of the journal: its entries, newest first, as the server
/// sent them. Days are the phone's own, so "Yesterday" means yesterday here.
struct JournalDay: Identifiable {
    let date: Date
    var items: [FeedItem]
    var id: Date { date }

    static func group(_ items: [FeedItem]) -> [JournalDay] {
        let calendar = Calendar.current
        var days: [JournalDay] = []
        for item in items {
            guard let taken = item.takenAt else { continue }
            let day = calendar.startOfDay(for: taken)
            if days.last?.date == day {
                days[days.count - 1].items.append(item)
            } else {
                days.append(JournalDay(date: day, items: [item]))
            }
        }
        return days
    }
}

/// A day's mark at the head of its page, the way a journal is dated: Today,
/// Yesterday, then the day's name. Photos live six days, so a name is never
/// ambiguous.
struct DayMark: View {
    let date: Date

    private var title: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        return date.formatted(.dateTime.weekday(.wide))
    }

    /// The day, then its date: the system's rounded face, the date quiet
    /// beside it. No rule (build 44).
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .font(.sectionTitle)
                .lineLimit(1)
                .fixedSize()
            Text(date, format: .dateTime.day().month(.wide))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .fixedSize()
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// Today's masthead: the circle on screen as the page's name, in SF Rounded,
/// opening the others; the day in small capitals; one hairline. It scrolls
/// away with the page.
struct TodayMasthead: View {
    @Environment(AppState.self) private var state
    let onJoinAnother: () -> Void
    var onCircleJournal: () -> Void = {}
    var onCapture: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center) {
                CircleSwitcher(onJoinAnother: onJoinAnother, onCircleJournal: onCircleJournal)
                Spacer(minLength: 12)
                NewPhotoButton(action: onCapture)
            }
            Text(Date.now.formatted(.dateTime.weekday(.wide).month(.wide).day().year()))
                .smallCaps()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            OfflineLine()
            // One circle's countdown (build 35), under the date it counts
            // from. Every other circle has none, and nothing is drawn.
            if let countdown = state.circle?.countdown {
                CountdownRoute(countdown: countdown)
                    .padding(.top, 4)
            }
            Rule(weight: 0.5)
                .padding(.top, 4)
        }
        .padding(.top, 8)
        // Room under the rule before the page begins (build 22).
        .padding(.bottom, 10)
    }
}

/// Today's photo, from the end of the masthead (build 29): a thin "+" in the
/// atmosphere's accent, nothing around it, the size of the masthead's other
/// marks, where a navigation bar's button would be. It replaced the
/// floating camera, which sat on the photos. Always there: with today's
/// photo already up, the capture sheet opens on it and says so ("Today's
/// moment is out there. Come back tomorrow."). Dimmed only while a capture
/// waits for signal, whose card in Today says why.
struct NewPhotoButton: View {
    @Environment(AppState.self) private var state
    @AppStorage("stanley.atmosphere") private var raw = "auto"
    @ScaledMetric(relativeTo: .title2) private var glyph: CGFloat = 22
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "plus")
                .font(.system(size: glyph, weight: .light))
                .foregroundStyle(Atmosphere.resolve(raw).palette.accent)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // A quiet invitation while today's photo isn't up yet (build 39):
        // a small swell every five seconds. It stops once you've posted.
        .gentlePulse(invites, color: Atmosphere.resolve(raw).palette.accent)
        .opacity(state.holdsTheDay ? 0.4 : 1)
        .disabled(state.holdsTheDay)
        .accessibilityLabel("Take today's photo")
    }

    /// Today has answered, and there's no photo of yours in it from today,
    /// posted or waiting to go up.
    private var invites: Bool {
        state.todayLoaded && state.sharedToday == nil && !state.holdsTheDay
    }
}

/// The circle on screen, as the title of Today, and the way to the others:
/// every circle this person is in (a check by the one showing), and joining
/// another. Names only, in the order they were joined, nothing ranked.
struct CircleSwitcher: View {
    @Environment(AppState.self) private var state
    let onJoinAnother: () -> Void
    /// The circle journal: past weeks' questions and answers (build 26).
    var onCircleJournal: () -> Void = {}

    var body: some View {
        let name = state.circle?.name ?? "Today"
        Menu {
            Picker("Circle", selection: Binding(
                get: { state.circle?.id ?? "" },
                set: { id in Task { await state.switchCircle(to: id) } }
            )) {
                ForEach(state.circles) { circle in
                    Text(circle.name).tag(circle.id)
                }
            }
            Divider()
            Button(action: onCircleJournal) {
                Label("Circle Journal", systemImage: "book")
            }
            Button(action: onJoinAnother) {
                Label("Join another circle", systemImage: "plus")
            }
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(name)
                    .font(.pageTitle)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Image(systemName: "chevron.down")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .foregroundStyle(.primary)
            .contentShape(Rectangle())
        }
        // In ink, like the paper's masthead: a menu's label otherwise takes
        // the mood's accent.
        .tint(.primary)
        .accessibilityAddTraits(.isHeader)
        .accessibilityLabel("Circle: \(name)")
        .accessibilityHint("Switch circles, read the circle journal, or join another")
    }
}

/// The tab bar when it stands on its side, as iOS 27 draws it on the iPhone
/// Duo's cover display: a floating dock down the trailing edge. Reports the
/// dock's visible frame in window coordinates, or nil where the tab bar runs
/// along the bottom, as on every ordinary iPhone.
///
/// UIKit gives the tab bar the whole strip, top to bottom; the dock you see
/// is a glass view inside the tab container, about 48 by 262pt on the Duo.
/// It's found by its shape (inside the strip, narrower than it, and well
/// short of the screen's height), not by a private class name, so a change
/// in how iOS builds it falls back to the bottom-right camera rather than
/// breaking.
struct SideDockReader: UIViewRepresentable {
    @Binding var dock: CGRect?

    func makeUIView(context: Context) -> Probe {
        let probe = Probe()
        probe.isUserInteractionEnabled = false
        return probe
    }

    func updateUIView(_ probe: Probe, context: Context) {
        probe.report = { frame in
            if dock != frame { dock = frame }
        }
    }

    final class Probe: UIView {
        var report: (CGRect?) -> Void = { _ in }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            measureSoon()
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            measureSoon()
        }

        /// After this pass, once the tab bar has laid out too. The dock can
        /// be drawn a moment after the tab bar is, so a vertical strip with
        /// no dock found yet is looked at again, a few times, shortly after.
        private func measureSoon(attempt: Int = 0) {
            DispatchQueue.main.asyncAfter(deadline: .now() + (attempt == 0 ? 0 : 0.3)) { [weak self] in
                self?.measure(attempt: attempt)
            }
        }

        private func measure(attempt: Int) {
            guard let window else { return }
            var responder: UIResponder? = self
            while let next = responder, !(next is UITabBarController) { responder = next.next }
            guard let tabs = responder as? UITabBarController, !tabs.tabBar.isHidden else {
                return report(nil)
            }
            let strip = tabs.tabBar.convert(tabs.tabBar.bounds, to: window)
            guard strip.height > strip.width else { return report(nil) }
            let found = Self.dock(in: tabs.view, strip: strip, window: window)
            report(found)
            if found == nil && attempt < 4 { measureSoon(attempt: attempt + 1) }
        }

        private static func dock(in root: UIView, strip: CGRect, window: UIWindow) -> CGRect? {
            let lane = strip.insetBy(dx: -8, dy: 0)
            var best: CGRect?
            var stack = root.subviews
            while let view = stack.popLast() {
                guard !view.isHidden, view.alpha > 0 else { continue }
                // A scroll view is content (the feed, a list), never the
                // dock, and holds most of the views there are.
                if !(view is UIScrollView) { stack.append(contentsOf: view.subviews) }
                let frame = view.convert(view.bounds, to: window)
                guard lane.contains(frame), frame.width > 20, frame.width < strip.width,
                      frame.height > 100, frame.height < window.bounds.height * 0.8 else { continue }
                if frame.width * frame.height > (best.map { $0.width * $0.height } ?? 0) {
                    best = frame
                }
            }
            return best
        }
    }
}

/// Today's photo, from a round button floating over the feed: the camera
/// in the palette's ink on a solid disc of its accent, so on Auto it's a
/// black camera on warm white in dark mode and a cream one on charcoal in
/// light, and on a mood it wears the mood's color. Solid, not Liquid Glass:
/// glass mixes in what's behind it, and over a dark feed it turned Auto's
/// warm white into the cool gray pilot users called outdated. A hairline of
/// light at the rim and a soft shadow lift it off the cards it passes. It
/// stays put while Today scrolls. Disabled, not hidden, while a queued
/// capture holds the day, so where it lives never changes.
struct CaptureButton: View {
    /// The ring's size. Only the empty Today draws one now (at 44pt, inside
    /// its sheet, since build 31), as the page's one thing to do; everywhere
    /// else it's the masthead's "+" (`NewPhotoButton`, build 29).
    static let size: CGFloat = 64
    @AppStorage("stanley.atmosphere") private var raw = "auto"
    let disabled: Bool
    /// Larger where it's the page's one thing to do (an empty Today).
    var diameter: CGFloat = CaptureButton.size
    let action: () -> Void

    /// A thin ring in the atmosphere's accent with the camera inside it, and
    /// nothing filled (pilot users found the solid disc heavy). A soft halo
    /// in the page's own color sits behind the ring and the glyph, so they
    /// stay legible over a photo, light or dark, without weighing it down.
    var body: some View {
        let palette = Atmosphere.resolve(raw).palette
        let scale = diameter / Self.size
        Button(action: action) {
            Image(systemName: "camera")
                .font(.system(size: 24 * scale, weight: .regular))
                .foregroundStyle(palette.accent)
                .frame(width: diameter, height: diameter)
                .background {
                    Circle().strokeBorder(palette.accent, lineWidth: 1.5)
                }
                .shadow(color: palette.floor.opacity(0.9), radius: 3)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .opacity(disabled ? 0.45 : 1)
        .disabled(disabled)
        .accessibilityLabel("Take today's photo")
    }
}

/// One story on a photo, and the line that asks for the next one.
enum StoryLine {
    /// Who, then what they remember: the name in bold in the writer's own
    /// tone (build 39; it was the page's ink), the same watercolor their
    /// name takes when a story mentions them, and the
    /// words a step quieter in the secondary color. Two people's lines never
    /// run together into one white run of text. A person the story mentions
    /// (build 19, `Mentions.swift`) is their name in bold, in their own tone,
    /// and a link to their profile, which the view showing the line opens.
    /// With `opening`, every other word (the name too) carries that link
    /// instead, so a tap anywhere on the line opens the photo's stories
    /// (build 24); the colors are set on each run, so none turns link-blue.
    @MainActor
    static func text(_ comment: Comment, people: MentionDirectory, opening stories: URL? = nil) -> Text {
        var line = AttributedString(comment.author.displayName)
        line.inlinePresentationIntent = .stronglyEmphasized
        line.swiftUI.foregroundColor = people.nameColor(comment.author.id)
        line.link = stories
        line += AttributedString("  ")
        for part in Mentions.parts(comment.body) {
            switch part {
            case .words(let words):
                var run = AttributedString(words)
                run.swiftUI.foregroundColor = .secondary
                run.link = stories
                line += run
            case .person(let id):
                if let name = people.name(id) {
                    var run = AttributedString(name)
                    run.inlinePresentationIntent = .stronglyEmphasized
                    run.swiftUI.foregroundColor = people.color(id)
                    run.link = Mentions.link(id)
                    line += run
                } else {
                    var run = AttributedString("someone")
                    run.swiftUI.foregroundColor = .secondary
                    run.link = stories
                    line += run
                }
            }
        }
        return Text(line)
    }

    /// The link a story line's words carry in Today: a tap on them opens
    /// the photo's stories sheet, as "More stories" does. Its own scheme,
    /// beside the mentions', so the card's `openURL` can tell the two apart.
    /// Never leaves the app.
    static func link(_ photoId: String) -> URL? { URL(string: "stanley-stories://\(photoId)") }

    /// The photo whose stories a tapped line asks for, if that's what the
    /// URL is.
    static func photo(in url: URL) -> String? {
        url.scheme == "stanley-stories" ? url.host() : nil
    }

    /// The empty field under a photo. A question about the moment, because a
    /// story here is co-remembering, not a post.
    static let prompt = "What do you remember?"
}

struct ViewedMember: Identifiable {
    let id: String
}

/// The heart and the bookmark: a small 17pt glyph (build 44; 22pt before,
/// when each sat on its own disc) inside a 44pt-tall target, Apple's
/// minimum, the two sharing one glass pill in the photo's corner. One
/// size for both, everywhere they appear, so they never drift apart. Views
/// read the glyph through `@ScaledMetric`, so it grows with Dynamic Type.
enum GestureIcon {
    static let glyph: CGFloat = 17
    static let target: CGFloat = 44
}

/// Where the double-tap heart is in its pop. At rest it's unseen.
private struct HeartPop {
    var scale: CGFloat = 0.8
    var opacity: Double = 0
}

/// The photo of a print: `PhotoShape`, cut nearly square, to sit inside the
/// print's paper border (`asPrint`). The heart and the bookmark sit in its
/// bottom-right; the poster's name and the time are written beneath the
/// print, on the page (`PrintByline`). Its gestures: double-tap to like (ephemeral, a
/// white heart that pops in the middle and is gone), press-and-hold to hold
/// (permanent, a bookmark). Color deepens under the thumb while held, with a
/// soft settle on commit — never applause. Reused by standalone photos, the prints in a shared moment and
/// a photo's stories.
struct PhotoImageView: View {
    @Environment(AppState.self) private var state
    @Environment(\.colorScheme) private var colorScheme
    let photo: Photo
    /// Every photo is cut the same (`PhotoCut`).
    var cornerRadius: CGFloat = PhotoCut.corner
    /// In Today's page the photo drifts a little behind its print as the
    /// page scrolls (build 39): up to 7pt, so the print has some depth.
    var drifts = false

    @State private var holdProgress: Double = 0
    @State private var settleScale: CGFloat = 1
    /// Bumped by a double-tap that likes, to play the heart once.
    @State private var heartPops = 0
    /// Report, delete or untag, asked for from the long-press menu.
    @State private var action: PhotoAction?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .body) private var glyph = GestureIcon.glyph

    private var fade: Double { Self.fade(photo.decayProgress) }

    /// How far a photo has faded, from its decay progress: nothing for its
    /// first third, then a smooth fall. Shared with the small prints on a
    /// member's page, so a photo fades the same wherever it's seen.
    static func fade(_ progress: Double) -> Double {
        let fadingStart = 1.0 / 3.0
        let t = min(1.0, max(0.0, (progress - fadingStart) / (1.0 - fadingStart)))
        return t * t * (3.0 - 2.0 * t)
    }

    private var opacityDrop: Double { colorScheme == .dark ? 0.62 : 0.82 }

    /// The photo as VoiceOver says it: whose, and where it is in its six
    /// days, in the words the page shows without words.
    private var spoken: String {
        let first = photo.owner.displayName.split(separator: " ").first.map(String.init) ?? photo.owner.displayName
        let who = photo.owner.id == state.myId ? "Your photo" : "Photo by \(first)"
        switch photo.state {
        case "LAST_LIGHT": return "\(who), in its last light"
        case "FADING": return "\(who), fading"
        default: return who
        }
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    }

    var body: some View {
        Group {
            if let urls = photo.urls, let url = state.api.absoluteURL(urls.image) {
                bed(url)
                // What the fade shows, said (the HCI audit, build 32): a
                // VoiceOver user heard nothing of whose photo it was or how
                // far it had faded. Words, never a time left.
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(spoken)
                .accessibilityAddTraits(.isImage)
                .accessibilityAction(named: photo.likedByMe ? "Unlike" : "Like") {
                    Task { await state.toggleLike(photo) }
                }
                .accessibilityAction(named: photo.anchoredByMe ? "Let go" : "Hold") { toggleHold() }
                .saturation(1.0 - 0.85 * fade)
                .opacity(1.0 - opacityDrop * fade)
                .overlay(shape.fill(Color.accentColor.opacity(0.38 * holdProgress)))
                .overlay { likeHeart }
                .overlay(alignment: .bottomTrailing) { gestures }
                .clipShape(shape)
                // Its final day: a warm edge, like candlelight. No text, no
                // countdown, no urgency — the decay said visually and quietly.
                .overlay {
                    if photo.state == "LAST_LIGHT" {
                        shape
                            .strokeBorder(Color.orange.opacity(0.45), lineWidth: 1.5)
                            .shadow(color: .orange.opacity(0.35), radius: 10)
                            .allowsHitTesting(false)
                    }
                }
                .scaleEffect(settleScale)
                .contentShape(Rectangle())
                .onTapGesture(count: 2) { doubleTap() }
                .onLongPressGesture(minimumDuration: 0.45, maximumDistance: 30) {
                    hold()
                } onPressingChanged: { pressing in
                    withAnimation(.easeOut(duration: pressing ? 0.45 : 0.25)) {
                        holdProgress = pressing && !photo.anchoredByMe ? 1 : 0
                    }
                }
                .contextMenu {
                    Button { Task { await state.toggleLike(photo) } } label: {
                        Label(photo.likedByMe ? "Unlike" : "Like", systemImage: "heart")
                    }
                    // A long press lands here: the menu takes the press before
                    // the hold gesture can, so this is how most holds happen.
                    Button { toggleHold() } label: {
                        Label(photo.anchoredByMe ? "Let go" : "Hold", systemImage: "bookmark")
                    }
                    Divider()
                    PhotoMenuItems(photo: photo, action: $action)
                }
                .photoActions(photo, $action)
            }
        }
    }

    /// The photo, cropped into exactly the shape of a print.
    ///
    /// The bed is what owns the size. Asking an aspect-*fill* image for a
    /// width makes it report the width it would need in order to fill, which
    /// is wider than the page — the entry then stretches past both screen
    /// edges and drags its words off with it. So a flexible bed takes the
    /// width on offer, its height follows from `PhotoShape`, and the photo
    /// fills it as an overlay, clipped to it.
    private func bed(_ url: URL) -> some View {
        Color.clear
            .aspectRatio(PhotoShape.aspect, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .overlay {
                SignedImage(url: url) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    Shimmer()
                }
                .modifier(Drift(reach: drifts && !reduceMotion ? 7 : 0))
            }
            .clipped()
    }

    /// The bookmark and the heart, on the photo itself. Personal state, never
    /// a public signal: they say "you held this" and "you liked this", only
    /// to you, and never how many did. Both are buttons, because people reach
    /// for them; pressing and holding the photo, and double-tapping it, do
    /// the same.
    private var gestures: some View {
        HStack(spacing: 0) {
            Button { toggleHold() } label: {
                marker(photo.anchoredByMe ? "bookmark.fill" : "bookmark",
                       photo.anchoredByMe ? Color.accentColor : DarkRoom.ink)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(photo.anchoredByMe ? "Let go of this memory" : "Hold this memory")
            Button { like() } label: {
                marker(photo.likedByMe ? "heart.fill" : "heart",
                       photo.likedByMe ? Color.pink : DarkRoom.ink)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(photo.likedByMe ? "Unlike" : "Like")
            .accessibilityValue(photo.likedByMe ? "You liked this" : "")
        }
        .padding(.horizontal, 3)
        // One small glass pill for the two (build 44; a material disc each
        // before): the page's own ink on it, so it reads over a white sky
        // and a black room alike.
        .glass(in: Capsule())
        .padding(8)
    }

    /// A gesture's mark inside the pill. The glyph is the shared gesture
    /// size; the target around it is 44pt tall and 40 wide, and the pill is
    /// drawn only as tall as the glyphs need.
    private func marker(_ systemName: String, _ tint: Color) -> some View {
        Image(systemName: systemName)
            .font(.system(size: glyph, weight: .medium))
            .foregroundStyle(tint)
            .contentTransition(.symbolEffect(.replace))
            .frame(width: 40, height: 34)
            .contentShape(Rectangle().inset(by: -5))
    }

    private func hold() {
        guard !photo.anchoredByMe else { return }
        // Felt as the bookmark fills, with the settle: a memory kept.
        Haptics.held()
        withAnimation(.easeOut(duration: 0.2)) { holdProgress = 0 }
        withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) { settleScale = 0.97 }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85).delay(0.12)) { settleScale = 1 }
        Task { await state.hold(photo) }
    }

    /// Hold or let go, from the bookmark or the menu. Holding is felt as the
    /// bookmark fills; letting go is quiet.
    private func toggleHold() {
        if !photo.anchoredByMe { Haptics.held() }
        Task { await state.toggleAnchor(photo) }
    }

    /// A double-tap that likes plays the heart. On a photo already liked it
    /// unlikes, as the corner heart does, and only the corner heart says so.
    private func doubleTap() {
        if !photo.likedByMe {
            heartPops += 1
            Haptics.liked()
        }
        like()
    }

    private func like() {
        Task { await state.toggleLike(photo) }
    }

    /// The double-tap heart: one white heart in the middle of the photo
    /// that grows from 0.7 to 1.2 and fades as it goes, the plain one
    /// everybody knows (build 44; build 39 threw four small hearts out with
    /// it). The photo itself is never tinted. Only the fade under Reduce
    /// Motion.
    private var likeHeart: some View {
        Image(systemName: "heart.fill")
            .font(.system(size: 80))
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.25), radius: 8)
            .keyframeAnimator(
                initialValue: HeartPop(scale: reduceMotion ? 1 : 0.7), trigger: heartPops
            ) { heart, pop in
                heart.scaleEffect(pop.scale).opacity(pop.opacity)
            } keyframes: { _ in
                KeyframeTrack(\.scale) {
                    SpringKeyframe(reduceMotion ? 1 : 1.0, duration: 0.2, spring: .init(response: 0.25, dampingRatio: 0.85))
                    CubicKeyframe(reduceMotion ? 1 : 1.2, duration: 0.25)
                }
                KeyframeTrack(\.opacity) {
                    LinearKeyframe(1, duration: 0.06)
                    LinearKeyframe(1, duration: 0.2)
                    LinearKeyframe(0, duration: 0.2)
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// A photo that lags a little behind its print as the page scrolls (build
/// 39): up to `reach` points, upward as the print nears the foot of the
/// page's window and downward near its top, a touch larger than its frame
/// so no edge ever shows. Its place is read as the page moves and kept
/// here, so only this small view is drawn again, not the print around it.
/// (Drawn with `visualEffect` instead, iOS 26's glass tab bar took on the
/// photo's darkness straight through the bar's floor.)
private struct Drift: ViewModifier {
    let reach: CGFloat
    /// Where the print is in the window: -1 at its top, 1 at its foot.
    @State private var place: CGFloat = 0

    func body(content: Content) -> some View {
        if reach > 0 {
            content
                .scaleEffect(1.035)
                .offset(y: -place * reach)
                .onGeometryChange(for: CGFloat.self) { proxy in
                    let window = proxy.bounds(of: .scrollView)?.height ?? 0
                    guard window > 0 else { return 0 }
                    let middle = proxy.frame(in: .scrollView).midY
                    // To the nearest fiftieth: a seventh of a point is
                    // finer than the eye, and fewer redraws.
                    return (min(1, max(-1, (middle - window / 2) / window)) * 50).rounded() / 50
                } action: { place = $0 }
        } else {
            content
        }
    }
}

/// A print laid on the page by hand is never quite square to it: a degree
/// or less either way, decided by the photo itself so it lies the same way
/// every time it's drawn. The album page lays its prints a little looser.
enum PrintTilt {
    static func degrees(_ id: String) -> Double {
        let seed = id.unicodeScalars.reduce(UInt32(7)) { $0 &* 31 &+ $1.value }
        return (Double(seed % 17) - 8) / 8 * 0.9
    }
}

/// An entry arriving on the page (build 24): as it scrolls into view it
/// fades in and settles up by 20pt over 0.3s, so Today has some weight to
/// it instead of everything simply being there (pilot users said the app
/// felt light). Once per entry: a refresh keeps the entries it had, and they
/// stay put; an entry scrolled far off and back arrives again, which is the
/// point. Under Reduce Motion it only fades.
private struct Entrance: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var arrived = false

    func body(content: Content) -> some View {
        content
            .opacity(arrived ? 1 : 0)
            .offset(y: arrived || reduceMotion ? 0 : 20)
            .onAppear {
                withAnimation(.easeOut(duration: 0.25)) { arrived = true }
            }
    }
}

extension View {
    func entrance() -> some View { modifier(Entrance()) }
}

/// One entry in Today: the photo, straight and clean, then beneath it with
/// no frame around any of it: who and when (small, quiet), the caption,
/// the place, who was there, the stories and the line that asks for the
/// next.
struct PhotoCard: View {
    @Environment(AppState.self) private var state
    @Environment(\.horizontalSizeClass) private var hSizeClass
    private var density: Density { Density(hSizeClass) }
    let photo: Photo
    @State private var viewedMember: ViewedMember?
    @State private var showFaces = false
    @State private var showStories = false
    @State private var action: PhotoAction?

    private var isMine: Bool { state.myId != nil && state.myId == photo.owner.id }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            PhotoImageView(photo: photo, drifts: true)
                .asPrint()
            words
            comments
            commentField
        }
        .sheet(item: $viewedMember) { member in
            MemberProfileView(memberId: member.id)
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showFaces) {
            FacesSheet(photoId: photo.id)
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showStories) {
            PhotoStoriesView(photo: photo)
        }
        .photoActions(photo, $action)
        // A tap on a story's words opens the stories; a name a story
        // mentions opens that person's profile.
        .environment(\.openURL, OpenURLAction { url in
            if StoryLine.photo(in: url) != nil {
                showStories = true
                return .handled
            }
            guard let id = Mentions.person(in: url) else { return .systemAction }
            viewedMember = ViewedMember(id: id)
            return .handled
        })
    }

    /// Who and when, then the caption, place and who was there,
    /// with the owner's faces button and the photo's "…" menu at the end of
    /// the first line. Always drawn, so the menu (report, delete, untag) is
    /// there on every print, not only behind a long press.
    private var words: some View {
        let caption = photo.caption.flatMap { $0.isEmpty ? nil : $0 }
        let place = photo.location.flatMap { $0.isEmpty ? nil : $0 }
        return HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                PrintByline(
                    owner: photo.owner, time: photo.takenAt,
                    plane: state.circle?.countdown?.marks(photo.takenAt) ?? false
                ) {
                    if let ownerId = photo.owner.id { viewedMember = ViewedMember(id: ownerId) }
                }
                .padding(.bottom, 2)
                if let caption {
                    // In a hand on your own photo, where the words are
                    // yours; plain on anyone else's (build 44).
                    Text(caption)
                        .font(isMine ? .hand(18, relativeTo: .body) : .body)
                        .foregroundStyle(.primary)
                }
                if let place {
                    Text(place).font(.footnote).foregroundStyle(.secondary)
                }
                // 'Who was there' — faces as a memory detail, not tappable (Part 3).
                if !photo.tagged.isEmpty {
                    HStack(spacing: 6) {
                        FaceCluster(
                            faces: photo.tagged.map { (id: $0.id ?? $0.displayName, url: $0.avatarUrl, name: $0.displayName) },
                            size: 20
                        )
                        Text("with " + photo.tagged.map(\.displayName).joined(separator: ", "))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .padding(.top, 1)
                }
            }
            Spacer(minLength: 8)
            // Your own photo with an entry written on it: a small book that
            // opens it (build 26). Only you ever see it.
            if isMine, photo.hasJournal == true {
                Button { action = .journal } label: {
                    Image(systemName: "book.closed")
                        .frame(width: GestureIcon.target, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Your journal entry")
            }
            // Your own photo: who liked and who held it, as faces.
            if isMine {
                Button { showFaces = true } label: {
                    Image(systemName: "person.2")
                        .frame(width: GestureIcon.target, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Who liked and held this")
            }
            // No negative padding to pull it to the edge: a row wider than
            // its frame let the keyboard nudge all of Today sideways.
            PhotoMenuButton(photo: photo, action: $action)
        }
    }

    /// Co-remembering, visible without digging, the way you'd overhear it:
    /// the first story and the newest, with any between them behind "More
    /// stories". The newest is there so a story just added shows up right
    /// above the field it was written in. With only the first shown, a
    /// second story vanished behind "More stories" the moment it posted,
    /// and looked as if it hadn't. A tap on either line's words opens the
    /// stories too (build 24): people tapped them expecting the thread.
    @ViewBuilder
    private var comments: some View {
        if let first = photo.comments.first {
            VStack(alignment: .leading, spacing: 4) {
                storyLine(first)
                if photo.comments.count > 2 {
                    // "More", never "2 more" — the no-counts rule holds here too.
                    Button("More stories") { showStories = true }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .buttonStyle(.plain)
                }
                if let newest = photo.comments.last, newest.id != first.id {
                    storyLine(newest)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            // The rest of the comment area, beside and between the lines,
            // opens the stories too. Behind the lines rather than over them,
            // so the words' own links (the stories, a mention's profile) are
            // still theirs.
            .background {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { showStories = true }
            }
        }
    }

    private func storyLine(_ comment: Comment) -> some View {
        StoryLine.text(comment, people: state.mentions, opening: StoryLine.link(photo.id))
            .font(.callout)
            .lineLimit(density.storyLineLimit)
            .storyMenu(comment, on: photo)
    }

    private var commentField: some View {
        StoryComposer(photo: photo)
            .creaseSafe(density)
    }
}

/// A shared moment (Part 3): one event, many phones, as a loose run of
/// prints from the same place and day. The place is written above them with
/// the faces of who posted from it (never a count); each print keeps its own
/// name, like, Held and decay.
struct MomentCard: View {
    @Environment(AppState.self) private var state
    @Environment(\.horizontalSizeClass) private var hSizeClass
    private var density: Density { Density(hSizeClass) }
    let item: FeedItem
    @State private var viewedMember: ViewedMember?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .bottom, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Together, from your circle")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Text(item.location ?? "Shared moment")
                        .font(.sectionTitle)
                }
                Spacer()
                if let members = item.members {
                    FaceCluster(
                        faces: members.map { (id: $0.id ?? $0.displayName, url: $0.avatarUrl, name: $0.displayName) },
                        size: 28
                    )
                }
            }
            // Inner display: two prints side by side at a size worth looking
            // at, with a sliver of the third so it's clear there is more.
            // Outer display: the same run, narrowed to fit.
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 16) {
                    ForEach(item.photos ?? []) { photo in
                        VStack(alignment: .leading, spacing: 10) {
                            PhotoImageView(photo: photo)
                                .asPrint()
                            PrintByline(
                                owner: photo.owner, time: photo.takenAt,
                                plane: state.circle?.countdown?.marks(photo.takenAt) ?? false
                            ) {
                                if let ownerId = photo.owner.id { viewedMember = ViewedMember(id: ownerId) }
                            }
                        }
                        .containerRelativeFrame(.horizontal) { length, _ in
                            density.momentTileWidth(container: length)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            .scrollTargetBehavior(.viewAligned)
        }
        .sheet(item: $viewedMember) { member in
            MemberProfileView(memberId: member.id)
                .presentationDetents([.medium, .large])
        }
    }
}

/// The weekly mosaic (Part 2): the week's photos as one fleeting artifact.
/// View-only — no holds, likes, comments, or counts. Each tile shows its
/// owner's face. Appears Sun/Mon, gone Tuesday.
struct MosaicCard: View {
    @Environment(AppState.self) private var state
    @Environment(\.horizontalSizeClass) private var hSizeClass
    private var density: Density { Density(hSizeClass) }
    let mosaic: Mosaic
    @State private var selection = 0
    @State private var headerShown = false

    // Each photo gets real presence — roughly half the screen, a page in a
    // small photo book rather than a tile in a wall.
    private var carouselHeight: CGFloat { density.mosaicHeight }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header stays above the carousel.
            VStack(alignment: .leading, spacing: 0) {
                Text("Your week")
                    .font(.sectionTitle)
                Text("All at once.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            // It arrives rather than appears: a slow fade on first sight.
            .opacity(headerShown ? 1 : 0)
            .task {
                guard !headerShown else { return }
                withAnimation(.easeIn(duration: 0.25)) { headerShown = true }
            }

            // One photo at a time, swipeable — flipping through the week.
            TabView(selection: $selection) {
                ForEach(Array(mosaic.tiles.enumerated()), id: \.offset) { index, tile in
                    tilePhoto(tile).tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: carouselHeight)

            // The photographer and caption for the photo on screen.
            if mosaic.tiles.indices.contains(selection) {
                let tile = mosaic.tiles[selection]
                HStack(spacing: 8) {
                    AvatarView(url: tile.owner.avatarUrl, name: tile.owner.displayName, size: 26, circular: true)
                    VStack(alignment: .leading, spacing: 1) {
                        // Written under the photo, the way a photo book is
                        // annotated: who took it, then what they said.
                        Text(tile.owner.displayName)
                            .font(.footnote.weight(.semibold))
                        if let caption = tile.caption, !caption.isEmpty {
                            Text(caption)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                    Spacer()
                }
                .animation(.easeInOut(duration: 0.2), value: selection)
            }

            // Page dots — how many there are, and where you are.
            if mosaic.tiles.count > 1 {
                HStack(spacing: 6) {
                    ForEach(mosaic.tiles.indices, id: \.self) { i in
                        Circle()
                            .fill(i == selection ? Color.primary.opacity(0.7) : Color.secondary.opacity(0.3))
                            .frame(width: 6, height: 6)
                    }
                }
                .frame(maxWidth: .infinity)
                .animation(.easeInOut(duration: 0.2), value: selection)
            }
        }
        .card(h: density.cardPadding + 4, v: density.cardPadding + 4)
    }

    private func tilePhoto(_ tile: MosaicTile) -> some View {
        Color.clear
            .overlay {
                if let url = state.api.absoluteURL(tile.image ?? tile.thumb) {
                    SignedImage(url: url) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        Rectangle().fill(.quaternary)
                    }
                }
            }
            .asPrint()
            .padding(.horizontal, 2)
            .padding(.vertical, 4)
    }
}

/// The one quiet Returned card (§14), set apart from circle content. Rescue is
/// time-critical (keep your own fading photo); anniversary and near-forgotten
/// resurface held memories. One exit, Dismiss (not now); resting a memory
/// for good was removed in build 44.
struct ReturnedCard: View {
    @Environment(AppState.self) private var state
    @Environment(\.horizontalSizeClass) private var hSizeClass
    private var density: Density { Density(hSizeClass) }
    let item: ReturnedItem
    @ScaledMetric(relativeTo: .body) private var glyph = GestureIcon.glyph

    private var isRescue: Bool { item.source == "rescue" }

    /// What the card says above the photo. A near-forgotten one says
    /// nothing: the photo coming back is the whole message.
    private var heading: String? {
        switch item.source {
        case "rescue": return "Fading soon"
        case "anniversary": return anniversaryLabel
        case "near_forgotten": return nil
        default: return "Returned"
        }
    }

    private var subheading: String {
        switch item.source {
        case "rescue": return rescueSubheading
        case "anniversary": return "From the memories you've held."
        default: return ""
        }
    }

    // A rescue is always a last-light photo (~5–6 days old), so name the real
    // day — never "today", which can't be true here.
    private var rescueSubheading: String {
        guard let taken = item.photo.takenAt else { return "Your moment, fading." }
        return "Your moment from \(taken.formatted(.dateTime.weekday(.wide)))."
    }

    private var anniversaryLabel: String {
        guard let taken = item.photo.takenAt else { return "On this day" }
        let months = Calendar.current.dateComponents([.month], from: taken, to: Date()).month ?? 0
        if months >= 12 {
            let years = months / 12
            return years == 1 ? "A year ago" : "\(years) years ago"
        }
        return months <= 1 ? "One month ago" : "\(months) months ago"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let heading {
                VStack(alignment: .leading, spacing: 0) {
                    Text(heading)
                        .font(.sectionTitle)
                    if !subheading.isEmpty {
                        Text(subheading)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            if let urls = item.photo.urls, let url = state.api.absoluteURL(urls.thumb) {
                Color.clear
                    .frame(maxWidth: .infinity)
                    .frame(height: density.returnedPhotoHeight)
                    .overlay {
                        SignedImage(url: url) { image in
                            image.resizable().aspectRatio(contentMode: .fill)
                        } placeholder: {
                            Rectangle().fill(.quaternary)
                        }
                    }
                    .asPrint()
            }
            if let caption = item.photo.caption, !caption.isEmpty {
                Text(caption).font(.callout)
            }
            if isRescue {
                Button {
                    // Keeping it is holding it: the bookmark fills.
                    Haptics.held()
                    Task { await state.keepReturned(photoId: item.photo.id) }
                } label: {
                    Label {
                        Text("Keep this")
                    } icon: {
                        Image(systemName: "bookmark")
                            .font(.system(size: glyph, weight: .medium))
                    }
                    .frame(maxWidth: .infinity)
                    .accentInk()
                }
                .buttonStyle(.borderedProminent)
            }
            HStack {
                Spacer()
                Button("Dismiss") {
                    Task { await state.dismissReturned() }
                }
            }
            .font(.callout)
            .foregroundStyle(.secondary)
            .padding(.top, 2)
        }
        // Set apart from the circle's own photos: a card of its own.
        .card(h: density.cardPadding + 4, v: density.cardPadding + 4)
    }
}

/// The whole thread, for when the card's one line isn't enough. Opened from
/// "More stories" — the photo, its caption, and every story on it, in the order
/// they were told. Adding one works here too.
struct PhotoStoriesView: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var hSizeClass
    private var density: Density { Density(hSizeClass) }
    let photo: Photo
    @State private var action: PhotoAction?
    @State private var viewedMember: ViewedMember?
    /// Stories added here. Opened from Today, the refreshed photo brings
    /// them too; opened from a profile's prints, nothing refreshes this
    /// copy of the photo, so without these a new story never appeared.
    @State private var added: [Comment] = []

    private var thread: [Comment] {
        photo.comments + added.filter { story in !photo.comments.contains { $0.id == story.id } }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    PhotoImageView(photo: photo)
                        .asPrint()
                    if let caption = photo.caption, !caption.isEmpty {
                        Text(caption)
                            .font(photo.owner.id == state.myId ? .hand(18, relativeTo: .body) : .body)
                    }
                    ForEach(thread) { comment in
                        StoryLine.text(comment, people: state.mentions)
                            .font(.callout)
                            .storyMenu(comment, on: photo)
                    }
                    StoryComposer(photo: photo) { added.append($0) }
                        .padding(.top, 2)
                        .creaseSafe(density)
                }
                .padding()
            }
            .safeAreaInset(edge: .bottom) { MentionBar() }
            .atmosphereWash()
            .navigationTitle(photo.owner.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        PhotoMenuItems(photo: photo, action: $action)
                    } label: {
                        Image(systemName: "ellipsis")
                    }
                    .accessibilityLabel("More")
                }
            }
            .photoActions(photo, $action)
            .environment(\.openURL, OpenURLAction { url in
                guard let id = Mentions.person(in: url) else { return .systemAction }
                viewedMember = ViewedMember(id: id)
                return .handled
            })
            .sheet(item: $viewedMember) { member in
                MemberProfileView(memberId: member.id)
                    .presentationDetents([.medium, .large])
            }
        }
    }
}

/// The photo that is waiting for a signal. Deliberately quiet: this is not an
/// error, just a moment that hasn't travelled yet. It sits where it will sit
/// once it lands, so nothing jumps when it does.
struct PendingCaptureCard: View {
    @Environment(AppState.self) private var state
    @Environment(\.horizontalSizeClass) private var hSizeClass
    private var density: Density { Density(hSizeClass) }
    let pending: PendingCapture

    private var image: UIImage? {
        guard let data = try? Data(contentsOf: pending.jpegURL) else { return nil }
        return UIImage(data: data)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let image {
                Color.clear
                    .aspectRatio(PhotoShape.aspect, contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .overlay {
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    }
                    // Held back a little until it's real for everyone else.
                    .opacity(pending.rejection == nil ? 0.72 : 0.5)
                    .asPrint()
            }
            if let caption = pending.caption, !caption.isEmpty {
                Text(caption).font(.hand(18, relativeTo: .body))
            }
            if let rejection = pending.rejection {
                Text(rejection)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                HStack {
                    Button("Save to Photos") { Task { await save() } }
                    Spacer()
                    Button("Discard", role: .destructive) { state.queue.clear(pending) }
                }
                .font(.callout)
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
            } else {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.mini)
                    Text("Waiting to upload")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    /// The last honest option for a photo that can never be posted: let its
    /// owner keep it. Stanley never writes to Photos otherwise.
    private func save() async {
        guard let image else { return }
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            state.errorMessage = "Stanley needs permission to add to your Photos library."
            return
        }
        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAsset(from: image)
            }
            state.flash = "Saved to Photos."
            state.queue.clear(pending)
        } catch {
            state.errorMessage = "Couldn't save that to Photos."
        }
    }
}

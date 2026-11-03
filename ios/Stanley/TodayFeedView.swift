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
    /// The capture sheet is up. Shared with `HomeView`, which shows the
    /// camera itself where the tab bar is a dock down the side.
    @Binding var capturing: Bool
    /// The tab bar's dock, when it stands down the side of the screen (the
    /// iPhone Duo's cover display). Nil on an ordinary iPhone. Read here,
    /// inside the tab bar controller, for `HomeView`.
    @Binding var sideDock: CGRect?
    /// The keyboard is up, so the floating camera is out of the way.
    @Binding var typing: Bool
    @State private var editingNote = false
    @State private var joiningAnother = false
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
                    TodayMasthead { joiningAnother = true }
                        .padding(.bottom, 22)
                        .id("masthead")
                    // The note is the circle talking to itself, so it goes
                    // first, above even the mosaic: one sticky note on the
                    // first page.
                    NoteBar(note: state.communityNote) { editingNote = true }
                        .padding(.bottom, 28)
                        .id("note")
                    // The weekly mosaic sits above the days themselves
                    // (Part 2), Sun/Mon only.
                    if let mosaic = state.mosaic {
                        MosaicCard(mosaic: mosaic)
                            .padding(.bottom, density.entrySpacing)
                            .id("mosaic")
                    }
                    // Returned sits above the circle's own pages, set apart.
                    if let item = state.returned {
                        ReturnedCard(item: item)
                            .padding(.bottom, density.entrySpacing)
                            .id("returned")
                    }
                    if let pending = state.pendingHere {
                        PendingCaptureCard(pending: pending)
                            .padding(.bottom, density.entrySpacing)
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
                    ForEach(Array(JournalDay.group(state.feedItems).enumerated()), id: \.element.id) { index, day in
                        DayMark(date: day.date)
                            .padding(.top, index == 0 ? 0 : density.daySpacing)
                            .padding(.bottom, 18)
                            .id("day:\(day.id.timeIntervalSince1970)")
                        // Entries carry their FeedItem id (a String, like the
                        // ids above), so one binding anchors to any of them.
                        // A day's entries are divided by a thin rule, the
                        // way the paper divides its stories, not by a gap.
                        ForEach(Array(day.items.enumerated()), id: \.element.id) { position, item in
                            VStack(alignment: .leading, spacing: 0) {
                                if position > 0 {
                                    Rule(weight: 0.5)
                                        .padding(.vertical, density.entrySpacing * 0.8)
                                }
                                if item.isMoment {
                                    MomentCard(item: item)
                                } else if let photo = item.photo {
                                    PhotoCard(photo: photo)
                                }
                            }
                        }
                    }
                  }
                  .padding(.horizontal, 20)
                  .frame(maxWidth: density.journalWidth)
                  .frame(maxWidth: .infinity)
                }
                .scrollTargetLayout()
                .padding(.bottom, 8)
                .foldAnimated(hSizeClass)
            }
            .scrollPosition(id: $anchor)
            // A tap on the Today tab: back to the top, or at the top the
            // pull's own refresh (`TabTaps`).
            .onTabTap(state.tabTaps.today, scroll: proxy, to: "masthead") {
                await state.refreshToday()
                await state.flushPendingCapture()
            }
            .background(SideDockReader(dock: $sideDock))
            // The camera floats where a thumb already is, instead of in the
            // top bar, which it can't reach on a tall phone. On an ordinary
            // iPhone that's the bottom right, as a safe-area inset, so the
            // pages scroll under it and the last entry can still scroll clear
            // of it. Where the tab bar is a dock down the side (the Duo's
            // cover), `HomeView` puts it in the dock's own column, just above
            // it. The day is claimed the moment the shutter closes, signal or
            // not, so a queued capture closes the camera too.
            .safeAreaInset(edge: .bottom, alignment: .trailing) {
                // While a story is being typed the button steps aside. Above
                // the keyboard it would sit on the field and its Add button.
                if !typing && sideDock == nil {
                    CaptureButton(disabled: state.holdsTheDay) { capturing = true }
                        .padding(.trailing, 16)
                        .padding(.bottom, 12)
                        .transition(.opacity)
                }
            }
            // While a story's @ is being typed: who it could be, right above
            // the keyboard.
            .safeAreaInset(edge: .bottom) { MentionBar() }
            .animation(.easeOut(duration: 0.15), value: typing)
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
                typing = true
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
                typing = false
            }
            // Paper, no navigation bar: the masthead is the page's own.
            .journalPage()
            .navigationTitle("Today")
            .sheet(isPresented: $capturing) { CaptureView() }
            .sheet(isPresented: $editingNote) { NoteEditor() }
            .sheet(isPresented: $joiningAnother) { CircleGateView(another: true) }
            .refreshable {
                Haptics.refreshed()
                // SwiftUI cancels a pull's own task as soon as the state it is
                // refreshing changes, which cut the pass short after the first
                // response: Returned and the queued upload never ran. The
                // pass runs as its own task and the pull waits on it.
                await Task {
                    await state.refreshToday()
                    await state.flushPendingCapture()
                }.value
            }
            .task {
                await state.refreshToday()
                await state.flushPendingCapture()
            }
          }
        }
    }
}

/// Today with nothing on it: a note tucked into the journal, written by hand,
/// and the camera large beneath it, because the day's photo is the one thing
/// to do here. The floating camera stays where it always is.
struct TodayEmptyPage: View {
    @Environment(AppState.self) private var state
    let onCapture: () -> Void

    var body: some View {
        VStack(spacing: 34) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Nothing here yet.")
                    .font(.hand(32, bold: true, relativeTo: .title))
                Text("Your circle's first moment is waiting.")
                    .font(.hand(22, relativeTo: .title3))
                    .foregroundStyle(.secondary)
                Rule(weight: 0.5)
                    .padding(.top, 10)
                Text("Photos live for six days, then they're gone.")
                    .smallCaps()
                    .padding(.top, 2)
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 24)
            .padding(.vertical, 28)
            .frame(maxWidth: .infinity, alignment: .leading)
            .paperInsert(tilt: -0.8)
            .accessibilityElement(children: .combine)
            VStack(spacing: 12) {
                CaptureButton(disabled: state.holdsTheDay, diameter: 78, action: onCapture)
                Button(action: onCapture) {
                    Text("Take today's photo")
                        .font(.hand(20, relativeTo: .body))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 12)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(state.holdsTheDay)
                // The camera above already says it.
                .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.top, 6)
        .padding(.bottom, 24)
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

    /// Written at the head of the page in a hand, the day and then its date,
    /// with the rest of the line ruled off in ink.
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(title)
                .font(.hand(30, bold: true, relativeTo: .title))
                .lineLimit(1)
                .fixedSize()
            Text(date, format: .dateTime.day().month(.wide))
                .font(.hand(17, relativeTo: .subheadline))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .fixedSize()
            Rule(weight: 0.5)
                .frame(maxWidth: .infinity)
                .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 4 }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// Today's masthead: the circle on screen as the journal's name, written in
/// a hand and opening the others, then the paper's double rule, the day in
/// small capitals and a hairline. It scrolls away with the page.
struct TodayMasthead: View {
    let onJoinAnother: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            CircleSwitcher(onJoinAnother: onJoinAnother)
            VStack(spacing: 2) {
                Rule(weight: 1.5)
                Rule(weight: 0.5)
            }
            Text(Date.now.formatted(.dateTime.weekday(.wide).month(.wide).day().year()))
                .smallCaps()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            OfflineLine()
            Rule(weight: 0.5)
        }
        .padding(.top, 8)
        // Room under the rule before the page begins (build 22).
        .padding(.bottom, 10)
    }
}

/// The circle on screen, as the title of Today, and the way to the others:
/// every circle this person is in (a check by the one showing), and joining
/// another. Names only, in the order they were joined, nothing ranked.
struct CircleSwitcher: View {
    @Environment(AppState.self) private var state
    let onJoinAnother: () -> Void

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
            Button(action: onJoinAnother) {
                Label("Join another circle", systemImage: "plus")
            }
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                // The journal's name, written on its cover.
                Text(name)
                    .font(.hand(40, bold: true, relativeTo: .largeTitle))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Image(systemName: "chevron.down")
                    .font(.footnote.weight(.bold))
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
        .accessibilityHint("Switch circles, or join another")
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
    static let size: CGFloat = 56
    @AppStorage("stanley.atmosphere") private var raw = "auto"
    let disabled: Bool
    /// Larger where it's the page's one thing to do (an empty Today).
    var diameter: CGFloat = CaptureButton.size
    let action: () -> Void

    var body: some View {
        let palette = Atmosphere.resolve(raw).palette
        Button(action: action) {
            Image(systemName: "camera.fill")
                .font(.system(size: 21 * diameter / Self.size, weight: .semibold))
                .foregroundStyle(palette.ink)
                .frame(width: diameter, height: diameter)
                .background {
                    Circle()
                        .fill(palette.accent)
                        .overlay(Circle().strokeBorder(.white.opacity(0.18), lineWidth: 1))
                        .shadow(color: .black.opacity(0.22), radius: 10, y: 4)
                }
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
    /// Who, then what they remember: the name in bold at full strength, the
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
        line.swiftUI.foregroundColor = .primary
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

/// The heart and the bookmark, at a size a thumb finds on a real device: a
/// 22pt glyph (about 24pt tall) inside a 44pt target, Apple's minimum. One
/// size for both, everywhere they appear, so they never drift apart. Views
/// read the glyph through `@ScaledMetric`, so it grows with Dynamic Type.
enum GestureIcon {
    static let glyph: CGFloat = 22
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
    /// A print's photo is cut nearly square inside its border (`asPrint`).
    var cornerRadius: CGFloat = PrintStock.photoCorner

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

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    }

    var body: some View {
        Group {
            if let urls = photo.urls, let url = state.api.absoluteURL(urls.image) {
                bed(url)
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
                    Rectangle().fill(.quaternary)
                }
            }
            .clipped()
    }

    /// The bookmark and the heart, on the photo itself. Personal state, never
    /// a public signal: they say "you held this" and "you liked this", only
    /// to you, and never how many did. Both are buttons, because people reach
    /// for them; pressing and holding the photo, and double-tapping it, do
    /// the same.
    private var gestures: some View {
        HStack(spacing: -6) {
            Button { toggleHold() } label: {
                marker(photo.anchoredByMe ? "bookmark.fill" : "bookmark",
                       photo.anchoredByMe ? .accentColor : .white)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(photo.anchoredByMe ? "Let go of this memory" : "Hold this memory")
            Button { like() } label: {
                marker(photo.likedByMe ? "heart.fill" : "heart",
                       photo.likedByMe ? .pink : .white)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(photo.likedByMe ? "Unlike" : "Like")
            .accessibilityValue(photo.likedByMe ? "You liked this" : "")
        }
        .padding(2)
    }

    /// A gesture marker on the photo, legible over a white sky and a black
    /// room alike. The material disc carries a soft shadow and the glyph its
    /// own, so neither dissolves into the picture. The glyph is the shared
    /// gesture size, and the whole 44pt square around the disc takes the
    /// tap. The outline is drawn a weight heavier than the default so an
    /// empty heart reads as clearly as a full one.
    private func marker(_ systemName: String, _ tint: Color) -> some View {
        Image(systemName: systemName)
            .font(.system(size: glyph, weight: .semibold))
            .foregroundStyle(tint)
            .contentTransition(.symbolEffect(.replace))
            .shadow(color: .black.opacity(0.3), radius: 2)
            .padding(6)
            .background {
                Circle()
                    .fill(.ultraThinMaterial)
                    .shadow(color: .black.opacity(0.22), radius: 4, y: 1)
            }
            .frame(minWidth: GestureIcon.target, minHeight: GestureIcon.target)
            .contentShape(Rectangle())
            .padding(4)
    }

    private func hold() {
        guard !photo.anchoredByMe else { return }
        // Felt as the bookmark fills, with the settle: a memory kept.
        Haptics.held()
        withAnimation(.easeOut(duration: 0.2)) { holdProgress = 0 }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.6)) { settleScale = 0.97 }
        withAnimation(.spring(response: 0.45, dampingFraction: 0.7).delay(0.12)) { settleScale = 1 }
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

    /// The double-tap heart: white, in the middle of the photo, up from 0.8
    /// to 1.2 and back to 1 in half a second, then faded out. The photo
    /// itself is never tinted. Still, without the scale, under Reduce Motion.
    private var likeHeart: some View {
        Image(systemName: "heart.fill")
            .font(.system(size: 80))
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.25), radius: 8)
            .keyframeAnimator(
                initialValue: HeartPop(scale: reduceMotion ? 1 : 0.8), trigger: heartPops
            ) { heart, pop in
                heart.scaleEffect(pop.scale).opacity(pop.opacity)
            } keyframes: { _ in
                KeyframeTrack(\.scale) {
                    CubicKeyframe(reduceMotion ? 1 : 1.2, duration: 0.2)
                    CubicKeyframe(1, duration: 0.3)
                }
                KeyframeTrack(\.opacity) {
                    LinearKeyframe(1, duration: 0.08)
                    LinearKeyframe(1, duration: 0.42)
                    LinearKeyframe(0, duration: 0.2)
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
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

/// One entry in the journal: the print laid on the page, then beneath it in
/// ink, with no frame around any of it: who and when in a hand, the
/// caption, the place, who was there, the stories and the line that asks
/// for the next.
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
            PhotoImageView(photo: photo)
                .asPrint(border: density.isRoom ? 9 : 7, tilt: PrintTilt.degrees(photo.id))
                .padding(.bottom, 6)
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

    /// Who and when in a hand, then the caption, place and who was there,
    /// with the owner's faces button and the photo's "…" menu at the end of
    /// the first line. Always drawn, so the menu (report, delete, untag) is
    /// there on every print, not only behind a long press.
    private var words: some View {
        let caption = photo.caption.flatMap { $0.isEmpty ? nil : $0 }
        let place = photo.location.flatMap { $0.isEmpty ? nil : $0 }
        return HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                PrintByline(owner: photo.owner, time: photo.takenAt) {
                    if let ownerId = photo.owner.id { viewedMember = ViewedMember(id: ownerId) }
                }
                .padding(.bottom, 2)
                if let caption {
                    Text(caption).font(.body)
                }
                if let place {
                    Text(place).font(.footnote).italic().foregroundStyle(.secondary)
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
        .padding(.horizontal, 2)
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
            .padding(.horizontal, 2)
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
            .padding(.horizontal, 2)
            .creaseSafe(density)
    }
}

/// A shared moment (Part 3): one event, many phones, as a loose run of
/// prints from the same place and day. The place is written above them with
/// the faces of who posted from it (never a count); each print keeps its own
/// name, like, Held and decay.
struct MomentCard: View {
    @Environment(\.horizontalSizeClass) private var hSizeClass
    private var density: Density { Density(hSizeClass) }
    let item: FeedItem
    @State private var viewedMember: ViewedMember?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .bottom, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("together, from your circle")
                        .smallCaps()
                    Text(item.location ?? "Shared moment")
                        .font(.hand(22, bold: true, relativeTo: .title3))
                }
                Spacer()
                if let members = item.members {
                    FaceCluster(
                        faces: members.map { (id: $0.id ?? $0.displayName, url: $0.avatarUrl, name: $0.displayName) },
                        size: 28
                    )
                }
            }
            .padding(.horizontal, 2)
            // Inner display: two prints side by side at a size worth looking
            // at, with a sliver of the third so it's clear there is more.
            // Outer display: the same run, narrowed to fit.
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 16) {
                    ForEach(item.photos ?? []) { photo in
                        VStack(alignment: .leading, spacing: 10) {
                            PhotoImageView(photo: photo)
                                .asPrint(border: 6, tilt: PrintTilt.degrees(photo.id))
                            PrintByline(owner: photo.owner, time: photo.takenAt, size: 16) {
                                if let ownerId = photo.owner.id { viewedMember = ViewedMember(id: ownerId) }
                            }
                            .padding(.horizontal, 4)
                        }
                        .containerRelativeFrame(.horizontal) { length, _ in
                            density.momentTileWidth(container: length)
                        }
                    }
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 4)
            }
            .scrollTargetBehavior(.viewAligned)
        }
        .sheet(item: $viewedMember) { member in
            MemberProfileView(memberId: member.id)
                .presentationDetents([.medium, .large])
        }
    }
}

/// The community note (Part 4), as a sticky note stuck to the first page of
/// the day: the circle's one shared line, in a hand, with a strip of tape.
/// Not a chat — tapping it just lets you write a new one over it.
struct NoteBar: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let note: CommunityNote?
    let onTap: () -> Void
    /// Bumped when the note's words change while it's on screen, to lift it
    /// off the board and settle it again.
    @State private var lifts = 0
    /// Not on the first load: the note arriving isn't someone changing it.
    @State private var settled = false

    /// Sticky-note yellow, always, because that's what makes it a sticky
    /// note: bright in the light, and in the dark a step down, as if under a
    /// lamp, so it doesn't glare off a black page. The ink is a soft pencil
    /// on both.
    private var paper: Color {
        colorScheme == .dark ? Color(red: 0.80, green: 0.72, blue: 0.40) : Color(red: 0.99, green: 0.93, blue: 0.62)
    }

    private var ink: Color { Color(red: 0.22, green: 0.18, blue: 0.10) }

    /// Stuck on a little crooked, between one and two degrees, and not the
    /// same way every time: each note's angle comes from its words (build 19).
    private var tilt: Double {
        guard let text = note?.text else { return -1.4 }
        let h = text.unicodeScalars.reduce(UInt32(7)) { $0 &* 31 &+ $1.value }
        let angle = 1.0 + Double(h % 11) / 10.0
        return h % 3 == 0 ? angle : -angle
    }

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                if let note {
                    Text(note.text)
                        .font(.hand(20, bold: true))
                        .fixedSize(horizontal: false, vertical: true)
                    Text("— \(note.author.displayName)")
                        .font(.hand(15, relativeTo: .footnote))
                        .opacity(0.7)
                } else {
                    Text("Leave a note for the circle…")
                        .font(.hand(18))
                        .opacity(0.55)
                }
            }
            .foregroundStyle(ink)
            .padding(.horizontal, 18)
            .padding(.top, 24)
            .padding(.bottom, 16)
            // A written note is a square-ish sticky; an empty one is a slip,
            // so it doesn't take the first page for an invitation.
            .frame(maxWidth: 300, minHeight: note == nil ? 0 : 110, alignment: .topLeading)
            .background {
                Rectangle()
                    .fill(paper)
                    .overlay(
                        // Paper isn't flat: a little lighter where the light
                        // falls, a little deeper at the curl, and a grain.
                        LinearGradient(
                            colors: [.white.opacity(0.10), .clear, .black.opacity(0.05)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
                    .overlay(PaperGrainView(strength: 0.55).clipped())
                    .shadow(color: .black.opacity(colorScheme == .dark ? 0.5 : 0.16), radius: 6, x: 1, y: 3)
            }
            // Taped to the page across its top edge, the way a note is
            // stuck in a journal: half the tape on the note, half on the page.
            .overlay(alignment: .top) {
                Tape().offset(y: -10)
            }
            .keyframeAnimator(initialValue: 0.0, trigger: lifts) { content, lift in
                content
                    .scaleEffect(1 + 0.035 * lift, anchor: .top)
                    .rotationEffect(.degrees(tilt * (1 - 0.6 * lift)), anchor: .top)
                    .offset(y: -5 * lift)
                    .shadow(color: .black.opacity(0.16 * lift), radius: 14 * lift, y: 10 * lift)
            } keyframes: { _ in
                // Up off the board, then back down with a little give.
                KeyframeTrack {
                    CubicKeyframe(1, duration: 0.22)
                    SpringKeyframe(0, duration: 0.7, spring: .init(duration: 0.6, bounce: 0.35))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.leading, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityLabel(note.map { "Note from \($0.author.displayName): \($0.text)" } ?? "Leave a note for the circle")
        .accessibilityHint("Write the circle's note")
        .onChange(of: note?.text) { _, words in
            if settled, words != nil, !reduceMotion { lifts += 1 }
        }
        .task {
            try? await Task.sleep(for: .seconds(1.5))
            settled = true
        }
    }
}

/// A strip of tape over the top edge of the note, holding it to the page
/// (build 22; a red pushpin from build 19 to 21): translucent cream, so the
/// note's yellow and the page both show through, a little crooked, catching
/// the light along its length, with the faintest shadow at its edges.
private struct Tape: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 1.5, style: .continuous)
        shape
            .fill(Color(red: 0.98, green: 0.96, blue: 0.90).opacity(colorScheme == .dark ? 0.55 : 0.62))
            .overlay(
                LinearGradient(
                    colors: [.white.opacity(0.35), .clear, .white.opacity(0.15)],
                    startPoint: .leading, endPoint: .trailing
                )
                .clipShape(shape)
            )
            .overlay(shape.strokeBorder(.white.opacity(0.4), lineWidth: 0.5))
            .frame(width: 66, height: 22)
            .shadow(color: .black.opacity(0.14), radius: 2, y: 1)
            .rotationEffect(.degrees(-6))
            .accessibilityHidden(true)
    }
}

struct NoteEditor: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""

    private let limit = 90

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("One line for the whole circle", text: $text, axis: .vertical)
                        .lineLimit(1...3)
                        .onChange(of: text) { _, new in
                            if new.count > limit { text = String(new.prefix(limit)) }
                        }
                } footer: {
                    Text("Everyone sees this line. It clears at the end of the day — it's a sticky note, not a chat.")
                }
                .atmosphereRows()
            }
            .atmosphereWash()
            .navigationTitle("Today's note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Set") {
                        let line = text.trimmingCharacters(in: .whitespacesAndNewlines)
                        // Sealed when it's on the board, not before: a note
                        // that didn't save gets no tap.
                        Task { if await state.setNote(line) { Haptics.noteSealed() } }
                        dismiss()
                    }
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear { text = state.communityNote?.text ?? "" }
        }
    }
}

/// The one quiet Returned card (§14), set apart from circle content. Rescue is
/// time-critical (keep your own fading photo); anniversary and near-forgotten
/// resurface held memories. Two distinct exits: Rest (never again) and
/// Dismiss (not now).
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
                    .font(.hand(24, bold: true, relativeTo: .title3))
                Text("Your week, all at once.")
                    .smallCaps()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            // It arrives rather than appears: a slow fade on first sight.
            .opacity(headerShown ? 1 : 0)
            .task {
                guard !headerShown else { return }
                withAnimation(.easeIn(duration: 0.8)) { headerShown = true }
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
                            .font(.hand(19, bold: true, relativeTo: .headline))
                        if let caption = tile.caption, !caption.isEmpty {
                            Text(caption)
                                .font(.hand(16, relativeTo: .subheadline))
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
        .padding(density.cardPadding + 4)
        // A sheet of its own tucked into the journal, not a card on it.
        .paperInsert()
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
            .clipShape(RoundedRectangle(cornerRadius: PrintStock.photoCorner, style: .continuous))
            .asPrint(border: 6)
            .padding(.horizontal, 6)
            .padding(.vertical, 8)
    }
}

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
                        .font(.hand(22, bold: true, relativeTo: .title3))
                    if !subheading.isEmpty {
                        Text(subheading).smallCaps()
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
                    .clipShape(RoundedRectangle(cornerRadius: PrintStock.photoCorner, style: .continuous))
                    .asPrint(border: 6, tilt: PrintTilt.degrees(item.photo.id))
                    .padding(.vertical, 4)
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
                Button("Rest this memory") {
                    Task { await state.restReturned(photoId: item.photo.id) }
                }
                Spacer()
                Button("Dismiss") {
                    Task { await state.dismissReturned() }
                }
            }
            .font(.callout)
            .foregroundStyle(.secondary)
            .padding(.top, 2)
        }
        .padding(density.cardPadding + 4)
        // Set apart from the circle's own pages: a slip of paper tucked in
        // among them, lying a little crooked.
        .paperInsert(tilt: -0.5)
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
                        .asPrint(border: density.isRoom ? 9 : 7)
                        .padding(.bottom, 4)
                    if let caption = photo.caption, !caption.isEmpty {
                        Text(caption).font(.body)
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
                    .clipShape(RoundedRectangle(cornerRadius: PrintStock.photoCorner, style: .continuous))
                    // Held back a little until it's real for everyone else.
                    .opacity(pending.rejection == nil ? 0.72 : 0.5)
                    .asPrint(border: density.isRoom ? 9 : 7)
                    .padding(.bottom, 6)
            }
            if let caption = pending.caption, !caption.isEmpty {
                Text(caption).font(.body)
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
                        .font(.hand(16, relativeTo: .subheadline))
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

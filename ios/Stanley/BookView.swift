import SwiftUI
import UIKit

// The Journal tab (build 46): the pages themselves. There's no cover and
// nothing to open: the tab lands on today's page, and a swipe to the right
// turns back through everything before it. Pages turn with the system's own
// page curl, which follows the finger and is the one page turn on iOS that
// feels like paper. Along the foot of the page, either side of its number,
// are Letters and the circle's questions, which aren't pages (build 49;
// build 48 had them at the head of the page, build 46 as paper tabs at its
// edge). Down the right of the page is the rest of the book seen edge-on,
// with a ribbon to drag back through time and the months marked along it.
// A pinch in lays the pages out small.

// MARK: - Turning pages

/// One page, hosted for the page controller.
private final class PageHost: UIHostingController<AnyView> {
    let pageID: String

    init(pageID: String, root: AnyView) {
        self.pageID = pageID
        super.init(rootView: root)
        // The page lays itself out to the screen's safe edges by hand
        // (`BookLayout`); the host adds none of its own.
        safeAreaRegions = []
        view.backgroundColor = BookPaper.pageUI
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }
}

/// The page controller, in a view a little wider than the page: the strip
/// down the right is the book's fore-edge, drawn over it by `BookEdge`. The
/// pages stop short of it, so it stays put while they turn; the gestures
/// are on the whole of it, so a swipe begun at the very edge of the screen
/// still turns a page.
private final class TurnerHost: UIViewController {
    let pages: UIPageViewController

    init(pages: UIPageViewController) {
        self.pages = pages
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        addChild(pages)
        pages.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(pages.view)
        NSLayoutConstraint.activate([
            pages.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            pages.view.topAnchor.constraint(equalTo: view.topAnchor),
            pages.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            pages.view.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -BookLayout.edge),
        ])
        pages.didMove(toParent: self)
    }
}

/// The pages, turning. A `UIPageViewController` with the page curl, the
/// spine on the left; with Reduce Motion on, pages slide instead.
private struct PageTurner: UIViewControllerRepresentable {
    let ids: [String]
    /// Changes when anything on any page does, so pages kept ready on
    /// either side are made again.
    let version: Int
    /// The page to show, by name. A position would mean a different page
    /// the moment pages arrived ahead of it (a photo kept, a letter opened,
    /// the rest of the book still loading); a name doesn't.
    @Binding var current: String?
    let curl: Bool
    /// Whether going to a page (a tap on the tab, a letter picked) turns a
    /// page to get there. Not while the ribbon is being dragged.
    let animatesJumps: Bool
    let page: (Int) -> AnyView
    var onTurn: () -> Void = {}
    var onPinchIn: () -> Void = {}
    /// The ribbon is being dragged: how far down the page the finger is.
    var onScrub: (CGFloat) -> Void = { _ in }
    var onScrubEnd: () -> Void = {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> TurnerHost {
        let coordinator = context.coordinator
        let controller = UIPageViewController(
            transitionStyle: curl ? .pageCurl : .scroll,
            navigationOrientation: .horizontal,
            options: curl ? [.spineLocation: UIPageViewController.SpineLocation.min.rawValue] : nil
        )
        controller.isDoubleSided = false
        controller.dataSource = coordinator
        controller.delegate = coordinator
        controller.view.backgroundColor = BookPaper.pageUI
        let host = TurnerHost(pages: controller)
        host.loadViewIfNeeded()

        // A drag up or down the fore-edge moves the ribbon. The page turn
        // waits to hear it isn't one, which it knows on the first movement.
        let scrub = UIPanGestureRecognizer(target: coordinator, action: #selector(Coordinator.scrubbed(_:)))
        scrub.delegate = coordinator
        scrub.maximumNumberOfTouches = 1
        host.view.addGestureRecognizer(scrub)
        coordinator.scrub = scrub

        for recognizer in controller.gestureRecognizers {
            // The curl also turns a page on a tap near either edge, which
            // would turn it under a tap meant for a photo or for today's
            // page. Pages turn by swipe.
            if recognizer is UITapGestureRecognizer {
                recognizer.isEnabled = false
                continue
            }
            // The curl's own drag, moved out to the wider view (as the
            // page controller allows), so it's felt over the fore-edge too.
            host.view.addGestureRecognizer(recognizer)
            recognizer.require(toFail: scrub)
        }
        // Sliding pages (Reduce Motion) are a scroll view's.
        for case let scroll as UIScrollView in controller.view.subviews {
            scroll.panGestureRecognizer.require(toFail: scrub)
        }
        let pinch = UIPinchGestureRecognizer(target: coordinator, action: #selector(Coordinator.pinched(_:)))
        host.view.addGestureRecognizer(pinch)

        coordinator.version = version
        coordinator.controller = controller
        if let first = coordinator.host(current.flatMap(ids.firstIndex(of:)) ?? 0) {
            controller.setViewControllers([first], direction: .forward, animated: false)
        }
        return host
    }

    func updateUIViewController(_ host: TurnerHost, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        coordinator.show(animated: animatesJumps)
    }

    final class Coordinator: NSObject, UIPageViewControllerDataSource, UIPageViewControllerDelegate,
        UIGestureRecognizerDelegate {
        var parent: PageTurner
        var version = 0
        /// A page is mid-turn: nothing else may be set until it lands.
        var turning = false
        weak var controller: UIPageViewController?
        weak var scrub: UIPanGestureRecognizer?
        private var pinchFired = false

        init(_ parent: PageTurner) { self.parent = parent }

        /// Bring what's showing in line with what was asked for: the same
        /// page drawn afresh, or a turn to another. Asked again whenever a
        /// turn lands, in case something changed while it was in the air.
        func show(animated: Bool) {
            guard let controller, !parent.ids.isEmpty else { return }
            let ids = parent.ids
            let shown = controller.viewControllers?.first as? PageHost
            // A page that's no longer in the book: the book says where to
            // go next (`BookView.follow`); until it does, stay put.
            guard let wanted = parent.current ?? shown?.pageID, let target = ids.firstIndex(of: wanted) else { return }
            if let shown, shown.pageID == wanted {
                shown.rootView = parent.page(target)
                // Sliding pages keep their neighbors ready; a neighbor made
                // before something changed would show the old page.
                if !parent.curl, version != parent.version, !turning, let fresh = host(target) {
                    controller.setViewControllers([fresh], direction: .forward, animated: false)
                }
                version = parent.version
                return
            }
            guard !turning, let next = host(target) else { return }
            version = parent.version
            let from = shown.flatMap { ids.firstIndex(of: $0.pageID) }
            let turns = animated && from != nil
            if turns { turning = true }
            controller.setViewControllers(
                [next], direction: (from ?? 0) <= target ? .forward : .reverse, animated: turns
            ) { [weak self] _ in
                guard let self, turns else { return }
                self.turning = false
                self.show(animated: false)
            }
        }

        func host(_ index: Int) -> PageHost? {
            guard parent.ids.indices.contains(index) else { return nil }
            return PageHost(pageID: parent.ids[index], root: parent.page(index))
        }

        private func index(of controller: UIViewController) -> Int? {
            (controller as? PageHost).flatMap { parent.ids.firstIndex(of: $0.pageID) }
        }

        func pageViewController(
            _ pageViewController: UIPageViewController, viewControllerBefore viewController: UIViewController
        ) -> UIViewController? {
            index(of: viewController).flatMap { host($0 - 1) }
        }

        func pageViewController(
            _ pageViewController: UIPageViewController, viewControllerAfter viewController: UIViewController
        ) -> UIViewController? {
            index(of: viewController).flatMap { host($0 + 1) }
        }

        func pageViewController(
            _ pageViewController: UIPageViewController, willTransitionTo pendingViewControllers: [UIViewController]
        ) {
            turning = true
        }

        func pageViewController(
            _ pageViewController: UIPageViewController, didFinishAnimating finished: Bool,
            previousViewControllers: [UIViewController], transitionCompleted completed: Bool
        ) {
            turning = false
            guard completed, let shown = pageViewController.viewControllers?.first as? PageHost,
                  parent.ids.contains(shown.pageID)
            else { return }
            parent.current = shown.pageID
            parent.onTurn()
        }

        @objc func pinched(_ recognizer: UIPinchGestureRecognizer) {
            switch recognizer.state {
            case .began:
                pinchFired = false
            case .changed where !pinchFired && recognizer.scale < 0.8:
                pinchFired = true
                parent.onPinchIn()
            default:
                break
            }
        }

        @objc func scrubbed(_ recognizer: UIPanGestureRecognizer) {
            switch recognizer.state {
            case .began, .changed:
                parent.onScrub(recognizer.location(in: recognizer.view).y)
            case .ended, .cancelled, .failed:
                parent.onScrubEnd()
            default:
                break
            }
        }

        /// Only a drag that begins at the fore-edge (or a thumb's width in
        /// from it) and sets off up or down is the ribbon's. Anything else,
        /// a swipe from the screen's edge included, is a page being turned.
        func gestureRecognizerShouldBegin(_ recognizer: UIGestureRecognizer) -> Bool {
            guard recognizer === scrub, let pan = recognizer as? UIPanGestureRecognizer, let view = pan.view else {
                return true
            }
            let velocity = pan.velocity(in: view)
            let moved = pan.translation(in: view)
            // Where the finger came down, not where it's got to.
            let began = pan.location(in: view).x - moved.x
            return began >= view.bounds.width - BookLayout.edge - 16 && abs(velocity.y) > abs(velocity.x)
        }
    }
}

// MARK: - The journal

/// What's being written.
enum WritingTarget: Identifiable {
    case today
    case page(DayPage)

    var id: String {
        switch self {
        case .today: "today"
        case .page(let page): page.id
        }
    }
}

struct BookView: View {
    @Environment(AppState.self) private var state
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("stanley.atmosphere") private var raw = "auto"

    /// Where the journal was last asked to be: today's page, each time the
    /// tab is come to; a day's page, from the widget.
    @State private var start = BookStart.today
    /// The page in view, by name, so it's still the page in view when the
    /// book changes under it (a page written, one torn out, more of the
    /// book arriving).
    @State private var currentID: String?
    /// Where that page last was in the book, for when it's torn out.
    @State private var lastIndex = 0
    /// A page has been turned by hand: the book no longer follows where it
    /// was asked to be.
    @State private var touched = false
    @State private var animatesJumps = true
    /// The page as it's laid out, for the writing that lies over it.
    @State private var shown: BookLayout?
    /// A keyboard is up, or on its way.
    @State private var typing = false

    @State private var grid = false
    @State private var scrubbing = false
    @State private var writing: WritingTarget?
    @State private var viewing = false
    @State private var openedPhoto = ""
    @State private var readingLetters = false
    @State private var readingPrompts = false
    @State private var reflecting = false
    @State private var tearingOut: DayPage?
    @State private var forgetting: Reflection?
    @State private var discarding: Letter?
    @State private var reporting: Letter?

    private var palette: Atmosphere.Palette { Atmosphere.resolve(raw).palette }

    /// The page keeps its size: something is up that brings a keyboard
    /// (writing, or a sheet with a field in it), or one is showing.
    private var held: Bool {
        writing != nil || typing || readingLetters || readingPrompts || reflecting || reporting != nil
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            // This reader keeps inside the safe edges so that it can say
            // where they are; what it holds then runs out over the top and
            // the sides. (A reader that ignored them itself said there were
            // none.) It stops at the tab bar: nothing turns under the bar.
            GeometryReader { geo in
                let insets = geo.safeAreaInsets
                let room = CGSize(
                    width: geo.size.width + insets.leading + insets.trailing,
                    height: geo.size.height + insets.top
                )
                // The page: everything but the fore-edge, and but the strip
                // a dock takes down the side of the Duo's cover.
                let measured = BookLayout(
                    size: CGSize(width: room.width - insets.trailing - BookLayout.edge, height: room.height),
                    safeTop: insets.top, safeLeading: insets.leading
                )
                // A keyboard takes room from this reader whatever it's told
                // to ignore (seen on iOS 26.5: the page was measured again
                // at half its height, and every long day broke anew). So
                // while there could be one, the page is the size it was.
                let layout = (held ? shown : nil) ?? measured
                let full = CGSize(width: room.width, height: layout.height)
                let book = BookBuilder.book(state, layout: layout)
                let ids = book.pages.map(\.id)
                let found = currentID.flatMap(book.index(id:))
                // Where the page in view is; or, for the moment after it has
                // gone and before `follow` has chosen another, where it was.
                let index = found ?? min(lastIndex, max(book.pages.count - 1, 0))
                ZStack(alignment: .topLeading) {
                    // What's past the book's edge, where anything is.
                    palette.floor
                        .accessibilityHidden(true)
                    pages(book, layout: layout, ids: ids, index: index)
                    // The page and the book's edge go on down behind the
                    // tab bar; nothing on them does.
                    // (Taller than any bar: the reader isn't told how much
                    // room the bar takes, only that it stops above it.)
                    BookFoot(layout: layout, height: 160, beyond: insets.trailing, floor: palette.floor)
                        .offset(y: full.height)
                }
                .frame(width: full.width, height: full.height, alignment: .topLeading)
                .ignoresSafeArea(.container, edges: [.top, .horizontal])
                .onChange(of: layout, initial: true) { _, layout in
                    shown = layout
                    BookLayout.shown = layout
                }
                .onChange(of: ids) { _, _ in follow(book) }
                .onChange(of: found, initial: true) { _, at in
                    if let at { lastIndex = at }
                }
                // The tab was come to (today's page), or the widget asked
                // for a day's.
                .onChange(of: state.journalAsked, initial: true) { _, _ in
                    start = state.journalDay.map { .day($0) } ?? .today
                    state.journalDay = nil
                    // A page half written stays where it is.
                    guard writing == nil else { return }
                    touched = false
                    grid = false
                    place(book)
                }
                // A tap on the Journal tab while it's showing: back to
                // today's page, and everything fetched again.
                .onChange(of: state.tabTaps.held) { _, _ in
                    guard writing == nil else { return }
                    grid = false
                    if index == book.todayIndex { Haptics.refreshed() } else { jump(to: book.todayIndex, in: book) }
                    Task { await load() }
                }
            }
            // A keyboard doesn't move the pages; the writing below rides it.
            .ignoresSafeArea(.keyboard)

            if let target = writing, let shown {
                PageWriting(target: target, layout: shown) { writing = nil }
                    .tint(palette.accent)
            }
        }
        .fullScreenCover(isPresented: $viewing) {
            HeldViewer(current: $openedPhoto)
        }
        .sheet(isPresented: $readingLetters) {
            NavigationStack {
                LettersPage { letter in
                    readingLetters = false
                    turn(to: "l-\(letter.id)-0")
                }
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) { Button("Done") { readingLetters = false } }
                }
            }
        }
        .sheet(isPresented: $readingPrompts) {
            NavigationStack {
                CircleJournalView(title: "Prompts")
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) { Button("Done") { readingPrompts = false } }
                    }
            }
        }
        .sheet(isPresented: $reflecting) {
            if let week = state.thisWeek { ReflectionSheet(week: week) }
        }
        .sheet(item: $reporting) { letter in
            ReportSheet(target: .letter(letter))
        }
        .alert("Tear out this page?", isPresented: present($tearingOut)) {
            Button("Delete", role: .destructive) {
                if let page = tearingOut { Task { await state.deletePage(page) } }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Pages don't fade, so this is the only way one leaves. It's gone for good.")
        }
        .alert("Delete this reflection?", isPresented: present($forgetting)) {
            Button("Delete", role: .destructive) {
                if let reflection = forgetting { Task { await state.deleteReflection(reflection) } }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Reflections don't fade, so this is the only way one leaves. It's gone for good.")
        }
        .alert("Delete this letter?", isPresented: present($discarding)) {
            Button("Delete", role: .destructive) {
                if let letter = discarding { Task { await state.deleteLetter(letter.id) } }
            }
            Button("Keep It", role: .cancel) {}
        } message: {
            Text("The letter is gone for good. Only you had it.")
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            typing = true
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardDidHideNotification)) { _ in
            typing = false
        }
        .task { await load() }
        .onChange(of: state.reloads) { Task { await load() } }
    }

    private func load() async {
        await state.loadBook()
        await state.loadThisWeek()
    }

    private func present<Item>(_ item: Binding<Item?>) -> Binding<Bool> {
        Binding(get: { item.wrappedValue != nil }, set: { if !$0 { item.wrappedValue = nil } })
    }

    /// Begin writing where the page lies: no sheet comes up, the cursor is
    /// simply in the page.
    private func write(_ target: WritingTarget) {
        var instant = Transaction()
        instant.disablesAnimations = true
        withTransaction(instant) { writing = target }
    }

    // MARK: the pages and what lies beside them

    private func pages(_ book: Book, layout: BookLayout, ids: [String], index: Int) -> some View {
        let actions = BookActions(
            write: { write(.today) },
            edit: { write(.page($0)) },
            changeInk: { page, ink in Task { _ = await state.editPage(page, ink: ink) } },
            delete: { tearingOut = $0 },
            openPhoto: { held in
                openedPhoto = held.id
                viewing = true
            },
            deleteReflection: { forgetting = $0 },
            deleteLetter: { discarding = $0 },
            reportLetter: { reporting = $0 }
        )
        let accent = palette.accent
        let state = self.state
        var hasher = Hasher()
        hasher.combine(state.journalPages)
        hasher.combine(state.threads)
        hasher.combine(state.lettersReceived.opened)
        hasher.combine(state.reflections)
        hasher.combine(state.journalTitle)
        hasher.combine(layout)
        let version = hasher.finalize()
        let whole = CGSize(width: layout.width + BookLayout.edge, height: layout.height)
        let count = book.pages.count

        return ZStack(alignment: .topLeading) {
            PageTurner(
                ids: ids, version: version, current: $currentID, curl: !reduceMotion, animatesJumps: animatesJumps,
                page: { at in
                    AnyView(
                        BookPageView(page: book.pages[at], number: at + 1, layout: layout, actions: actions)
                            .environment(state)
                            .tint(accent)
                            .darkRoomInk()
                    )
                },
                onTurn: { touched = true },
                onPinchIn: { withAnimation(.easeOut(duration: 0.25)) { grid = true } },
                onScrub: { y in
                    guard count > 1 else { return }
                    let along = (y - layout.trackTop) / max(layout.trackBottom - layout.trackTop, 1)
                    // The top of the ribbon is today; the foot, the first page.
                    let at = Int(((1 - min(max(along, 0), 1)) * CGFloat(count - 1)).rounded())
                    scrubbing = true
                    animatesJumps = false
                    touched = true
                    if book.pages[at].id != currentID { currentID = book.pages[at].id }
                },
                onScrubEnd: {
                    scrubbing = false
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(150))
                        if !scrubbing { animatesJumps = true }
                    }
                }
            )
            // Made again if Reduce Motion changes: curl or slide is decided
            // when the page controller is.
            .id(reduceMotion)
            .frame(width: whole.width, height: whole.height)
            .accessibilityHidden(grid)

            if book.pages.isEmpty {
                // Nothing fetched yet (or nothing can be): a page all the same.
                BookSheet(layout: layout, lined: true)
                if state.offline {
                    PageHeading(text: "Not here yet.", color: BookPaper.quiet, layout: layout)
                }
            }

            BookEdge(
                book: book, layout: layout, index: index, accent: accent, scrubbing: scrubbing,
                step: { by in jump(to: index + by, in: book) }
            )
            .opacity(grid ? 0 : 1)
            .accessibilityHidden(grid)

            // What isn't a page: Letters and Prompts, either side of the
            // page's number at its foot, over nothing that's on it.
            BookBar(
                layout: layout, accent: accent,
                sealed: !state.lettersReceived.sealed.isEmpty,
                ready: state.lettersReceived.sealed.contains { $0.deliverable == true },
                prompts: state.circle != nil,
                week: state.thisWeek,
                openLetters: { readingLetters = true },
                openPrompts: { readingPrompts = true },
                openWeek: { reflecting = true }
            )
            .opacity(grid ? 0 : 1)
            .accessibilityHidden(grid)

            if grid {
                BookGrid(book: book, layout: layout, current: index, floor: palette.floor, accent: accent) { picked in
                    if let picked, book.pages.indices.contains(picked) {
                        animatesJumps = false
                        currentID = book.pages[picked].id
                        touched = true
                    }
                    withAnimation(.easeOut(duration: 0.25)) { grid = false }
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(300))
                        animatesJumps = true
                    }
                }
                .transition(.opacity.combined(with: .scale(scale: 1.06)))
            }
        }
        .frame(width: whole.width, height: whole.height, alignment: .topLeading)
    }

    // MARK: where the journal is open

    /// Put the journal at the page it was asked to be at.
    private func place(_ book: Book) {
        let at: Int
        switch start {
        case .today: at = book.todayIndex
        case .day(let day): at = book.index(day: day) ?? book.todayIndex
        }
        go(to: at, in: book)
    }

    /// Go to a page without turning the pages between.
    private func go(to at: Int, in book: Book) {
        animatesJumps = false
        currentID = book.pages.indices.contains(at) ? book.pages[at].id : nil
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(120))
            animatesJumps = true
        }
    }

    /// The book changed under the page in view. Before anyone has turned a
    /// page, go where the journal was asked to be (its pages may only now
    /// have arrived). After that the page in view stays the page in view;
    /// if it's the one that went, find the nearest thing to it.
    private func follow(_ book: Book) {
        let stillHere = currentID.flatMap(book.index(id:)) != nil
        // (A page that has gone was taken out by hand, which is as good as
        // a page turned: that's not the book still arriving.)
        if !touched, stillHere || currentID == nil {
            place(book)
            return
        }
        touched = true
        guard let currentID, !stillHere else { return }
        // Today's blank page goes when it's written, and what was written
        // is where to be; a long day's later part goes when the day is cut
        // shorter, and its first part is still there. Otherwise, as near
        // as there is.
        if currentID == "today" {
            go(to: book.todayIndex, in: book)
        } else if let cut = currentID.lastIndex(of: "-"),
                  let first = book.index(id: String(currentID[..<cut]) + "-0") {
            go(to: first, in: book)
        } else {
            go(to: min(lastIndex, max(book.pages.count - 1, 0)), in: book)
        }
    }

    /// Turn to a page: a tap on the tab, a step from VoiceOver.
    private func jump(to target: Int, in book: Book) {
        guard book.pages.indices.contains(target), book.pages[target].id != currentID else { return }
        touched = true
        currentID = book.pages[target].id
    }

    /// Turn to a page by its name, from somewhere the book isn't in hand
    /// (the Letters sheet).
    private func turn(to id: String) {
        guard let shown else { return }
        let book = BookBuilder.book(state, layout: shown)
        if let at = book.index(id: id) { jump(to: at, in: book) }
    }
}

/// The foot of the page and of the book's edge, under the tab bar: paper
/// and nothing on it, so the bar sits on the page.
private struct BookFoot: View {
    @Environment(\.colorScheme) private var colorScheme
    let layout: BookLayout
    let height: CGFloat
    /// What's past the book's edge (the Duo's dock strip), and its color.
    let beyond: CGFloat
    let floor: Color

    var body: some View {
        let dark = colorScheme == .dark
        HStack(spacing: 0) {
            ZStack(alignment: .leading) {
                BookPaper.page
                Image(uiImage: PaperGrain.tile)
                    .resizable(resizingMode: .tile)
                    .opacity(dark ? 0.16 : 0.3)
                    .blendMode(dark ? .screen : .normal)
                LinearGradient(
                    colors: [.black.opacity(dark ? 0.4 : 0.07), .clear], startPoint: .leading, endPoint: .trailing
                )
                .frame(width: 26)
            }
            .frame(width: layout.width)
            ZStack(alignment: .leading) {
                BookPaper.edge
                BookPaper.next.frame(width: 2)
            }
            .frame(width: BookLayout.edge)
            floor.frame(width: beyond)
        }
        .frame(height: height)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - The fore-edge

/// What stays put down the right while the pages turn: the edge of the next
/// page, the rest of the book stacked behind it, the ribbon that says how
/// far back you are (dragged, it goes there), and the months marked along
/// it.
private struct BookEdge: View {
    @Environment(\.colorScheme) private var colorScheme
    let book: Book
    let layout: BookLayout
    let index: Int
    let accent: Color
    let scrubbing: Bool
    /// A page newer (+1) or older (-1), for VoiceOver.
    let step: (Int) -> Void

    /// A month's mark on the ribbon: where it begins, and where its name
    /// goes when there's room for one.
    private struct Mark {
        let y: CGFloat
        let name: String
        let nameTop: CGFloat?
    }

    /// How far down the ribbon a page is: today's at the top, the first
    /// page at the foot.
    private func y(_ at: Int) -> CGFloat {
        let count = book.pages.count
        guard count > 1 else { return layout.trackTop }
        return layout.trackTop + (1 - CGFloat(at) / CGFloat(count - 1)) * (layout.trackBottom - layout.trackTop)
    }

    private var marks: [Mark] {
        var made: [Mark] = []
        // Newest first, so each month's name can sit at the top of its
        // stretch, under the mark before it.
        // (The newest starts a little down, clear of the ribbon's bead
        // when it's at the top, on today's page.)
        var above = layout.trackTop + 5
        for (at, page) in book.pages.enumerated().reversed() {
            guard case .chapter = page.kind else { continue }
            let here = y(at)
            made.append(Mark(
                y: here,
                name: page.date.formatted(.dateTime.month(.abbreviated)).uppercased(),
                nameTop: here - above >= 24 ? above + 4 : nil
            ))
            above = here
        }
        return made
    }

    var body: some View {
        let dark = colorScheme == .dark
        let x0 = layout.width
        let wide = BookLayout.edge
        let at = y(index)
        ZStack(alignment: .topLeading) {
            Canvas { context, size in
                // Every page behind this one, edge-on.
                context.fill(
                    Path(CGRect(x: x0, y: 0, width: wide, height: size.height)), with: .color(BookPaper.edge)
                )
                // The very next page: a sliver of it shows past this one.
                context.fill(Path(CGRect(x: x0, y: 0, width: 2, height: size.height)), with: .color(BookPaper.next))
                let line = Color.black.opacity(dark ? 0.5 : 0.10)
                context.fill(Path(CGRect(x: x0, y: 0, width: 0.5, height: size.height)), with: .color(line))
                context.fill(Path(CGRect(x: x0 + 2, y: 0, width: 0.5, height: size.height)), with: .color(line))
                // This page's shadow on what's under it.
                context.fill(
                    Path(CGRect(x: x0 + 2.5, y: 0, width: 6, height: size.height)),
                    with: .linearGradient(
                        Gradient(colors: [.black.opacity(dark ? 0.35 : 0.07), .clear]),
                        startPoint: CGPoint(x: x0 + 2.5, y: 0), endPoint: CGPoint(x: x0 + 8.5, y: 0)
                    )
                )
                // The months, marked as a thumb index marks its letters.
                let quiet = BookPaper.quiet
                for mark in marks {
                    context.fill(
                        Path(CGRect(x: x0 + 4, y: mark.y.rounded(), width: wide - 10, height: 0.5)),
                        with: .color(quiet.opacity(0.7))
                    )
                    guard let top = mark.nameTop else { continue }
                    var turned = context
                    turned.translateBy(x: x0 + 7, y: top)
                    turned.rotate(by: .degrees(90))
                    turned.draw(
                        Text(mark.name)
                            .font(.system(size: 6.5, weight: .semibold))
                            .tracking(0.7)
                            .foregroundStyle(quiet.opacity(0.9)),
                        at: .zero, anchor: .leading
                    )
                }
                // The ribbon.
                context.fill(
                    Path(roundedRect: CGRect(
                        x: x0 + wide - 6, y: layout.trackTop - 8,
                        width: 3, height: layout.trackBottom - layout.trackTop + 16
                    ), cornerRadius: 1.5),
                    with: .color(accent.opacity(dark ? 0.4 : 0.38))
                )
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)

            // The same, for VoiceOver: a thing to adjust.
            Color.clear
                .frame(width: wide, height: layout.trackBottom - layout.trackTop)
                .offset(x: x0, y: layout.trackTop)
                .allowsHitTesting(false)
                .accessibilityElement()
                .accessibilityLabel("Place in the journal")
                .accessibilityValue(book.pages.indices.contains(index) ? "Page \(index + 1). \(book.pages[index].name)" : "")
                .accessibilityHint("Swipe up for a newer page, down for an older one")
                .accessibilityAdjustableAction { direction in
                    switch direction {
                    case .increment: step(1)
                    case .decrement: step(-1)
                    @unknown default: break
                    }
                }

            // Where you are on the ribbon.
            Circle()
                .fill(accent)
                .overlay(Circle().strokeBorder(BookPaper.edge, lineWidth: 1.5))
                .frame(width: scrubbing ? 13 : 9, height: scrubbing ? 13 : 9)
                .shadow(color: .black.opacity(0.2), radius: 1, y: 0.5)
                .position(x: x0 + wide - 4.5, y: at)
                .animation(scrubbing ? nil : .spring(response: 0.3, dampingFraction: 0.85), value: at)
                .animation(.easeOut(duration: 0.15), value: scrubbing)
                .allowsHitTesting(false)
                .accessibilityHidden(true)

            if scrubbing, book.pages.indices.contains(index) {
                let page = book.pages[index]
                Text(page.heading ?? page.name)
                    .font(.system(.footnote, design: .rounded).weight(.medium))
                    .foregroundStyle(Ink.black.color)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background {
                        Capsule()
                            .fill(BookPaper.page)
                            .overlay(Capsule().strokeBorder(BookPaper.quiet.opacity(0.35), lineWidth: 0.5))
                            .shadow(color: .black.opacity(dark ? 0.5 : 0.14), radius: 6, y: 2)
                    }
                    .frame(width: x0 - 14, alignment: .trailing)
                    .position(x: (x0 - 14) / 2, y: min(max(at, layout.safeTop + 18), layout.height - 20))
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                    .transition(.opacity)
            }
        }
        .frame(width: x0 + wide, height: layout.height, alignment: .topLeading)
        .animation(.easeOut(duration: 0.15), value: scrubbing)
    }
}

// MARK: - The marks at the foot

/// Along the foot of the page, either side of its number: Letters at the
/// left, Prompts at the right, and on Sunday evening the week beside
/// Prompts. Thin marks in the accent, each in a 44pt target, in the band
/// under everything a page holds. They stay put while pages turn. (Build
/// 49. Build 48 had them on the date's line at the head of the page;
/// build 46 as paper tabs at its edge, too small to press.)
private struct BookBar: View {
    let layout: BookLayout
    let accent: Color
    /// A letter written to you is still sealed; and its day has come.
    let sealed: Bool
    let ready: Bool
    let prompts: Bool
    /// The week a reflection would be about, when one can be written.
    let week: ThisWeek?
    let openLetters: () -> Void
    let openPrompts: () -> Void
    let openWeek: () -> Void

    /// A mark's own width.
    private static let glyph: CGFloat = 24

    var body: some View {
        // The week's mark comes and goes with the evening.
        TimelineView(.periodic(from: .now, by: 60)) { context in
            HStack(spacing: 0) {
                mark(
                    "envelope", label: "Letters",
                    hint: ready ? "A letter is ready to open" : sealed ? "A sealed letter is waiting for its day" : "",
                    dot: sealed, action: openLetters
                )
                Spacer(minLength: 0)
                if let week, week.reflection == nil, ReflectionWindow.isOpen(context.date) {
                    mark("moon", label: "How was your week?", hint: "Write this week's reflection", action: openWeek)
                }
                if prompts {
                    mark(
                        "questionmark.bubble", label: "Prompts",
                        hint: "Your circle's questions and what everyone said", action: openPrompts
                    )
                }
            }
            // Each outer mark's own edge is on the writing's margin; its
            // target reaches a little past that.
            .padding(.leading, layout.left - (44 - Self.glyph) / 2)
            .padding(.trailing, layout.width - layout.right - (44 - Self.glyph) / 2)
            .frame(width: layout.width, height: BookLayout.foot)
            .offset(y: layout.height - layout.safeBottom - BookLayout.foot)
        }
    }

    private func mark(
        _ symbol: String, label: String, hint: String, dot: Bool = false, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 20, weight: .light))
                .foregroundStyle(accent)
                .frame(width: Self.glyph, height: Self.glyph)
                .overlay(alignment: .topTrailing) {
                    // A sealed letter is waiting: a dot of wax.
                    if dot {
                        Circle()
                            .fill(Ink.red.color)
                            .overlay(Circle().strokeBorder(BookPaper.page, lineWidth: 1.5))
                            .frame(width: 9, height: 9)
                            .offset(x: 3, y: -1)
                    }
                }
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityHint(hint)
    }
}

// MARK: - The pages, small

/// Every page laid out small, six to a screen, after a pinch in. A tap on
/// one goes to it; a pinch out goes back to the page that was open.
private struct BookGrid: View {
    let book: Book
    let layout: BookLayout
    let current: Int
    let floor: Color
    let accent: Color
    /// The page picked, or nil to go back where it was.
    let done: (Int?) -> Void

    var body: some View {
        let gap: CGFloat = 16
        let side: CGFloat = 20
        let top = layout.safeTop + 44
        // Over the page and the fore-edge both.
        let whole = layout.width + BookLayout.edge
        let width = ((whole - layout.safeLeading - side * 2 - gap) / 2).rounded(.down)
        // Three rows to a screen, so six pages show at once.
        let height = ((layout.height - top - gap * 3) / 3).rounded(.down)
        ZStack(alignment: .top) {
            floor
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVGrid(columns: [GridItem(.fixed(width), spacing: gap), GridItem(.fixed(width))], spacing: gap) {
                        ForEach(Array(book.pages.enumerated()), id: \.element.id) { at, page in
                            Button { done(at) } label: {
                                BookThumb(page: page, number: at + 1, layout: layout, width: width, height: height)
                                    .overlay {
                                        if at == current {
                                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                                .strokeBorder(accent, lineWidth: 1.5)
                                        }
                                    }
                                    .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
                            }
                            .buttonStyle(PressedPrint())
                            .id(page.id)
                            .accessibilityLabel("Page \(at + 1). \(page.name)")
                        }
                    }
                    .padding(.leading, layout.safeLeading + side)
                    .padding(.trailing, side)
                    .padding(.top, top)
                    .padding(.bottom, gap)
                }
                .onAppear {
                    if book.pages.indices.contains(current) {
                        proxy.scrollTo(book.pages[current].id, anchor: .center)
                    }
                }
            }
            // Its own strip under the status bar, with the way back.
            HStack {
                Text("Pages")
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Done") { done(nil) }
                    .wordButton()
            }
            .padding(.leading, layout.safeLeading + side)
            .padding(.trailing, side)
            .frame(height: 44)
            .padding(.top, layout.safeTop)
            .background(floor)
        }
        .frame(width: whole, height: layout.height)
        .simultaneousGesture(
            MagnifyGesture().onEnded { pinch in
                if pinch.magnification > 1.15 { done(nil) }
            }
        )
    }
}

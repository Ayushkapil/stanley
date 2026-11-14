import SwiftUI
import UIKit

// The book, open (build 45). It lies over the whole app, tab bar and all:
// the cover on the Journal tab grows to the middle of the screen and swings
// open on its spine, and the pages are underneath. They turn sideways with
// the system's own page curl, which follows the finger and is the one
// page turn on iOS that feels like paper. A pinch in lays the pages out
// small; a swipe down shuts the book.

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
    /// Whether a jump (the ribbon, a date) turns a page to get there.
    let animatesJumps: Bool
    let page: (Int) -> AnyView
    var onTurn: () -> Void = {}
    var onPinchIn: () -> Void = {}
    var onPull: (CGFloat) -> Void = { _ in }
    var onPullEnd: (CGFloat, CGFloat) -> Void = { _, _ in }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> UIPageViewController {
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

        // The curl also turns a page on a tap near either edge, which
        // would turn it under a tap meant for a photo or today's blank
        // page. Pages turn by swipe.
        for recognizer in controller.gestureRecognizers where recognizer is UITapGestureRecognizer {
            recognizer.isEnabled = false
        }
        let pinch = UIPinchGestureRecognizer(target: coordinator, action: #selector(Coordinator.pinched(_:)))
        controller.view.addGestureRecognizer(pinch)
        // A drag straight down shuts the book. The curl waits to hear it
        // isn't one, which it knows on the first movement.
        let pull = UIPanGestureRecognizer(target: coordinator, action: #selector(Coordinator.pulled(_:)))
        pull.delegate = coordinator
        pull.maximumNumberOfTouches = 1
        controller.view.addGestureRecognizer(pull)
        for recognizer in controller.gestureRecognizers where recognizer is UIPanGestureRecognizer {
            recognizer.require(toFail: pull)
        }

        coordinator.version = version
        coordinator.controller = controller
        if let first = coordinator.host(current.flatMap(ids.firstIndex(of:)) ?? 0) {
            controller.setViewControllers([first], direction: .forward, animated: false)
        }
        return controller
    }

    func updateUIViewController(_ controller: UIPageViewController, context: Context) {
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

        @objc func pulled(_ recognizer: UIPanGestureRecognizer) {
            let moved = recognizer.translation(in: recognizer.view).y
            switch recognizer.state {
            case .changed:
                parent.onPull(max(0, moved))
            case .ended:
                parent.onPullEnd(max(0, moved), recognizer.velocity(in: recognizer.view).y)
            case .cancelled, .failed:
                parent.onPullEnd(0, 0)
            default:
                break
            }
        }

        /// Only a drag that sets off downward, and more down than sideways,
        /// is the book being shut.
        func gestureRecognizerShouldBegin(_ recognizer: UIGestureRecognizer) -> Bool {
            guard let pan = recognizer as? UIPanGestureRecognizer else { return true }
            let velocity = pan.velocity(in: pan.view)
            return velocity.y > 0 && abs(velocity.y) > abs(velocity.x) * 1.3
        }
    }
}

// MARK: - The open book

/// What's being written from inside the book.
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
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("stanley.atmosphere") private var raw = "auto"
    let opening: BookOpening

    private enum Stage { case cover, grown, open }
    @State private var stage: Stage = .cover
    /// The cover has swung away and is out of the way of touches.
    @State private var coverGone = false
    @State private var closing = false

    /// The page in view, by name, so it's still the page in view when the
    /// book changes under it (a page written, one torn out, more of the
    /// book arriving).
    @State private var currentID: String?
    /// Where that page last was in the book, for when it's torn out.
    @State private var lastIndex = 0
    /// A page has been turned by hand: the book no longer follows where it
    /// was asked to open.
    @State private var touched = false
    @State private var animatesJumps = true

    @State private var grid = false
    @State private var pull: CGFloat = 0
    @State private var picking = false
    @State private var writing: WritingTarget?
    @State private var viewing = false
    @State private var openedPhoto = ""
    @State private var tearingOut: DayPage?
    @State private var forgetting: Reflection?
    @State private var discarding: Letter?
    @State private var reporting: Letter?

    private var palette: Atmosphere.Palette { Atmosphere.resolve(raw).palette }

    var body: some View {
        // This reader keeps inside the screen's safe edges so that it can
        // say where they are; what it holds then runs out over them. (A
        // reader that ignored them itself said there were none.)
        GeometryReader { geo in
            let insets = geo.safeAreaInsets
            let full = CGSize(
                width: geo.size.width + insets.leading + insets.trailing,
                height: geo.size.height + insets.top + insets.bottom
            )
            let layout = BookLayout(
                size: full, safeTop: insets.top, safeBottom: insets.bottom,
                safeLeading: insets.leading, safeTrailing: insets.trailing
            )
            let book = BookBuilder.book(state, layout: layout)
            let ids = book.pages.map(\.id)
            let found = currentID.flatMap(book.index(id:))
            // Where the page in view is; or, for the moment after it has
            // gone and before `follow` has chosen another, where it was.
            let index = found ?? min(lastIndex, max(book.pages.count - 1, 0))
            ZStack {
                // The room the book lies in.
                palette.floor
                    .opacity(stage == .cover ? 0 : 1)
                    .accessibilityHidden(true)

                pages(book, layout: layout, ids: ids, index: index)
                    .opacity(stage == .open ? 1 : 0)
                    .scaleEffect(1 - min(pull, 420) / 4200)
                    .offset(y: pull * 0.45)

                if !coverGone {
                    cover(in: full)
                }
            }
            .frame(width: full.width, height: full.height)
            .ignoresSafeArea()
            .onAppear { place(book); open() }
            .onChange(of: ids) { _, _ in follow(book) }
            .onChange(of: found, initial: true) { _, at in
                if let at { lastIndex = at }
            }
            // The widget asked for another day while the book was open.
            .onChange(of: opening.start) { _, _ in
                touched = false
                place(book)
            }
            .sheet(isPresented: $picking) {
                JumpToDate(span: book.span, from: book.pages.indices.contains(index) ? book.pages[index].date : .now) { date in
                    jump(to: book.index(onOrAfter: date), in: book)
                }
            }
        }
        // A keyboard somewhere above the book doesn't move its pages.
        .ignoresSafeArea(.keyboard)
        .fullScreenCover(item: $writing) { target in
            BookWritingView(target: target)
        }
        .fullScreenCover(isPresented: $viewing) {
            HeldViewer(current: $openedPhoto)
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
        // Opened from the widget, the Journal tab may not have fetched yet.
        .task { if opening.cover == nil { await state.loadBook() } }
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(.escape) { close() }
    }

    private func present<Item>(_ item: Binding<Item?>) -> Binding<Bool> {
        Binding(get: { item.wrappedValue != nil }, set: { if !$0 { item.wrappedValue = nil } })
    }

    // MARK: the pages and what lies over them

    private func pages(_ book: Book, layout: BookLayout, ids: [String], index: Int) -> some View {
        let actions = BookActions(
            write: { writing = .today },
            edit: { writing = .page($0) },
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
        hasher.combine(layout)
        let version = hasher.finalize()

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
                onPull: { pull = $0 },
                onPullEnd: { moved, speed in
                    if moved > 110 || speed > 1100 {
                        close()
                    } else {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { pull = 0 }
                    }
                }
            )
            .frame(width: layout.width, height: layout.height)
            .accessibilityHidden(grid)

            chrome(book, layout: layout, index: index)
                .opacity(grid ? 0 : 1)

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
        .frame(width: layout.width, height: layout.height)
    }

    /// What stays put while the pages turn: the way out, the ribbon that
    /// marks today, and the place marker along the foot.
    private func chrome(_ book: Book, layout: BookLayout, index: Int) -> some View {
        let today = book.todayIndex
        let count = max(book.pages.count, 1)
        let onToday = index == today
        return ZStack(alignment: .topLeading) {
            // Shutting the book, for anyone who doesn't swipe.
            Button { close() } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(BookPaper.quiet)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close the journal")
            .position(x: layout.left + 8, y: layout.safeTop + 22)

            // The ribbon: it hangs from the top of the book at the right
            // edge, longer on the page it marks. A tap goes there.
            Button { jump(to: today, in: book) } label: {
                Ribbon()
                    .fill(palette.accent.opacity(colorScheme == .dark ? 0.85 : 0.9))
                    .frame(width: 16, height: layout.safeTop + (onToday ? 58 : 34))
                    .shadow(color: .black.opacity(0.18), radius: 1.5, x: -0.5, y: 1)
                    .frame(width: 44, height: layout.safeTop + 70, alignment: .top)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .animation(.spring(response: 0.3, dampingFraction: 0.85), value: onToday)
            .accessibilityLabel(onToday ? "Today's page" : "Go to today's page")
            // Hard against the page's edge, clear of the status bar's
            // battery (and of the Duo's strip).
            .position(x: layout.width - layout.safeTrailing - 17, y: (layout.safeTop + 70) / 2)

            // Where you are in the book: a line, and a dot along it. A tap
            // goes to a date.
            Button { picking = true } label: {
                PlaceMarker(fraction: count > 1 ? CGFloat(index) / CGFloat(count - 1) : 1, accent: palette.accent)
                    .frame(width: layout.textWidth * 0.56, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Page \(index + 1) of the journal")
            .accessibilityHint("Goes to a date")
            .position(x: layout.middle, y: layout.height - layout.safeBottom - 14)
        }
        .frame(width: layout.width, height: layout.height)
    }

    // MARK: where the book is open

    /// Put the book at the page it was asked to open to.
    private func place(_ book: Book) {
        let at: Int
        switch opening.start {
        case .today: at = book.todayIndex
        case .day(let day): at = book.index(day: day) ?? book.todayIndex
        case .first: at = 0
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
    /// page, go where the book was asked to open (its pages may only now
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

    /// Turn to a page: the ribbon, a date.
    private func jump(to target: Int, in book: Book) {
        guard book.pages.indices.contains(target), book.pages[target].id != currentID else { return }
        touched = true
        currentID = book.pages[target].id
    }

    // MARK: opening and shutting

    /// The cover as it lies on the Journal tab, and as it's held up in the
    /// middle of the screen before it opens.
    private func cover(in size: CGSize) -> some View {
        let from = opening.cover ?? CGRect(
            x: size.width * 0.14, y: size.height * 0.2, width: size.width * 0.72, height: size.width * 0.72 * BookCover.shape
        )
        let scale = min((size.width - 36) / from.width, size.height * 0.74 / from.height)
        let lifted = stage != .cover
        return BookCoverFace(title: state.journalTitle, name: state.profile?.displayName, span: BookBuilder.span(state))
            .frame(width: from.width, height: from.height)
            .rotation3DEffect(
                .degrees(stage == .open ? -90 : 0), axis: (x: 0, y: 1, z: 0), anchor: .leading, perspective: 0.4
            )
            .scaleEffect(lifted ? scale : 1)
            .position(
                x: lifted ? size.width / 2 : from.midX,
                y: lifted ? size.height / 2 : from.midY
            )
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private func open() {
        guard stage == .cover else { return }
        if reduceMotion || opening.cover == nil {
            coverGone = true
            withAnimation(.easeInOut(duration: 0.25)) { stage = .open }
            return
        }
        withAnimation(.spring(response: 0.36, dampingFraction: 0.88)) { stage = .grown }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(300))
            withAnimation(.easeIn(duration: 0.4)) { stage = .open }
            try? await Task.sleep(for: .milliseconds(410))
            if !closing { coverGone = true }
        }
    }

    private func close() {
        guard !closing else { return }
        closing = true
        grid = false
        if reduceMotion || opening.cover == nil {
            withAnimation(.easeInOut(duration: 0.25)) {
                stage = .cover
                pull = 0
            }
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(260))
                state.book = nil
            }
            return
        }
        coverGone = false
        withAnimation(.easeOut(duration: 0.36)) {
            stage = .grown
            pull = 0
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(360))
            withAnimation(.spring(response: 0.34, dampingFraction: 0.9)) { stage = .cover }
            try? await Task.sleep(for: .milliseconds(340))
            state.book = nil
        }
    }
}

/// The bookmark ribbon: a strip with a notch cut from its end.
private struct Ribbon: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY - rect.width * 0.55))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

/// Where you are in the book: a thin line with a dot on it. Not a
/// scrollbar: it says how far through, and nothing is dragged.
private struct PlaceMarker: View {
    let fraction: CGFloat
    let accent: Color

    var body: some View {
        GeometryReader { geo in
            let x = min(max(fraction, 0), 1) * geo.size.width
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(BookPaper.quiet.opacity(0.4))
                    .frame(height: 1)
                Circle()
                    .fill(accent)
                    .frame(width: 7, height: 7)
                    .offset(x: x - 3.5)
                    .animation(.spring(response: 0.3, dampingFraction: 0.85), value: fraction)
            }
            .frame(maxHeight: .infinity)
        }
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
        let width = ((layout.width - layout.safeLeading - layout.safeTrailing - side * 2 - gap) / 2).rounded(.down)
        // Three rows to a screen, so six pages show at once.
        let height = ((layout.height - top - layout.safeBottom - gap * 3) / 3).rounded(.down)
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
                    .padding(.trailing, layout.safeTrailing + side)
                    .padding(.top, top)
                    .padding(.bottom, layout.safeBottom + gap)
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
            .padding(.trailing, layout.safeTrailing + side)
            .frame(height: 44)
            .padding(.top, layout.safeTop)
            .background(floor)
        }
        .frame(width: layout.width, height: layout.height)
        .simultaneousGesture(
            MagnifyGesture().onEnded { pinch in
                if pinch.magnification > 1.15 { done(nil) }
            }
        )
    }
}

// MARK: - Going to a date

private struct JumpToDate: View {
    @Environment(\.dismiss) private var dismiss
    let span: ClosedRange<Date>
    let go: (Date) -> Void
    @State private var date: Date

    init(span: ClosedRange<Date>, from: Date, go: @escaping (Date) -> Void) {
        self.span = span
        self.go = go
        _date = State(initialValue: min(max(from, span.lowerBound), span.upperBound))
    }

    var body: some View {
        NavigationStack {
            DatePicker("Date", selection: $date, in: span, displayedComponents: .date)
                .datePickerStyle(.graphical)
                .padding(.horizontal, 16)
                .frame(maxHeight: .infinity, alignment: .top)
                .atmosphereWash()
                .navigationTitle("Go to a date")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Go") {
                            go(date)
                            dismiss()
                        }
                    }
                }
        }
        .presentationDetents([.medium, .large])
    }
}

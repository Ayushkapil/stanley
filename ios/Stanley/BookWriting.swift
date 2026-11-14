import SwiftUI
import UIKit

// Writing a page (build 46; a full-screen cover in build 45). The page is
// written where it lies: a tap on today's page and the cursor is in it, the
// same paper, the same rules, the same date at its head, the three inks
// along its foot, riding up over the keyboard. Done keeps it at today's
// date. There is one page a day: writing today's again replaces what was
// there. No counter and no limit shown: it's a journal.

/// The ink a new page starts in: the last one used.
enum InkWell {
    static let key = "stanley.journal.ink"

    static var last: Ink {
        get { Ink.named(UserDefaults.standard.string(forKey: key)) }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: key) }
    }
}

/// The page being written on: a text view whose lines are exactly as far
/// apart as the rules drawn under them, so the words sit on the paper's
/// lines as they will in the book.
/// A way to ask the page being written what's on it, once writing is done.
final class EditorHandle {
    weak var view: RuledTextView?
}

private struct RuledEditor: UIViewRepresentable {
    /// What's on the page, for whoever needs to know whether anything is.
    /// The page itself is the text view's; nothing is set back into it.
    @Binding var text: String
    /// The pen in hand.
    let ink: Ink
    /// What the page held when writing began, ink by ink.
    let start: [InkRun]
    let handle: EditorHandle
    let layout: BookLayout
    /// The most a page holds. Far past a day's writing; never shown.
    let limit: Int

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> RuledTextView {
        // The words begin and end where the page's do.
        let view = RuledTextView(fontSize: layout.fontSize, left: layout.left, right: layout.width - layout.right)
        view.delegate = context.coordinator
        view.load(start, pen: ink)
        handle.view = view
        return view
    }

    func updateUIView(_ view: RuledTextView, context: Context) {
        context.coordinator.parent = self
        if view.ink != ink { view.use(ink) }
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: RuledEditor
        init(_ parent: RuledEditor) { self.parent = parent }

        func textViewDidChange(_ textView: UITextView) {
            guard let view = textView as? RuledTextView else { return }
            view.mend()
            parent.text = view.text
            view.layRules()
        }

        /// Wherever the cursor is put, what's written next is in the pen
        /// in hand. (Left alone, a text view takes up the ink of whatever
        /// the cursor lands beside.)
        func textViewDidChangeSelection(_ textView: UITextView) {
            (textView as? RuledTextView)?.takeUpPen()
        }

        func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
            (textView.text as NSString).length - range.length + (text as NSString).length <= parent.limit
        }
    }
}

extension NSAttributedString.Key {
    /// Which of the three inks a stretch of a page being written is in.
    /// The color is drawn from it; this is what's read back when the page
    /// is kept, since a color that changes with the room can't be compared.
    static let ink = NSAttributedString.Key("stanley.ink")
}

final class RuledTextView: UITextView {
    private let rules = UIView()
    private let hand: UIFont
    private let pitch: CGFloat
    private(set) var ink: Ink = .black

    init(fontSize: CGFloat, left: CGFloat, right: CGFloat) {
        hand = BookHand.font(fontSize)
        pitch = ceil(hand.lineHeight)
        let storage = NSTextStorage()
        let manager = NSLayoutManager()
        manager.usesFontLeading = false
        storage.addLayoutManager(manager)
        let container = NSTextContainer(size: CGSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        container.lineFragmentPadding = 0
        manager.addTextContainer(container)
        super.init(frame: .zero, textContainer: container)
        backgroundColor = .clear
        alwaysBounceVertical = true
        keyboardDismissMode = .interactive
        // Nothing above the first line: it sits where the page's first
        // line sits, so the words don't move when the cursor arrives.
        textContainerInset = UIEdgeInsets(top: 0, left: left, bottom: 28, right: right)
        showsVerticalScrollIndicator = false
        autocapitalizationType = .sentences
        rules.isUserInteractionEnabled = false
        insertSubview(rules, at: 0)
        accessibilityLabel = "Today's page"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    private var arrived = false

    /// The cursor is in the page as it's laid down: at the top of a blank
    /// one, after the last word of one being gone on with.
    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil, !arrived else { return }
        arrived = true
        DispatchQueue.main.async { [weak self] in
            guard let self, self.window != nil else { return }
            self.becomeFirstResponder()
            let end = NSRange(location: (self.text as NSString).length, length: 0)
            self.selectedRange = end
            self.scrollRangeToVisible(end)
        }
    }

    private func attributes(_ ink: Ink) -> [NSAttributedString.Key: Any] {
        let style = NSMutableParagraphStyle()
        style.minimumLineHeight = pitch
        style.maximumLineHeight = pitch
        return [.font: hand, .foregroundColor: ink.ui, .paragraphStyle: style, .ink: ink.rawValue]
    }

    /// Lay down what the page already holds, each stretch in its ink, and
    /// take up a pen.
    func load(_ runs: [InkRun], pen: Ink) {
        let page = NSMutableAttributedString()
        for run in runs {
            page.append(NSAttributedString(string: run.text, attributes: attributes(Ink.named(run.ink))))
        }
        attributedText = page
        ink = pen
        typingAttributes = attributes(pen)
        tintColor = pen.ui
        layRules()
    }

    /// Take up another pen: what's written from here on is in this ink.
    /// What's already on the page keeps the ink it was written in (build
    /// 50; until then a change of ink set the whole page in it), unless
    /// some of it is selected, and then the selection is gone over in it.
    func use(_ ink: Ink) {
        self.ink = ink
        let selection = selectedRange
        if selection.length > 0 {
            textStorage.addAttributes([.foregroundColor: ink.ui, .ink: ink.rawValue], range: selection)
            delegate?.textViewDidChange?(self)
        }
        typingAttributes = attributes(ink)
        tintColor = ink.ui
    }

    /// The pen in hand is what writes next, wherever the cursor is.
    func takeUpPen() {
        // Not in the middle of composing a character: that's the
        // keyboard's to finish.
        guard markedTextRange == nil else { return }
        typingAttributes = attributes(ink)
    }

    /// Anything that arrived without an ink of the page's (pasted from
    /// somewhere else, say) is in the pen in hand, and in the page's hand.
    /// (Only the ink is looked for: the text system puts a font of its
    /// own on an emoji, and that's not a stray.)
    func mend() {
        let whole = NSRange(location: 0, length: textStorage.length)
        guard whole.length > 0 else { return }
        var strays: [NSRange] = []
        textStorage.enumerateAttribute(.ink, in: whole) { value, range, _ in
            if (value as? String).flatMap(Ink.init(rawValue:)) == nil { strays.append(range) }
        }
        guard !strays.isEmpty else { return }
        let selection = selectedRange
        textStorage.beginEditing()
        for range in strays {
            let kept = textStorage.attribute(.ink, at: range.location, effectiveRange: nil) as? String
            textStorage.setAttributes(attributes(kept.flatMap(Ink.init(rawValue:)) ?? ink), range: range)
        }
        textStorage.endEditing()
        selectedRange = selection
    }

    /// The page as it would be kept: its words without the space at either
    /// end, ink by ink.
    func stretches() -> [InkRun] {
        let all = textStorage.string as NSString
        let blank = CharacterSet.whitespacesAndNewlines
        var from = 0
        var to = all.length
        while from < to, let scalar = UnicodeScalar(all.character(at: from)), blank.contains(scalar) { from += 1 }
        while to > from, let scalar = UnicodeScalar(all.character(at: to - 1)), blank.contains(scalar) { to -= 1 }
        var runs: [InkRun] = []
        textStorage.enumerateAttribute(.ink, in: NSRange(location: from, length: to - from)) { value, range, _ in
            let name = (value as? String).flatMap(Ink.init(rawValue:))?.rawValue ?? ink.rawValue
            let words = all.substring(with: range)
            if let last = runs.last, last.ink == name {
                runs[runs.count - 1] = InkRun(ink: name, text: last.text + words)
            } else {
                runs.append(InkRun(ink: name, text: words))
            }
        }
        return runs
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layRules()
    }

    override func traitCollectionDidChange(_ previous: UITraitCollection?) {
        super.traitCollectionDidChange(previous)
        tile = nil
        layRules()
    }

    private var tile: UIImage?

    /// One line of ruled paper, repeated down the page.
    private func ruleTile() -> UIImage {
        if let tile { return tile }
        let size = CGSize(width: 8, height: pitch)
        let rise = max(0, -hand.descender - 3)
        let color = BookPaper.ruleUI.resolvedColor(with: traitCollection)
        let made = UIGraphicsImageRenderer(size: size).image { context in
            color.setFill()
            // Where `BookSheet` rules the page, to the half point.
            context.fill(CGRect(x: 0, y: (pitch - rise).rounded(), width: size.width, height: 0.5))
        }
        tile = made
        return made
    }

    /// The rules run from the first line to past the last, and as far as
    /// the page shows, so a short page is still a ruled one.
    func layRules() {
        let height = max(contentSize.height, bounds.height) + bounds.height
        let frame = CGRect(x: 0, y: textContainerInset.top, width: bounds.width, height: height)
        if rules.frame != frame { rules.frame = frame }
        rules.backgroundColor = UIColor(patternImage: ruleTile())
        sendSubviewToBack(rules)
    }
}

/// The three inks at the foot of the page: small circles, the one in use
/// ringed.
struct InkPicker: View {
    @Binding var ink: Ink

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Ink.allCases) { choice in
                Button { ink = choice } label: {
                    Circle()
                        .fill(choice.color)
                        .frame(width: 20, height: 20)
                        .padding(4)
                        .overlay {
                            Circle()
                                .strokeBorder(choice.color.opacity(ink == choice ? 0.9 : 0), lineWidth: 1.5)
                        }
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(choice.name) ink")
                .accessibilityAddTraits(ink == choice ? .isSelected : [])
            }
        }
        .animation(.easeOut(duration: 0.15), value: ink)
    }
}

/// A page being written, laid exactly over the page it is: the same sheet,
/// the same date, the first line where the first line was. Cancel and Done
/// are at the head, on the date's line, only while it's being written.
/// Where a page being written will land (build 51).
enum PageLanding {
    /// Where it already is: a page being gone on with. A new page, with
    /// you alone.
    case asIs
    /// With you alone, whatever it was.
    case privately
    /// In the shared journal of the circle on screen.
    case shared
}

struct PageWriting: View {
    @Environment(AppState.self) private var state
    @AppStorage("stanley.atmosphere") private var raw = "auto"
    let target: WritingTarget
    var landing = PageLanding.asIs
    let layout: BookLayout
    /// Writing is over. True when the page was kept; false when it was
    /// torn out, let go, or left as it was.
    let close: (Bool) -> Void

    @State private var text = ""
    /// The pen in hand: what's written next is in it. Taking up another
    /// leaves what's written as it is.
    @State private var ink = InkWell.last
    /// What the page held when writing began; nil until that's known.
    @State private var start: [InkRun]?
    @State private var handle = EditorHandle()
    @State private var saving = false
    @State private var confirmDiscard = false
    @State private var confirmDelete = false

    /// The page already in the journal that this would replace: the one
    /// asked for, or today's if it's been written.
    private var existing: DayPage? {
        switch target {
        case .page(let page): return state.journalPages.first { $0.id == page.id } ?? page
        case .today:
            let today = WidgetSnapshot.day(.now)
            return state.journalPages.first { $0.day == today }
        }
    }

    private var date: Date {
        if case .page(let page) = target, let day = WeekRange.day(page.day) { return day }
        return .now
    }

    private var words: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }
    /// The page as it stands, ink by ink.
    private var written: [InkRun] { handle.view?.stretches() ?? [] }
    /// Whether the page will be in a circle's shared journal once kept,
    /// and which circle's.
    private var sharing: String? {
        switch landing {
        case .shared: state.circle?.name ?? "your circle"
        case .privately: nil
        case .asIs: existing?.isShared == true ? (existing?.circleName ?? "your circle") : nil
        }
    }

    /// Whether keeping it would move a page already written between your
    /// own book and the shared one, or from one circle's to another's.
    private var moves: Bool {
        guard let existing else { return false }
        switch landing {
        case .asIs: return false
        case .privately: return existing.isShared
        case .shared: return !existing.isShared || existing.circleId != state.circle?.id
        }
    }

    /// The date is in the ink the page begins in, as it is when the page
    /// is read: the pen in hand on a page with nothing on it yet.
    private var headInk: Ink { written.first.map { Ink.named($0.ink) } ?? ink }
    /// Whether that's anything other than what was there.
    private var changed: Bool { written != (existing?.stretches ?? []) }

    var body: some View {
        let accent = Atmosphere.resolve(raw).palette.accent
        VStack(spacing: 0) {
            Group {
                if let start {
                    RuledEditor(text: $text, ink: ink, start: start, handle: handle, layout: layout, limit: 50_000)
                } else {
                    Color.clear
                }
            }
            .padding(.top, layout.contentTop)
            // The three inks, where the page's number is when it's read.
            InkPicker(ink: $ink)
                .frame(width: layout.textWidth, height: BookLayout.foot)
                .frame(maxWidth: .infinity)
                .padding(.leading, layout.left)
                .padding(.trailing, layout.width - layout.right)
        }
        .frame(width: layout.width)
        .overlay(alignment: .topLeading) {
            ZStack(alignment: .topLeading) {
                PageHeading(text: BookType.dayTitle(date), color: headInk.color.opacity(0.7), layout: layout)
                // Where this page will land, so there's never any doubt.
                PageTag(
                    text: sharing.map { "Shared with \($0)" } ?? "Private",
                    color: sharing == nil ? BookPaper.quiet : accent, layout: layout
                )
                HStack(spacing: 18) {
                    Button("Cancel") { cancel() }
                        .wordButton(.subheadline, bold: false)
                        .foregroundStyle(BookPaper.quiet)
                    Button(saving ? "Keeping…" : "Done") { done() }
                        .wordButton(.subheadline)
                        .foregroundStyle(accent)
                        .disabled(saving || (words.isEmpty && existing == nil))
                        .opacity(words.isEmpty && existing == nil ? 0.4 : 1)
                }
                .frame(height: 44)
                .frame(width: layout.textWidth, alignment: .trailing)
                .position(x: layout.middle, y: layout.headY)
            }
            .frame(width: layout.width, height: layout.contentTop, alignment: .topLeading)
        }
        .background(alignment: .topLeading) {
            // The same sheet, unruled: the rules are the text view's own,
            // so they move with the words when a long day scrolls.
            BookSheet(layout: layout, lined: false)
        }
        // Over the whole tab, the fore-edge too: nothing under a page
        // being written is pressed.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .contentShape(Rectangle())
        .ignoresSafeArea(.container, edges: [.top, .horizontal])
        .onAppear {
            guard start == nil else { return }
            // A page being gone on with: its words in their inks, and the
            // pen it was last written with.
            let held = existing?.stretches ?? []
            text = existing?.body ?? ""
            if let last = held.last { ink = Ink.named(last.ink) }
            start = held
        }
        .alert("Leave this page unwritten?", isPresented: $confirmDiscard) {
            Button("Discard", role: .destructive) { close(false) }
            Button("Keep Writing", role: .cancel) {}
        } message: {
            Text(existing == nil ? "What you've written here won't be kept." : "Your changes won't be kept.")
        }
        .alert("Tear out this page?", isPresented: $confirmDelete) {
            Button("Delete", role: .destructive) {
                guard let existing else { return }
                saving = true
                Task {
                    await state.deletePage(existing)
                    saving = false
                    close(false)
                }
            }
            Button("Keep Writing", role: .cancel) {}
        } message: {
            Text("A page with nothing on it isn't kept. This one would be gone for good.")
        }
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(.escape) { cancel() }
    }

    private func cancel() {
        if changed && !words.isEmpty { confirmDiscard = true } else { close(false) }
    }

    private func done() {
        // The ink is the next page's to start with, whatever happens to this one.
        InkWell.last = ink
        let runs = written
        // Nothing rewritten and nowhere new to land: as it was.
        guard runs != (existing?.stretches ?? []) || moves else { close(false); return }
        // Every word rubbed out of a page that was there: it's being torn out.
        if runs.isEmpty {
            confirmDelete = true
            return
        }
        saving = true
        Task {
            let kept: Bool
            if case .page(let page) = target {
                kept = await state.editPage(existing ?? page, runs: runs)
            } else {
                // Where it lands is said only when it was chosen: a page
                // gone on with stays where it is.
                let shared: Bool? = landing == .asIs ? nil : landing == .shared
                kept = await state.writeToday(runs, shared: shared)
            }
            saving = false
            if kept {
                Haptics.pageKept()
                close(true)
            }
        }
    }
}

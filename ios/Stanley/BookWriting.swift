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
private struct RuledEditor: UIViewRepresentable {
    @Binding var text: String
    let ink: Ink
    let layout: BookLayout
    /// The most a page holds. Far past a day's writing; never shown.
    let limit: Int

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> RuledTextView {
        // The words begin and end where the page's do.
        let view = RuledTextView(fontSize: layout.fontSize, left: layout.left, right: layout.width - layout.right)
        view.delegate = context.coordinator
        view.text = text
        view.use(ink)
        return view
    }

    func updateUIView(_ view: RuledTextView, context: Context) {
        context.coordinator.parent = self
        if view.text != text { view.text = text }
        if view.ink != ink { view.use(ink) }
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: RuledEditor
        init(_ parent: RuledEditor) { self.parent = parent }

        func textViewDidChange(_ textView: UITextView) {
            parent.text = textView.text
            (textView as? RuledTextView)?.layRules()
        }

        func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
            (textView.text as NSString).length - range.length + (text as NSString).length <= parent.limit
        }
    }
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

    /// Write in this ink from here on, and set what's already written in it:
    /// a page is one ink.
    func use(_ ink: Ink) {
        self.ink = ink
        let style = NSMutableParagraphStyle()
        style.minimumLineHeight = pitch
        style.maximumLineHeight = pitch
        let attributes: [NSAttributedString.Key: Any] = [
            .font: hand, .foregroundColor: ink.ui, .paragraphStyle: style,
        ]
        let selection = selectedRange
        textStorage.setAttributes(attributes, range: NSRange(location: 0, length: textStorage.length))
        typingAttributes = attributes
        selectedRange = selection
        tintColor = ink.ui
    }

    override var text: String! {
        didSet {
            use(ink)
            layRules()
        }
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
struct PageWriting: View {
    @Environment(AppState.self) private var state
    @AppStorage("stanley.atmosphere") private var raw = "auto"
    let target: WritingTarget
    let layout: BookLayout
    /// Writing is over: kept, torn out, or let go.
    let close: () -> Void

    @State private var text = ""
    @State private var ink = InkWell.last
    @State private var began = false
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
    private var changed: Bool { words != (existing?.body ?? "") || (existing != nil && Ink.named(existing?.ink) != ink) }

    var body: some View {
        let accent = Atmosphere.resolve(raw).palette.accent
        VStack(spacing: 0) {
            RuledEditor(text: $text, ink: ink, layout: layout, limit: 50_000)
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
                PageHeading(text: BookType.dayTitle(date), color: ink.color.opacity(0.7), layout: layout)
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
            guard !began else { return }
            began = true
            if let existing {
                text = existing.body
                ink = Ink.named(existing.ink)
            }
        }
        .alert("Leave this page unwritten?", isPresented: $confirmDiscard) {
            Button("Discard", role: .destructive) { close() }
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
                    close()
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
        if changed && !words.isEmpty { confirmDiscard = true } else { close() }
    }

    private func done() {
        // The ink is the next page's to start with, whatever happens to this one.
        InkWell.last = ink
        guard changed else { close(); return }
        // Every word rubbed out of a page that was there: it's being torn out.
        if words.isEmpty {
            confirmDelete = true
            return
        }
        saving = true
        Task {
            let kept: Bool
            if case .page(let page) = target {
                kept = await state.editPage(existing ?? page, body: words, ink: ink)
            } else {
                kept = await state.writeToday(words, ink: ink)
            }
            saving = false
            if kept {
                Haptics.pageKept()
                close()
            }
        }
    }
}

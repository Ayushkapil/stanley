import SwiftUI
import UIKit

// Writing a page (build 45). A blank page of the book, ruled, with the
// cursor on its first line; three inks at its foot. Done puts it into the
// book at today's date. There is one page a day: writing today's again
// replaces what was there. No counter and no limit shown: it's a journal.

/// The ink a new page starts in: the last one used.
enum InkWell {
    private static let key = "stanley.journal.ink"

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
    let fontSize: CGFloat
    /// The most a page holds. Far past a day's writing; never shown.
    let limit: Int

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> RuledTextView {
        let view = RuledTextView(fontSize: fontSize)
        view.delegate = context.coordinator
        view.text = text
        view.use(ink)
        // The cursor is in the page as it opens: at the top of a blank
        // one, after the last word of one being rewritten.
        DispatchQueue.main.async { view.becomeFirstResponder() }
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

    init(fontSize: CGFloat) {
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
        textContainerInset = UIEdgeInsets(top: 8, left: 30, bottom: 40, right: 30)
        autocapitalizationType = .sentences
        rules.isUserInteractionEnabled = false
        insertSubview(rules, at: 0)
        accessibilityLabel = "Today's page"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

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
            let y = (pitch - rise).rounded() - 0.25
            context.fill(CGRect(x: 0, y: y, width: size.width, height: 0.5))
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
private struct InkPicker: View {
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

/// Writing mode: a page of the book with nothing on it but a date, to be
/// written on.
struct BookWritingView: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("stanley.atmosphere") private var raw = "auto"
    let target: WritingTarget

    @State private var text = ""
    @State private var ink = InkWell.last
    @State private var began = false
    @State private var saving = false
    @State private var confirmDiscard = false
    @State private var confirmDelete = false

    /// The page already in the book that this would replace: the one asked
    /// for, or today's if it's been written.
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
    private var fontSize: CGFloat { BookLayout(size: .zero, safeTop: 0, safeBottom: 0).fontSize }

    var body: some View {
        let accent = Atmosphere.resolve(raw).palette.accent
        VStack(spacing: 0) {
            // Cancel, the day, Done: along the head of the page.
            HStack(alignment: .center) {
                Button("Cancel") {
                    if changed && !words.isEmpty { confirmDiscard = true } else { dismiss() }
                }
                .wordButton(bold: false)
                .foregroundStyle(BookPaper.quiet)
                Spacer()
                Button(saving ? "Keeping…" : "Done") { done() }
                    .wordButton()
                    .foregroundStyle(accent)
                    .disabled(saving || (words.isEmpty && existing == nil))
                    .opacity(words.isEmpty && existing == nil ? 0.4 : 1)
            }
            .padding(.horizontal, 22)
            .frame(height: 44)

            Text(BookType.dayTitle(date))
                .font(.custom(BookHand.font(fontSize + 1, bold: true).fontName, size: fontSize + 1, relativeTo: .body))
                .foregroundStyle(ink.color)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 30)
                .padding(.top, 6)
                .accessibilityAddTraits(.isHeader)

            RuledEditor(text: $text, ink: ink, fontSize: fontSize, limit: 50_000)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            InkPicker(ink: $ink)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 2)
                .background(BookPaper.page)
        }
        .background {
            ZStack {
                BookPaper.page
                if colorScheme != .dark {
                    Image(uiImage: PaperGrain.tile)
                        .resizable(resizingMode: .tile)
                        .opacity(0.28)
                }
            }
            .ignoresSafeArea()
        }
        .onAppear {
            guard !began else { return }
            began = true
            if let existing {
                text = existing.body
                ink = Ink.named(existing.ink)
            }
        }
        .alert("Leave this page unwritten?", isPresented: $confirmDiscard) {
            Button("Discard", role: .destructive) { dismiss() }
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
                    dismiss()
                }
            }
            Button("Keep Writing", role: .cancel) {}
        } message: {
            Text("A page with nothing on it isn't kept. This one would be gone for good.")
        }
    }

    private func done() {
        // The ink is the next page's to start with, whatever happens to this one.
        InkWell.last = ink
        guard changed else { dismiss(); return }
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
                dismiss()
            }
        }
    }
}

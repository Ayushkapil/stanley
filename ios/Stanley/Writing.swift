import SwiftUI

// Writing things down (build 26). Three kinds, each on the journal's paper
// and in a hand, because they're a person's own words:
//
// - "Anything else about today?": a private entry on your own photo, asked
//   once, quietly, right after it goes up. A small book on the print says
//   one is written; it opens to read or rewrite. In Held it's beneath the
//   photo. Nobody else ever sees it.
// - "How was your week?": on Sunday evenings the You tab asks, with your
//   week's photos that are still there. What you write is kept in the
//   Journal at the foot of the You tab, and doesn't fade.
// - "This week's question": the circle's question, on a slip under the
//   note. Answered privately, then everyone's opens together on Saturday.
//   Past weeks are in the circle journal.
//
// No counts anywhere: not how many answered, not how many words are left.

/// The limits the server keeps, by the characters it counts.
enum WritingLimit {
    static let entry = 1000
    static let reflection = 500
    static let answer = 300
    /// A letter to the circle (build 42, `CircleLetters.swift`).
    static let circleLetter = 500

    /// Cut to the server's limit, which counts Unicode scalars, so an emoji
    /// that's several of them can't push a full field over.
    static func clamp(_ text: String, _ limit: Int) -> String {
        guard text.unicodeScalars.count > limit else { return text }
        var out = ""
        var used = 0
        for character in text {
            let size = character.unicodeScalars.count
            if used + size > limit { break }
            out.append(character)
            used += size
        }
        return out
    }
}

extension String {
    /// Words worth sending: not just spaces and returns.
    var hasWords: Bool { !trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    var trimmedWords: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}

/// A week's days, as the server names them ("2026-11-02"), written the way
/// a journal dates a page: "Nov 2 – 8".
enum WeekRange {
    private static let parser: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func day(_ text: String) -> Date? { parser.date(from: text) }

    static func text(_ start: String, _ end: String) -> String {
        guard let first = day(start), let last = day(end), first <= last else { return "" }
        let thisYear = Calendar.current.isDate(last, equalTo: .now, toGranularity: .year)
        let style = thisYear
            ? Date.IntervalFormatStyle().month(.abbreviated).day()
            : Date.IntervalFormatStyle().month(.abbreviated).day().year()
        return (first..<last).formatted(style)
    }
}

/// When the circle's answers open, said in the reader's own time: Saturday
/// at midnight UTC is Friday evening in Bloomington, and a promise of
/// "private until Saturday" would be broken by hours.
enum RevealTime {
    static func phrase(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        let day = date.formatted(.dateTime.weekday(.wide))
        if parts.hour == 0 && parts.minute == 0 { return day }
        let time = parts.minute == 0
            ? date.formatted(.dateTime.hour())
            : date.formatted(.dateTime.hour().minute())
        return "\(day) at \(time)"
    }
}

/// The evening Stanley asks how the week was: Sunday from 6pm until
/// midnight, on the phone's own clock. Nothing is sent: it's simply there
/// when the You tab is opened then.
enum ReflectionWindow {
    static func isOpen(_ date: Date = .now, calendar: Calendar = gregorian) -> Bool {
        #if DEBUG
        // For trying the card on a simulator on a weekday.
        if ProcessInfo.processInfo.environment["STANLEY_SUNDAY_EVENING"] == "1" { return true }
        #endif
        let parts = calendar.dateComponents([.weekday, .hour], from: date)
        return parts.weekday == 1 && (parts.hour ?? 0) >= 18
    }

    /// Weekday 1 is Sunday in the Gregorian calendar, whatever the phone's
    /// own calendar numbers its days by.
    static var gregorian: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar
    }
}

/// A field that writes in a hand on the page: no box, the placeholder in
/// the same hand, a rule beneath it like a line on paper. What sends it sits
/// at the end of the line being written, as Add does beside a story, because
/// anywhere below it the keyboard covers it.
private struct HandField<Send: View>: View {
    let prompt: String
    @Binding var text: String
    let limit: Int
    var size: CGFloat = 19
    var lines: ClosedRange<Int> = 2...8
    @ViewBuilder var send: () -> Send

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .lastTextBaseline, spacing: 10) {
                TextField("", text: $text, prompt: Text(prompt).foregroundColor(.secondary), axis: .vertical)
                    .font(.hand(size, relativeTo: .body))
                    .textFieldStyle(.plain)
                    .lineLimit(lines)
                    .onChange(of: text) { _, new in
                        let clamped = WritingLimit.clamp(new, limit)
                        if clamped != new { text = clamped }
                    }
                send()
            }
            Rule(weight: 0.5)
        }
    }
}

extension HandField where Send == EmptyView {
    init(prompt: String, text: Binding<String>, limit: Int, size: CGFloat = 19, lines: ClosedRange<Int> = 2...8) {
        self.init(prompt: prompt, text: text, limit: limit, size: size, lines: lines) { EmptyView() }
    }
}

// MARK: - The journal entry on your own photo

/// Right after today's photo goes up, under it: a quiet question and a line
/// to answer it on, for your eyes only. Skipping is the default: "Not now"
/// puts it away, and so does doing nothing (it's gone at the next launch).
struct JournalOfferSlip: View {
    @Environment(AppState.self) private var state
    let photo: Photo
    @State private var text = ""
    @State private var saving = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Anything else about today?")
                    .font(.hand(21, bold: true, relativeTo: .title3))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Button("Not now") {
                    withAnimation(.easeOut(duration: 0.2)) { state.journalOffer = nil }
                }
                .wordButton(.footnote, bold: false)
                .foregroundStyle(.secondary)
                .buttonStyle(.plain)
                .frame(minHeight: 44)
            }
            HandField(prompt: "What happened, in a few lines", text: $text, limit: WritingLimit.entry, size: 18) {
                if text.hasWords {
                    Button(saving ? "Keeping…" : "Keep it") { save() }
                        .wordButton()
                        .fixedSize()
                        .disabled(saving)
                }
            }
            Label("Only you see this", systemImage: "lock")
                .labelStyle(.titleAndIcon)
                .quietLabel()
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        // A page of your journal: paper, in both rooms.
        .creamPaper()
        .transition(.opacity)
    }

    private func save() {
        saving = true
        Task {
            _ = await state.writeJournal(photo.id, text.trimmedWords)
            saving = false
        }
    }
}

/// Your entry on your own photo, opened from the book on its print, its
/// menu, or the words beneath it in Held: read it, rewrite it, or delete it.
struct JournalEntrySheet: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss
    let photoId: String
    /// The photo's small copy, for the corner of the page.
    var thumb: String?
    var takenAt: Date?

    @State private var text = ""
    @State private var written: JournalEntry?
    @State private var loaded = false
    @State private var saving = false
    @State private var confirmDelete = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(alignment: .top, spacing: 16) {
                        if let thumb, let url = state.api.absoluteURL(thumb) {
                            Color.clear
                                .aspectRatio(PhotoShape.aspect, contentMode: .fit)
                                .frame(width: 76)
                                .overlay {
                                    SignedImage(url: url) { image in
                                        image.resizable().aspectRatio(contentMode: .fill)
                                    } placeholder: {
                                        Rectangle().fill(.quaternary)
                                    }
                                }
                                .asPrint(corner: 5)
                                .accessibilityHidden(true)
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            if let takenAt {
                                Text(takenAt.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                                    .font(.hand(24, bold: true, relativeTo: .title2))
                            }
                            Label("Only you see this", systemImage: "lock")
                                .labelStyle(.titleAndIcon)
                                .quietLabel()
                        }
                        Spacer(minLength: 0)
                    }
                    if loaded {
                        HandField(
                            prompt: "What happened today?", text: $text, limit: WritingLimit.entry,
                            size: 20, lines: 6...24
                        )
                    } else {
                        ProgressView().frame(maxWidth: .infinity).padding(.vertical, 30)
                    }
                    if written != nil {
                        Button("Delete Entry", role: .destructive) { confirmDelete = true }
                            .destructiveInk()
                            .font(.callout)
                            .padding(.top, 8)
                    }
                }
                .padding(20)
            }
            .atmosphereWash()
            .navigationTitle("Your journal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(saving ? "Keeping…" : "Keep") { save() }
                        .disabled(!loaded || saving || !text.hasWords || text.trimmedWords == written?.body)
                }
            }
            // Unsaved words don't go with a stray swipe; Cancel still
            // leaves on purpose (the HCI audit, build 32, as the reflection).
            .interactiveDismissDisabled(loaded && text.hasWords && text.trimmedWords != written?.body)
            .alert("Delete this entry?", isPresented: $confirmDelete) {
                Button("Delete", role: .destructive) {
                    Task { if await state.deleteJournal(photoId) { dismiss() } }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("What you wrote about this photo is gone for good. The photo stays as it is.")
            }
            .task { await load() }
        }
    }

    private func load() async {
        do {
            written = try await state.journalEntry(photoId)
            text = written?.body ?? ""
            loaded = true
        } catch {
            state.surface(error)
            dismiss()
        }
    }

    private func save() {
        saving = true
        Task {
            if await state.writeJournal(photoId, text.trimmedWords) { dismiss() }
            saving = false
        }
    }
}

/// Your entry beneath your own held photo in the album, in a hand, marked as
/// yours alone. A tap opens it to rewrite.
struct HeldJournalNote: View {
    let memory: Memory
    let words: String
    @State private var editing = false

    var body: some View {
        Button { editing = true } label: {
            VStack(alignment: .leading, spacing: 3) {
                Label("Only you see this", systemImage: "lock")
                    .labelStyle(.titleAndIcon)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(words)
                    .font(.hand(17, relativeTo: .callout))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens your journal entry")
        .sheet(isPresented: $editing) {
            JournalEntrySheet(photoId: memory.id, thumb: memory.urls?.thumb, takenAt: memory.takenAt)
        }
    }
}

// MARK: - The circle's question of the week

/// This week's question, as a clean card under the notes: the question in
/// serif italic, and under it a line to answer on in your own hand, or
/// "You answered" behind a lock until the answers open, then the way to
/// read them. Never how many have answered.
struct QuestionSlip: View {
    @Environment(AppState.self) private var state
    let question: WeekQuestion
    @State private var text = ""
    @State private var sending = false
    @State private var reading = false

    private var reveal: String { RevealTime.phrase(question.prompt.revealsAt) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("This week's question")
                .quietLabel()
            Text(question.prompt.text)
                .questionType()
                .fixedSize(horizontal: false, vertical: true)
            if question.revealed {
                Button { reading = true } label: {
                    HStack(spacing: 8) {
                        Text("See what everyone said")
                            .wordButton(.body)
                        Image(systemName: "arrow.right")
                            .font(.footnote.weight(.semibold))
                    }
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
            } else if let mine = question.response {
                VStack(alignment: .leading, spacing: 6) {
                    Label("You answered", systemImage: "lock.fill")
                        .font(.subheadline.weight(.medium))
                    Text(mine.body)
                        .font(.hand(18, relativeTo: .callout))
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Responses revealed \(reveal)")
                        .quietLabel()
                        .padding(.top, 2)
                }
            } else {
                HandField(prompt: "Your answer", text: $text, limit: WritingLimit.answer, lines: 1...8) {
                    if text.hasWords {
                        Button(sending ? "Sending…" : "Answer") { send() }
                            .wordButton()
                            .fixedSize()
                            .disabled(sending)
                    }
                }
                Text("Your answer is private until \(reveal)")
                    .quietLabel()
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // A clean card (build 44; a dog-eared slip of paper before).
        .card()
        .sheet(isPresented: $reading) {
            AnswersSheet(question: question.prompt)
        }
    }

    private func send() {
        sending = true
        Task {
            if await state.answerQuestion(text.trimmedWords) {
                Haptics.answered()
                text = ""
            }
            sending = false
        }
    }
}

/// One person's answer: their name small in their own tone, as a mention of
/// them is, and their words in a hand, as they wrote them. A long press
/// reports it.
struct AnswerLine: View {
    @Environment(AppState.self) private var state
    let answer: Answer
    @State private var reporting = false

    private var isMine: Bool { state.myId != nil && answer.author.id == state.myId }

    private var tone: Color {
        guard let id = answer.author.id, let circle = state.circle else { return .primary }
        return MentionInk.color(MentionTones.index(for: id, in: circle))
    }

    var body: some View {
        let line = VStack(alignment: .leading, spacing: 4) {
            Text(answer.author.displayName)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(tone)
            Text(answer.body)
                .font(.hand(19, relativeTo: .body))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        if isMine {
            line
        } else {
            line
                .contextMenu {
                    Button { reporting = true } label: {
                        Label("Report Answer", systemImage: "flag")
                    }
                }
                .sheet(isPresented: $reporting) {
                    ReportSheet(target: .answer(answer))
                }
        }
    }
}

/// A week's question and everyone's answers, in the order they were
/// written: the question in a hand atop the page, then each answer under a
/// hairline. Opened from the slip once the answers are out, or handed a past
/// week's from the circle journal.
struct AnswersSheet: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss
    let question: Question
    /// A past week's answers, already here. Nil asks for this week's.
    var given: [Answer]?

    @State private var answers: [Answer]?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text(WeekRange.text(question.weekStart, question.weekEnd))
                        .quietLabel()
                    Text(question.text)
                        .questionType(.title2)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 6)
                    Rule(weight: 0.5)
                        .padding(.vertical, 14)
                    if let answers {
                        if answers.isEmpty {
                            Text("No one wrote this week.")
                                .font(.body)
                                .foregroundStyle(.secondary)
                        }
                        ForEach(Array(answers.enumerated()), id: \.element.id) { index, answer in
                            if index > 0 { Rule(weight: 0.5).padding(.vertical, 14) }
                            AnswerLine(answer: answer)
                        }
                    } else {
                        ProgressView().frame(maxWidth: .infinity).padding(.vertical, 30)
                    }
                }
                .padding(20)
                .frame(maxWidth: 600, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .atmosphereWash()
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .task {
                if let given {
                    answers = given
                } else {
                    answers = await state.questionAnswers()?.responses ?? []
                }
            }
        }
    }
}

/// The circle journal: every week's question whose answers are out, newest
/// first, with what everyone said, from the week you joined. Opened from the
/// circle's name atop Today and from Settings.
struct CircleJournalView: View {
    @Environment(AppState.self) private var state
    @State private var weeks: [PastQuestion] = []
    @State private var cursor: String?
    @State private var loaded = false
    @State private var loadingMore = false

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(state.circle?.name ?? "Your circle")
                        .font(.pageTitle)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text("Each week's question, and what everyone said")
                        .quietLabel()
                }
                .padding(.bottom, 18)
                if loaded && weeks.isEmpty {
                    Text("Nothing here yet. Once a week's answers are read together, they're kept here.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 6)
                }
                ForEach(weeks) { week in
                    VStack(alignment: .leading, spacing: 0) {
                        Rule(weight: 0.5)
                        Text(WeekRange.text(week.weekStart, week.weekEnd))
                            .quietLabel()
                            .padding(.top, 12)
                        Text(week.text)
                            .questionType()
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 4)
                            .padding(.bottom, 14)
                        ForEach(Array(week.responses.enumerated()), id: \.element.id) { index, answer in
                            if index > 0 { Rule(weight: 0.5).padding(.vertical, 12) }
                            AnswerLine(answer: answer)
                        }
                    }
                    .padding(.bottom, 34)
                }
                if cursor != nil {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                        .task(id: cursor) { await more() }
                }
                if !loaded {
                    ProgressView().frame(maxWidth: .infinity).padding(.vertical, 30)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 30)
            .frame(maxWidth: 600, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .atmosphereWash()
        .navigationTitle("Circle Journal")
        .navigationBarTitleDisplayMode(.inline)
        .sunRefreshable {
            Haptics.refreshed()
            await Task { await first() }.value
        }
        .task {
            Trail.note(.openedCircleJournal)
            await first()
        }
        .onChange(of: state.reloads) { Task { await first() } }
    }

    private func first() async {
        do {
            let page = try await state.circleJournal(cursor: nil)
            weeks = page.prompts
            cursor = page.nextCursor
            loaded = true
        } catch {
            state.missed(error)
            loaded = true
        }
    }

    private func more() async {
        guard let asked = cursor, !loadingMore else { return }
        loadingMore = true
        defer { loadingMore = false }
        do {
            let page = try await state.circleJournal(cursor: asked)
            guard cursor == asked else { return }
            let showing = Set(weeks.map(\.id))
            weeks += page.prompts.filter { !showing.contains($0.id) }
            cursor = page.nextCursor
        } catch {
            state.missed(error)
        }
    }
}

// MARK: - Your reflection on the week

/// One of the week's photos as a small print: at full light if you held
/// it, otherwise faded as far as it has in Today.
struct WeekPhotoThumb: View {
    @Environment(AppState.self) private var state
    @Environment(\.colorScheme) private var colorScheme
    let photo: WeekPhoto
    var width: CGFloat = 48

    var body: some View {
        let fade = photo.held ? 0 : PhotoImageView.fade(photo.decayProgress)
        Color.clear
            .aspectRatio(PhotoShape.aspect, contentMode: .fit)
            .frame(width: width)
            .overlay {
                SignedImage(url: state.api.absoluteURL(photo.thumb)) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    Rectangle().fill(.quaternary)
                }
            }
            .saturation(1 - 0.85 * fade)
            .opacity(1 - (colorScheme == .dark ? 0.62 : 0.82) * fade)
            .asPrint(corner: width > 60 ? 6 : 4)
            .accessibilityLabel(photo.caption ?? "Your photo from \(photo.takenAt.formatted(.dateTime.weekday(.wide)))")
    }
}

/// Sunday evening, atop the You tab: "How was your week?" with the week's
/// photos still there, as a slip tucked inside the cover. Gone at midnight,
/// and once the week's reflection is written.
struct ReflectionCard: View {
    let week: ThisWeek
    @State private var writing = false

    var body: some View {
        Button { writing = true } label: {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("How was your week?")
                        .font(.hand(26, bold: true, relativeTo: .title2))
                    Text(WeekRange.text(week.weekStart, week.weekEnd))
                        .quietLabel()
                }
                if !week.photos.isEmpty {
                    HStack(spacing: 10) {
                        ForEach(week.photos.prefix(7)) { photo in
                            WeekPhotoThumb(photo: photo, width: 40)
                        }
                    }
                    .padding(.vertical, 4)
                }
                Text("A few lines for yourself. Only you see this.")
                    .quietLabel()
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .creamPaper()
        .accessibilityHint("Write about your week")
        .sheet(isPresented: $writing) { ReflectionSheet(week: week) }
    }
}

/// Writing the week's reflection: its photos in a row along the top, and
/// the page beneath them.
struct ReflectionSheet: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss
    let week: ThisWeek
    @State private var text = ""
    @State private var saving = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(WeekRange.text(week.weekStart, week.weekEnd))
                            .quietLabel()
                        Text("How was your week?")
                            .font(.hand(30, bold: true, relativeTo: .largeTitle))
                    }
                    if !week.photos.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(alignment: .top, spacing: 14) {
                                ForEach(week.photos) { photo in
                                    WeekPhotoThumb(photo: photo, width: 92)
                                }
                            }
                            .padding(.vertical, 8)
                            .padding(.horizontal, 4)
                        }
                        .scrollClipDisabled()
                    }
                    HandField(
                        prompt: "What stayed with you", text: $text, limit: WritingLimit.reflection,
                        size: 20, lines: 4...16
                    )
                    Label("Only you see this. It's kept in your journal, and it doesn't fade.", systemImage: "lock")
                        .quietLabel()
                }
                .padding(20)
            }
            .atmosphereWash()
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(saving ? "Keeping…" : "Keep") { save() }
                        .disabled(saving || !text.hasWords)
                }
            }
        }
        .interactiveDismissDisabled(text.hasWords)
    }

    private func save() {
        saving = true
        Task {
            if await state.writeReflection(text.trimmedWords) { dismiss() }
            saving = false
        }
    }
}

/// A week's page in the journal at the foot of the You tab: the days in
/// small capitals, what you wrote in your hand, and the week's photos that
/// are still there. A long press deletes it; nothing else ever does.
struct ReflectionPage: View {
    @Environment(AppState.self) private var state
    let reflection: Reflection
    @State private var confirmDelete = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(WeekRange.text(reflection.weekStart, reflection.weekEnd))
                .quietLabel()
            Text(reflection.body)
                .font(.hand(19, relativeTo: .body))
                .fixedSize(horizontal: false, vertical: true)
            if !reflection.photos.isEmpty {
                HStack(spacing: 10) {
                    ForEach(reflection.photos.prefix(7)) { photo in
                        WeekPhotoThumb(photo: photo, width: 40)
                    }
                }
                .padding(.top, 4)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        // A page of the journal: cream paper, the words in your hand.
        .creamPaper()
        .contextMenu {
            Button(role: .destructive) { confirmDelete = true } label: {
                Label("Delete Reflection", systemImage: "trash")
            }
        }
        .alert("Delete this reflection?", isPresented: $confirmDelete) {
            Button("Delete", role: .destructive) { Task { await state.deleteReflection(reflection) } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Reflections don't fade, so this is the only way one leaves. It's gone for good.")
        }
        .accessibilityElement(children: .combine)
    }
}

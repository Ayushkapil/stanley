import SwiftUI

/// Report, block, delete and untag (build 18). The server has had them since
/// the first pilot builds; these are the ways in. Each photo has a menu (its
/// own "…" under a print, the long-press menu on any print, the top of its
/// stories), each story a long-press menu, and each member's profile a Block.
/// App Review asks for report and block in any app where people post
/// (guideline 1.2), and the Terms promise both.
///
/// Quiet, like the rest of Stanley: no counts, nothing that tells anyone
/// they were reported or blocked, and every irreversible step behind an
/// alert that says plainly what happens.

/// What someone asked to do to a photo from one of its menus.
enum PhotoAction: Identifiable {
    case report, delete, untag
    /// Your own journal entry on it (build 26).
    case journal
    var id: Self { self }
}

/// The photo menu's rows, for a `Menu` or a `.contextMenu` alike. Your own
/// photo can be deleted; anyone else's reported; one you're tagged in, left.
struct PhotoMenuItems: View {
    @Environment(AppState.self) private var state
    let photo: Photo
    @Binding var action: PhotoAction?

    private var isMine: Bool { state.myId != nil && state.myId == photo.owner.id }
    private var isTagged: Bool { photo.tagged.contains { $0.id != nil && $0.id == state.myId } }

    var body: some View {
        if isTagged {
            Button { action = .untag } label: {
                Label("Remove Me from This Photo", systemImage: "person.crop.circle.badge.minus")
            }
        }
        if isMine {
            // A server before build 26 says nothing about entries.
            if let written = photo.hasJournal {
                Button { action = .journal } label: {
                    Label(written ? "Your Journal Entry" : "Write in Your Journal", systemImage: "book.closed")
                }
            }
            Button(role: .destructive) { action = .delete } label: {
                Label("Delete Photo", systemImage: "trash")
            }
        } else {
            Button { action = .report } label: {
                Label("Report Photo", systemImage: "flag")
            }
        }
    }
}

/// The "…" under a print: the photo menu where anyone can find it, without
/// knowing to press and hold.
struct PhotoMenuButton: View {
    let photo: Photo
    @Binding var action: PhotoAction?

    var body: some View {
        Menu {
            PhotoMenuItems(photo: photo, action: $action)
        } label: {
            Image(systemName: "ellipsis")
                .frame(width: GestureIcon.target, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .accessibilityLabel("More")
    }
}

extension View {
    /// Carries out what a photo menu asked for: the report sheet, or an alert
    /// before deleting or untagging.
    func photoActions(_ photo: Photo, _ action: Binding<PhotoAction?>) -> some View {
        modifier(PhotoActions(photo: photo, action: action))
    }

    /// A story's long-press menu: Report, on anyone's story but your own.
    func storyMenu(_ comment: Comment, on photo: Photo) -> some View {
        modifier(StoryMenu(comment: comment, photo: photo))
    }
}

private struct PhotoActions: ViewModifier {
    @Environment(AppState.self) private var state
    let photo: Photo
    @Binding var action: PhotoAction?

    private func showing(_ which: PhotoAction) -> Binding<Bool> {
        Binding(get: { action == which }, set: { if !$0 { action = nil } })
    }

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: showing(.report)) {
                ReportSheet(target: .photo(photo))
            }
            .sheet(isPresented: showing(.journal)) {
                JournalEntrySheet(photoId: photo.id, thumb: photo.urls?.thumb, takenAt: photo.takenAt)
            }
            .alert("Delete this photo?", isPresented: showing(.delete)) {
                Button("Delete", role: .destructive) { Task { await state.deletePhoto(photo) } }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(Self.deleteMessage(photo))
            }
            .alert("Remove you from this photo?", isPresented: showing(.untag)) {
                Button("Remove Me", role: .destructive) { Task { await state.untagMe(from: photo) } }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Your face comes off it for everyone. It can't be put back.")
            }
    }

    /// What deleting does, before it happens. Whether it gives the day back
    /// is the server's answer (`retake_on_delete`), never a guess.
    static func deleteMessage(_ photo: Photo) -> String {
        let gone = "It's removed for everyone, including anyone who held it."
        switch photo.retakeOnDelete {
        case true?: return gone + " It's today's photo, so you can take today's again, once."
        case false?: return gone + " Deleting it won't give you another photo today."
        case nil: return gone
        }
    }
}

private struct StoryMenu: ViewModifier {
    @Environment(AppState.self) private var state
    let comment: Comment
    let photo: Photo
    @State private var reporting = false

    private var isMine: Bool { state.myId != nil && state.myId == comment.author.id }

    func body(content: Content) -> some View {
        if isMine {
            content
        } else {
            content
                .contextMenu {
                    Button { reporting = true } label: {
                        Label("Report Story", systemImage: "flag")
                    }
                }
                .sheet(isPresented: $reporting) {
                    ReportSheet(target: .story(comment, on: photo))
                }
        }
    }
}

/// What's being reported.
enum ReportTarget {
    case photo(Photo)
    case story(Comment, on: Photo)
    /// An answer to the circle's question of the week (build 26).
    case answer(Answer)
    /// A note on the circle's board (build 27).
    case note(CommunityNote)
    /// An unsigned letter to the circle (build 42).
    case circleLetter(CircleLetter)
    /// A letter written to you, once it's open (build 42).
    case letter(Letter)
    /// A page in the circle's shared journal (build 51).
    case page(SharedPage)

    /// Whose it is. Nil for a letter to the circle: nobody's, as far as
    /// the app is told.
    var author: UserBrief? {
        switch self {
        case .photo(let photo): photo.owner
        case .story(let comment, _): comment.author
        case .answer(let answer): answer.author
        case .note(let note): note.author
        case .circleLetter: nil
        case .letter(let letter):
            letter.sender ?? UserBrief(id: nil, displayName: "someone", avatarUrl: nil)
        case .page(let page): page.writer
        }
    }

    var noun: String {
        switch self {
        case .photo: "photo"
        case .story: "story"
        case .answer: "answer"
        case .note: "note"
        case .circleLetter: "letter"
        case .letter: "letter"
        case .page: "page"
        }
    }
}

/// Report a photo or a story: why, in one tap, and then a thank-you that
/// offers to block the person too. The report goes to the person who runs
/// Stanley, never to whoever posted it, and is read within a day (Terms §5).
struct ReportSheet: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss
    let target: ReportTarget
    @State private var sending = false
    @State private var sent = false
    @State private var writing = false
    @State private var words = ""
    @State private var blocked = false

    static let reasons = [
        "It's hurtful, bullying or harassing",
        "It's sexual or explicit",
        // Its own reason (the production audit), so the operator reads it
        // first and follows the CSAM steps in PRODUCTION_CHECKLIST.md.
        "It sexualizes or endangers a child",
        "It's violent or threatening",
        "It's hateful",
        "It shows someone who didn't want it shared",
        "It's spam or a scam",
    ]

    private var name: String {
        guard let full = target.author?.displayName else { return "whoever wrote it" }
        return full.split(separator: " ").first.map(String.init) ?? full
    }

    /// Someone who still has an account and isn't you. Never for a letter:
    /// there's nobody to name.
    private var canBlock: Bool {
        guard let author = target.author, let id = author.id else { return false }
        return id != state.myId && author.displayName != "departed"
    }

    /// Who reads a report, and for an unsigned letter, what they can see
    /// that the circle can't.
    private var whoReadsIt: String {
        let line = "Your report goes to the person who runs Stanley, not to \(name), and it's read within a day."
        guard case .circleLetter = target else { return line }
        return line + " They can see who wrote a reported letter. You and your circle can't."
    }

    var body: some View {
        NavigationStack {
            Group {
                if sent { thanks } else { reasons }
            }
            .atmosphereWash()
            .navigationTitle(sent ? "" : "Report")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: sent ? .confirmationAction : .cancellationAction) {
                    Button(sent ? "Done" : "Cancel") { dismiss() }
                }
            }
        }
        .interactiveDismissDisabled(sending)
        // Their photos leave Today once this sheet has gone, not under it.
        .onDisappear { if blocked { Task { await state.refreshToday() } } }
    }

    private var reasons: some View {
        Form {
            Group {
                Section {
                    ForEach(Self.reasons, id: \.self) { reason in
                        Button(reason) { send(reason) }
                            .foregroundStyle(.primary)
                    }
                    Button("Something else") { writing = true }
                        .foregroundStyle(.primary)
                } header: {
                    Text("Why are you reporting this \(target.noun)?")
                } footer: {
                    Text(whoReadsIt)
                }
                if writing {
                    Section {
                        TextField("What's wrong with it?", text: $words, axis: .vertical)
                            .lineLimit(2...5)
                        Button("Send Report") { send(words.trimmingCharacters(in: .whitespacesAndNewlines)) }
                            .disabled(words.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
            .atmosphereRows()
            .disabled(sending)
        }
        .overlay { if sending { ProgressView() } }
    }

    private var thanks: some View {
        VStack(spacing: 14) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.secondary)
            Text("Thank you for telling us.")
                .font(.title3.weight(.semibold))
            Text("Someone will look at it within a day. If it breaks Stanley's rules, it comes down.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if canBlock {
                if blocked {
                    Text("\(name) is blocked.")
                        .font(.callout)
                        .padding(.top, 18)
                } else {
                    Button("Block \(name)", role: .destructive) {
                        Task { if let author = target.author { blocked = await state.block(author) } }
                    }
                    .destructiveInk()
                    .padding(.top, 18)
                    Text("You won't see each other's photos or stories. They aren't told.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func send(_ reason: String) {
        guard !reason.isEmpty, !sending else { return }
        sending = true
        Task {
            var photo: Photo?, comment: Comment?, answer: Answer?, note: CommunityNote?
            var circleLetter: CircleLetter?, letter: Letter?, page: SharedPage?
            switch target {
            case .photo(let p): photo = p
            case .story(let c, _): comment = c
            case .answer(let a): answer = a
            case .note(let n): note = n
            case .circleLetter(let l): circleLetter = l
            case .letter(let l): letter = l
            case .page(let p): page = p
            }
            let ok = await state.report(
                photo: photo, comment: comment, answer: answer, note: note,
                circleLetter: circleLetter, letter: letter, page: page, reason: reason
            )
            sending = false
            if ok { withAnimation { sent = true } }
        }
    }
}

/// Block, from a member's profile: what it means, then done. The profile
/// closes behind it, since a blocked person's profile isn't shown.
struct BlockButton: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss
    let person: UserBrief
    @State private var confirming = false
    @State private var blocked = false

    private var name: String {
        person.displayName.split(separator: " ").first.map(String.init) ?? person.displayName
    }

    var body: some View {
        Button("Block \(name)", role: .destructive) { confirming = true }
            .destructiveInk()
            .font(.callout)
            .alert("Block \(name)?", isPresented: $confirming) {
                Button("Block", role: .destructive) {
                    Task {
                        if await state.block(person) {
                            blocked = true
                            dismiss()
                        }
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("You won't see each other's photos or stories, in any circle you share. \(name) isn't told. You can unblock them in Settings.")
            }
            // Once the profile has closed: their photos leave Today, and a
            // word says why.
            .onDisappear {
                guard blocked else { return }
                Task {
                    await state.refreshToday()
                    state.flash = "Blocked. You won't see each other's photos."
                }
            }
    }
}

/// Settings → Privacy & Security → About Your Account → Blocked (build 22;
/// it was a row of Privacy & Security): the people you've blocked, as
/// faces and names, each with Unblock. Never a number, and never who has
/// blocked you.
struct BlockedView: View {
    @Environment(AppState.self) private var state
    @State private var people: [UserBrief]?

    var body: some View {
        List {
            Group {
                if let people, people.isEmpty {
                    Text("No one. If you block someone, they'll be here, so you can unblock them.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(people ?? [], id: \.id) { person in
                        HStack(spacing: 12) {
                            AvatarView(url: person.avatarUrl, name: person.displayName, size: 40)
                            Text(person.displayName)
                            Spacer()
                            Button("Unblock") {
                                Task {
                                    if await state.unblock(person) {
                                        withAnimation { self.people?.removeAll { $0.id == person.id } }
                                    }
                                }
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                        .padding(.vertical, 3)
                    }
                }
            }
            .atmosphereRows()
        }
        .overlay { if people == nil { ProgressView() } }
        .atmosphereWash()
        .navigationTitle("Blocked")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: state.reloads) {
            do {
                people = try await state.blockedPeople()
            } catch {
                // Offline, "No one" would be a guess: keep waiting instead,
                // and load when Stanley answers.
                state.missed(error)
                if !isOffline(error) { people = [] }
            }
        }
    }
}

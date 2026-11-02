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

    var author: UserBrief {
        switch self {
        case .photo(let photo): photo.owner
        case .story(let comment, _): comment.author
        }
    }

    var noun: String {
        switch self {
        case .photo: "photo"
        case .story: "story"
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
        "It's violent or threatening",
        "It's hateful",
        "It shows someone who didn't want it shared",
        "It's spam or a scam",
    ]

    private var name: String {
        let full = target.author.displayName
        return full.split(separator: " ").first.map(String.init) ?? full
    }

    /// Someone who still has an account and isn't you.
    private var canBlock: Bool {
        guard let id = target.author.id else { return false }
        return id != state.myId && target.author.displayName != "departed"
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
                    Text("Your report goes to the person who runs Stanley, not to \(name), and it's read within a day.")
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
                        Task { blocked = await state.block(target.author) }
                    }
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
            let (photo, comment): (Photo?, Comment?) = switch target {
            case .photo(let p): (p, nil)
            case .story(let c, _): (nil, c)
            }
            let ok = await state.report(photo: photo, comment: comment, reason: reason)
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

/// Settings → Privacy & Security → Blocked: the people you've blocked, as
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

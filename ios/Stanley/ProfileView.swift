import SwiftUI

/// Your own profile, as the inside cover of the journal (build 20): a
/// bookplate that says whose journal it is, with your photo pasted in and
/// your name and words in your hand; the circle it's kept with; and the
/// prints you've kept. The prints are a private self-view (A2) — no other
/// member can ever see them. Deliberately absent: follower counts, and
/// numbers about anyone else. The one number here (build 19) is how many
/// moments you've shared, quiet and yours alone: it's only on `/me`, never
/// on the page others see of you.
struct ProfileView: View {
    @Environment(AppState.self) private var state
    @Environment(\.horizontalSizeClass) private var hSizeClass
    private var density: Density { Density(hSizeClass) }
    @State private var showEdit = false
    @State private var inviting = false
    @State private var milestones: [Milestone] = []

    private var kept: [Memory] {
        state.threads.flatMap(\.memories)
    }

    /// Everyone in the circle but you.
    private var others: [CircleMember] {
        (state.circle?.members ?? []).filter { $0.id != state.myId }
    }

    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: Spacing.section), count: density.keptColumns)
    }

    /// When this journal was begun: the month the account was made.
    private var begun: String {
        guard let created = state.profile?.createdAt else {
            return Date.now.formatted(.dateTime.weekday(.wide).month(.wide).day().year())
        }
        return "Kept since \(created.formatted(.dateTime.month(.wide).year()))"
    }

    @ViewBuilder
    private var bioView: some View {
        if let bio = state.profile?.bio, !bio.isEmpty {
            Text(bio)
                .font(.subheadline)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            Button("Write a little about yourself") { showEdit = true }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .buttonStyle(.plain)
        }
    }

    /// Who you are, on a card: your photo (a tap changes it), your name
    /// in the system's rounded face (it's your identity, not a journal
    /// entry), your username and your words. A bookplate in a double rule
    /// with the name in a hand until build 44.
    private var bookplate: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: density.profileIsHorizontal ? .top : .center, spacing: 16) {
                AvatarEditor()
                VStack(alignment: .leading, spacing: 2) {
                    Text(state.profile?.displayName ?? " ")
                        .font(.system(.title2, design: .rounded).weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    if let username = state.profile?.username {
                        Text("@\(username)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    // Inner display: the words flow beside the face
                    // instead of stacking under it.
                    if density.profileIsHorizontal {
                        bioView.padding(.top, 10)
                    }
                }
                Spacer(minLength: 0)
            }
            if !density.profileIsHorizontal {
                bioView
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(h: 18, v: 18)
    }

    var body: some View {
        NavigationStack {
          ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    JournalMasthead(title: "You", line: begun) {
                        Button("Edit") { showEdit = true }
                            .font(.system(.body, design: .rounded).weight(.medium))
                            .frame(minHeight: 44)
                    }
                    .id("masthead")
                    bookplate
                        .padding(.top, Spacing.section)
                    if let shared = state.profile?.momentsShared, shared > 0 {
                        Text("You've shared \(shared == 1 ? "one moment" : "\(shared) moments"). Only you see this.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .padding(.top, Spacing.section)
                    }
                    // The circle's faces, and at their end the way to add one
                    // (build 33). Shown even before anyone else has joined,
                    // when inviting is the one thing to do.
                    if let circle = state.circle {
                        VStack(alignment: .leading, spacing: Spacing.section) {
                            JournalSectionHead(label: "Your circle", title: circle.name)
                            CircleCards(members: others) { inviting = true }
                        }
                        .padding(.top, Spacing.chapter)
                    }
                    ForEach(milestones) { milestone in
                        MilestoneCard(milestone: milestone) {
                            Task {
                                await state.dismissMilestone(milestone.id)
                                milestones.removeAll { $0.id == milestone.id }
                            }
                        }
                        .padding(.top, Spacing.section)
                    }
                    JournalSectionHead(label: "Only you see this", title: "Held")
                        .padding(.top, Spacing.chapter)
                        .padding(.bottom, Spacing.section)
                    if kept.isEmpty {
                        Text("Moments you hold will gather here at full light. Only you see this — nothing here fades.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        LazyVGrid(columns: columns, spacing: Spacing.section) {
                            ForEach(kept) { memory in
                                HeldTile(memory: memory)
                            }
                        }
                    }
                    // Letters you can write to someone in the circle for one
                    // day in the future (build 42). Your weekly reflections
                    // were under this until build 44; they're the Journal
                    // tab's pages now.
                    LettersOnYou()
                        .padding(.top, Spacing.chapter)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, Spacing.chapter)
                .frame(maxWidth: .infinity, alignment: .leading)
                .readableWidth(density)
                .foldAnimated(hSizeClass)
            }
            // A tap on the You tab: back to the top, or at the top the
            // pull's own refresh (`TabTaps`).
            .onTabTap(state.tabTaps.you, scroll: proxy, to: "masthead") {
                await state.loadProfile()
                await state.refreshMemories()
                milestones = await state.loadMilestones()
            }
            .journalPage()
            .navigationTitle("You")
            .sheet(isPresented: $showEdit) { EditProfileSheet() }
            .sheet(isPresented: $inviting) { InviteSheet() }
            .task {
                await state.loadProfile()
                await state.refreshMemories()
                milestones = await state.loadMilestones()
            }
            .sunRefreshable {
                Haptics.refreshed()
                await Task {
                    await state.loadProfile()
                    await state.refreshMemories()
                    milestones = await state.loadMilestones()
                }.value
            }
            // The profile and Held are fetched again by `AppState`; the
            // milestones are this page's to ask for.
            .onChange(of: state.reloads) {
                Task {
                    milestones = await state.loadMilestones()
                }
            }
          }
        }
    }
}

/// The circle on the You tab, as a cluster of friends (the polish pass,
/// build 28): round faces overlapping a little at their edges, the way
/// shared-with-you faces sit together, each ringed in a hairline of paper so
/// one face reads against the next, with a first name small beneath and a
/// quiet mark on whoever started the circle. The row scrolls when there are
/// more than fit. Each opens that person's profile. People, never a number:
/// the row has no "+7", and nothing says how many there are.
private struct CircleCards: View {
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("stanley.atmosphere") private var raw = "auto"
    let members: [CircleMember]
    /// The Invite card at the end of the row.
    let onInvite: () -> Void
    @ScaledMetric(relativeTo: .caption) private var face: CGFloat = 52
    /// How far each face lies over the one before it.
    private let overlap: CGFloat = 9

    /// Room for the organizer's mark on every card, so the row lines up,
    /// only when the organizer is in it.
    private var marksOrganizer: Bool { members.contains { $0.isCreator == true } }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: -overlap) {
                ForEach(members) { member in
                    NavigationLink {
                        MemberProfileView(memberId: member.id)
                    } label: {
                        card(member)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(
                        (member.displayName ?? "New member") + (member.isCreator == true ? ", organizer" : "")
                    )
                    .accessibilityHint("Opens their profile")
                }
                inviteCard
                    // Clear of the last face rather than lying over it.
                    .padding(.leading, members.isEmpty ? 0 : overlap + 8)
            }
            .padding(.vertical, 4)
        }
        .scrollClipDisabled()
    }

    /// A face-sized ring in the accent with a plus, and "Invite" beneath in
    /// the same hand as the names: the next face, not yet there.
    private var inviteCard: some View {
        let accent = Atmosphere.resolve(raw).palette.accent
        return Button(action: onInvite) {
            VStack(spacing: 4) {
                Image(systemName: "plus")
                    .font(.system(size: face * 0.36, weight: .light))
                    .foregroundStyle(accent)
                    .frame(width: face, height: face)
                    .overlay(Circle().strokeBorder(accent, lineWidth: 1))
                Text("Invite")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(accent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .padding(.top, 4)
            .frame(width: face)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Invite someone")
        .accessibilityHint("Shows the circle's invite code to copy or share")
    }

    private func card(_ member: CircleMember) -> some View {
        // Each face is ringed in the atmosphere's accent, as every face is
        // since build 39, with a hairline of the page outside it so one
        // reads against the next where they overlap.
        let page = Atmosphere.resolve(raw).palette.floor
        let full = member.displayName ?? "New member"
        return VStack(spacing: 4) {
            AvatarView(url: member.avatarUrl, name: member.displayName, size: face, circular: true)
                .padding(1)
                .background(page, in: Circle())
                .padding(-1)
            Text(full.split(separator: " ").first.map(String.init) ?? full)
                .font(.caption)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(width: face - overlap)
            // Who started it, said quietly: a word, not a crown.
            if marksOrganizer {
                Text("organizer")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .opacity(member.isCreator == true ? 1 : 0)
            }
        }
        .padding(.top, 4)
        .frame(width: face)
        .contentShape(Rectangle())
    }
}

/// A milestone (Part 4): a journal noticing its own age, as a slip tucked
/// inside the cover. Private, gentle, dismissable. No progress bars, no
/// scores, no unlock language.
struct MilestoneCard: View {
    @Environment(AppState.self) private var state
    @Environment(\.horizontalSizeClass) private var hSizeClass
    private var density: Density { Density(hSizeClass) }
    let milestone: Milestone
    let onDismiss: () -> Void

    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 3), count: density.threadColumns)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                Text(milestone.title)
                    .font(.sectionTitle)
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss")
            }
            if let body = milestone.body, !body.isEmpty {
                Text(body)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if let faces = milestone.faces, !faces.isEmpty {
                FaceCluster(
                    faces: faces.map { (id: $0.id ?? $0.displayName, url: $0.avatarUrl, name: $0.displayName) },
                    size: 32
                )
            }
            if let photos = milestone.photos, !photos.isEmpty {
                LazyVGrid(columns: columns, spacing: 3) {
                    ForEach(photos, id: \.self) { thumb in
                        Color.clear
                            .aspectRatio(1, contentMode: .fit)
                            .overlay {
                                if let url = state.api.absoluteURL(thumb) {
                                    SignedImage(url: url) { image in
                                        image.resizable().scaledToFill()
                                    } placeholder: {
                                        Rectangle().fill(.quaternary)
                                    }
                                }
                            }
                            .asPrint(corner: 4)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(h: 16, v: 16)
    }
}

/// A held print on the You page (Part 6): full saturation — Held is the one
/// place nothing fades — on its paper, a little crooked, with "held · date"
/// in small capitals beneath. A tombstone is a blank print with the words
/// on it. Reads well at three or thirty.
struct HeldTile: View {
    @Environment(AppState.self) private var state
    let memory: Memory

    private var trace: String? {
        guard let taken = memory.takenAt else { return nil }
        return "Held · \(taken.formatted(.dateTime.month(.abbreviated).day()))"
    }

    var body: some View {
        VStack(spacing: 7) {
            if memory.isTombstone {
                Color.clear
                    .aspectRatio(PhotoShape.aspect, contentMode: .fit)
                    .overlay {
                        Text("A memory was here")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(6)
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(DarkRoom.line(0.14), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    }
            } else {
                Color.clear
                    .aspectRatio(PhotoShape.aspect, contentMode: .fit)
                    .overlay {
                        if let urls = memory.urls, let url = state.api.absoluteURL(urls.thumb) {
                            SignedImage(url: url) { image in
                                image.resizable().scaledToFill()
                            } placeholder: {
                                Rectangle().fill(.quaternary)
                            }
                        }
                    }
                    .asPrint(corner: 6)
            }
            if let trace {
                Text(trace)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .contentShape(Rectangle())
    }
}

struct EditProfileSheet: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var username = ""
    @State private var bio = ""
    @State private var saving = false

    @State private var usernameStatus: Username.Status = .idle

    private var trimmedUsername: String {
        username.trimmingCharacters(in: .whitespaces).lowercased()
    }

    var body: some View {
        let profile = state.profile
        let uploading = state.avatarUploading
        NavigationStack {
            Form {
                Group {
                    Section {
                        HStack(spacing: 14) {
                            AvatarView(url: profile?.avatarUrl, name: profile?.displayName, size: 56)
                                .overlay {
                                    if uploading { ProgressView() }
                                }
                            AvatarChooser {
                                Text(profile?.avatarUrl == nil ? "Add a photo" : "Change photo")
                                    .foregroundStyle(Color.accentColor)
                            }
                            Spacer(minLength: 0)
                        }
                    }
                    Section("Name") {
                        TextField("Your name", text: $name)
                    }
                    Section {
                        TextField("username", text: $username)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    } header: {
                        Text("Username")
                    } footer: {
                        Username.footer(for: usernameStatus)
                    }
                    Section {
                        TextEditor(text: $bio)
                            .frame(minHeight: 140)
                    } header: {
                        Text("About you")
                    } footer: {
                        Text("As much room as you need. Circle members see your name and these words — never what you've kept.")
                    }
                }
                .atmosphereRows()
            }
            .atmosphereWash()
            .navigationTitle("Edit profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saving = true
                        Task {
                            let saved = await state.updateProfile(
                                displayName: name.trimmingCharacters(in: .whitespaces),
                                username: username.trimmingCharacters(in: .whitespaces),
                                bio: bio
                            )
                            saving = false
                            if saved { dismiss() }
                        }
                    }
                    .disabled(
                        saving
                            || name.trimmingCharacters(in: .whitespaces).isEmpty
                            || usernameStatus == .invalid
                            || usernameStatus == .taken
                    )
                }
            }
            .onAppear {
                name = state.profile?.displayName ?? ""
                username = state.profile?.username ?? ""
                bio = state.profile?.bio ?? ""
            }
            // Debounced real-time availability: retyping cancels the previous
            // check (task identity is the text itself), then we wait a beat.
            .task(id: username) {
                let candidate = trimmedUsername
                guard !candidate.isEmpty, candidate != state.profile?.username else {
                    usernameStatus = .idle
                    return
                }
                guard Username.isLocallyValid(candidate) else {
                    usernameStatus = .invalid
                    return
                }
                usernameStatus = .checking
                try? await Task.sleep(nanoseconds: 400_000_000)
                guard !Task.isCancelled else { return }
                guard let result = await state.checkUsername(candidate) else {
                    usernameStatus = .idle  // unknown ≠ blocked; the server re-checks on save
                    return
                }
                usernameStatus = result.available ? .available : (result.valid ? .taken : .invalid)
            }
        }
    }
}

/// Another member's profile: their name and their words. Their kept memories
/// are theirs alone — this view has nothing to render them with.
struct MemberProfileView: View {
    @Environment(AppState.self) private var state
    let memberId: String
    @State private var member: MemberProfile?
    /// One of their photos, opened from the page with its stories.
    @State private var opened: Photo?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 14), count: 3)

    var body: some View {
        Group {
            if let member {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        AvatarView(url: member.avatarUrl, name: member.displayName, size: 84)
                        Text(member.displayName ?? "New member")
                            .font(.system(.title, design: .rounded).weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                            .padding(.top, 16)
                        if let username = member.username {
                            Text("@\(username)")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        since(member)
                            .padding(.top, 8)
                        words(member)
                            .padding(.top, 20)
                        if let photos = member.photos, !photos.isEmpty {
                            inTheLight(photos)
                                .padding(.top, 26)
                        }
                        if member.id != state.myId {
                            BlockButton(person: UserBrief(
                                id: member.id,
                                displayName: member.displayName ?? "New member",
                                avatarUrl: member.avatarUrl
                            ))
                            .padding(.top, 40)
                        }
                    }
                    .padding(24)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                VStack(spacing: 14) {
                    ProgressView()
                    OfflineLine()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .atmosphereWash()
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $opened) { photo in
            PhotoStoriesView(photo: photo)
        }
        // Again when Stanley answers after it couldn't, or when the links
        // to their photos ran out; a photo open from here gets the fresh one.
        .task(id: state.reloads) {
            do {
                let loaded = try await state.loadMember(memberId)
                member = loaded
                if let open = opened, let fresh = loaded.photos?.first(where: { $0.id == open.id }) {
                    opened = fresh
                }
            } catch {
                state.missed(error)
            }
        }
    }

    /// "Member since October 2026", and a quiet mark on whoever started the
    /// circle. A date and a role, never a number.
    @ViewBuilder
    private func since(_ member: MemberProfile) -> some View {
        HStack(spacing: 6) {
            if let since = member.memberSince {
                Text("Member since \(since.formatted(.dateTime.month(.wide).year()))")
            }
            if member.isOrganizer == true {
                Text("· Organizer")
            }
        }
        .quietLabel()
    }

    /// Their words, or a kind line where they haven't
    /// written any yet.
    @ViewBuilder
    private func words(_ member: MemberProfile) -> some View {
        if let bio = member.bio, !bio.isEmpty {
            Text(bio)
                .font(.body)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            Text("Still writing this part…")
                .font(.body)
                .foregroundStyle(.secondary)
        }
    }

    /// Their photos you can still see, newest first, as small prints that
    /// fade as they do in Today: a reason to come by. Each opens with its
    /// stories. What they've held is theirs alone and never here.
    private func inTheLight(_ photos: [Photo]) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            JournalSectionHead(title: "Still in the light")
            LazyVGrid(columns: columns, spacing: 18) {
                ForEach(photos) { photo in
                    Button { opened = photo } label: { PrintThumb(photo: photo) }
                        .buttonStyle(.plain)
                        .accessibilityLabel(photo.caption ?? "A photo")
                }
            }
        }
    }
}

/// A small print: the photo's own shape on its paper, a little off square,
/// and faded as far as it has faded in Today.
private struct PrintThumb: View {
    @Environment(AppState.self) private var state
    @Environment(\.colorScheme) private var colorScheme
    let photo: Photo

    var body: some View {
        let fade = PhotoImageView.fade(photo.decayProgress)
        Color.clear
            .aspectRatio(PhotoShape.aspect, contentMode: .fit)
            .overlay {
                SignedImage(url: photo.urls.flatMap { state.api.absoluteURL($0.thumb) }) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    Rectangle().fill(.quaternary)
                }
            }
            .saturation(1 - 0.85 * fade)
            .opacity(1 - (colorScheme == .dark ? 0.62 : 0.82) * fade)
            .asPrint(corner: 6)
    }
}

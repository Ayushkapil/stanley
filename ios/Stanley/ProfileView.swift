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
    @State private var milestones: [Milestone] = []

    private var kept: [Memory] {
        state.threads.flatMap(\.memories)
    }

    /// Everyone in the circle but you.
    private var others: [CircleMember] {
        (state.circle?.members ?? []).filter { $0.id != state.myId }
    }

    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 18), count: density.keptColumns)
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
                .font(.hand(19, relativeTo: .body))
                .lineSpacing(1)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            Button("Write a little about yourself") { showEdit = true }
                .font(.hand(19, relativeTo: .body))
                .foregroundStyle(.secondary)
                .buttonStyle(.plain)
        }
    }

    /// The bookplate inside the cover: "This journal belongs to", your photo
    /// pasted in a little crooked (a tap changes it), your name written on
    /// the line, and your words beneath. Framed in a double rule, like the
    /// plate a book is signed on.
    private var bookplate: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("This journal belongs to")
                .smallCaps(11)
                .frame(maxWidth: .infinity)
            HStack(alignment: density.profileIsHorizontal ? .top : .center, spacing: 18) {
                AvatarEditor()
                    .pastedFace(state.profile?.avatarUrl, border: 5, tilt: -2.5)
                VStack(alignment: .leading, spacing: 4) {
                    Text(state.profile?.displayName ?? " ")
                        .font(.hand(34, bold: true, relativeTo: .largeTitle))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    // The line it's signed on.
                    Rule(weight: 0.5)
                    if let username = state.profile?.username {
                        Text("@\(username)").smallCaps()
                            .padding(.top, 2)
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
        .padding(.horizontal, 20)
        .padding(.vertical, 22)
        .overlay {
            ZStack {
                Rectangle().strokeBorder(DarkRoom.line(0.55), lineWidth: 1.2)
                Rectangle().strokeBorder(DarkRoom.line(0.3), lineWidth: 0.5).padding(4)
            }
            .allowsHitTesting(false)
        }
    }

    var body: some View {
        NavigationStack {
          ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    JournalMasthead(title: "You", line: begun) {
                        Button("Edit") { showEdit = true }
                            .font(.hand(20, bold: true, relativeTo: .body))
                            .frame(minHeight: 44)
                    }
                    .id("masthead")
                    // Sunday evening (build 26): how was the week? Gone at
                    // midnight, and once it's written. Checked each minute,
                    // so it leaves on time with the page open.
                    TimelineView(.everyMinute) { context in
                        if ReflectionWindow.isOpen(context.date), let week = state.thisWeek, week.reflection == nil {
                            ReflectionCard(week: week)
                                .padding(.top, 22)
                        }
                    }
                    bookplate
                        .padding(.top, 26)
                    if let shared = state.profile?.momentsShared, shared > 0 {
                        Text("You've shared \(shared == 1 ? "one moment" : "\(shared) moments"). Only you see this.")
                            .font(.hand(16, relativeTo: .footnote))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 14)
                    }
                    if let circle = state.circle, !others.isEmpty {
                        VStack(alignment: .leading, spacing: 16) {
                            JournalSectionHead(label: "Kept with", title: circle.name)
                            CircleCards(members: others)
                        }
                        .padding(.top, 34)
                    }
                    ForEach(milestones) { milestone in
                        MilestoneCard(milestone: milestone) {
                            Task {
                                await state.dismissMilestone(milestone.id)
                                milestones.removeAll { $0.id == milestone.id }
                            }
                        }
                        .padding(.top, 26)
                    }
                    JournalSectionHead(label: "Only you see this", title: "Held")
                        .padding(.top, 34)
                        .padding(.bottom, 16)
                    if kept.isEmpty {
                        Text("Moments you hold will gather here at full light. Only you see this — nothing here fades.")
                            .font(.hand(18, relativeTo: .callout))
                            .foregroundStyle(.secondary)
                    } else {
                        LazyVGrid(columns: columns, spacing: 22) {
                            ForEach(kept) { memory in
                                HeldTile(memory: memory)
                            }
                        }
                    }
                    // Your reflections, newest week first (build 26).
                    JournalSectionHead(label: "Only you see this", title: "Journal")
                        .padding(.top, 34)
                        .padding(.bottom, 16)
                    if state.reflections.isEmpty {
                        Text("On Sunday evenings, Stanley asks how your week was. What you write is kept here, and it doesn't fade.")
                            .font(.hand(18, relativeTo: .callout))
                            .foregroundStyle(.secondary)
                    } else {
                        LazyVStack(alignment: .leading, spacing: 18) {
                            ForEach(state.reflections) { reflection in
                                ReflectionPage(reflection: reflection)
                            }
                            if state.reflectionsCursor != nil {
                                ProgressView()
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 18)
                                    .task(id: state.reflectionsCursor) { await state.loadMoreReflections() }
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 30)
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
                await state.loadThisWeek()
                await state.loadReflections()
            }
            .journalPage()
            .navigationTitle("You")
            .sheet(isPresented: $showEdit) { EditProfileSheet() }
            .task {
                await state.loadProfile()
                await state.refreshMemories()
                milestones = await state.loadMilestones()
                await state.loadThisWeek()
                await state.loadReflections()
            }
            .refreshable {
                Haptics.refreshed()
                await Task {
                    await state.loadProfile()
                    await state.refreshMemories()
                    milestones = await state.loadMilestones()
                    await state.loadThisWeek()
                    await state.loadReflections()
                }.value
            }
            // The profile and Held are fetched again by `AppState`; the
            // milestones and the journal are this page's to ask for.
            .onChange(of: state.reloads) {
                Task {
                    milestones = await state.loadMilestones()
                    await state.loadThisWeek()
                    await state.loadReflections()
                }
            }
          }
        }
    }
}

/// The circle on the You tab, as a row of small portraits pasted in along
/// the page that scrolls when there are more than fit: each person's face
/// (or their initial) on a scrap of photo paper, a little crooked, their
/// name written beneath, and a quiet mark on whoever started the circle.
/// Each opens that person's profile, their name and their words. People,
/// never a number: the row has no "+7", and nothing says how many there are.
private struct CircleCards: View {
    let members: [CircleMember]
    @ScaledMetric(relativeTo: .caption) private var width: CGFloat = 84

    /// Room for the organizer's mark on every card, so the row lines up,
    /// only when the organizer is in it.
    private var marksOrganizer: Bool { members.contains { $0.isCreator == true } }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 12) {
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
            }
            .padding(.vertical, 4)
        }
        .scrollClipDisabled()
    }

    private func card(_ member: CircleMember) -> some View {
        VStack(spacing: 9) {
            AvatarView(url: member.avatarUrl, name: member.displayName, size: 56)
                .pastedFace(member.avatarUrl, tilt: PrintTilt.degrees(member.id) * 3)
            Text(member.displayName ?? "New member")
                .font(.hand(16, bold: true, relativeTo: .caption))
                .lineLimit(1)
                .truncationMode(.tail)
            // Who started it, said quietly: a word, not a crown.
            if marksOrganizer {
                Text("organizer")
                    .smallCaps(9)
                    .opacity(member.isCreator == true ? 1 : 0)
            }
        }
        .padding(.top, 6)
        .frame(width: width)
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
                    .font(.hand(22, bold: true, relativeTo: .title3))
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
                    .font(.hand(17, relativeTo: .callout))
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
                            .clipShape(RoundedRectangle(cornerRadius: PrintStock.photoCorner, style: .continuous))
                            .asPrint(border: 3)
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .paperInsert(tilt: 0.6)
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
        return "held · \(taken.formatted(.dateTime.month(.abbreviated).day()))"
    }

    var body: some View {
        VStack(spacing: 7) {
            if memory.isTombstone {
                Color.clear
                    .aspectRatio(PhotoShape.aspect, contentMode: .fit)
                    .overlay {
                        Text("a memory was here")
                            .font(.hand(12, relativeTo: .caption2))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(6)
                    }
                    .asPrint(border: 4, tilt: PrintTilt.degrees(memory.id) * 2)
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
                    .clipShape(RoundedRectangle(cornerRadius: PrintStock.photoCorner, style: .continuous))
                    .asPrint(border: 4, tilt: PrintTilt.degrees(memory.id) * 2)
            }
            if let trace {
                Text(trace)
                    .smallCaps(8)
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
                            .pastedFace(member.avatarUrl, border: 5, tilt: -2)
                        Text(member.displayName ?? "New member")
                            .font(.hand(38, bold: true, relativeTo: .largeTitle))
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                            .padding(.top, 16)
                        if let username = member.username {
                            Text("@\(username)").smallCaps()
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
        .paperPage()
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
        VStack(alignment: .leading, spacing: 6) {
            Rule(weight: 0.5)
            HStack(spacing: 8) {
                if let since = member.memberSince {
                    Text("Member since \(since.formatted(.dateTime.month(.wide).year()))")
                }
                if member.isOrganizer == true {
                    Text("· organizer")
                }
            }
            .smallCaps()
            Rule(weight: 0.5)
        }
    }

    /// Their words, in their hand, or a kind line where they haven't
    /// written any yet.
    @ViewBuilder
    private func words(_ member: MemberProfile) -> some View {
        if let bio = member.bio, !bio.isEmpty {
            Text(bio)
                .font(.hand(19, relativeTo: .body))
                .lineSpacing(1)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            Text("Still writing this part…")
                .font(.hand(19, relativeTo: .body))
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
            .clipShape(RoundedRectangle(cornerRadius: PrintStock.photoCorner, style: .continuous))
            .saturation(1 - 0.85 * fade)
            .opacity(1 - (colorScheme == .dark ? 0.62 : 0.82) * fade)
            .asPrint(border: 4, tilt: PrintTilt.degrees(photo.id) * 2)
    }
}

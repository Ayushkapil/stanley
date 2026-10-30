import SwiftUI

/// Your own profile: a name, your words, and the grid of what you've kept.
/// The grid is a private self-view (A2) — no other member can ever see it.
/// Deliberately absent: follower counts, post counts, numbers of any kind.
struct ProfileView: View {
    @Environment(AppState.self) private var state
    @Environment(\.horizontalSizeClass) private var hSizeClass
    private var density: Density { Density(hSizeClass) }
    @State private var showEdit = false
    @State private var milestones: [Milestone] = []

    private var kept: [Memory] {
        state.threads.flatMap(\.memories)
    }

    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 3), count: density.keptColumns)
    }

    @ViewBuilder
    private var bioView: some View {
        if let bio = state.profile?.bio, !bio.isEmpty {
            Text(bio)
                .font(.callout)
                .padding(.top, 2)
        } else {
            Button("Write a little about yourself") { showEdit = true }
                .font(.callout)
                .foregroundStyle(.secondary)
                .buttonStyle(.plain)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: density.profileIsHorizontal ? .top : .center, spacing: 16) {
                        AvatarEditor()
                        VStack(alignment: .leading, spacing: 2) {
                            Text(state.profile?.displayName ?? " ")
                                .font(.keepsake(30))
                            if let username = state.profile?.username {
                                Text("@\(username)")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            // Inner display: the words flow beside the face
                            // instead of stacking under it.
                            if density.profileIsHorizontal {
                                bioView.padding(.top, 8)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    if !density.profileIsHorizontal {
                        bioView
                    }
                    if let members = state.circle?.members, !members.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Your circle")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.secondary)
                            AvatarCluster(members: members, maxFaces: density.circleFacesShown)
                        }
                        .padding(.top, 6)
                    }
                    ForEach(milestones) { milestone in
                        MilestoneCard(milestone: milestone) {
                            Task {
                                await state.dismissMilestone(milestone.id)
                                milestones.removeAll { $0.id == milestone.id }
                            }
                        }
                    }
                    Divider()
                        .padding(.vertical, 8)
                    Text("Held")
                        .font(.keepsake(24))
                    if kept.isEmpty {
                        Text("Moments you hold will gather here at full light. Only you see this — nothing here fades.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    } else {
                        LazyVGrid(columns: columns, spacing: 3) {
                            ForEach(kept) { memory in
                                HeldTile(memory: memory)
                            }
                        }
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .foldAnimated(hSizeClass)
            }
            .atmosphereWash()
            .navigationTitle("You")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Edit") { showEdit = true }
                }
            }
            .sheet(isPresented: $showEdit) { EditProfileSheet() }
            .task {
                await state.loadProfile()
                await state.refreshMemories()
                milestones = await state.loadMilestones()
            }
            .refreshable {
                await state.loadProfile()
                await state.refreshMemories()
                milestones = await state.loadMilestones()
            }
        }
    }
}

/// A milestone card (Part 4): a journal noticing its own age. Private, gentle,
/// dismissable. No progress bars, no scores, no unlock language.
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
                    .font(.keepsake(20))
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
            if let body = milestone.body, !body.isEmpty {
                Text(body).font(.callout).foregroundStyle(.secondary)
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
                                    AsyncImage(url: url) { image in
                                        image.resizable().scaledToFill()
                                    } placeholder: {
                                        Rectangle().fill(.quaternary)
                                    }
                                }
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}

/// A Held tile (Part 6): full saturation — Held is the one place nothing fades
/// — with a faint "held · date" trace. Reads well at three tiles or thirty.
struct HeldTile: View {
    @Environment(AppState.self) private var state
    let memory: Memory

    private var trace: String? {
        guard let taken = memory.takenAt else { return nil }
        return "held · \(taken.formatted(.dateTime.month(.abbreviated).day()))"
    }

    var body: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if memory.isTombstone {
                    ZStack {
                        Rectangle().fill(.quinary)
                        Image(systemName: "leaf")
                            .foregroundStyle(.secondary)
                    }
                } else if let urls = memory.urls, let url = state.api.absoluteURL(urls.thumb) {
                    AsyncImage(url: url) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        Rectangle().fill(.quaternary)
                    }
                }
            }
            .overlay(alignment: .bottomLeading) {
                if let trace {
                    Text(trace)
                        .font(.caption2)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(.black.opacity(0.28), in: Capsule())
                        .padding(5)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
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
        NavigationStack {
            Form {
                Group {
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

    var body: some View {
        Group {
            if let member {
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        AvatarView(url: member.avatarUrl, name: member.displayName, size: 72)
                            .padding(.bottom, 4)
                        Text(member.displayName ?? "New member")
                            .font(.keepsake(28))
                        if let username = member.username {
                            Text("@\(username)")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        if let bio = member.bio, !bio.isEmpty {
                            Text(bio)
                                .font(.callout)
                                .padding(.top, 10)
                        } else {
                            Text("No bio yet.")
                                .font(.callout)
                                .foregroundStyle(.tertiary)
                                .padding(.top, 10)
                        }
                    }
                    .padding(24)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task {
            do {
                member = try await state.loadMember(memberId)
            } catch {
                state.surface(error)
            }
        }
    }
}

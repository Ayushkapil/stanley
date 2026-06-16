import SwiftUI

/// Your own profile: a name, your words, and the grid of what you've kept.
/// The grid is a private self-view (A2) — no other member can ever see it.
/// Deliberately absent: follower counts, post counts, numbers of any kind.
struct ProfileView: View {
    @Environment(AppState.self) private var state
    @State private var showEdit = false

    private var kept: [Memory] {
        state.threads.flatMap(\.memories)
    }

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 3), count: 3)

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .center, spacing: 16) {
                        AvatarEditor()
                        VStack(alignment: .leading, spacing: 2) {
                            Text(state.profile?.displayName ?? " ")
                                .font(.keepsake(30))
                            if let username = state.profile?.username {
                                Text("@\(username)")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
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
                    if let members = state.circle?.members, !members.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Your circle")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.secondary)
                            AvatarCluster(members: members)
                        }
                        .padding(.top, 6)
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
            }
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
            }
            .refreshable {
                await state.loadProfile()
                await state.refreshMemories()
            }
        }
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

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("Display name", text: $name)
                }
                Section("Username") {
                    TextField("username", text: $username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
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
                    .disabled(saving || name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                name = state.profile?.displayName ?? ""
                username = state.profile?.username ?? ""
                bio = state.profile?.bio ?? ""
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
                        Text(member.displayName ?? "departed")
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

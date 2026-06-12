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
                    VStack(alignment: .leading, spacing: 4) {
                        Text(state.profile?.displayName ?? " ")
                            .font(.title2.weight(.medium))
                        if let username = state.profile?.username {
                            Text("@\(username)")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
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
                    Divider()
                        .padding(.vertical, 8)
                    Text("Kept")
                        .font(.headline)
                    if kept.isEmpty {
                        Text("Moments you anchor will gather here. Only you see this.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    } else {
                        LazyVGrid(columns: columns, spacing: 3) {
                            ForEach(kept) { memory in
                                KeptTile(memory: memory)
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

struct KeptTile: View {
    @Environment(AppState.self) private var state
    let memory: Memory

    var body: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if memory.tombstone {
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
            .clipped()
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
                        Text(member.displayName ?? "departed")
                            .font(.title2.weight(.medium))
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

import SwiftUI

/// Setting up a new account, one thing to a screen: a name, a username, a few
/// words, a face. Then the circle gate.
///
/// Shown after the first sign-in on a new account, and to anyone Stanley has
/// no name for (Apple gives a name only on the first authorization, and only
/// if the person shares it; build 13 gave such people a name screen of its
/// own). Only the name is required: a circle of unnamed faces is the one
/// thing this exists to prevent. Every other step has Skip, and all of it can
/// be changed later in You → Edit. Each step saves as it goes, and every
/// field starts from what the profile already holds, so a setup left halfway
/// loses nothing and Continue walks straight through what's done.
struct SetupView: View {
    enum Step: Int, CaseIterable {
        case name, username, bio, photo
    }

    @Environment(AppState.self) private var state
    @Environment(\.horizontalSizeClass) private var hSizeClass
    private var density: Density { Density(hSizeClass) }
    @AppStorage("stanley.atmosphere") private var raw = "auto"

    @State private var step: Step = .name
    @State private var name = ""
    @State private var username = ""
    @State private var bio = ""
    @State private var status: Username.Status = .idle
    @State private var saving = false
    @State private var filled = false
    @FocusState private var typing: Bool

    private var trimmedName: String { name.trimmingCharacters(in: .whitespaces) }
    private var trimmedUsername: String { username.trimmingCharacters(in: .whitespaces).lowercased() }
    private var trimmedBio: String { bio.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                Dots(step: step)
                    .padding(.bottom, 28)
                Group {
                    Text(title)
                        .font(.keepsake(34))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(subtitle)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 10)
                    field
                        .padding(.top, 32)
                }
                .id(step)
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .offset(x: 24)),
                    removal: .opacity
                ))
                Spacer(minLength: 24)
                WideButton(title: "Continue", busy: saving, action: proceed)
                    .disabled(!canContinue)
                Button("Skip") { advance() }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .opacity(step == .name ? 0 : 1)
                    .disabled(step == .name || saving)
                    .accessibilityHidden(step == .name)
            }
            .padding(.horizontal, 24)
            .padding(.top, 8)
            .padding(.bottom, 8)
            .readableWidth(density)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .atmosphereWash()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if step == .name {
                        // The way back to Welcome: Settings is past setup.
                        Button("Sign out") { state.signOut() }
                            .disabled(saving)
                    } else {
                        Button {
                            go(to: Step(rawValue: step.rawValue - 1) ?? .name)
                        } label: {
                            Label("Back", systemImage: "chevron.left")
                        }
                        .disabled(saving)
                    }
                }
            }
            .task {
                if state.profile == nil { await state.loadProfile() }
                fill()
            }
            .task(id: step) { await focusStep() }
            // Same debounce as the edit sheet: retyping cancels the check
            // before it, then we wait a beat before asking the server.
            .task(id: username) { await check() }
        }
    }

    private var title: String {
        switch step {
        case .name: return "What should we call you?"
        case .username: return "Pick a username"
        case .bio: return "Write a little about yourself"
        case .photo: return "Add a photo of yourself"
        }
    }

    private var subtitle: String {
        switch step {
        case .name: return "However you'd introduce yourself. Your circle sees it on your photos."
        case .username: return "It sits under your name on your profile. You can leave it for later."
        case .bio: return "A line or two, as you'd say it. Your circle sees your name and these words, never what you keep."
        case .photo: return "So your circle knows it's you. A face, not a logo."
        }
    }

    @ViewBuilder
    private var field: some View {
        switch step {
        case .name:
            TextField("Your name", text: $name)
                .font(.title3)
                .textInputAutocapitalization(.words)
                .textContentType(.name)
                .submitLabel(.continue)
                .onSubmit(proceed)
                .focused($typing)
                .padding(16)
                .cardSurface(corner: 14)
        case .username:
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 2) {
                    Text("@").foregroundStyle(.secondary)
                    TextField("username", text: $username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .textContentType(.username)
                        .submitLabel(.continue)
                        .onSubmit(proceed)
                        .focused($typing)
                }
                .font(.title3)
                .padding(16)
                .cardSurface(corner: 14)
                Username.footer(for: status)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
            }
        case .bio:
            TextEditor(text: $bio)
                .scrollContentBackground(.hidden)
                .focused($typing)
                .frame(minHeight: 140, maxHeight: 220)
                .padding(10)
                .overlay(alignment: .topLeading) {
                    if bio.isEmpty {
                        Text("I live on the third floor and…")
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 15)
                            .padding(.vertical, 18)
                            .allowsHitTesting(false)
                    }
                }
                .cardSurface(corner: 14)
        case .photo:
            photo
        }
    }

    private var photo: some View {
        let profile = state.profile
        let uploading = state.avatarUploading
        let hasPhoto = profile?.avatarUrl != nil
        return VStack(spacing: 18) {
            AvatarChooser {
                AvatarView(url: profile?.avatarUrl, name: profile?.displayName, size: 132)
                    .overlay {
                        if uploading { ProgressView() }
                    }
            }
            AvatarChooser {
                Label(hasPhoto ? "Choose another" : "Choose a photo", systemImage: "photo.on.rectangle")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Atmosphere.resolve(raw).palette.accent)
                    .frame(minHeight: 44)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
    }

    private var canContinue: Bool {
        guard !saving else { return false }
        switch step {
        case .name: return !trimmedName.isEmpty
        case .username: return !trimmedUsername.isEmpty && status != .invalid && status != .taken
        case .bio: return !trimmedBio.isEmpty
        case .photo: return state.profile?.avatarUrl != nil && !state.avatarUploading
        }
    }

    /// Save this step's answer, then move on. A refusal (a username taken
    /// since it was checked) stays on the step, with the server's reason.
    private func proceed() {
        guard canContinue else { return }
        let fields: [String: Any?]
        switch step {
        case .name:
            guard trimmedName != state.profile?.displayName else { return advance() }
            fields = ["display_name": trimmedName]
        case .username:
            guard trimmedUsername != state.profile?.username else { return advance() }
            fields = ["username": trimmedUsername]
        case .bio:
            guard trimmedBio != state.profile?.bio else { return advance() }
            fields = ["bio": trimmedBio]
        case .photo:
            return advance()
        }
        saving = true
        Task {
            let saved = await state.patchProfile(fields)
            saving = false
            if saved {
                advance()
            } else if step == .username {
                status = .idle
            }
        }
    }

    private func advance() {
        if let next = Step(rawValue: step.rawValue + 1) {
            go(to: next)
        } else {
            typing = false
            state.finishSetup()
        }
    }

    private func go(to next: Step) {
        withAnimation(.easeInOut(duration: 0.25)) { step = next }
    }

    /// The keyboard comes up for each field and goes down for the photo.
    /// Focus waits for the step's field to have arrived: set in the same
    /// update as the step, it went to a field that didn't exist yet.
    private func focusStep() async {
        guard step != .photo else {
            typing = false
            return
        }
        try? await Task.sleep(nanoseconds: 350_000_000)
        guard !Task.isCancelled else { return }
        typing = true
    }

    /// Every field starts from what the profile holds: the name Apple gave,
    /// or whatever an earlier, unfinished setup saved.
    private func fill() {
        guard !filled, let profile = state.profile else { return }
        filled = true
        name = profile.displayName ?? ""
        username = profile.username ?? ""
        bio = profile.bio ?? ""
    }

    private func check() async {
        let candidate = trimmedUsername
        guard !candidate.isEmpty, candidate != state.profile?.username else {
            status = candidate.isEmpty ? .idle : .available
            return
        }
        guard Username.isLocallyValid(candidate) else {
            status = .invalid
            return
        }
        status = .checking
        try? await Task.sleep(nanoseconds: 400_000_000)
        guard !Task.isCancelled else { return }
        guard let result = await state.checkUsername(candidate) else {
            status = .idle  // unknown isn't blocked; the server checks again on save
            return
        }
        status = result.available ? .available : (result.valid ? .taken : .invalid)
    }
}

/// Where setup is: four small marks, the ones done and the one here filled.
/// A sense of place, not a score.
private struct Dots: View {
    @AppStorage("stanley.atmosphere") private var raw = "auto"
    let step: SetupView.Step

    var body: some View {
        // The palette's accent, said outright: `Color.accentColor` came out
        // the system's blue from the second step on (seen on iOS 26.5,
        // build 44), though the first step had the tint.
        let accent = Atmosphere.resolve(raw).palette.accent
        HStack(spacing: 6) {
            ForEach(SetupView.Step.allCases, id: \.self) { each in
                Capsule()
                    .fill(each.rawValue <= step.rawValue ? accent : Color.secondary.opacity(0.3))
                    .frame(width: each == step ? 22 : 8, height: 8)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: step)
        .accessibilityElement()
        .accessibilityLabel("Step \(step.rawValue + 1) of \(SetupView.Step.allCases.count)")
    }
}

import SwiftUI

/// "What should we call you?" — shown once, between sign-in and the circle gate.
///
/// Apple hands over a name only on the very first authorization, and only if
/// the person agrees to share it. Decline, and Stanley genuinely does not know
/// what to call them: their own photos went out labelled with the placeholder
/// for a deleted account. So ask, plainly, before they meet anyone.
///
/// Required: a name. Optional: a username, under the same rules the edit sheet
/// and the server both use. No skip — a circle of unnamed faces is the one
/// thing this screen exists to prevent — but a name can be anything, and it
/// can be changed later in You → Edit.
struct NameGateView: View {
    @Environment(AppState.self) private var state
    @Environment(\.horizontalSizeClass) private var hSizeClass
    private var density: Density { Density(hSizeClass) }

    @State private var name = ""
    @State private var username = ""
    @State private var saving = false
    @State private var status: Username.Status = .idle

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespaces)
    }

    private var trimmedUsername: String {
        username.trimmingCharacters(in: .whitespaces).lowercased()
    }

    private var canContinue: Bool {
        !saving && !trimmedName.isEmpty && status != .invalid && status != .taken
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Your name", text: $name)
                        .textInputAutocapitalization(.words)
                } header: {
                    Text("Name")
                } footer: {
                    Text("However you'd introduce yourself. Your circle sees this on your photos.")
                }
                Section {
                    TextField("username", text: $username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("Username (optional)")
                } footer: {
                    Username.footer(for: status)
                }
                Section {
                    Button(action: save) {
                        if saving {
                            ProgressView()
                        } else {
                            Text("Continue")
                        }
                    }
                    .disabled(!canContinue)
                }
            }
            .readableWidth(density)
            .foldAnimated(hSizeClass)
            .navigationTitle("What should we call you?")
            .navigationBarTitleDisplayMode(.inline)
            // Same debounce as the edit sheet: retyping cancels the previous
            // check, then we wait a beat before asking the server.
            .task(id: username) {
                let candidate = trimmedUsername
                guard !candidate.isEmpty else {
                    status = .idle
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
                    status = .idle  // unknown ≠ blocked; the server re-checks on save
                    return
                }
                status = result.available ? .available : (result.valid ? .taken : .invalid)
            }
        }
    }

    private func save() {
        saving = true
        Task {
            // Carry the existing bio through rather than blanking it — this
            // screen is about a name, and should not quietly erase anything.
            let saved = await state.updateProfile(
                displayName: trimmedName,
                username: trimmedUsername,
                bio: state.profile?.bio ?? ""
            )
            saving = false
            // On success `profile` is refreshed, `needsName` goes false, and
            // RootView falls through to the circle gate on its own.
            if !saved { status = .idle }
        }
    }
}

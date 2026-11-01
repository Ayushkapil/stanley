import SwiftUI

/// Circle-first onboarding (§4): a circle is created and joined as a group
/// act, and the feed is alive from the first session. There is no
/// account-first path into an empty feed.
///
/// The same screen joins another circle once you're in one (build 17), as a
/// sheet from the switcher atop Today or from Settings. A person can be in up
/// to five, each with its own photo a day; whichever is joined or started
/// here comes up on Today straight after.
struct CircleGateView: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var hSizeClass
    private var density: Density { Density(hSizeClass) }
    /// Joining another circle, from inside the app, rather than the first.
    var another = false
    @State private var circleName = ""
    @State private var inviteCode = ""
    @State private var working = false

    var body: some View {
        NavigationStack {
            Form {
                Group {
                    Section(another ? "Join with a code" : "Join your circle") {
                        TextField("e.g. NECR-7KX4", text: $inviteCode)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.characters)
                        Button("Join") {
                            run { await state.joinCircle(code: inviteCode.trimmingCharacters(in: .whitespaces)) }
                        }
                        .disabled(inviteCode.trimmingCharacters(in: .whitespaces).isEmpty || working)
                    }
                    Section {
                        TextField("A name for it — your floor, your house", text: $circleName)
                        Button("Create") {
                            run { await state.createCircle(name: circleName.trimmingCharacters(in: .whitespaces)) }
                        }
                        .disabled(circleName.trimmingCharacters(in: .whitespaces).isEmpty || working)
                    } header: {
                        Text("Or start one")
                    } footer: {
                        Text(another
                            ? "Stanley works best with people you actually know. Each circle keeps its own day: one photo a day in each, up to five circles."
                            : "Stanley works best with people you actually know.")
                    }
                }
                .atmosphereRows()
            }
            .atmosphereWash()
            .readableWidth(density)
            .foldAnimated(hSizeClass)
            .navigationTitle(another ? "Join another circle" : "Your circle")
            .navigationBarTitleDisplayMode(another ? .inline : .automatic)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if another {
                        Button("Cancel") { dismiss() }
                    } else {
                        // The way back to Welcome: the wrong Apple ID, a
                        // different person on this phone, or just not now.
                        // Settings, where Sign out usually lives, is past this
                        // gate. Nothing is lost by leaving, so there's no
                        // confirmation, the same as Settings.
                        Button("Sign out") { state.signOut() }
                    }
                }
            }
        }
    }

    /// Join or create, then, joining another, close: the new circle is
    /// already on Today underneath.
    private func run(_ action: @escaping () async -> Bool) {
        working = true
        Task {
            let done = await action()
            working = false
            if done && another { dismiss() }
        }
    }
}

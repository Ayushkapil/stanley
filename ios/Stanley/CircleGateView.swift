import SwiftUI

/// Circle-first onboarding (§4): a circle is created and joined as a group
/// act, and the feed is alive from the first session. There is no
/// account-first path into an empty feed.
struct CircleGateView: View {
    @Environment(AppState.self) private var state
    @Environment(\.horizontalSizeClass) private var hSizeClass
    private var density: Density { Density(hSizeClass) }
    @State private var circleName = ""
    @State private var inviteCode = ""

    var body: some View {
        NavigationStack {
            Form {
                Group {
                    Section("Join your circle") {
                        TextField("e.g. NECR-7KX4", text: $inviteCode)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.characters)
                        Button("Join") {
                            Task { await state.joinCircle(code: inviteCode.trimmingCharacters(in: .whitespaces)) }
                        }
                        .disabled(inviteCode.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    Section {
                        TextField("A name for it — your floor, your house", text: $circleName)
                        Button("Create") {
                            Task { await state.createCircle(name: circleName.trimmingCharacters(in: .whitespaces)) }
                        }
                        .disabled(circleName.trimmingCharacters(in: .whitespaces).isEmpty)
                    } header: {
                        Text("Or start one")
                    } footer: {
                        Text("Stanley works best with people you actually know. One circle per person.")
                    }
                }
                .atmosphereRows()
            }
            .atmosphereWash()
            .readableWidth(density)
            .foldAnimated(hSizeClass)
            .navigationTitle("Your circle")
            .toolbar {
                // The way back to Welcome: the wrong Apple ID, a different
                // person on this phone, or just not now. Settings, where
                // Sign out usually lives, is past this gate. Nothing is lost
                // by leaving, so there's no confirmation, the same as Settings.
                ToolbarItem(placement: .cancellationAction) {
                    Button("Sign out") { state.signOut() }
                }
            }
        }
    }
}

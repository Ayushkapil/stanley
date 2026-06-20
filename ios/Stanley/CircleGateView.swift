import SwiftUI

/// Circle-first onboarding (§4): a circle is created and joined as a group
/// act, and the feed is alive from the first session. There is no
/// account-first path into an empty feed.
struct CircleGateView: View {
    @Environment(AppState.self) private var state
    @State private var circleName = ""
    @State private var inviteCode = ""

    var body: some View {
        NavigationStack {
            Form {
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
                    TextField("Circle name", text: $circleName)
                    Button("Create") {
                        Task { await state.createCircle(name: circleName.trimmingCharacters(in: .whitespaces)) }
                    }
                    .disabled(circleName.trimmingCharacters(in: .whitespaces).isEmpty)
                } header: {
                    Text("Or start one")
                } footer: {
                    Text("A circle holds at most thirty people. One circle per person.")
                }
            }
            .navigationTitle("Your circle")
        }
    }
}

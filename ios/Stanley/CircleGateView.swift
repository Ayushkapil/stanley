import SwiftUI

/// Circle-first onboarding (§4): a circle is created and joined as a group
/// act, and the feed is alive from the first session. There is no
/// account-first path into an empty feed.
///
/// The same screen joins another circle once you're in one (build 17), as a
/// sheet from the switcher atop Today or from Settings. A person can be in up
/// to five, each with its own photo a day; whichever is joined or started
/// here comes up on Today straight after.
///
/// Since build 31 it's the journal's first page rather than a system form
/// (the QA audit found it the one plain gray screen a new person meets):
/// a masthead, then two slips taped into the page, one to join with a code
/// and one to start a circle, each with its line written on by hand.
struct CircleGateView: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var hSizeClass
    private var density: Density { Density(hSizeClass) }
    /// Joining another circle, from inside the app, rather than the first.
    var another = false
    @State private var circleName = ""
    @State private var inviteCode = ""
    /// Which of the two is on its way to the server.
    @State private var running: Field?
    private var working: Bool { running != nil }
    @FocusState private var field: Field?

    private enum Field { case code, name }

    private var code: String { inviteCode.trimmingCharacters(in: .whitespaces) }
    private var name: String { circleName.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    JournalMasthead(
                        title: another ? "Another circle" : "Your circle",
                        line: another ? "Each one keeps its own day" : "Who this journal is kept with"
                    )
                    .padding(.bottom, Spacing.section)
                    Text(another
                        ? "One photo a day in each, up to five circles."
                        : "Stanley is kept with a few people you actually know: a floor, a house, a team.")
                        .font(.hand(20, relativeTo: .body))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.bottom, Spacing.chapter)

                    GateSlip(
                        label: "Have an invite code?",
                        title: another ? "Join with a code" : "Join your circle",
                        tilt: -0.7
                    ) {
                        TextField("", text: $inviteCode, prompt: Text("NECR-7KX4").foregroundColor(.secondary.opacity(0.6)))
                            .font(.hand(26, bold: true, relativeTo: .title2))
                            .tracking(2)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.characters)
                            .submitLabel(.join)
                            .focused($field, equals: .code)
                            .onSubmit(join)
                            .accessibilityLabel("Invite code")
                        Rule(weight: 0.5)
                        Text("Anyone in the circle can find it in Settings.")
                            .smallCaps()
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 2)
                        WideButton(title: "Join", busy: running == .code, action: join)
                            .disabled(code.isEmpty || working)
                            .padding(.top, Spacing.section)
                    }

                    // Between the two slips, the way a page says "or".
                    HStack(spacing: 12) {
                        Rule(weight: 0.5)
                        Text("or").font(.hand(18, relativeTo: .body)).foregroundStyle(.secondary)
                        Rule(weight: 0.5)
                    }
                    .padding(.vertical, Spacing.chapter)
                    .accessibilityHidden(true)

                    GateSlip(label: "No code yet?", title: "Start a circle", tilt: 0.6) {
                        TextField("", text: $circleName, prompt: Text("Your floor, your house…").foregroundColor(.secondary.opacity(0.6)))
                            .font(.hand(24, relativeTo: .title3))
                            .submitLabel(.done)
                            .focused($field, equals: .name)
                            .onSubmit(create)
                            .accessibilityLabel("A name for the circle")
                        Rule(weight: 0.5)
                        Text("You'll get a code to pass around.")
                            .smallCaps()
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 2)
                        WideButton(title: "Start it", busy: running == .name, action: create)
                            .disabled(name.isEmpty || working)
                            .padding(.top, Spacing.section)
                    }

                    Text(another
                        ? "Stanley works best with people you actually know."
                        : "Photos live for six days, then they're gone, unless someone keeps them.")
                        .smallCaps()
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity)
                        .padding(.top, Spacing.chapter)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, Spacing.chapter)
                .readableWidth(density)
            }
            .scrollDismissesKeyboard(.interactively)
            .atmosphereWash()
            .foldAnimated(hSizeClass)
            .navigationBarTitleDisplayMode(.inline)
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

    private func join() {
        guard !code.isEmpty, !working else { return }
        run(.code) { await state.joinCircle(code: code) }
    }

    private func create() {
        guard !name.isEmpty, !working else { return }
        run(.name) { await state.createCircle(name: name) }
    }

    /// Join or create, then, joining another, close: the new circle is
    /// already on Today underneath.
    private func run(_ which: Field, _ action: @escaping () async -> Bool) {
        running = which
        field = nil
        Task {
            let done = await action()
            running = nil
            if done && another { dismiss() }
        }
    }
}

/// One of the gate's two slips: a sheet tucked into the page (`paperInsert`)
/// under a strip of tape, a little off square, its label in small capitals
/// and its title in a hand over whatever it asks for. In the dark room
/// there's no paper to tape, so no tape: the same black, boxed in a rule.
private struct GateSlip<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    let label: String
    let title: String
    let tilt: Double
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label).smallCaps()
            Text(title)
                .font(.hand(28, bold: true, relativeTo: .title))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
                .padding(.bottom, 4)
            content()
        }
        .padding(.horizontal, 22)
        .padding(.top, 26)
        .padding(.bottom, 22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .paperInsert(tilt: tilt)
        .overlay(alignment: .top) {
            if !DarkRoom.isDark(colorScheme) {
                Tape().offset(y: -11)
            }
        }
    }
}

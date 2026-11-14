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
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.bottom, Spacing.chapter)

                    GateSlip(
                        label: "Have an invite code?",
                        title: another ? "Join with a code" : "Join your circle",
                    ) {
                        TextField("", text: $inviteCode, prompt: Text("NECR-7KX4").foregroundColor(.secondary.opacity(0.6)))
                            .font(.system(.title2, design: .monospaced).weight(.medium))
                            .tracking(2)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.characters)
                            .submitLabel(.join)
                            .focused($field, equals: .code)
                            .onSubmit(join)
                            .accessibilityLabel("Invite code")
                        Rule(weight: 0.5)
                        Text("Anyone in the circle can find it in Settings.")
                            .quietLabel()
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 2)
                        WideButton(title: "Join", busy: running == .code, action: join)
                            .disabled(code.isEmpty || working)
                            .padding(.top, Spacing.section)
                    }

                    // Between the two slips, the way a page says "or".
                    HStack(spacing: 12) {
                        Rule(weight: 0.5)
                        Text("or").font(.subheadline).foregroundStyle(.secondary)
                        Rule(weight: 0.5)
                    }
                    .padding(.vertical, Spacing.chapter)
                    .accessibilityHidden(true)

                    GateSlip(label: "No code yet?", title: "Start a circle") {
                        TextField("", text: $circleName, prompt: Text("Your floor, your house…").foregroundColor(.secondary.opacity(0.6)))
                            .font(.title3)
                            .submitLabel(.done)
                            .focused($field, equals: .name)
                            .onSubmit(create)
                            .accessibilityLabel("A name for the circle")
                        Rule(weight: 0.5)
                        Text("You'll get a code to pass around.")
                            .quietLabel()
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 2)
                        WideButton(title: "Start it", busy: running == .name, action: create)
                            .disabled(name.isEmpty || working)
                            .padding(.top, Spacing.section)
                    }

                    Text(another
                        ? "Stanley works best with people you actually know."
                        : "Photos live for six days, then they're gone, unless someone keeps them.")
                        .quietLabel()
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

/// One of the gate's two cards: a quiet label and a title over whatever it
/// asks for. Slips of paper under tape until build 44; joining a circle is
/// a tool, so it's a plain card (and in the dark, nothing but its content).
private struct GateSlip<Content: View>: View {
    let label: String
    let title: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label).quietLabel()
            Text(title)
                .font(.sectionTitle)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
                .padding(.bottom, 4)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(h: 20, v: 20)
    }
}

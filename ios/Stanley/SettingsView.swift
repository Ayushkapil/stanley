import SwiftUI
import UIKit
import UserNotifications

/// Settings, laid out the way iOS lays out its own: five groups, every row in
/// one, and nothing loose. Circle, Appearance, Quiet, Privacy & Security,
/// About. Anything serious (resetting the invite code, deleting the account)
/// is a level down, behind its own page and a confirmation.
struct SettingsView: View {
    @Environment(AppState.self) private var state
    @AppStorage("stanley.appearance") private var appearance = "system"
    @AppStorage("stanley.atmosphere") private var atmosphere = "auto"
    @AppStorage("stanley.appLock") private var appLock = false

    @Environment(\.horizontalSizeClass) private var hSizeClass
    private var density: Density { Density(hSizeClass) }

    @State private var confirmLeave = false
    @State private var joiningAnother = false

    @State private var exporting = false
    @State private var exportURL: URL?
    @State private var showShare = false

    private var isCreator: Bool { state.circle?.isCreator ?? false }
    private var palette: Atmosphere.Palette { Atmosphere.resolve(atmosphere).palette }

    var body: some View {
        NavigationStack {
            Form {
                // The page's masthead, on the paper rather than in a row.
                Section {
                    JournalMasthead(title: "Settings", line: "Stanley, and how it's kept")
                        .padding(.bottom, 4)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 0, leading: 6, bottom: 0, trailing: 6))
                }
                Group {
                    circleSection
                    appearanceSection
                    QuietSection(toggleTint: palette.toggle)
                    privacySection
                    aboutSection
                }
                .atmosphereRows()
            }
            .readableWidth(density)
            .foldAnimated(hSizeClass)
            .journalPage()
            .navigationTitle("Settings")
            .alert("Leave \(state.circle?.name ?? "this circle")?", isPresented: $confirmLeave) {
                Button("Leave", role: .destructive) { Task { await state.leaveCircle() } }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(state.circles.count > 1
                    ? "You'll stop seeing this circle. Your other circles stay as they are, and the memories you've held stay yours."
                    : "You'll stop seeing the circle. The memories you've held stay yours.")
            }
            .sheet(isPresented: $joiningAnother) { CircleGateView(another: true) }
            .sheet(isPresented: $showShare) {
                if let exportURL {
                    ShareSheet(items: [exportURL])
                }
            }
        }
    }

    /// The circle on Today: what it's called, who's in it, how people join,
    /// and the way out. Leave is last and the only red row.
    @ViewBuilder
    private var circleSection: some View {
        if let circle = state.circle {
            Section {
                if isCreator {
                    NavigationLink {
                        CircleNameView(name: circle.name)
                    } label: {
                        LabeledContent("Name", value: circle.name)
                    }
                } else {
                    LabeledContent("Name", value: circle.name)
                }
                NavigationLink {
                    MembersView()
                } label: {
                    HStack(spacing: 10) {
                        Text("Members")
                        Spacer()
                        // Faces as the summary, never a number (A2).
                        FaceCluster(
                            faces: (circle.members ?? []).prefix(4).map {
                                (id: $0.id, url: $0.avatarUrl, name: $0.displayName)
                            },
                            size: 22
                        )
                    }
                }
                // Each week's question and what everyone said (build 26).
                NavigationLink("Circle Journal") {
                    CircleJournalView()
                }
                if let code = state.inviteCode {
                    NavigationLink {
                        InviteCodeView()
                    } label: {
                        LabeledContent("Invite Code") {
                            Text(code).monospaced()
                        }
                    }
                }
                Button("Join Another Circle") { joiningAnother = true }
                    .foregroundStyle(.primary)
                Button("Leave Circle", role: .destructive) { confirmLeave = true }
                    .destructiveInk()
            } header: {
                Text("Circle").smallCaps(11)
            } footer: {
                Text("Stanley works best with people you actually know. Each circle keeps its own day: one photo a day in each.")
            }
        }
    }

    private var appearanceSection: some View {
        Section {
            Picker("Appearance", selection: $appearance) {
                Text("System").tag("system")
                Text("Light").tag("light")
                Text("Dark").tag("dark")
            }
            .pickerStyle(.segmented)
            // A menu, the way iOS picks one of a few: the choice shows in the
            // row, and the six names open from it.
            Picker("Atmosphere", selection: $atmosphere) {
                ForEach(Atmosphere.allCases) { atmosphere in
                    Text(atmosphere.label).tag(atmosphere.rawValue)
                }
            }
            .pickerStyle(.menu)
        } header: {
            Text("Appearance").smallCaps(11)
        } footer: {
            Text("Auto is Stanley's own quiet look: warm white in light mode, black in dark. The others are moods, and Rain is the quiet one. It's only color — nothing about how Stanley works changes.")
        }
    }

    private var privacySection: some View {
        Section {
            Toggle("Require Face ID", isOn: $appLock)
                .tint(palette.toggle)
            Button {
                exporting = true
                Task {
                    if let data = await state.exportMemories() {
                        let url = FileManager.default.temporaryDirectory
                            .appendingPathComponent("stanley-memories.zip")
                        try? data.write(to: url)
                        exportURL = url
                        showShare = true
                    }
                    exporting = false
                }
            } label: {
                HStack {
                    Text("Export My Memories")
                    if exporting {
                        Spacer()
                        ProgressView()
                    }
                }
            }
            .foregroundStyle(.primary)
            .disabled(exporting)
            NavigationLink {
                AccountView()
            } label: {
                Text("About Your Account")
            }
        } header: {
            Text("Privacy & Security").smallCaps(11)
        } footer: {
            Text("With Face ID on, Stanley asks for it each time it opens. The export bundles the photos you've held, with their captions; there's no archive of everything you've ever posted.")
        }
    }

    private var aboutSection: some View {
        Section {
            NavigationLink("About Stanley") { AboutStanleyView() }
            NavigationLink("Terms of Use") {
                LegalDocumentView(title: "Terms of Use", sections: Legal.terms)
            }
            NavigationLink("Privacy Policy") {
                LegalDocumentView(title: "Privacy Policy", sections: Legal.privacy, effective: Legal.privacyEffective)
            }
            NavigationLink("Acknowledgements") { AcknowledgementsView() }
        } header: {
            Text("About").smallCaps(11)
        } footer: {
            Text(Self.versionLine)
                .smallCaps()
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 18)
        }
    }

    static var versionLine: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? ""
        let build = info?["CFBundleVersion"] as? String ?? ""
        return "Stanley \(version) (\(build))"
    }
}

/// The two notices Stanley can send, and the words for why there are so few.
/// Both are off until asked for. Turning one on asks iOS for permission then
/// and there, in the moment it means something, rather than at first launch;
/// if iOS has it switched off, the row says so and opens Settings.
private struct QuietSection: View {
    @Environment(AppState.self) private var state
    @Environment(\.scenePhase) private var scenePhase
    let toggleTint: Color
    @State private var lastLight = false
    @State private var digest = false
    @State private var loaded = false
    @State private var blocked = false

    var body: some View {
        Section {
            Toggle("When My Photo Is Fading", isOn: $lastLight)
                .tint(toggleTint)
                .disabled(!loaded)
                .onChange(of: lastLight) { _, on in save("last_light_notice_enabled", on) { lastLight = $0 } }
            Toggle("When My Circle Has Posted", isOn: $digest)
                .tint(toggleTint)
                .disabled(!loaded)
                .onChange(of: digest) { _, on in save("digest_enabled", on) { digest = $0 } }
            if blocked {
                Button("Allow Notifications in Settings") {
                    if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
            }
        } header: {
            Text("Quiet").smallCaps(11)
        } footer: {
            Text(blocked
                ? "Notifications for Stanley are off in iOS Settings, so these can't reach you yet."
                : "Stanley is quiet on purpose. Two notices exist, both off unless you ask: one when your own photo reaches its last day, and one in the evening when someone in your circle has posted. No streaks, no nudges, nothing about likes or holds, and never a number.")
        }
        .task(id: state.reloads) { await load() }
        .onChange(of: scenePhase) { _, phase in
            // Back from iOS Settings: see whether notifications are allowed now.
            if phase == .active { Task { await checkBlocked() } }
        }
    }

    private func load() async {
        guard !loaded else { return }
        // Offline, the switches can't say what's set: they'd show off for
        // a notice that's on. They wait, dimmed, and load once Stanley
        // answers (`AppState.reloads`). `loaded` turns on only after the
        // await below, so setting them here never reads as the person
        // flipping them.
        var answered = false
        if let me: MeSettings = try? await state.api.send("GET", "/me") {
            lastLight = me.lastLightNoticeEnabled
            digest = me.digestEnabled ?? false
            answered = true
        }
        await checkBlocked()
        if answered { loaded = true }
    }

    private func checkBlocked() async {
        let status = await Push.shared.authorization()
        blocked = status == .denied && (lastLight || digest)
    }

    /// Turning a notice on asks iOS first. If iOS says no, the switch goes
    /// back off: a notice that can't arrive shouldn't look as if it will.
    private func save(_ field: String, _ on: Bool, revert: @escaping (Bool) -> Void) {
        guard loaded else { return }
        Task {
            if on {
                let allowed = await Push.shared.requestPermission()
                if !allowed {
                    revert(false)
                    blocked = true
                    return
                }
            }
            do {
                let _: MeSettings = try await state.api.send("PATCH", "/me/settings", json: [field: on])
                await checkBlocked()
            } catch {
                revert(!on)
                state.surface(error)
            }
        }
    }
}

/// The circle's name, which its organizer can change. Everyone in it sees
/// the new name atop Today.
private struct CircleNameView: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss
    @State var name: String
    @State private var saving = false
    @FocusState private var focused: Bool

    private var trimmed: String { name.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        Form {
            Section {
                TextField("Circle name", text: $name)
                    .focused($focused)
                    .submitLabel(.done)
                    .onSubmit(save)
            } footer: {
                Text("Everyone in the circle sees this name.")
            }
            .atmosphereRows()
        }
        .atmosphereWash()
        .navigationTitle("Name")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save", action: save)
                    .disabled(trimmed.isEmpty || trimmed == state.circle?.name || saving)
            }
        }
        .onAppear { focused = true }
    }

    private func save() {
        guard !trimmed.isEmpty, trimmed != state.circle?.name else { return }
        saving = true
        Task {
            if await state.renameCircle(trimmed) { dismiss() }
            saving = false
        }
    }
}

/// How people join: the code, a way to copy it and a way to send it, and,
/// for the organizer, a way to make it stop working.
private struct InviteCodeView: View {
    @Environment(AppState.self) private var state
    @State private var confirmReset = false

    var body: some View {
        let code = state.inviteCode ?? ""
        let name = state.circle?.name ?? "the circle"
        List {
            Group {
                Section {
                    Text(code)
                        .font(.system(.largeTitle, design: .monospaced).weight(.semibold))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .accessibilityLabel("Invite code \(code.map(String.init).joined(separator: " "))")
                } footer: {
                    Text("Anyone with this code can join \(name).")
                        .frame(maxWidth: .infinity, alignment: .center)
                }
                Section {
                    Button {
                        UIPasteboard.general.string = code
                        state.flash = "Copied"
                    } label: {
                        Label("Copy Code", systemImage: "doc.on.doc")
                    }
                    ShareLink(item: "Join \(name) on Stanley with the code \(code).") {
                        Label("Share Invite", systemImage: "square.and.arrow.up")
                    }
                }
                if state.circle?.isCreator == true {
                    Section {
                        Button("Reset Code", role: .destructive) { confirmReset = true }
                            .destructiveInk()
                    } footer: {
                        Text("A new code replaces this one, and this one stops working.")
                    }
                }
            }
            .atmosphereRows()
        }
        .atmosphereWash()
        .navigationTitle("Invite Code")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Reset the invite code?", isPresented: $confirmReset) {
            Button("Reset Code", role: .destructive) { Task { await state.rotateInvite() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will invalidate the current code. Anyone with the old code won't be able to join.")
        }
    }
}

/// The circle as people: faces, names, and who started it. Deliberately has no
/// activity, no "last active", and no count — A2 extends to the roster, so a
/// full circle looks like more faces, never like a number.
struct MembersView: View {
    @Environment(AppState.self) private var state
    @State private var memberToRemove: CircleMember?

    private var isCreator: Bool { state.circle?.isCreator ?? false }

    var body: some View {
        List {
            ForEach(state.circle?.members ?? []) { member in
                NavigationLink {
                    MemberProfileView(memberId: member.id)
                } label: {
                    HStack(spacing: 12) {
                        AvatarView(url: member.avatarUrl, name: member.displayName, size: 40)
                        Text(member.displayName ?? "New member")
                        if member.isCreator == true {
                            Text("organizer")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 3)
                }
                .swipeActions {
                    if isCreator && member.id != state.myId {
                        Button(role: .destructive) {
                            memberToRemove = member
                        } label: {
                            Label("Remove", systemImage: "person.badge.minus")
                        }
                    }
                }
            }
            .atmosphereRows()
        }
        .atmosphereWash()
        .navigationTitle("Members")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            "Remove \(memberToRemove?.displayName ?? "this member")?",
            isPresented: Binding(
                get: { memberToRemove != nil },
                set: { if !$0 { memberToRemove = nil } }
            ),
            presenting: memberToRemove
        ) { member in
            Button("Remove", role: .destructive) {
                Task { await state.removeMember(member.id) }
            }
            Button("Cancel", role: .cancel) {}
        }
    }
}

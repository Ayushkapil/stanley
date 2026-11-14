import SwiftUI
import UIKit
import UserNotifications

/// Settings, laid out the way iOS lays out its own: five groups, every row in
/// one, and nothing loose. Circle, Appearance, Quiet, Privacy & Security,
/// About. Anything serious (resetting the invite code, deleting the account)
/// is a level down, behind its own page and a confirmation.
struct SettingsView: View {
    @Environment(AppState.self) private var state
    @Environment(\.colorScheme) private var colorScheme
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
                // Plain iOS Settings (build 44): the system's own large
                // title and grouped rows, in Stanley's accent. No masthead,
                // no paper.
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
            .atmosphereWash()
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
            .alert("Leave \(state.circle?.name ?? "this circle")?", isPresented: $confirmLeave) {
                Button("Leave", role: .destructive) { Task { await state.leaveCircle() } }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(state.circles.count > 1
                    ? "You'll stop seeing this circle. Your other circles stay as they are, and the memories you've held stay yours."
                    : "You'll stop seeing the circle. The memories you've held stay yours.")
            }
            .sheet(isPresented: $joiningAnother) { CircleGateView(another: true) }
            .task { await state.loadCircle() }
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
                // Which circle this page is about, once there's more than one
                // (the same choice as the circle's name atop Today).
                if state.circles.count > 1 {
                    Picker("Circle", selection: Binding(
                        get: { state.circle?.id ?? "" },
                        set: { id in Task { await state.switchCircle(to: id) } }
                    )) {
                        ForEach(state.circles) { Text($0.name).tag($0.id) }
                    }
                    .pickerStyle(.menu)
                }
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

    /// What's chosen among Light, Dark and Rain; nil is matching the phone.
    private var look: Binding<Look?> {
        Binding(
            get: { Look.current(appearance: appearance, atmosphere: atmosphere) },
            set: { chosen in
                let stored = Look.stored(chosen)
                appearance = stored.appearance
                atmosphere = stored.atmosphere
            }
        )
    }

    /// Three looks in one segmented control (build 44; an appearance
    /// control and a menu of six atmospheres before). With none chosen
    /// Stanley is light or dark as the phone is, which is where it starts.
    private var appearanceSection: some View {
        Section {
            Picker("Appearance", selection: look) {
                ForEach(Look.allCases) { each in
                    Text(each.label).tag(Optional(each))
                }
            }
            .pickerStyle(.segmented)
            Toggle("Match iPhone", isOn: Binding(
                get: { look.wrappedValue == nil },
                set: { matching in
                    // Off keeps what's showing: the phone's own, held.
                    look.wrappedValue = matching ? nil : (colorScheme == .dark ? .dark : .light)
                }
            ))
            .tint(palette.toggle)
        } header: {
            Text("Appearance").smallCaps(11)
        } footer: {
            Text("Light is warm white. Dark is true black, a gallery for the photos. Rain is fog on a window, in light or dark as your iPhone is. It's only color: nothing about how Stanley works changes.")
        }
    }


    private var privacySection: some View {
        Section {
            // Named for the phone's own biometric. A phone without one has
            // no row, unless the lock is already on, so it can be turned off.
            if Biometrics.kind != .none || appLock {
                Toggle(isOn: $appLock) {
                    Label("Require \(Biometrics.kind.name)", systemImage: Biometrics.kind.symbol)
                }
                .tint(palette.toggle)
            }
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
            Text(lockFooter + "The export bundles the photos you've held, with their captions; there's no archive of everything you've ever posted.")
        }
    }

    /// What the lock does, named for the phone's own biometric.
    private var lockFooter: String {
        Biometrics.kind == .none && !appLock
            ? ""
            : "With \(Biometrics.kind.name) on, Stanley asks for it each time it opens. "
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
                .font(.footnote)
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

/// The three notices Stanley can send, and the words for why there are so
/// few. All are off until asked for. Turning one on asks iOS for permission
/// then and there, in the moment it means something, rather than at first
/// launch; if iOS has it switched off, the row says so and opens Settings.
/// Each says in a line what it is, since the evening note and Circle Posts
/// (build 37, "{name} shared a moment" each time) are both about the circle
/// posting.
private struct QuietSection: View {
    @Environment(AppState.self) private var state
    @Environment(\.scenePhase) private var scenePhase
    let toggleTint: Color
    @State private var lastLight = false
    @State private var digest = false
    @State private var circlePosts = false
    /// Whether the server knows Circle Posts. One from before build 37
    /// doesn't, and a switch it can't keep would look on and do nothing.
    @State private var offersCirclePosts = false
    /// The two reminders a person sets for themselves (build 39), each at
    /// one of four times of day. Shown only when the server knows them.
    @State private var noteReminder = false
    @State private var noteHour = 9
    @State private var photoReminder = false
    @State private var photoHour = 18
    @State private var offersReminders = false
    @State private var loaded = false
    @State private var blocked = false

    var body: some View {
        Section {
            Toggle(isOn: $lastLight) {
                QuietRow(title: "When My Photo Is Fading", detail: "Once, on your photo's last day")
            }
                .tint(toggleTint)
                .disabled(!loaded)
                .onChange(of: lastLight) { _, on in save("last_light_notice_enabled", on) { lastLight = $0 } }
            Toggle(isOn: $digest) {
                QuietRow(title: "When My Circle Has Posted", detail: "One note in the evening, if anyone posted that day")
            }
                .tint(toggleTint)
                .disabled(!loaded)
                .onChange(of: digest) { _, on in save("digest_enabled", on) { digest = $0 } }
            if offersCirclePosts {
                Toggle(isOn: $circlePosts) {
                    QuietRow(title: "Circle Posts", detail: "Get notified when someone in your circle shares a moment")
                }
                    .tint(toggleTint)
                    .disabled(!loaded)
                    .onChange(of: circlePosts) { _, on in save("circle_posts_enabled", on) { circlePosts = $0 } }
            }
            if offersReminders {
                Toggle(isOn: $noteReminder) {
                    QuietRow(title: "Daily Note Reminder", detail: "Once a day, if you haven't left a note yet")
                }
                    .tint(toggleTint)
                    .disabled(!loaded)
                    .onChange(of: noteReminder) { _, on in save("note_reminder_enabled", on) { noteReminder = $0 } }
                if noteReminder {
                    ReminderTime(hour: $noteHour)
                        .disabled(!loaded)
                        .onChange(of: noteHour) { old, hour in saveHour("note_reminder_hour", hour) { noteHour = old } }
                }
                Toggle(isOn: $photoReminder) {
                    QuietRow(title: "Daily Photo Reminder", detail: "Once a day, if you haven't shared today's photo yet")
                }
                    .tint(toggleTint)
                    .disabled(!loaded)
                    .onChange(of: photoReminder) { _, on in save("photo_reminder_enabled", on) { photoReminder = $0 } }
                if photoReminder {
                    ReminderTime(hour: $photoHour)
                        .disabled(!loaded)
                        .onChange(of: photoHour) { old, hour in saveHour("photo_reminder_hour", hour) { photoHour = old } }
                }
            }
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
                : offersReminders
                    ? "Stanley is quiet on purpose. Five notices exist, all off unless you ask: one when your own photo reaches its last day, one in the evening when someone in your circle has posted, one each time someone in your circle shares a moment, and two reminders you can set for yourself. No streaks, nothing about likes or holds, and never a number."
                    : "Stanley is quiet on purpose. Three notices exist, all off unless you ask: one when your own photo reaches its last day, one in the evening when someone in your circle has posted, and one each time someone in your circle shares a moment. No streaks, no nudges, nothing about likes or holds, and never a number.")
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
            circlePosts = me.circlePostsEnabled ?? false
            offersCirclePosts = me.circlePostsEnabled != nil
            noteReminder = me.noteReminderEnabled ?? false
            noteHour = me.noteReminderHour ?? 9
            photoReminder = me.photoReminderEnabled ?? false
            photoHour = me.photoReminderHour ?? 18
            offersReminders = me.noteReminderEnabled != nil
            answered = true
        }
        await checkBlocked()
        if answered { loaded = true }
    }

    private func checkBlocked() async {
        let status = await Push.shared.authorization()
        blocked = status == .denied && (lastLight || digest || circlePosts || noteReminder || photoReminder)
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

extension QuietSection {
    /// A reminder's time of day changed. Kept as it was if it didn't save.
    fileprivate func saveHour(_ field: String, _ hour: Int, revert: @escaping () -> Void) {
        guard loaded else { return }
        Task {
            do {
                let _: MeSettings = try await state.api.send("PATCH", "/me/settings", json: [field: hour])
            } catch {
                revert()
                state.surface(error)
            }
        }
    }
}

/// When a reminder arrives: one of four times of day, chosen from a menu,
/// in the person's own time.
private struct ReminderTime: View {
    @Binding var hour: Int

    private static let choices: [(hour: Int, name: String)] = [
        (9, "Morning"), (14, "Afternoon"), (18, "Evening"), (21, "Night"),
    ]

    private static func clock(_ hour: Int) -> String {
        var parts = DateComponents()
        parts.hour = hour
        let date = Calendar.current.date(from: parts) ?? .now
        return date.formatted(.dateTime.hour())
    }

    var body: some View {
        Picker("Time", selection: $hour) {
            ForEach(Self.choices, id: \.hour) { choice in
                Text("\(choice.name), \(Self.clock(choice.hour))").tag(choice.hour)
            }
        }
        .pickerStyle(.menu)
        .font(.subheadline)
        .padding(.leading, 2)
    }
}

/// A notice's switch: its name, and a line under it saying what it is.
private struct QuietRow: View {
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
            Text(detail)
                .font(.footnote)
                .foregroundStyle(.secondary)
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
/// for the organizer, a way to make it stop working. Pushed from Settings
/// and, since build 33, opened as a sheet from the Invite card at the end of
/// the You tab's faces (`InviteSheet`).
struct InviteCodeView: View {
    @Environment(AppState.self) private var state
    @State private var confirmReset = false
    /// Copy says so on its own row: the app's flash sits at the root, under
    /// a sheet, where nobody would see it.
    @State private var copied = false

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
                        withAnimation(.easeOut(duration: 0.2)) { copied = true }
                        Task {
                            try? await Task.sleep(for: .seconds(2))
                            withAnimation(.easeOut(duration: 0.2)) { copied = false }
                        }
                    } label: {
                        Label(copied ? "Copied" : "Copy Code", systemImage: copied ? "checkmark" : "doc.on.doc")
                            .contentTransition(.opacity)
                    }
                    .disabled(code.isEmpty)
                    ShareLink(item: "Join \(name) on Stanley with the code \(code).") {
                        Label("Share Invite", systemImage: "square.and.arrow.up")
                    }
                    .disabled(code.isEmpty)
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

/// The invite page as a sheet, for the Invite card on the You tab (build 33):
/// growing the circle one tap from where its faces are, not two levels into
/// Settings (the HCI audit). The same page, with Done.
struct InviteSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            InviteCodeView()
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
        }
        .presentationDetents([.medium, .large])
    }
}

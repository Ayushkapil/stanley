import SwiftUI
import UIKit

struct SettingsView: View {
    @Environment(AppState.self) private var state
    @AppStorage("stanley.appearance") private var appearance = "system"
    @AppStorage("stanley.atmosphere") private var atmosphere = "auto"
    @AppStorage("stanley.appLock") private var appLock = false
    @State private var lastLight = false
    @State private var loaded = false

    @Environment(\.horizontalSizeClass) private var hSizeClass
    private var density: Density { Density(hSizeClass) }

    @State private var confirmRotate = false
    @State private var confirmLeave = false
    @State private var confirmDelete = false

    @State private var exporting = false
    @State private var exportURL: URL?
    @State private var showShare = false

    private var isCreator: Bool { state.circle?.isCreator ?? false }

    var body: some View {
        NavigationStack {
            Form {
                circleSection
                appearanceSection
                quietSection
                privacySection
                dataSection
                accountSection
            }
            .readableWidth(density)
            .foldAnimated(hSizeClass)
            .atmosphereWash()
            .navigationTitle("Settings")
            .task {
                if !loaded {
                    if let me: MeSettings = try? await state.api.send("GET", "/me") {
                        lastLight = me.lastLightNoticeEnabled
                    }
                    loaded = true
                }
            }
            .alert("Rotate the invite code?", isPresented: $confirmRotate) {
                Button("Rotate", role: .destructive) { Task { await state.rotateInvite() } }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("The current code stops working immediately. Anyone with the old link won't be able to join.")
            }
            .alert("Leave this circle?", isPresented: $confirmLeave) {
                Button("Leave", role: .destructive) { Task { await state.leaveCircle() } }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("You'll stop seeing the circle. The memories you've held stay yours.")
            }
            .alert("Delete your account?", isPresented: $confirmDelete) {
                Button("Delete", role: .destructive) { Task { await state.deleteAccount() } }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Your photos are removed everywhere within a day. People who held them keep only a note that a memory was there. This can't be undone.")
            }
            .sheet(isPresented: $showShare) {
                if let exportURL {
                    ShareSheet(items: [exportURL])
                }
            }
        }
    }

    @ViewBuilder
    private var circleSection: some View {
        if let circle = state.circle {
            Section {
                LabeledContent("Name", value: circle.name)
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
                if let code = state.inviteCode {
                    HStack(alignment: .center) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Invite code")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            Text(code)
                                .font(.system(.title3, design: .monospaced).weight(.semibold))
                                .textSelection(.enabled)
                        }
                        Spacer()
                        Button {
                            UIPasteboard.general.string = code
                            state.flash = "Copied"
                        } label: {
                            Image(systemName: "doc.on.doc")
                                .imageScale(.medium)
                        }
                        .buttonStyle(.borderless)
                        .padding(.leading, 8)
                        ShareLink(item: "Join my circle on Stanley: \(code)") {
                            Image(systemName: "square.and.arrow.up")
                                .imageScale(.medium)
                        }
                        .buttonStyle(.borderless)
                        .padding(.leading, 4)
                    }
                    if isCreator {
                        Button("Rotate code") { confirmRotate = true }
                            .foregroundStyle(.primary)
                    }
                }
                Button("Leave circle", role: .destructive) { confirmLeave = true }
            } header: {
                Text("Circle")
            } footer: {
                Text("Stanley works best with people you actually know. People, not numbers.")
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
            Picker("Atmosphere", selection: $atmosphere) {
                ForEach(Atmosphere.allCases) { a in
                    Text(a.label).tag(a.rawValue)
                }
            }
        } header: {
            Text("Appearance")
        } footer: {
            Text("Atmosphere shifts the color with the season (Auto), or you can pick a mood. Rain is the quiet one. It's only color — nothing about how Stanley works changes.")
        }
    }

    private var quietSection: some View {
        Section {
            Toggle("Tell me when my own photo is fading", isOn: $lastLight)
                .onChange(of: lastLight) { _, newValue in
                    guard loaded else { return }
                    Task {
                        do {
                            let settings: MeSettings = try await state.api.send(
                                "PATCH", "/me/settings",
                                json: ["last_light_notice_enabled": newValue]
                            )
                            lastLight = settings.lastLightNoticeEnabled
                        } catch {
                            state.surface(error)
                        }
                    }
                }
        } header: {
            Text("Quiet")
        } footer: {
            Text("The only notice that exists: one, for your own photo, on its last day. Off unless you ask. Stanley sends at most one digest a day and nothing else — no streaks, no nudges.")
        }
    }

    private var privacySection: some View {
        Section {
            Toggle("Require Face ID to open", isOn: $appLock)
        } header: {
            Text("Lock")
        } footer: {
            Text("Off by default. When on, Stanley asks for Face ID or your passcode each time it opens.")
        }
    }

    private var dataSection: some View {
        Section {
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
                    Text("Export my memories")
                    if exporting {
                        Spacer()
                        ProgressView()
                    }
                }
            }
            .disabled(exporting)
            NavigationLink {
                AboutView()
            } label: {
                Text("About")
            }
        } footer: {
            Text("Export bundles the photos you've held, with their captions. Held only — there's no archive of everything you've ever posted.")
        }
    }

    private var accountSection: some View {
        Section {
            Button("Sign out", role: .destructive) { state.signOut() }
            Button("Delete account", role: .destructive) { confirmDelete = true }
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
                        Text(member.displayName ?? "departed")
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
        }
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

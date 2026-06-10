import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var state
    @State private var lastLight = false
    @State private var loaded = false

    var body: some View {
        NavigationStack {
            Form {
                if let circle = state.circle {
                    Section("Circle") {
                        LabeledContent("Name", value: circle.name)
                        if let code = state.inviteCode {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Invite code")
                                Text(code)
                                    .font(.caption.monospaced())
                                    .textSelection(.enabled)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
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
                Section {
                    Button("Sign out", role: .destructive) {
                        state.signOut()
                    }
                }
            }
            .navigationTitle("Quiet")
            .task {
                if !loaded {
                    if let me: MeSettings = try? await state.api.send("GET", "/me") {
                        lastLight = me.lastLightNoticeEnabled
                    }
                    loaded = true
                }
            }
        }
    }
}

import SwiftUI

/// About Stanley: what it is and why, in Stanley's own words. One page, read
/// top to bottom, no links out.
struct AboutStanleyView: View {
    private static let paragraphs = [
        "Stanley is a photo app for small circles. You post one photo a day. It fades in six days unless someone in your circle keeps it.",
        "There are no followers, no like counts, no algorithm deciding what you see. Your feed is small because your circle is small. Your photos fade because not everything needs to last forever — but the ones someone reaches out to save become more meaningful because of everything that was allowed to go.",
        "What you post here belongs to you. What your friends keep lives in their memory of you. If you ever delete something, it's gone everywhere. Stanley doesn't sell your data, doesn't show you ads, and doesn't use your photos to train anything.",
    ]

    /// How it's used, said once somewhere (the HCI audit, build 32): the
    /// gestures and the corners of the journal were explained nowhere but
    /// the empty Held page.
    private static let howItWorks = [
        "Today is your circle's journal. The + at the top takes today's photo: one a day in each circle you're in.",
        "Tap the bookmark on a photo, or press and hold it and choose Hold, to keep it in Held. Double-tap a photo to like it; only the person who posted it sees who did.",
        "Under a photo, write what you remember. Type @ to mention someone.",
        "The board at the top of Today holds a sticky note from each of you, for the day. Swipe to read them.",
        "Each week your circle gets one question. Answers stay sealed until the week's end, then everyone's open at once.",
        "On Sunday evening, the You tab asks how your week was. Your journal entries and reflections are only ever yours.",
        "Tap the tab you're on to go back to the top of it.",
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("One day, one photo.")
                    .font(.keepsake(32))
                    .padding(.bottom, 4)
                ForEach(Self.paragraphs, id: \.self) { paragraph in
                    Text(paragraph)
                        .font(.body)
                        .lineSpacing(5)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text("How it works")
                    .font(.keepsake(22))
                    .accessibilityAddTraits(.isHeader)
                    .padding(.top, 12)
                ForEach(Self.howItWorks, id: \.self) { line in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text("·").font(.body.weight(.bold)).foregroundStyle(.secondary)
                        Text(line)
                            .font(.body)
                            .lineSpacing(5)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .atmosphereWash()
        .navigationTitle("About Stanley")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// About your account: your name, your username, and when you joined, and
/// nothing else (no post count, no activity; there's nothing to total up).
/// Signing out, the people you've blocked (build 22; it was a row of Privacy
/// & Security, more visible than it's needed) and deleting the account live
/// here, one level down from Settings, the way iOS keeps its own serious
/// actions.
struct AccountView: View {
    @Environment(AppState.self) private var state
    @State private var confirmDelete = false

    private var name: String? {
        state.profile?.displayName?.trimmingCharacters(in: .whitespaces).nilIfEmpty
    }

    private var username: String? {
        state.profile?.username?.trimmingCharacters(in: .whitespaces).nilIfEmpty
    }

    private var joined: String? {
        state.profile?.createdAt?.formatted(.dateTime.month(.wide).year())
    }

    var body: some View {
        List {
            Group {
                Section {
                    // A dash reads like a bug. Say what is actually true: we
                    // haven't been told yet.
                    LabeledContent("Name", value: name ?? "Not set yet")
                    LabeledContent("Username", value: username.map { "@\($0)" } ?? "Not set yet")
                    if let joined {
                        LabeledContent("Joined", value: joined)
                    }
                } footer: {
                    Text("Change your name, username and photo from Edit on the You tab.")
                }
                Section {
                    Button("Sign Out") { state.signOut() }
                        .foregroundStyle(.primary)
                }
                Section {
                    NavigationLink("Blocked") { BlockedView() }
                } footer: {
                    Text("The people you've blocked. Neither of you sees the other's photos or stories.")
                }
                Section {
                    Button("Delete Account", role: .destructive) { confirmDelete = true }
                        .destructiveInk()
                } footer: {
                    Text("Deletes your account and everything you've posted. People who kept your photos keep only a note that a memory was there.")
                }
            }
            .atmosphereRows()
        }
        .atmosphereWash()
        .task { await state.loadProfile() }
        .navigationTitle("About Your Account")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Delete your account?", isPresented: $confirmDelete) {
            Button("Delete", role: .destructive) { Task { await state.deleteAccount() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your photos are removed everywhere within a day. People who held them keep only a note that a memory was there. This can't be undone.")
        }
    }
}

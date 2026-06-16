import SwiftUI

/// About (Part 2): why Stanley exists, an account summary, and the Terms of
/// Use required for App Review. No insights, no analytics — nothing countable.
struct AboutView: View {
    @Environment(AppState.self) private var state

    private var joinDate: String? {
        guard let created = state.profile?.createdAt else { return nil }
        return created.formatted(date: .long, time: .omitted)
    }

    var body: some View {
        List {
            Section {
                NavigationLink {
                    AboutStanleyView()
                } label: {
                    Label("About Stanley", systemImage: "moon.stars")
                }
                NavigationLink {
                    TermsView()
                } label: {
                    Label("Terms of use", systemImage: "doc.plaintext")
                }
            }
            Section("Your account") {
                LabeledContent("Name", value: state.profile?.displayName ?? "—")
                if let joinDate {
                    LabeledContent("Joined", value: joinDate)
                }
            }
        }
        .navigationTitle("About")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct AboutStanleyView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("One day, one photo")
                    .font(.keepsake(30))
                Group {
                    Text("Stanley is a small place for a small circle. One photo a day, no more. Every photo fades on its own within six days — unless someone holds it.")
                    Text("There are no likes to chase, no counts to climb, no feed that reorders itself to keep you scrolling. The order is just time. What you see is just the people you chose.")
                    Text("Holding a photo is a quiet act of keeping — light that didn't go out. Warmth is lighter still, and it fades with the photo it was given to. Neither is ever a number. We show faces, never tallies, because a circle is people, not metrics.")
                    Text("Keeping it this minimal is the point. With nothing to perform for, what's left is the small true stuff: a Tuesday, a lake, a face you're glad to see. That's enough for a circle to stay close.")
                }
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineSpacing(4)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("About Stanley")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct TermsView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Terms of use")
                    .font(.title3.weight(.medium))
                Text("Last updated June 2026 · pilot build")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                term("Who this is for", "Stanley is a private, invite-only app for small circles. You must be old enough to use it under the laws where you live.")
                term("Your content", "You own the photos and words you share. You grant the people in your circle the ability to see them while they're live, and to keep (hold) them after — including after a photo would otherwise fade. Deleting your photo removes the image everywhere; people who held it keep only an honest note that a memory was there.")
                term("What fades", "Photos fade within six days unless held. Warmth is ephemeral and disappears with the photo. None of this is recoverable — that's the contract, on purpose.")
                term("Be kind", "No harassment, no abuse, no illegal content, no sharing of others' images without consent. You can block any member and report any photo or comment; reports are reviewed and acted on within 24 hours.")
                term("No guarantees", "This is a pilot. The service is provided as-is, without warranty. We may suspend accounts that violate these terms.")
                term("Contact", "Reach the team through the circle's organizer for anything not covered here.")
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("Terms")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func term(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.headline)
            Text(body).font(.callout).foregroundStyle(.secondary).lineSpacing(3)
        }
    }
}

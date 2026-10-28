import SwiftUI

/// About hub, reached from Settings → About. Two quiet doors: the product
/// story, and a plain account summary. No insights, no analytics — nothing
/// countable lives here.
struct AboutView: View {
    var body: some View {
        List {
            Section {
                NavigationLink {
                    AboutStanleyView()
                } label: {
                    Label("About Stanley", systemImage: "moon.stars")
                }
                NavigationLink {
                    AboutAccountView()
                } label: {
                    Label("Your account", systemImage: "person")
                }
            }
        }
        .atmosphereWash()
        .navigationTitle("About")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// The product story — one scrollable page, warm and brief. Three sections,
/// then the legal doors and the build number. Headers in the keepsake serif;
/// body in the system font; lots of room to breathe.
struct AboutStanleyView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                section(
                    "What Stanley is",
                    [
                        "One photo a day. Everything fades within six days — unless someone keeps it.",
                        "No likes you can count, no followers, no algorithm deciding what you see. Just a small circle of people sharing one moment a day and choosing which ones to hold onto.",
                    ]
                )
                section(
                    "Why it's built this way",
                    [
                        "Stanley exists because social media stopped being social. Feeds got infinite, photos became performances, and the number under your post started mattering more than the moment in it.",
                        "Stanley goes the other way. Your feed is small because your circle is small. Your photos fade because not everything needs to last forever — and the ones someone reaches out to keep mean more because of everything that was allowed to go.",
                        "There are no counts anywhere. You see faces, not numbers. The only measure is whether this felt like a good place to share a photo today.",
                    ]
                )
                section(
                    "Your memories, your circle",
                    [
                        "What you post here belongs to you. What your friends keep lives in their memory of you — and if you ever delete it, it's gone everywhere.",
                        "Stanley doesn't sell your data, doesn't show you ads, and doesn't use your photos to train anything.",
                        "Stanley works best with people you actually know. There is a ceiling, but you are unlikely to meet it — nothing here will ever ask you to invite more people.",
                    ]
                )

                VStack(spacing: 0) {
                    NavigationLink {
                        TermsView()
                    } label: {
                        legalRow("Terms of Use")
                    }
                    Divider().opacity(0.4)
                    NavigationLink {
                        PrivacyView()
                    } label: {
                        legalRow("Privacy Policy")
                    }
                }
                .padding(.top, 4)

                Text(versionLine)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 4)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .atmosphereWash()
        .navigationTitle("About Stanley")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func section(_ title: String, _ paragraphs: [String]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.keepsake(26))
            ForEach(paragraphs, id: \.self) { paragraph in
                Text(paragraph)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .lineSpacing(5)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func legalRow(_ title: String) -> some View {
        HStack {
            Text(title).font(.callout)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .foregroundStyle(.primary)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }

    private var versionLine: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String ?? "—"
        return "Version \(version) (\(build))"
    }
}

/// A plain account summary. Name, username, and when you joined — and nothing
/// else. No post count, no activity, no analytics; there's nothing to total up.
struct AboutAccountView: View {
    @Environment(AppState.self) private var state

    private var memberSince: String? {
        guard let created = state.profile?.createdAt else { return nil }
        return "Member since " + created.formatted(.dateTime.month(.wide).year())
    }

    var body: some View {
        List {
            Section {
                LabeledContent("Name", value: state.profile?.displayName ?? "—")
                if let username = state.profile?.username, !username.isEmpty {
                    LabeledContent("Username", value: "@\(username)")
                }
            } footer: {
                if let memberSince {
                    Text(memberSince)
                }
            }
        }
        .atmosphereWash()
        .navigationTitle("Your account")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct TermsView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Terms of use")
                    .font(.title3.weight(.medium))
                Text("Draft · June 2026 · pilot build. A plain-language summary for the pilot — these terms will be finalized before Stanley is released publicly.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                LegalParagraph(heading: "Who this is for", text: "Stanley is a private, invite-only app for small circles. You must be old enough to use it under the laws where you live.")
                LegalParagraph(heading: "Your content", text: "You own the photos and words you share. You grant the people in your circle the ability to see them while they're live, and to keep (hold) them after — including after a photo would otherwise fade. Deleting your photo removes the image everywhere; people who held it keep only an honest note that a memory was there.")
                LegalParagraph(heading: "What fades", text: "Photos fade within six days unless held. Warmth is ephemeral and disappears with the photo. None of this is recoverable — that's the contract, on purpose.")
                LegalParagraph(heading: "Be kind", text: "No harassment, no abuse, no illegal content, no sharing of others' images without consent. You can block any member and report any photo or comment; reports are reviewed and acted on within 24 hours.")
                LegalParagraph(heading: "No guarantees", text: "This is a pilot. The service is provided as-is, without warranty. We may suspend accounts that violate these terms.")
                LegalParagraph(heading: "Contact", text: "Reach the team through the circle's organizer for anything not covered here.")
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .atmosphereWash()
        .navigationTitle("Terms")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct PrivacyView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Privacy policy")
                    .font(.title3.weight(.medium))
                Text("Draft · June 2026. A working summary for the pilot, not a final legal document — it will be finalized before Stanley is released publicly.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                LegalParagraph(heading: "What we collect", text: "Your sign-in through Apple, the name, username and bio you choose, and the photos and words you post. That's the whole list.")
                LegalParagraph(heading: "What we don't do", text: "We don't sell your data. We don't show ads. We don't use your photos to train anything, and we never will.")
                LegalParagraph(heading: "Your photos", text: "Location is stripped from every photo before it's stored — the GPS is gone, not hidden. Images are served over short-lived signed links, never public URLs.")
                LegalParagraph(heading: "Fading and deletion", text: "Photos fade on their own within six days unless someone holds them. Deleting your photo removes the image everywhere within a day; deleting your account purges everything you posted.")
                LegalParagraph(heading: "Who sees what", text: "Only your circle ever sees your photos. There is no public surface, and nothing is indexed or shared outside it.")
                LegalParagraph(heading: "Questions", text: "Reach the team through your circle's organizer until a contact address is published with the final policy.")
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .atmosphereWash()
        .navigationTitle("Privacy")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// One titled paragraph of legal-ish copy, shared by Terms and Privacy.
private struct LegalParagraph: View {
    let heading: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(heading).font(.headline)
            Text(text)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineSpacing(3)
        }
    }
}

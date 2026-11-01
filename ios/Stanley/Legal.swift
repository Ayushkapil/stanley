import SwiftUI

/// The Terms of Use and the Privacy Policy, word for word as the server serves
/// them at /terms and /privacy (`server/stanley/legal.py`, which App Store
/// Connect links to). `server/tests/test_legal.py` fails if the two differ, so
/// a change goes in both places. A line starting with "- " is a list item.
enum Legal {
    struct Section: Hashable {
        let heading: String?
        let lines: [String]
    }

    static let updated = "November 1, 2026"

    static let terms: [Section] = [
        Section(heading: "By using Stanley, you agree to:", lines: [
            "- Post only photos you have the right to share",
            "- Treat your circle with respect",
            "- Not use Stanley to harass, threaten, or harm anyone",
            "- Not upload illegal content",
        ]),
        Section(heading: nil, lines: [
            "There's no tolerance for objectionable content or abusive behavior. You can block anyone in your circle and report any photo or story; reports are reviewed within 24 hours.",
            "Stanley reserves the right to remove content or accounts that violate these terms. Your photos are stored on our servers and deleted when they fade (unless someone in your circle keeps them), when you delete them, or when you delete your account.",
            "For questions, contact ayushkapileshwar@gmail.com.",
        ]),
    ]

    static let privacy: [Section] = [
        Section(heading: "What Stanley collects:", lines: [
            "- Your name and username (from Sign in with Apple or entered by you), and the profile photo and few words about yourself you choose to add",
            "- Photos you post, with their captions and the stories your circle adds (stored on our servers, deleted when they fade unless someone in your circle keeps them, and deleted everywhere when you delete them or your account)",
            "- Place names on your photos, typed by you or suggested from where your phone is, which you can change or clear (your phone works out the name; Stanley's servers never receive GPS coordinates, and Stanley never tracks your location)",
            "- The name of your town, if you allow location, to show headlines from near you (sent with the request and not stored with your account)",
            "- A notification token for your phone, only if you turn on a notification (removed when you sign out on that phone or delete your account)",
            "- Crash reports (anonymous, via Sentry)",
        ]),
        Section(heading: "What Stanley does not collect:", lines: [
            "- Your email address",
            "- Your contacts",
            "- Browsing or usage analytics",
            "- GPS or precise location data",
        ]),
        Section(heading: "Your data:", lines: [
            "- Your photos are seen only by the circle you post them to",
            "- You can export your held memories anytime from Settings",
            "- You can delete your account anytime from Settings, which removes all your data within 24 hours",
            "- Stanley does not sell, share, or use your data for advertising",
            "- Photos are not used to train AI models",
        ]),
        Section(heading: nil, lines: [
            "For questions, contact ayushkapileshwar@gmail.com.",
        ]),
    ]
}

/// One legal document, as plain as the server's page: a heading per section,
/// its paragraphs, and its list items.
struct LegalDocumentView: View {
    let title: String
    let sections: [Legal.Section]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text("Updated \(Legal.updated)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                ForEach(sections, id: \.self) { section in
                    VStack(alignment: .leading, spacing: 10) {
                        if let heading = section.heading {
                            Text(heading).font(.headline)
                        }
                        ForEach(section.lines, id: \.self) { line in
                            if line.hasPrefix("- ") {
                                HStack(alignment: .firstTextBaseline, spacing: 10) {
                                    Text("•").foregroundStyle(.secondary)
                                    Text(String(line.dropFirst(2)))
                                }
                            } else {
                                Text(line)
                            }
                        }
                    }
                    .font(.callout)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .atmosphereWash()
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

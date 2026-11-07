import SwiftUI

/// The Terms of Use and the Privacy Policy, word for word as the server serves
/// them at /terms and /privacy (`server/stanley/legal.py`, which App Store
/// Connect links to). `server/tests/test_legal.py` fails if the two differ, so
/// a change goes in both places. A line starting with "- " is a list item, and
/// one starting with "## " a subheading.
enum Legal {
    struct Section: Hashable {
        let heading: String?
        let lines: [String]
    }

    /// Where questions go, as both documents' Contact sections say it; a
    /// link that opens Mail wherever it appears.
    static let contact = "ayushkapileshwar@gmail.com"
    static let effective = "November 7, 2026"
    /// The Privacy Policy's own date. Both last changed on November 7, 2026
    /// (Circle Posts, the third notice, which carries the poster's name,
    /// build 37). `legal.py` keeps the same two.
    static let privacyEffective = "November 7, 2026"

    static let terms: [Section] = [
        Section(heading: "1. Introduction and acceptance", lines: [
            "Welcome to Stanley. These Terms of Use are an agreement between you and Ayush Kapileshwar, who builds and runs Stanley (“Stanley”, “we”, “us”). They cover the Stanley app and the server it uses.",
            "By creating an account or using Stanley, you agree to these terms and to our Privacy Policy. If you don't agree, please don't use Stanley.",
            "You must be at least 13 years old to use Stanley. If you're under the age of majority where you live, you need a parent's or guardian's permission, and they agree to these terms for you.",
            "These terms are effective November 7, 2026.",
        ]),
        Section(heading: "2. Your account", lines: [
            "- You need Sign in with Apple to create an account. It's the only way in",
            "- One account per person. Your account is yours alone: don't share it, sell it, or let anyone else use it",
            "- Keep your phone and your Apple Account secure. You can also lock Stanley with Face ID or Touch ID in Settings",
            "- You're responsible for what happens on your account. If you think someone else has used it, tell us",
            "- Use your own name, or the one your circle knows you by. Don't choose a name or username meant to mislead",
        ]),
        Section(heading: "3. Your content", lines: [
            "“Content” means the photos, captions, stories, place names, community notes, tags, journal entries, reflections, answers to your circle's questions and profile information you create or share on Stanley.",
            "You own your content. Stanley does not claim ownership of anything you post.",
            "To run Stanley, we need your permission to handle it. So you give us a limited, non-exclusive, royalty-free, worldwide license to store your content on our servers, to process it as needed to provide the service (resizing it, cropping it to fit, removing its metadata, and serving it), and to show it to the people Stanley shows it to: the members of the circle you posted it to, the people who hold it, and you.",
            "This license is only for running Stanley. It ends when your content is deleted: when a photo fades and no one has held it, when you delete it, or when you delete your account. Copies that people in your circle exported before then are theirs, and outside our reach.",
            "- Stanley does not use your content for AI training",
            "- Stanley does not license or sell your content to third parties",
            "- Stanley does not use your content for advertising, or show it to anyone outside your circle",
            "You promise that you have the right to share what you post, and that posting it doesn't break these terms or anyone's rights. If other people are in your photo, think about whether they'd want it shared.",
            "## Other people's content",
            "What other people post is theirs. When you hold someone's photo, or export your memories, you're keeping a copy for yourself, the way you'd keep a print a friend gave you. Don't repost it outside Stanley, or use it commercially, without their permission.",
        ]),
        Section(heading: "4. How Stanley works", lines: [
            "Stanley is built on a few rules, and they're the point:",
            "- One photo per day in each circle you're in, at least 12 hours apart. If you delete today's photo, you can take it again once; deleting it a second time spends the day",
            "- Photos fade over approximately six days and then disappear, unless someone holds them",
            "- A photo you hold stays with you until you let go of it or delete your account, or until the person who posted it deletes it",
            "- Likes and holds are private: only the person who posted a photo sees who liked or held it, and Stanley never counts them",
            "- You can be in up to 5 circles, and each circle has a soft cap of 100 members",
            "- Anyone with a circle's invite code can join it, so share it only with people you'd want there. The person who started a circle can reset its code and remove members",
            "- Notifications are off until you turn them on, and there are only three",
            "These mechanics may be adjusted as we improve the service. If a change matters to how you use Stanley, we'll tell you in the app.",
        ]),
        Section(heading: "5. Community guidelines", lines: [
            "Stanley is for people who know each other. Treat your circle with respect, the way you'd treat them in person.",
            "Don't post or share content that:",
            "- Is illegal, or encourages anything illegal",
            "- Is harmful, threatening, abusive or harassing, or bullies or intimidates anyone",
            "- Is defamatory, or shares someone's private information without their permission",
            "- Is hateful toward people because of who they are, including their race, ethnicity, religion, disability, sex, gender identity or sexual orientation",
            "- Is sexually explicit",
            "- Exploits or endangers minors in any way",
            "- Shows graphic violence",
            "- Impersonates someone else",
            "- You don't have the right to share, including other people's photos or work",
            "Don't use Stanley to spam, phish or distribute malware, and don't try to break, overload, scrape or get around how Stanley works, or to see what you're not meant to see.",
            "There's no tolerance for objectionable content or abusive behavior. Breaking these guidelines may result in your content being removed or your account being terminated.",
            "If someone's content or behavior bothers you, you can report it or block them. Blocking someone means you no longer see each other's photos. Reported content is reviewed within 24 hours.",
        ]),
        Section(heading: "6. Content moderation", lines: [
            "- We may remove content that violates these terms or our community guidelines",
            "- We may suspend or terminate accounts for violations, without notice when the situation calls for it",
            "- We review every report within 24 hours, and remove the content, the person who posted it, or both, when that's warranted",
            "- Block and report are there for your safety. Use them whenever you need to",
            "- We comply with applicable laws regarding illegal content, including reporting content that exploits children to the authorities",
            "If you think we've removed your content or account by mistake, write to us and we'll take another look.",
        ]),
        Section(heading: "7. News content", lines: [
            "The World Today shows headlines, and some summaries, from third-party news sources: currently PBS News Hour, the BBC and Google News.",
            "Stanley does not create, edit, endorse or verify news content. Each source chooses its own stories, and what they say is theirs.",
            "News is provided for your convenience only. Stanley is not a news service, and we don't guarantee that any story is accurate, complete or current.",
            "A full article opens on the publisher's own website, under the publisher's terms.",
        ]),
        Section(heading: "8. Intellectual property", lines: [
            "Stanley, including its name, logo, design, code, words and visual identity, is the property of Ayush Kapileshwar and is protected by copyright, trademark and other laws.",
            "We give you a personal, non-exclusive, non-transferable, revocable license to use the Stanley app on Apple devices you own or control, for your own non-commercial use, under these terms.",
            "You may not copy, modify or distribute Stanley's code or design, sell or rent any part of Stanley, or reverse engineer it, without our written permission or unless the law allows it.",
            "Don't use the Stanley name or look in a way that suggests we endorse you or anything you make.",
            "If you send us ideas or feedback, we may use them without owing you anything. Thank you for them.",
        ]),
        Section(heading: "9. Termination", lines: [
            "You can delete your account at any time, in Settings → Privacy & Security → About Your Account → Delete Account.",
            "We may suspend or terminate accounts that violate these terms, when the law requires it, or to protect other people. If we terminate your account for a violation, please don't make a new one without our permission. We may also stop offering Stanley altogether; if we do, we'll tell you in the app first and give you time to export your held memories.",
            "When an account is deleted, for whatever reason, its content is deleted right away, and from our backups within seven days.",
            "That includes copies of its photos held by other people: when the person who posted a photo deletes it, it's removed everywhere. The people who held it keep a note that a memory was there, and the stories they wrote themselves.",
            "Sections 8 and 10 through 17 continue to apply after your account ends.",
        ]),
        Section(heading: "10. Disclaimer of warranties", lines: [
            "Stanley is provided “as is” and “as available”. To the fullest extent the law allows, we disclaim all warranties, express or implied, including warranties of merchantability, fitness for a particular purpose and non-infringement.",
            "We do not guarantee that Stanley will be uninterrupted, secure or error-free, or that content will never be lost. Photos fade by design; if one matters to you, hold it.",
            "We do not guarantee the accuracy of news content, and we're not responsible for content posted by other users, or for what they say or do.",
            "Some places don't allow these disclaimers, so some of them may not apply to you.",
        ]),
        Section(heading: "11. Limitation of liability", lines: [
            "To the maximum extent permitted by law, Stanley and its creator are not liable for any indirect, incidental, special, consequential or punitive damages, or for any loss of data, photos, profits or goodwill, arising from or related to your use of Stanley, even if we were told such damages were possible.",
            "Our total liability for any claim about Stanley is limited to the amount you paid for Stanley in the twelve months before the claim. Stanley is free, so that amount is currently $0.",
            "Nothing in these terms limits liability that the law doesn't allow to be limited.",
        ]),
        Section(heading: "12. Indemnification", lines: [
            "You agree to defend, indemnify and hold harmless Stanley and its creator from any claims, damages, losses and costs (including reasonable legal fees) arising from your use of Stanley, your content, or your violation of these terms or of anyone else's rights.",
        ]),
        Section(heading: "13. Governing law", lines: [
            "These terms are governed by the laws of the State of Indiana, United States, without regard to its conflict of law rules.",
            "Any dispute about Stanley or these terms will be resolved in the courts of Monroe County, Indiana, and you and we both agree to their jurisdiction.",
            "If the consumer laws where you live give you the right to bring a claim in your own courts or under your own laws, nothing in these terms takes that right away.",
        ]),
        Section(heading: "14. Changes to these terms", lines: [
            "We may update these terms. When we do, we'll change the effective date at the top.",
            "If a change is material, we'll tell you in the app before it takes effect.",
            "If you keep using Stanley after a change takes effect, that means you accept the updated terms. If you don't, you can delete your account at any time.",
        ]),
        Section(heading: "15. Severability", lines: [
            "If any provision of these terms is found unenforceable, it will be enforced as far as it can be, and the rest of these terms remain in full effect.",
            "If we don't enforce part of these terms right away, we haven't given up the right to enforce it later.",
        ]),
        Section(heading: "16. Entire agreement", lines: [
            "These terms and the Privacy Policy are the entire agreement between you and Stanley about Stanley, and they replace anything said before. No other promises or representations apply.",
            "You can't transfer your rights under these terms to anyone else. We may transfer ours, for example if Stanley moves to a new owner, and these terms will continue to protect you.",
        ]),
        Section(heading: "17. Apple", lines: [
            "Stanley is distributed through Apple's App Store, so a few things about Apple apply:",
            "- These terms are between you and us, not Apple. We, not Apple, are responsible for Stanley and its content",
            "- Apple has no obligation to provide maintenance or support for Stanley",
            "- If Stanley fails to meet a warranty that applies to it, you may notify Apple, and Apple will refund its purchase price, which is $0. Apple has no other warranty obligation for Stanley",
            "- Apple is not responsible for any claims relating to Stanley, including product liability claims, claims that Stanley fails to meet a legal or regulatory requirement, claims under consumer protection or privacy laws, and claims that Stanley infringes someone's intellectual property. We are responsible for dealing with those",
            "- You confirm that you're not in a country under a United States government embargo, and not on any United States government list of prohibited or restricted parties",
            "- You must also follow the App Store's own terms when you use Stanley",
            "- Apple and its subsidiaries are third-party beneficiaries of these terms, and once you accept them, Apple has the right to enforce them against you",
        ]),
        Section(heading: "18. Contact", lines: [
            "Questions about these terms, or something to report: ayushkapileshwar@gmail.com",
            "Stanley, Bloomington, Indiana, United States",
        ]),
    ]

    static let privacy: [Section] = [
        Section(heading: "1. Introduction", lines: [
            "Stanley is built by Ayush Kapileshwar. This policy explains what data Stanley collects, how it's used, and your rights.",
            "Stanley is a small app for small circles of people who know each other: one photo a day, seen only by your circle, fading unless someone keeps it. We've tried to collect only what that needs, and to say plainly what it is. When this policy says “we” or “us”, it means Stanley and the person who builds it.",
            "This policy covers the Stanley app for iPhone and the server it talks to. It's effective November 7, 2026.",
        ]),
        Section(heading: "2. What we collect", lines: [
            "## Account data",
            "- Your display name, which you enter, or which Sign in with Apple gives us the first time you sign in if you choose to share it",
            "- Your username, which you choose",
            "- An identifier from Sign in with Apple, so we recognize you when you sign in again. It's a code Apple makes for Stanley alone, not your Apple Account's email or password",
            "- Your profile photo, if you add one",
            "- Your bio, if you write one",
            "- The circles you're in, when you joined them, and which ones you started",
            "- Your settings, such as which notifications you've turned on",
            "## Content you create",
            "- Photos you post. We keep each one at full size, with smaller copies for the app to show",
            "- When each photo was taken. That's the only photo metadata we keep: everything else, including any location, is removed before a photo is stored",
            "- Captions and the place names you put on your photos",
            "- Stories you add to photos, your answers to “What do you remember?”",
            "- Notes you leave on your circle's board",
            "- Journal entries you write on your own photos, and your reflections on your week. Only you ever see these",
            "- Your answers to your circle's question of the week",
            "- Who was there: the people you tag on a photo",
            "- The photos you like and hold, and any private note you keep with a held photo",
            "- Reports you make and the people you block",
            "## Collected automatically",
            "- Your time zone, so your day starts at your midnight and an evening notice arrives in your evening",
            "- Your town and country, only if you allow location, sent when you open the World tab to choose which headlines to show you. We don't store them with your account",
            "- A notification token for your phone, only if you turn on a notification. Apple gives it to your phone so we can send it the notices you asked for",
            "- Crash reports, through Sentry, when crash reporting is on in your version of the app: what went wrong in the code, your iPhone model, the iOS and app versions, and a short trail of what the app did just before, such as opening Held or posting a photo. They're anonymous, with no account, name, photo or location attached, and the trail never says what you wrote, whose photo it was or who you are",
            "- Your phone's IP address, which our host receives with each request in order to answer it, as every internet service does. We don't keep it with your account or use it to identify you",
            "## About location",
            "If you allow location, your phone uses it to suggest a place name for a new photo, by asking Apple's maps service what's there. Those coordinates stay between your phone and Apple: Stanley's servers never receive GPS coordinates. Only the place name you keep on a photo reaches us, and you can change or clear it. For a photo from your library, the suggestion comes from the location saved in that photo, worked out on your phone the same way.",
            "## What we don't collect",
            "- Your email address. Stanley doesn't ask Apple for it, so we never receive it, real or relayed",
            "- Your phone number",
            "- Your contacts or address book",
            "- Precise location or GPS coordinates",
            "- Your photo library. The system's photo picker gives Stanley only the one photo you choose, and your phone removes its metadata before it's sent",
            "- Browsing, usage or analytics data. Nothing in Stanley records what you tap, view or open, except that short trail, which stays on your phone and is sent only with a crash report",
            "- Advertising identifiers",
            "- Biometric data. If you lock Stanley with Face ID or Touch ID, your iPhone checks your face or fingerprint; Stanley only learns whether it matched",
        ]),
        Section(heading: "3. How we use your data", lines: [
            "We use what we collect to run Stanley, and for nothing else:",
            "- To show your photos, stories, answers and profile to your circle, and theirs to you",
            "- To keep your journal entries and reflections, and show them to you alone",
            "- To keep Stanley's rules: one photo a day in each circle, the fading, and the keeping",
            "- To run your circles, their invite codes, and your blocks",
            "- To send the notices you've turned on, and only those",
            "- To show headlines from near you, if you've allowed location",
            "- To find and fix crashes",
            "- To review reports and keep people safe",
            "We do not use your data for advertising. There are no ads in Stanley.",
            "We do not sell your data to anyone.",
            "We do not use your photos, or anything else you post, to train AI models, ours or anyone else's.",
            "We don't build a profile of you, and we don't rank you or your photos. Today shows your circle's photos newest first, and that's all.",
        ]),
        Section(heading: "4. How long we keep it", lines: [
            "Fading is the point of Stanley, and it applies to your data too.",
            "- A photo is seen for about six days, fading as it goes",
            "- If no one held it, it then becomes a tombstone, and within seven days the photo, its caption, place, likes, tags and stories are permanently deleted from our servers",
            "- A photo someone held stays with them until they let go of it or delete their account, or until the person who posted it deletes it",
            "- When someone deletes a photo they posted, its image is removed everywhere at once, including from the collections of people who held it. They keep a note that a memory was there, and the stories they wrote themselves. The person who posted a photo always has the last word",
            "- A journal entry on your photo lasts as long as the photo does for you: while it's in Today, and after that only while you hold it. It's deleted when the photo fades without your hold, when you let go of it, when the photo is deleted, or when you delete the entry",
            "- Reflections don't fade. Each is kept until you delete it or your account",
            "- Your note on your circle's board clears at the end of the day you wrote it, and is deleted from our servers then. If someone reports a note, the report keeps a copy of its words so it can be reviewed",
            "- Your answers to your circle's weekly questions are kept in the circle's journal until you delete your account",
            "- When you delete your account, we delete your data right away: your profile, your photos (including ones other people held), your stories, likes, holds, tags, notes, journal entries, reflections, answers, settings, notification tokens and circle memberships. What's left is a bare record with nothing about you in it, so that the people who held your photos see “a memory was here” instead of an error, and so that reports can still be reviewed",
            "- Our database is backed up once a day and each backup is kept for seven days, so anything deleted is gone from our backups within seven days",
            "- A notification token is deleted when you sign out on that phone, when you delete your account, or when Apple tells us it no longer works",
            "- Places you've used recently or starred are saved only on your phone, never on our servers, and are erased from your phone when you delete your account there",
            "- Headlines aren't about you. We keep each edition for about half an hour before fetching it fresh, and forget a town's headlines once no one has asked for them in a day",
        ]),
        Section(heading: "5. Who we share it with", lines: [
            "## Your circle",
            "Your photos, captions, places, stories and tags are seen by the members of the circle you post them to, and your profile by the people who share a circle with you. Likes and holds are different: only the person who posted a photo sees who liked or held it, as faces, never as a number.",
            "When you post a photo, the people in that circle who turned on Circle Posts get a notice with your name, saying you shared a moment. It carries nothing else: not the photo, the caption or the place. People you've blocked, and people who have blocked you, don't get it.",
            "Your journal entries and reflections are never shown to anyone but you. Your answer to your circle's question of the week is sealed until that week's answers open, on Saturday at midnight UTC (Friday afternoon or evening in the United States). Then everyone in the circle can read the answers together, whether they answered or not, including anyone who joined that week. People who join later don't see the weeks before they joined.",
            "People who hold your photo keep it, and can include it when they export their memories. A copy someone has exported is outside Stanley, where we can't delete it. And as with anything you show people, someone could take a screenshot.",
            "## Services that run Stanley",
            "Beyond your circle, we share data only with the services Stanley needs to work:",
            "- Apple, to sign you in, and to deliver the notifications you've turned on (Apple carries the words of each notice to your phone). Place-name suggestions also come from Apple, on your phone",
            "- Fly.io, which hosts our server, database and photos",
            "- Sentry, which receives anonymous crash reports",
            "- PBS, the BBC and Google News, the sources of The World Today. Our server fetches their headlines; for local news it asks Google News for your town's headlines without saying who asked. Nothing else about you reaches them",
            "When you open a full news article, it loads from the publisher's own website, where their privacy policy applies.",
            "We don't share your data with advertisers, data brokers or analytics companies.",
            "## When the law requires it",
            "We may disclose information if the law requires it, or if we believe in good faith that it's needed to prevent harm to someone, to deal with fraud or abuse, or to protect Stanley and the people who use it.",
        ]),
        Section(heading: "6. Where it's stored and how it's protected", lines: [
            "Stanley's server, database and photos are in the United States, hosted by Fly.io in Chicago.",
            "- Every connection between the app and our server is encrypted with HTTPS (TLS)",
            "- Photos are never public. Each one is shown through a signed link that stops working after 15 minutes",
            "- Our database and photos are stored on an encrypted disk",
            "- Your sign-in is kept in your iPhone's Keychain, and you can lock Stanley with Face ID or Touch ID",
            "We take reasonable care to protect your data, but no system is perfectly secure. If something happens that affects your data, we'll tell you.",
        ]),
        Section(heading: "7. Children", lines: [
            "Stanley is not intended for children under 13, and you must be at least 13 to use it.",
            "We don't knowingly collect data from children under 13. If you believe a child under 13 has created an account, contact us and we will delete it.",
        ]),
        Section(heading: "8. Your rights and choices", lines: [
            "- Export: your held memories, with their captions and places and your journal entries on them, your reflections, and your answers to your circle's questions, any time from Settings → Privacy & Security → Export My Memories",
            "- Change: your name, username, bio and photo, any time, from the You tab",
            "- Delete: a journal entry or a reflection, any time, from where you read it; your account, any time, from Settings → Privacy & Security → About Your Account → Delete Account",
            "- Notifications: all three are off until you turn them on in Settings → Quiet, and you can turn them off there or in iOS Settings",
            "- Location: you can say no, or change your mind in iOS Settings. Stanley works without it; you type your own places and see national news",
            "- Ask us: for a copy of the data we hold about you, or to correct or delete something, write to us. We'll answer within 30 days",
            "California residents: we do not sell or share personal information as the California Consumer Privacy Act defines those words, and we don't use it for targeted advertising. You have the right to know what we collect, to have it corrected or deleted, and not to be treated differently for asking.",
            "If you're in the European Economic Area, the United Kingdom or Switzerland: we process your data to provide the service you signed up for, with your consent for location and notifications (which you can withdraw any time in Settings), and in our legitimate interest in keeping Stanley working and safe, such as crash reports and reviewing reports. You have the right to access, correct, delete or export your data, to restrict or object to how we use it, and to complain to your local data protection authority.",
        ]),
        Section(heading: "9. International data transfers", lines: [
            "Stanley is run from the United States. If you use it from somewhere else, your data is transferred to and processed in the United States, where data protection laws may differ from yours. Wherever you are, we protect it as this policy describes.",
        ]),
        Section(heading: "10. Changes to this policy", lines: [
            "We may update this policy as Stanley changes. When we do, we'll change the effective date at the top.",
            "If a change is material, such as collecting something new or using data in a new way, we'll tell you in the app before it takes effect.",
            "If you keep using Stanley after a change takes effect, that means you accept the updated policy. If you don't, you can delete your account at any time.",
        ]),
        Section(heading: "11. Contact", lines: [
            "Questions, requests or worries about your privacy: ayushkapileshwar@gmail.com",
            "Stanley, Bloomington, Indiana, United States",
        ]),
    ]
}

/// One legal document, set for reading: the system font, left
/// aligned, bold section headers and room between the lines, on a plain
/// white page (black in dark mode). The journal stays out of it on purpose:
/// no paper, no grain, no hand. Terms someone agrees to should look like
/// terms and read easily, as the server's pages at /terms and /privacy do.
/// The contact address is a link that opens Mail.
struct LegalDocumentView: View {
    let title: String
    let sections: [Legal.Section]
    var effective: String = Legal.effective

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Stanley")
                        .font(.subheadline.weight(.semibold))
                    Text("Effective \(effective)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.bottom, 20)
                Divider()
                ForEach(sections, id: \.self) { section in
                    VStack(alignment: .leading, spacing: 12) {
                        if let heading = section.heading {
                            Text(heading)
                                .font(.title3.weight(.bold))
                                .padding(.bottom, 2)
                        }
                        ForEach(section.lines, id: \.self) { line in
                            Self.line(line)
                        }
                    }
                    .padding(.top, 30)
                }
            }
            .font(.body)
            .lineSpacing(5)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: 680, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 48)
            .frame(maxWidth: .infinity)
        }
        .background(Color(uiColor: .systemBackground).ignoresSafeArea())
        // Links in the system's own blue, not the atmosphere's accent: on
        // Auto that's a warm charcoal no one would take for a link.
        .tint(.blue)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.large)
    }

    /// A subheading, a list item with its bullet hanging, or a paragraph.
    @ViewBuilder
    private static func line(_ line: String) -> some View {
        if line.hasPrefix("## ") {
            Text(String(line.dropFirst(3)))
                .font(.headline)
                .padding(.top, 6)
        } else if line.hasPrefix("- ") {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("•").foregroundStyle(.secondary)
                Text(linked(String(line.dropFirst(2))))
            }
        } else {
            Text(linked(line))
        }
    }

    /// The line as written, with the contact address a mailto link.
    private static func linked(_ line: String) -> AttributedString {
        var text = AttributedString(line)
        if let range = text.range(of: Legal.contact), let mail = URL(string: "mailto:\(Legal.contact)") {
            text[range].link = mail
        }
        return text
    }
}

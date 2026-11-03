"""Terms of Use and the Privacy Policy, served as plain pages at /terms and
/privacy (build 18): App Store Connect asks for a privacy policy URL, and
these are it. The app shows the same words natively (`ios/Stanley/
Legal.swift`); `tests/test_legal.py` fails if the two ever differ.

Each document is a list of sections, each a heading (or None) and its
lines. A line starting with "- " is a list item, and one starting with
"## " is a subheading within the section.

Every claim here is about what the code does. When the code changes what
it collects, keeps, shares or deletes, change the words with it, and
`PRIVACY_LABEL.md` too. No straight double quotes or backslashes in the
text: it's copied into Swift string literals verbatim.
"""
from __future__ import annotations

from html import escape

CONTACT = "ayushkapileshwar@gmail.com"
# The Terms' date. The Privacy Policy has its own since it last changed
# (November 3, 2026: the crash report's short trail of what the app did).
EFFECTIVE = "November 1, 2026"
PRIVACY_EFFECTIVE = "November 3, 2026"

PRIVACY: list[tuple[str | None, list[str]]] = [
    (
        "1. Introduction",
        [
            "Stanley is built by Ayush Kapileshwar. This policy explains what data Stanley collects, how it's used, and your rights.",
            "Stanley is a small app for small circles of people who know each other: one photo a day, seen only by your circle, fading unless someone keeps it. We've tried to collect only what that needs, and to say plainly what it is. When this policy says “we” or “us”, it means Stanley and the person who builds it.",
            "This policy covers the Stanley app for iPhone and the server it talks to. It's effective November 3, 2026.",
        ],
    ),
    (
        "2. What we collect",
        [
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
            "- Community notes you leave for your circle",
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
            "- Biometric data. If you lock Stanley with Face ID, your iPhone checks your face; Stanley only learns whether it matched",
        ],
    ),
    (
        "3. How we use your data",
        [
            "We use what we collect to run Stanley, and for nothing else:",
            "- To show your photos, stories and profile to your circle, and theirs to you",
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
        ],
    ),
    (
        "4. How long we keep it",
        [
            "Fading is the point of Stanley, and it applies to your data too.",
            "- A photo is seen for about six days, fading as it goes",
            "- If no one held it, it then becomes a tombstone, and within seven days the photo, its caption, place, likes, tags and stories are permanently deleted from our servers",
            "- A photo someone held stays with them until they let go of it or delete their account, or until the person who posted it deletes it",
            "- When someone deletes a photo they posted, its image is removed everywhere at once, including from the collections of people who held it. They keep a note that a memory was there, and the stories they wrote themselves. The person who posted a photo always has the last word",
            "- When you delete your account, we delete your data right away: your profile, your photos (including ones other people held), your stories, likes, holds, tags, notes, settings, notification tokens and circle memberships. What's left is a bare record with nothing about you in it, so that the people who held your photos see “a memory was here” instead of an error, and so that reports can still be reviewed",
            "- Our database is backed up once a day and each backup is kept for seven days, so anything deleted is gone from our backups within seven days",
            "- A notification token is deleted when you sign out on that phone, when you delete your account, or when Apple tells us it no longer works",
            "- Places you've used recently or starred are saved only on your phone, never on our servers, and are erased from your phone when you delete your account there",
            "- Headlines aren't about you. We keep each edition for about half an hour before fetching it fresh, and forget a town's headlines once no one has asked for them in a day",
        ],
    ),
    (
        "5. Who we share it with",
        [
            "## Your circle",
            "Your photos, captions, places, stories and tags are seen by the members of the circle you post them to, and your profile by the people who share a circle with you. Likes and holds are different: only the person who posted a photo sees who liked or held it, as faces, never as a number.",
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
        ],
    ),
    (
        "6. Where it's stored and how it's protected",
        [
            "Stanley's server, database and photos are in the United States, hosted by Fly.io in Chicago.",
            "- Every connection between the app and our server is encrypted with HTTPS (TLS)",
            "- Photos are never public. Each one is shown through a signed link that stops working after 15 minutes",
            "- Our database and photos are stored on an encrypted disk",
            "- Your sign-in is kept in your iPhone's Keychain, and you can lock Stanley with Face ID",
            "We take reasonable care to protect your data, but no system is perfectly secure. If something happens that affects your data, we'll tell you.",
        ],
    ),
    (
        "7. Children",
        [
            "Stanley is not intended for children under 13, and you must be at least 13 to use it.",
            "We don't knowingly collect data from children under 13. If you believe a child under 13 has created an account, contact us and we will delete it.",
        ],
    ),
    (
        "8. Your rights and choices",
        [
            "- Export: your held memories, with their captions and places, any time from Settings → Privacy & Security → Export My Memories",
            "- Change: your name, username, bio and photo, any time, from the You tab",
            "- Delete: your account, any time, from Settings → Privacy & Security → About Your Account → Delete Account",
            "- Notifications: both are off until you turn them on in Settings → Quiet, and you can turn them off there or in iOS Settings",
            "- Location: you can say no, or change your mind in iOS Settings. Stanley works without it; you type your own places and see national news",
            "- Ask us: for a copy of the data we hold about you, or to correct or delete something, write to us. We'll answer within 30 days",
            "California residents: we do not sell or share personal information as the California Consumer Privacy Act defines those words, and we don't use it for targeted advertising. You have the right to know what we collect, to have it corrected or deleted, and not to be treated differently for asking.",
            "If you're in the European Economic Area, the United Kingdom or Switzerland: we process your data to provide the service you signed up for, with your consent for location and notifications (which you can withdraw any time in Settings), and in our legitimate interest in keeping Stanley working and safe, such as crash reports and reviewing reports. You have the right to access, correct, delete or export your data, to restrict or object to how we use it, and to complain to your local data protection authority.",
        ],
    ),
    (
        "9. International data transfers",
        [
            "Stanley is run from the United States. If you use it from somewhere else, your data is transferred to and processed in the United States, where data protection laws may differ from yours. Wherever you are, we protect it as this policy describes.",
        ],
    ),
    (
        "10. Changes to this policy",
        [
            "We may update this policy as Stanley changes. When we do, we'll change the effective date at the top.",
            "If a change is material, such as collecting something new or using data in a new way, we'll tell you in the app before it takes effect.",
            "If you keep using Stanley after a change takes effect, that means you accept the updated policy. If you don't, you can delete your account at any time.",
        ],
    ),
    (
        "11. Contact",
        [
            f"Questions, requests or worries about your privacy: {CONTACT}",
            "Stanley, Bloomington, Indiana, United States",
        ],
    ),
]

TERMS: list[tuple[str | None, list[str]]] = [
    (
        "1. Introduction and acceptance",
        [
            "Welcome to Stanley. These Terms of Use are an agreement between you and Ayush Kapileshwar, who builds and runs Stanley (“Stanley”, “we”, “us”). They cover the Stanley app and the server it uses.",
            "By creating an account or using Stanley, you agree to these terms and to our Privacy Policy. If you don't agree, please don't use Stanley.",
            "You must be at least 13 years old to use Stanley. If you're under the age of majority where you live, you need a parent's or guardian's permission, and they agree to these terms for you.",
            "These terms are effective November 1, 2026.",
        ],
    ),
    (
        "2. Your account",
        [
            "- You need Sign in with Apple to create an account. It's the only way in",
            "- One account per person. Your account is yours alone: don't share it, sell it, or let anyone else use it",
            "- Keep your phone and your Apple Account secure. You can also lock Stanley with Face ID in Settings",
            "- You're responsible for what happens on your account. If you think someone else has used it, tell us",
            "- Use your own name, or the one your circle knows you by. Don't choose a name or username meant to mislead",
        ],
    ),
    (
        "3. Your content",
        [
            "“Content” means the photos, captions, stories, place names, community notes, tags and profile information you create or share on Stanley.",
            "You own your content. Stanley does not claim ownership of anything you post.",
            "To run Stanley, we need your permission to handle it. So you give us a limited, non-exclusive, royalty-free, worldwide license to store your content on our servers, to process it as needed to provide the service (resizing it, cropping it to fit, removing its metadata, and serving it), and to show it to the people Stanley shows it to: the members of the circle you posted it to, the people who hold it, and you.",
            "This license is only for running Stanley. It ends when your content is deleted: when a photo fades and no one has held it, when you delete it, or when you delete your account. Copies that people in your circle exported before then are theirs, and outside our reach.",
            "- Stanley does not use your content for AI training",
            "- Stanley does not license or sell your content to third parties",
            "- Stanley does not use your content for advertising, or show it to anyone outside your circle",
            "You promise that you have the right to share what you post, and that posting it doesn't break these terms or anyone's rights. If other people are in your photo, think about whether they'd want it shared.",
            "## Other people's content",
            "What other people post is theirs. When you hold someone's photo, or export your memories, you're keeping a copy for yourself, the way you'd keep a print a friend gave you. Don't repost it outside Stanley, or use it commercially, without their permission.",
        ],
    ),
    (
        "4. How Stanley works",
        [
            "Stanley is built on a few rules, and they're the point:",
            "- One photo per day in each circle you're in, at least 12 hours apart. If you delete today's photo, you can take it again once; deleting it a second time spends the day",
            "- Photos fade over approximately six days and then disappear, unless someone holds them",
            "- A photo you hold stays with you until you let go of it or delete your account, or until the person who posted it deletes it",
            "- Likes and holds are private: only the person who posted a photo sees who liked or held it, and Stanley never counts them",
            "- You can be in up to 5 circles, and each circle has a soft cap of 100 members",
            "- Anyone with a circle's invite code can join it, so share it only with people you'd want there. The person who started a circle can reset its code and remove members",
            "- Notifications are off until you turn them on, and there are only two",
            "These mechanics may be adjusted as we improve the service. If a change matters to how you use Stanley, we'll tell you in the app.",
        ],
    ),
    (
        "5. Community guidelines",
        [
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
        ],
    ),
    (
        "6. Content moderation",
        [
            "- We may remove content that violates these terms or our community guidelines",
            "- We may suspend or terminate accounts for violations, without notice when the situation calls for it",
            "- We review every report within 24 hours, and remove the content, the person who posted it, or both, when that's warranted",
            "- Block and report are there for your safety. Use them whenever you need to",
            "- We comply with applicable laws regarding illegal content, including reporting content that exploits children to the authorities",
            "If you think we've removed your content or account by mistake, write to us and we'll take another look.",
        ],
    ),
    (
        "7. News content",
        [
            "The World Today shows headlines, and some summaries, from third-party news sources: currently PBS News Hour, the BBC and Google News.",
            "Stanley does not create, edit, endorse or verify news content. Each source chooses its own stories, and what they say is theirs.",
            "News is provided for your convenience only. Stanley is not a news service, and we don't guarantee that any story is accurate, complete or current.",
            "A full article opens on the publisher's own website, under the publisher's terms.",
        ],
    ),
    (
        "8. Intellectual property",
        [
            "Stanley, including its name, logo, design, code, words and visual identity, is the property of Ayush Kapileshwar and is protected by copyright, trademark and other laws.",
            "We give you a personal, non-exclusive, non-transferable, revocable license to use the Stanley app on Apple devices you own or control, for your own non-commercial use, under these terms.",
            "You may not copy, modify or distribute Stanley's code or design, sell or rent any part of Stanley, or reverse engineer it, without our written permission or unless the law allows it.",
            "Don't use the Stanley name or look in a way that suggests we endorse you or anything you make.",
            "If you send us ideas or feedback, we may use them without owing you anything. Thank you for them.",
        ],
    ),
    (
        "9. Termination",
        [
            "You can delete your account at any time, in Settings → Privacy & Security → About Your Account → Delete Account.",
            "We may suspend or terminate accounts that violate these terms, when the law requires it, or to protect other people. If we terminate your account for a violation, please don't make a new one without our permission. We may also stop offering Stanley altogether; if we do, we'll tell you in the app first and give you time to export your held memories.",
            "When an account is deleted, for whatever reason, its content is deleted right away, and from our backups within seven days.",
            "That includes copies of its photos held by other people: when the person who posted a photo deletes it, it's removed everywhere. The people who held it keep a note that a memory was there, and the stories they wrote themselves.",
            "Sections 8 and 10 through 17 continue to apply after your account ends.",
        ],
    ),
    (
        "10. Disclaimer of warranties",
        [
            "Stanley is provided “as is” and “as available”. To the fullest extent the law allows, we disclaim all warranties, express or implied, including warranties of merchantability, fitness for a particular purpose and non-infringement.",
            "We do not guarantee that Stanley will be uninterrupted, secure or error-free, or that content will never be lost. Photos fade by design; if one matters to you, hold it.",
            "We do not guarantee the accuracy of news content, and we're not responsible for content posted by other users, or for what they say or do.",
            "Some places don't allow these disclaimers, so some of them may not apply to you.",
        ],
    ),
    (
        "11. Limitation of liability",
        [
            "To the maximum extent permitted by law, Stanley and its creator are not liable for any indirect, incidental, special, consequential or punitive damages, or for any loss of data, photos, profits or goodwill, arising from or related to your use of Stanley, even if we were told such damages were possible.",
            "Our total liability for any claim about Stanley is limited to the amount you paid for Stanley in the twelve months before the claim. Stanley is free, so that amount is currently $0.",
            "Nothing in these terms limits liability that the law doesn't allow to be limited.",
        ],
    ),
    (
        "12. Indemnification",
        [
            "You agree to defend, indemnify and hold harmless Stanley and its creator from any claims, damages, losses and costs (including reasonable legal fees) arising from your use of Stanley, your content, or your violation of these terms or of anyone else's rights.",
        ],
    ),
    (
        "13. Governing law",
        [
            "These terms are governed by the laws of the State of Indiana, United States, without regard to its conflict of law rules.",
            "Any dispute about Stanley or these terms will be resolved in the courts of Monroe County, Indiana, and you and we both agree to their jurisdiction.",
            "If the consumer laws where you live give you the right to bring a claim in your own courts or under your own laws, nothing in these terms takes that right away.",
        ],
    ),
    (
        "14. Changes to these terms",
        [
            "We may update these terms. When we do, we'll change the effective date at the top.",
            "If a change is material, we'll tell you in the app before it takes effect.",
            "If you keep using Stanley after a change takes effect, that means you accept the updated terms. If you don't, you can delete your account at any time.",
        ],
    ),
    (
        "15. Severability",
        [
            "If any provision of these terms is found unenforceable, it will be enforced as far as it can be, and the rest of these terms remain in full effect.",
            "If we don't enforce part of these terms right away, we haven't given up the right to enforce it later.",
        ],
    ),
    (
        "16. Entire agreement",
        [
            "These terms and the Privacy Policy are the entire agreement between you and Stanley about Stanley, and they replace anything said before. No other promises or representations apply.",
            "You can't transfer your rights under these terms to anyone else. We may transfer ours, for example if Stanley moves to a new owner, and these terms will continue to protect you.",
        ],
    ),
    (
        "17. Apple",
        [
            "Stanley is distributed through Apple's App Store, so a few things about Apple apply:",
            "- These terms are between you and us, not Apple. We, not Apple, are responsible for Stanley and its content",
            "- Apple has no obligation to provide maintenance or support for Stanley",
            "- If Stanley fails to meet a warranty that applies to it, you may notify Apple, and Apple will refund its purchase price, which is $0. Apple has no other warranty obligation for Stanley",
            "- Apple is not responsible for any claims relating to Stanley, including product liability claims, claims that Stanley fails to meet a legal or regulatory requirement, claims under consumer protection or privacy laws, and claims that Stanley infringes someone's intellectual property. We are responsible for dealing with those",
            "- You confirm that you're not in a country under a United States government embargo, and not on any United States government list of prohibited or restricted parties",
            "- You must also follow the App Store's own terms when you use Stanley",
            "- Apple and its subsidiaries are third-party beneficiaries of these terms, and once you accept them, Apple has the right to enforce them against you",
        ],
    ),
    (
        "18. Contact",
        [
            f"Questions about these terms, or something to report: {CONTACT}",
            "Stanley, Bloomington, Indiana, United States",
        ],
    ),
]


# The web pages are set for reading, not in the app's journal look: these
# are the URLs App Store Connect links, and terms someone agrees to should
# look like terms. A white page, a 680px column, the system's sans-serif at
# 16px, bold headings, the effective date under the title, the contact
# address as a mailto link, and nothing fetched from anywhere else.
STYLE = """
:root { color-scheme: light; }
* { box-sizing: border-box; }
html { -webkit-text-size-adjust: 100%; text-size-adjust: 100%; }
body { margin: 0; background: #ffffff; color: #1d1d1f;
       font: 16px/1.65 -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif; }
main { max-width: 680px; margin: 0 auto; padding: 48px 24px 72px; }
header { padding-bottom: 28px; margin-bottom: 8px; border-bottom: 1px solid #e5e5ea; }
.brand { margin: 0 0 20px; font-size: 15px; font-weight: 700; letter-spacing: .02em; }
h1 { margin: 0; font-size: 32px; line-height: 1.2; font-weight: 700; letter-spacing: -.01em; }
.effective { margin: 8px 0 0; color: #6e6e73; font-size: 15px; }
h2 { margin: 40px 0 12px; font-size: 21px; line-height: 1.3; font-weight: 700; }
h3 { margin: 28px 0 8px; font-size: 17px; line-height: 1.35; font-weight: 700; }
p { margin: 0 0 14px; }
ul { margin: 0 0 16px; padding-left: 22px; }
li { margin: 0 0 8px; padding-left: 2px; }
a { color: #0066cc; text-decoration: none; overflow-wrap: anywhere; }
a:hover, a:focus { text-decoration: underline; }
footer { margin-top: 48px; padding-top: 24px; border-top: 1px solid #e5e5ea; color: #6e6e73; font-size: 15px; }
footer p { margin: 0 0 6px; }
@media (max-width: 480px) {
  main { padding: 32px 20px 56px; }
  h1 { font-size: 28px; }
  h2 { font-size: 19px; margin-top: 32px; }
}
"""


def _linked(text: str) -> str:
    """A line made safe for HTML, with the contact address as a mailto link."""
    safe = escape(text)
    return safe.replace(escape(CONTACT), f'<a href="mailto:{CONTACT}">{escape(CONTACT)}</a>')


def page(title: str, sections: list[tuple[str | None, list[str]]], effective: str = EFFECTIVE) -> str:
    """A plain, readable page: no scripts, no trackers, no external assets."""
    parts: list[str] = []
    for heading, lines in sections:
        if heading:
            parts.append(f"<h2>{escape(heading)}</h2>")
        items: list[str] = []
        for line in lines + [""]:
            if line.startswith("- "):
                items.append(f"<li>{_linked(line[2:])}</li>")
                continue
            if items:
                parts.append("<ul>" + "".join(items) + "</ul>")
                items = []
            if line.startswith("## "):
                parts.append(f"<h3>{escape(line[3:])}</h3>")
            elif line:
                parts.append(f"<p>{_linked(line)}</p>")
    body = "\n".join(parts)
    return f"""<!doctype html>
<html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{escape(title)} · Stanley</title>
<style>{STYLE}</style></head>
<body>
<main>
<header>
<p class="brand">Stanley</p>
<h1>{escape(title)}</h1>
<p class="effective">Effective {escape(effective)}</p>
</header>
{body}
<footer>
<p>Questions: <a href="mailto:{CONTACT}">{escape(CONTACT)}</a></p>
<p><a href="/terms">Terms of Use</a> · <a href="/privacy">Privacy Policy</a></p>
</footer>
</main>
</body></html>"""

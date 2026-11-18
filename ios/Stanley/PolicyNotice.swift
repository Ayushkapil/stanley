import Foundation

/// The notice that the Privacy Policy changed (build 70). The policy's
/// section 10 promises material changes are told "in the app before it
/// takes effect", and until now nothing in the app did it.
///
/// A sheet comes up once when the policy's date is newer than the one this
/// phone last acknowledged, with what changed since, written plainly, a way
/// to the whole policy, and one button to acknowledge it. The acknowledged
/// date is kept on the phone (`key`).
///
/// - Signing in agrees to the policy as it stands (Welcome says so), so a
///   sign-in acknowledges the current date and shows nothing.
/// - Someone already signed in when this build arrives has acknowledged
///   nothing. They're taken to have read the policy build 40 carried
///   (November 12, the last build uploaded before this notice), so they're
///   told everything since.
///
/// Each change of the policy adds a `Revision` here, newest last, with its
/// date exactly as `Legal.privacyEffective` writes it (a test holds the two
/// together).
enum PolicyNotice {
    struct Revision: Equatable {
        /// The day it took effect, as yyyy-MM-dd (they sort as strings).
        let day: String
        /// The same day as the policy writes it ("November 15, 2026").
        let title: String
        /// What changed, a line each, in plain words.
        let changes: [String]
    }

    static let key = "stanley.privacyAcknowledged"

    /// What someone signed in from before the notice existed is taken to
    /// have read: the policy in build 40.
    static let assumedRead = "2026-11-12"

    static let revisions: [Revision] = [
        Revision(day: "2026-11-13", title: "November 13, 2026", changes: [
            "You can write your circle one unsigned letter a month. Your circle never sees who wrote it. Our server keeps who wrote each one, so you can change or delete yours and so a reported letter can be reviewed. A month's letters open together when it ends and are deleted seven days later.",
        ]),
        Revision(day: "2026-11-14", title: "November 14, 2026", changes: [
            "Your journal: the pages you write are kept for you alone, unless you choose to share a page with your circle or with one person in it.",
            "A heart left on a shared page is shown only to the page's writer, and never counted.",
            "The Journal widget keeps the opening lines of your last few days' pages on your phone, and nowhere else.",
            "Written to You: when someone writes you a page or sends you a letter, you're told with their name. It's on until you turn it off in Settings → Quiet.",
        ]),
        Revision(day: "2026-11-15", title: "November 15, 2026", changes: [
            "The mark you may leave on your day can be set only on that day, is seen by no one but you, and stays when a photo from that day is deleted.",
        ]),
        Revision(day: "2026-11-16", title: "November 16, 2026", changes: [
            "You can choose a photo from your phone for your own journal's cover. It's kept on our server for you alone, without its location or any other details, until you choose another, put the automatic cover back, or delete your account.",
        ]),
        Revision(day: "2026-11-17", title: "November 17, 2026", changes: [
            "Photos you've seen, and profile photos, are kept on your phone so they open without downloading again. Each is erased a day after you last saw it, and all of them when you sign out.",
        ]),
    ]

    static var current: Revision { revisions[revisions.count - 1] }

    /// What changed since `acknowledged` (nil: since what build 40 carried),
    /// newest first. Empty when there's nothing to tell.
    static func unread(acknowledged: String?) -> [Revision] {
        let since = acknowledged ?? assumedRead
        return revisions.filter { $0.day > since }.reversed()
    }

    /// Whether the sheet is due.
    static func due(acknowledged: String?) -> Bool { !unread(acknowledged: acknowledged).isEmpty }

    static func acknowledged(in defaults: UserDefaults = .standard) -> String? {
        defaults.string(forKey: key)
    }

    /// Acknowledge the policy as it stands: from the sheet's button, or by
    /// signing in.
    static func acknowledge(in defaults: UserDefaults = .standard) {
        defaults.set(current.day, forKey: key)
    }
}

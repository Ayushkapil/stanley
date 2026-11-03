import Sentry

/// The short trail a crash report carries (the production audit, November
/// 2026): the last few things the app did before it crashed, so a crash can
/// be read as "after posting a photo, in Held" rather than a bare stack.
///
/// Fixed words only, from this list. Never an id, a name, a caption, a story,
/// a place, a URL or anything someone wrote, so the report stays anonymous
/// (PRIVACY_LABEL.md, Privacy Policy section 2). Sentry keeps the trail on
/// the phone and sends it only inside a crash report, and only in a build
/// with a DSN; in every other build `SentrySDK.isEnabled` is false and this
/// does nothing. Sentry's own automatic trail (taps, screens, network
/// requests with their URLs) is off in `StanleyApp`.
enum Trail {
    enum Step: String {
        case signedIn = "signed in"
        case signedOut = "signed out"
        case refreshedSignIn = "refreshed the sign-in"
        case openedToday = "opened Today"
        case openedHeld = "opened Held"
        case openedYou = "opened You"
        case openedWorld = "opened World"
        case openedSettings = "opened Settings"
        case openedCamera = "opened the camera"
        case postedPhoto = "posted a photo"
        case keptPhotoForLater = "kept a photo to post later"
        case deletedPhoto = "deleted a photo"
        case held = "held a photo"
        case letGo = "let go of a photo"
        case liked = "liked a photo"
        case unliked = "unliked a photo"
        case addedStory = "added a story"
        case leftNote = "left the circle a note"
        case switchedCircle = "switched circles"
        case startedCircle = "started a circle"
        case joinedCircle = "joined a circle"
        case leftCircle = "left a circle"
        case reported = "reported something"
        case blocked = "blocked someone"
        case loadedMoreToday = "loaded more of Today"
        case wentOffline = "lost the connection"
        case cameBack = "reached Stanley again"
        case renewedLinks = "renewed photo links"
        // Build 26. What was done, never what was written.
        case wroteJournal = "wrote in the journal"
        case wroteReflection = "wrote a reflection"
        case answeredQuestion = "answered the circle's question"
        case openedCircleJournal = "opened the circle journal"
    }

    static func note(_ step: Step) {
        guard SentrySDK.isEnabled else { return }
        let crumb = Breadcrumb(level: .info, category: "stanley")
        crumb.message = step.rawValue
        SentrySDK.addBreadcrumb(crumb)
    }
}

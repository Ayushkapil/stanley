import Foundation

/// When Stanley asks to notify you (build 61, from the brief "Move the
/// notification permission request"). iOS asks once, ever, and a refusal is
/// for good, so it's asked at the first moment the value is concrete, and
/// never on launch or on opening a tab:
///
/// - the first time you come upon a letter or a page written to you (in
///   Letters, or a page for you in a circle's journal), or
/// - the first time you send a letter or write a page to one person.
///
/// Before iOS's own prompt, a soft sheet of Stanley's says what the notices
/// are, with Continue and Not now. Only Continue calls iOS. Not now is asked
/// again at the next such moment, at most twice more, and then never.
///
/// Pure: what happened, in; whether to offer, out. Kept per account by
/// `AppState`. Its tests are in `StanleyTests`.
struct AskToNotify: Codable, Equatable {
    /// How many times Not now may be followed by another offer.
    static let reAsks = 2
    /// The one line on the sheet.
    static let line = "Stanley only notifies you when someone writes to you directly."

    /// How many times Not now was chosen.
    private(set) var notNow = 0
    /// Continue was chosen: iOS has been asked, and Stanley never asks again.
    private(set) var continued = false
    /// Letters and pages written to you that have already been a moment, so
    /// that coming upon the same one again isn't a new moment.
    private(set) var seen: Set<String> = []

    /// Whether the sheet may be offered at a moment: iOS hasn't been asked,
    /// Written to You is on, Continue hasn't been chosen, and Not now hasn't
    /// used up its two re-asks.
    func offers(iosUndecided: Bool, switchOn: Bool) -> Bool {
        iosUndecided && switchOn && !continued && notNow <= Self.reAsks
    }

    /// You came upon these things written to you: a moment if any of them
    /// is new. All are remembered.
    mutating func cameUpon<S: Sequence>(_ ids: S) -> Bool where S.Element == String {
        let fresh = Set(ids).subtracting(seen)
        seen.formUnion(fresh)
        return !fresh.isEmpty
    }

    mutating func choseNotNow() { notNow += 1 }
    mutating func choseContinue() { continued = true }
}

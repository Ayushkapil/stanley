import SwiftUI
import UIKit

/// The dark room (build 24). In dark mode Stanley stops being a journal at
/// night, which pilot users kept calling bad, and is a photo gallery in a
/// dark room: pure black, no paper and no grain; a photo is the card, with
/// no frame, no print and no lean; the words in a warm white rather than a
/// stark one; the rules a gray that is barely there. Only the tab bar and
/// the accents keep the atmosphere. Light mode keeps the journal, untouched.
enum DarkRoom {
    /// The words: warm white in the dark; in daylight the label color, so
    /// nothing in light mode moves.
    static let ink = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 240 / 255, green: 235 / 255, blue: 227 / 255, alpha: 1)   // #F0EBE3
            : .label
    })

    /// A rule's gray in the dark: #2A2A2A, barely there.
    private static let ruleGray = UIColor(red: 42 / 255, green: 42 / 255, blue: 42 / 255, alpha: 1)

    /// A line of ink at `opacity` in daylight; in the dark, the rule gray at
    /// whatever weight, since the dark room draws every rule the same.
    static func line(_ opacity: CGFloat) -> Color {
        Color(UIColor { traits in
            traits.userInterfaceStyle == .dark ? ruleGray : UIColor.label.withAlphaComponent(opacity)
        })
    }

    /// A photo on black, cut with a small radius so it reads as a card.
    static let photoCorner: CGFloat = 4

    /// Whether the view is in the dark room: dark mode, as resolved for it.
    static func isDark(_ scheme: ColorScheme) -> Bool { scheme == .dark }
}

/// Photo paper: warm white in daylight; in the dark a step down, as if under
/// a lamp (the sticky note does the same). Since build 24 the dark room
/// hangs photos without paper, so the dark value is only seen on the note.
enum PrintStock {
    static let paper = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.74, green: 0.71, blue: 0.66, alpha: 1)
            : UIColor(red: 1.00, green: 0.99, blue: 0.97, alpha: 1)
    })
    /// Inside a print's border the photo's own corners are barely rounded:
    /// a print is cut, not molded.
    static let photoCorner: CGFloat = 1.5
}

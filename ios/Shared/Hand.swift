import SwiftUI
import UIKit

extension Font {
    /// Stanley's own voice for names and page titles: SF Rounded, warm and
    /// a little informal, the way a name is written on a page someone keeps.
    /// It was a serif until build 19; serif now belongs to the World tab
    /// alone (the morning paper), so personal pages and the paper never read
    /// as the same thing.
    static func keepsake(_ size: CGFloat, weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }

    /// A page's name atop it: SF Rounded, medium (Today's circle, You).
    static var pageTitle: Font { .system(.largeTitle, design: .rounded).weight(.medium) }
    /// A section's name: SF Rounded, semibold.
    static var sectionTitle: Font { .system(.title3, design: .rounded).weight(.semibold) }

    /// Handwriting, for the words that are a person's own hand on the page:
    /// their note, their journal, their letter, the caption on their own
    /// photo. Never a label, a button, someone else's name or a time (the
    /// Quiet Warmth pass, build 44). Noteworthy is built into iOS; the
    /// system's rounded face stands in if it's ever missing. Scales with
    /// Dynamic Type from `size`.
    static func hand(_ size: CGFloat, bold: Bool = false, relativeTo style: Font.TextStyle = .body) -> Font {
        let name = bold ? "Noteworthy-Bold" : "Noteworthy-Light"
        if UIFont(name: name, size: size) != nil {
            return .custom(name, size: size, relativeTo: style)
        }
        return .system(style, design: .rounded).weight(bold ? .semibold : .regular)
    }
}

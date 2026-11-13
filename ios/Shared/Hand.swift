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

    /// Handwriting, for the words that are a person's own hand on the page:
    /// a name on a photo, a sticky note. Noteworthy is built into iOS; the
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

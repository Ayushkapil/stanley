import SwiftUI
import UIKit

// The journal as a book (build 45): its three inks and its paper, shared by
// the app and the Journal widget so a page looks the same in both.

/// The ink a page is written in. Chosen per page; the last one used is the
/// next page's to start with.
enum Ink: String, CaseIterable, Codable, Identifiable {
    case black, blue, red

    var id: String { rawValue }

    /// An unknown ink (a newer server's) reads as black.
    static func named(_ raw: String?) -> Ink { raw.flatMap(Ink.init(rawValue:)) ?? .black }

    var name: String {
        switch self {
        case .black: "Black"
        case .blue: "Blue"
        case .red: "Red"
        }
    }

    /// On the dark page black ink would be lost, so it's the warm white the
    /// rest of the dark room writes in, and the blue and red are lifted.
    func uiColor(dark: Bool) -> UIColor {
        switch (self, dark) {
        case (.black, false): UIColor(red: 0.102, green: 0.102, blue: 0.102, alpha: 1)   // #1A1A1A
        case (.blue, false): UIColor(red: 0.169, green: 0.298, blue: 0.494, alpha: 1)    // #2B4C7E
        case (.red, false): UIColor(red: 0.608, green: 0.173, blue: 0.173, alpha: 1)     // #9B2C2C
        case (.black, true): UIColor(red: 0.941, green: 0.922, blue: 0.890, alpha: 1)    // #F0EBE3
        case (.blue, true): UIColor(red: 0.482, green: 0.639, blue: 0.851, alpha: 1)     // #7BA3D9
        case (.red, true): UIColor(red: 0.878, green: 0.522, blue: 0.522, alpha: 1)      // #E08585
        }
    }

    /// The ink for whichever room it's drawn in.
    var ui: UIColor {
        UIColor { self.uiColor(dark: $0.userInterfaceStyle == .dark) }
    }

    var color: Color { Color(ui) }
}

/// The book's paper. Warm cream in daylight; in the dark a very dark
/// charcoal, not the dark room's black, so a page still reads as paper.
enum BookPaper {
    private static let day = UIColor(red: 0.988, green: 0.968, blue: 0.921, alpha: 1)     // #FCF7EB
    private static let night = UIColor(red: 0.078, green: 0.078, blue: 0.078, alpha: 1)   // #141414

    static let pageUI = UIColor { $0.userInterfaceStyle == .dark ? night : day }
    static let page = Color(pageUI)

    /// The ruled lines: very faint in daylight, not there in the dark.
    static let ruleUI = UIColor {
        $0.userInterfaceStyle == .dark
            ? .clear
            : UIColor(red: 0.16, green: 0.14, blue: 0.11, alpha: 0.10)
    }
    static let rule = Color(ruleUI)

    /// What's printed on the page and isn't the writer's ink: a page
    /// number, a week's dates.
    static let quietUI = UIColor {
        $0.userInterfaceStyle == .dark
            ? UIColor(red: 0.42, green: 0.40, blue: 0.376, alpha: 1)    // #6B6560
            : UIColor(red: 0.541, green: 0.522, blue: 0.502, alpha: 1)  // #8A8580
    }
    static let quiet = Color(quietUI)

    /// The cover: a deeper cream card in daylight, deep charcoal in the dark.
    static let cover = Color(UIColor {
        $0.userInterfaceStyle == .dark
            ? UIColor(red: 0.149, green: 0.141, blue: 0.129, alpha: 1)  // #262421
            : UIColor(red: 0.945, green: 0.910, blue: 0.835, alpha: 1)  // #F1E8D5
    })
    /// What's written on the cover.
    static let coverInk = Color(UIColor {
        $0.userInterfaceStyle == .dark
            ? UIColor(red: 0.941, green: 0.922, blue: 0.890, alpha: 1)
            : UIColor(red: 0.20, green: 0.17, blue: 0.13, alpha: 1)
    })
}

/// The hand a page is written in, as UIKit needs it: the app lays a page
/// out with TextKit so the words sit on the ruled lines, and breaks a long
/// day across pages the same way it draws them.
enum BookHand {
    static func font(_ size: CGFloat, bold: Bool = false) -> UIFont {
        UIFont(name: bold ? "Noteworthy-Bold" : "Noteworthy-Light", size: size)
            ?? .systemFont(ofSize: size, weight: bold ? .semibold : .regular)
    }
}

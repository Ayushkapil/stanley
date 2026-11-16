import Foundation

/// The warm field a journal with no cover photo is drawn on, worked out as
/// numbers (build 69), so the words on it can take the ink the field asks
/// for: near-black on a light field, the warm off-white on a dark one. The
/// title on a light field was always the off-white until now, and on the
/// caramel field by day it was about 1.4:1.
///
/// Foundation only, so the unit tests compile it alone. `CoverTone` (in
/// `Atmosphere.swift`) draws the field from these same numbers, and
/// `CoverCard` (in `JournalCovers.swift`) asks `ink(for:dark:)` which ink
/// to write in.
enum CoverField {
    /// A colour as the screen draws it: gamma-encoded sRGB, 0 to 1.
    struct RGB: Equatable {
        var r: Double
        var g: Double
        var b: Double

        init(r: Double, g: Double, b: Double) {
            self.r = r
            self.g = g
            self.b = b
        }

        init(_ hex: UInt32) {
            r = Double((hex >> 16) & 0xFF) / 255
            g = Double((hex >> 8) & 0xFF) / 255
            b = Double(hex & 0xFF) / 255
        }

        /// `colour` laid over this at `alpha`, blended as the screen blends
        /// layers (in the encoded values, not light).
        func under(_ colour: RGB, _ alpha: Double) -> RGB {
            RGB(r: r + (colour.r - r) * alpha, g: g + (colour.g - g) * alpha, b: b + (colour.b - b) * alpha)
        }

        /// Relative luminance, as WCAG measures it.
        var luminance: Double {
            func light(_ c: Double) -> Double { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
            return 0.2126 * light(r) + 0.7152 * light(g) + 0.0722 * light(b)
        }

        /// The contrast ratio between this and `other`, 1 to 21.
        func contrast(with other: RGB) -> Double {
            let (a, b) = (luminance, other.luminance)
            return (max(a, b) + 0.05) / (min(a, b) + 0.05)
        }
    }

    /// Which ink the words on the field are written in.
    enum Ink: Equatable {
        /// The words' near-black (`TextTone.primary` by day), on a light field.
        case dark
        /// The warm off-white words on a photo have, on a dark field.
        case light
    }

    // The field's layers, bottom to top, as `CoverCard` draws them.

    /// The ground: a caramel by day, a brown at night.
    static func ground(dark: Bool) -> UInt32 { dark ? 0x402B1F : 0xCC946B }
    /// The journal's own warmth over it, at this much.
    static func wash(dark: Bool) -> Double { dark ? 0.22 : 0.18 }
    /// Light from the top left, fading to nothing at the bottom right.
    static let lightTone: UInt32 = 0xFFD199
    static func lightAlpha(dark: Bool) -> Double { dark ? 0.22 : 0.55 }
    /// A little deeper from the middle down.
    static let deepTone: UInt32 = 0x593324
    static func deepAlpha(dark: Bool) -> Double { dark ? 0.35 : 0.3 }
    /// The dark under the words at the card's head and foot, for words in
    /// the off-white: black at this much at the edge, gone this far in.
    static let scrimHead = 0.38
    static let scrimHeadReach = 0.42
    static let scrimFoot = 0.5
    static let scrimFootReach = 0.26
    /// The slab's glass: white at this much.
    static func slab(dark: Bool) -> Double { dark ? 0.08 : 0.2 }
    /// The sheen across the slab's top left: the off-white at this much,
    /// gone by this point.
    static let sheen = 0.4
    static let sheenEnd = (x: 0.45, y: 0.35)

    /// The inks.
    static let offWhite = RGB(0xF2EADC)
    static let nearBlack = RGB(0x1A1A1A)
    /// Small capitals and the foot's line in near-black: this much of it.
    /// (The off-white's are at 70% over their own shade, `CoverTone`.)
    /// 0.85 is the least that keeps 4.5:1 on the lightest and the darkest
    /// field the generator makes.
    static let darkLabel = 0.85

    /// The card's shape (it's always held to it).
    static let aspect = (width: 290.0, height: 416.0)

    /// A journal's own warmth, the same every time for the same journal: a
    /// stable hash of its id (FNV-1a, never Swift's `hashValue`, which
    /// changes each launch), kept to reds, oranges and ambers.
    static func warmthHSB(_ id: String) -> (hue: Double, saturation: Double, brightness: Double) {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in id.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        let hue = 0.03 + Double(hash % 1000) / 1000 * 0.09
        let saturation = 0.5 + Double((hash >> 16) % 100) / 100 * 0.18
        let brightness = 0.78 + Double((hash >> 32) % 100) / 100 * 0.12
        return (hue, saturation, brightness)
    }

    /// The same, as a colour.
    static func warmth(_ id: String) -> RGB {
        let (h, s, v) = warmthHSB(id)
        return rgb(hue: h, saturation: s, brightness: v)
    }

    /// Hue, saturation and brightness to a colour, as SwiftUI's
    /// `Color(hue:saturation:brightness:)` does.
    static func rgb(hue: Double, saturation s: Double, brightness v: Double) -> RGB {
        let h = (hue - floor(hue)) * 6
        let i = Int(h) % 6
        let f = h - floor(h)
        let p = v * (1 - s), q = v * (1 - s * f), t = v * (1 - s * (1 - f))
        switch i {
        case 0: return RGB(r: v, g: t, b: p)
        case 1: return RGB(r: q, g: v, b: p)
        case 2: return RGB(r: p, g: v, b: t)
        case 3: return RGB(r: p, g: q, b: v)
        case 4: return RGB(r: t, g: p, b: v)
        default: return RGB(r: v, g: p, b: q)
        }
    }

    /// What the card shows at a point (in the card's own 0-to-1 space):
    /// the field, with the scrims for the off-white or without them, and
    /// the slab's glass and sheen over it.
    static func colour(warmth: RGB, dark: Bool, x: Double, y: Double, scrims: Bool) -> RGB {
        let (w, h) = (aspect.width, aspect.height)
        var c = RGB(ground(dark: dark)).under(warmth, wash(dark: dark))
        // Light from the top left to the bottom right, along the card's
        // diagonal.
        let along = (x * w * w + y * h * h) / (w * w + h * h)
        c = c.under(RGB(lightTone), lightAlpha(dark: dark) * (1 - min(max(along, 0), 1)))
        if y > 0.5 { c = c.under(RGB(deepTone), deepAlpha(dark: dark) * (y - 0.5) / 0.5) }
        if scrims {
            if y < scrimHeadReach { c = c.under(RGB(0), scrimHead * (1 - y / scrimHeadReach)) }
            if y > 1 - scrimFootReach { c = c.under(RGB(0), scrimFoot * (y - (1 - scrimFootReach)) / scrimFootReach) }
        }
        c = c.under(RGB(0xFFFFFF), slab(dark: dark))
        let (sx, sy) = (sheenEnd.x * w, sheenEnd.y * h)
        let sheenAt = (x * w * sx + y * h * sy) / (sx * sx + sy * sy)
        if sheenAt < 1 { c = c.under(offWhite, sheen * (1 - max(sheenAt, 0))) }
        return c
    }

    /// Where the title sits on the card: from the inset to near the right
    /// edge, from under the small capitals down three lines of the hand.
    static let titleArea: [(x: Double, y: Double)] = [0.09, 0.3, 0.5, 0.7, 0.9].flatMap { x in
        [0.12, 0.2, 0.3, 0.4].map { (x, $0) }
    }
    /// Where the small capitals sit: the place at the head, the dates and
    /// "Vol. I" at the foot.
    static let labelArea: [(x: Double, y: Double)] =
        [0.09, 0.2, 0.35, 0.5].map { ($0, 0.07) } + [0.09, 0.25, 0.75, 0.91].map { ($0, 0.93) }

    /// The ink for a journal's field, from the field's luminance under
    /// the title: the mean luminance under where it sits, as each ink would
    /// have it drawn (the off-white over the scrims, near-black without
    /// them), and whichever ink stands further from that. The mean, not the
    /// least: the sheen leaves the very top left light at night, and a
    /// brown field isn't a light one for that corner.
    static func ink(for id: String, dark: Bool) -> Ink {
        ink(warmth: warmth(id), dark: dark)
    }

    static func ink(warmth: RGB, dark: Bool) -> Ink {
        func mean(scrims: Bool) -> Double {
            let all = titleArea.map { colour(warmth: warmth, dark: dark, x: $0.x, y: $0.y, scrims: scrims).luminance }
            return all.reduce(0, +) / Double(all.count)
        }
        let underOffWhite = mean(scrims: true), underNearBlack = mean(scrims: false)
        let offWhiteStands = (offWhite.luminance + 0.05) / (underOffWhite + 0.05)
        let nearBlackStands = (underNearBlack + 0.05) / (nearBlack.luminance + 0.05)
        return nearBlackStands > offWhiteStands ? .dark : .light
    }
}

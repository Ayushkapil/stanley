import SwiftUI
import UIKit
import WidgetKit

// The home screen widget's three sizes (build 40), drawn from a
// `WidgetSnapshot` at a moment. A corner of Stanley left on the home screen,
// in the app's own look (Quiet Warmth, build 44): the flat warm-white page
// or the dark room's black, photos cut straight with nothing round them,
// system type for names and labels, and a hand only where someone wrote
// (the day's slip, a note from the board). Until build 44 it was grained
// paper, tilted prints on photo paper, and the hand throughout. Nothing
// here reaches the network or counts anything.
//
// These views are in `Shared` so a Debug build of the app can lay the three
// sizes out on one screen to be looked at (`WidgetGallery`); the widget
// extension is what puts them on the home screen.

/// Which of the three.
enum WidgetSize {
    case small, medium, large
}

/// The page the widget is drawn on: the atmosphere's floor, flat (grained
/// paper until build 44), or the dark room's black.
struct WidgetBackdrop: View {
    let atmosphere: String

    var body: some View {
        Atmosphere.resolve(atmosphere).palette.floor
            .accessibilityHidden(true)
    }
}

/// The widget itself, at one size.
struct StanleyWidgetView: View {
    @Environment(\.colorScheme) private var colorScheme
    let snapshot: WidgetSnapshot
    let date: Date
    let size: WidgetSize

    private var dark: Bool { colorScheme == .dark }
    private var palette: Atmosphere.Palette { Atmosphere.resolve(snapshot.atmosphere).palette }
    private var ink: Color { DarkRoom.ink }
    /// Small capitals and asides. On paper the ink is held back less than
    /// in the dark room: gray on cream loses more than gray on black.
    private var quiet: Color { DarkRoom.ink.opacity(dark ? 0.55 : 0.7) }
    /// A whole sentence the widget says when it has nothing to show. It's
    /// the only thing to read there, so on paper it's close to full ink.
    private var said: Color { DarkRoom.ink.opacity(dark ? 0.55 : 0.85) }
    private var phase: Countdown.Phase? { snapshot.phase(at: date) }
    private var note: WidgetSnapshot.Note? { snapshot.note(at: date) }

    /// The photos to show, with their pictures in hand: one whose file has
    /// gone isn't a blank print, it just isn't there.
    private var prints: [(shot: WidgetSnapshot.Shot, image: UIImage)] {
        snapshot.photos(at: date).compactMap { shot in
            guard let url = WidgetStore.photo(shot.file), let image = UIImage(contentsOfFile: url.path)
            else { return nil }
            return (shot, image)
        }
    }

    var body: some View {
        Group {
            if !snapshot.signedIn || snapshot.circleName == nil {
                welcome
            } else {
                switch size {
                case .small: small
                case .medium: medium
                case .large: large
                }
            }
        }
        .foregroundStyle(ink)
    }

    // MARK: nobody here yet

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Stanley")
                .font(.uiFixed(size == .small ? 23 : 26, .semibold))
            Text(snapshot.signedIn ? "Join a circle to begin." : "Open Stanley to see your circle.")
                .font(.uiFixed(13.5))
                .foregroundStyle(said)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            rule
            caps("One day, one photo")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: small

    /// The day's countdown note if the circle has one running; otherwise the
    /// circle's name, and whether today's photo is up.
    @ViewBuilder
    private var small: some View {
        if let phase {
            VStack(alignment: .leading, spacing: 0) {
                if let reminder = phase.reminder {
                    slip(reminder, lines: 4)
                        .padding(.top, 6)
                    Spacer(minLength: 6)
                } else {
                    mark(phase)
                        .padding(.top, 2)
                    Spacer(minLength: 4)
                }
                Text(phase.text)
                    .font(.uiFixed(phase.reminder == nil ? 17 : 14, .semibold))
                    .lineLimit(phase.reminder == nil ? 3 : 2)
                    .minimumScaleFactor(0.75)
                    .fixedSize(horizontal: false, vertical: true)
                caps(snapshot.circleName ?? "")
                    .padding(.top, 3)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel([phase.reminder, phase.text].compactMap { $0 }.joined(separator: ". "))
        } else {
            VStack(alignment: .leading, spacing: 0) {
                Text(snapshot.circleName ?? "")
                    .font(.uiFixed(22, .semibold))
                    .lineLimit(2)
                    .minimumScaleFactor(0.6)
                    .fixedSize(horizontal: false, vertical: true)
                rule.padding(.top, 6)
                caps(date.formatted(.dateTime.weekday(.wide).day().month(.abbreviated)))
                    .padding(.top, 5)
                Spacer(minLength: 4)
                status
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    // MARK: medium

    /// A print on the left, yours if you have one in the light; on the
    /// right the countdown and its clock, or the circle and its newest note.
    private var medium: some View {
        let prints = self.prints
        let print = prints.first { $0.shot.mine } ?? prints.first
        return HStack(alignment: .center, spacing: 16) {
            if let print {
                WidgetPrint(image: print.image, takenAt: print.shot.takenAt, date: date)
                    .frame(maxHeight: .infinity)
                    .padding(.vertical, 2)
                    .accessibilityLabel(print.shot.mine ? "Your photo" : "Photo by \(print.shot.name)")
                    .privacySensitive()
            }
            VStack(alignment: .leading, spacing: 0) {
                heading
                Spacer(minLength: 4)
                if phase == nil || print == nil { status }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    // MARK: large

    /// The countdown or the circle's note on top; under it the circle's
    /// newest photos as small prints, signed in a hand.
    private var large: some View {
        let prints = Array(self.prints.prefix(3))
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 0) { heading }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                if let reminder = phase?.reminder {
                    slip(reminder, lines: 3)
                        .frame(maxWidth: 124)
                        .padding(.top, 8)
                }
            }
            Spacer(minLength: 8)
            rule
            if prints.isEmpty {
                Text(snapshot.emptied(at: date)
                     ? "Nothing in the light right now."
                     : "Open Stanley to see your circle.")
                    .font(.uiFixed(15))
                    .foregroundStyle(said)
                    .frame(maxWidth: .infinity, minHeight: 120, alignment: .center)
            } else {
                HStack(alignment: .top, spacing: 14) {
                    ForEach(Array(prints.enumerated()), id: \.element.shot.id) { _, print in
                        VStack(spacing: 5) {
                            WidgetPrint(image: print.image, takenAt: print.shot.takenAt, date: date)
                            Text(print.shot.mine ? "You" : print.shot.name)
                                .font(.uiFixed(12, .medium))
                                .foregroundStyle(quiet)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                        .frame(maxWidth: 104)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(print.shot.mine ? "Your photo" : "Photo by \(print.shot.name)")
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 14)
                .privacySensitive()
            }
            Spacer(minLength: 8)
            status
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: the pieces

    /// What heads the medium and large sizes: the countdown with its clock,
    /// or the circle's name with the newest note on its board.
    @ViewBuilder
    private var heading: some View {
        if let phase {
            caps(snapshot.circleName ?? "")
            Text(phase.text)
                .font(.uiFixed(size == .large ? 19 : 16, .semibold))
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 3)
            if let until = phase.until {
                WidgetClock(remaining: until.timeIntervalSince(date))
                    .padding(.top, 8)
            } else {
                mark(phase).padding(.top, 8)
            }
        } else {
            Text(snapshot.circleName ?? "")
                .font(.uiFixed(size == .large ? 23 : 20, .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                // The name keeps its size; a long note gives way instead.
                .fixedSize(horizontal: false, vertical: true)
                .layoutPriority(1)
            if let note {
                VStack(alignment: .leading, spacing: 2) {
                    Text(note.text)
                        .font(.handFixed(15))
                        .lineLimit(size == .large ? 3 : 2)
                    Text("— \(note.name)")
                        .font(.handFixed(13))
                        .foregroundStyle(quiet)
                        .lineLimit(1)
                }
                .padding(.top, 6)
                .privacySensitive()
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Note from \(note.name): \(note.text)")
            } else {
                caps(date.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                    .padding(.top, 5)
            }
        }
    }

    /// Whether today's photo is up: words and a small drawn mark, never a
    /// number.
    private var status: some View {
        let posted = snapshot.posted(at: date)
        return HStack(spacing: 6) {
            Image(systemName: posted ? "checkmark" : "plus")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(palette.accent)
                .frame(width: 20, height: 20)
                .overlay(Circle().strokeBorder(palette.accent.opacity(0.7), lineWidth: 1))
            Text(posted ? "Today's moment" : "One photo waiting")
                .font(.uiFixed(13.5, .medium))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(posted ? "Today's moment is shared" : "One photo waiting")
    }

    /// Where the trip stands, drawn: a plane before landing, a house after.
    private func mark(_ phase: Countdown.Phase) -> some View {
        Image(systemName: phase.mark == .home ? "house" : "airplane")
            .font(.system(size: 17, weight: .light))
            .foregroundStyle(quiet)
            .accessibilityHidden(true)
    }

    /// The day's note, as the scrap it is in the app: the sticky note's
    /// paper, torn along the bottom, a little crooked, under a bit of tape.
    private func slip(_ words: String, lines: Int) -> some View {
        let seed = words.unicodeScalars.reduce(UInt32(7)) { $0 &* 31 &+ $1.value }
        let degrees = 2 + Double(seed % 21) / 10
        let edge = TornEdge(seed: seed)
        return Text(words)
            .font(.handFixed(14))
            .foregroundStyle(NotePaper.ink)
            .multilineTextAlignment(.center)
            .lineLimit(lines)
            .minimumScaleFactor(0.75)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 10)
            .padding(.top, 10)
            .padding(.bottom, 11)
            .frame(maxWidth: .infinity)
            .background {
                edge.fill(NotePaper.base(colorScheme))
                    .shadow(color: .black.opacity(dark ? 0.45 : 0.14), radius: 3, x: 0.5, y: 1.5)
            }
            .overlay(alignment: .top) {
                Tape().scaleEffect(0.55).offset(y: -9)
            }
            .rotationEffect(.degrees(seed & 0x100 == 0 ? degrees : -degrees))
    }

    private var rule: some View {
        VStack(spacing: 2) {
            Rectangle().fill(DarkRoom.line(0.75)).frame(height: 1.2)
            Rectangle().fill(DarkRoom.line(0.3)).frame(height: 0.5)
        }
        .accessibilityHidden(true)
    }

    private func caps(_ words: String) -> some View {
        Text(words)
            .font(.system(size: 9.5, weight: .semibold))
            .tracking(1.05)
            .textCase(.uppercase)
            .foregroundStyle(quiet)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }
}

/// A photo in the widget: 3:4, cut with small corners, straight, faded as
/// far as it has faded in Today. On the page a hairline and the faintest
/// shadow; in the dark room nothing round it at all. (A tilted print on
/// photo paper until build 44.)
struct WidgetPrint: View {
    @Environment(\.colorScheme) private var colorScheme
    let image: UIImage
    let takenAt: Date
    let date: Date

    var body: some View {
        let dark = colorScheme == .dark
        let fade = WidgetSnapshot.fade(takenAt, at: date)
        let shape = RoundedRectangle(cornerRadius: 6, style: .continuous)
        Color.clear
            .aspectRatio(3.0 / 4.0, contentMode: .fit)
            .overlay {
                Image(uiImage: image)
                    .resizable()
                    .fullColorInWidget()
                    .aspectRatio(contentMode: .fill)
            }
            .clipped()
            .saturation(1 - 0.85 * fade)
            .opacity(1 - (dark ? 0.62 : 0.82) * fade)
            .clipShape(shape)
            .overlay {
                if !dark { shape.strokeBorder(.black.opacity(0.08), lineWidth: 0.5) }
            }
            .shadow(color: .black.opacity(dark ? 0 : 0.07), radius: 3, y: 1)
    }
}

/// What's left, to the minute: Days, Hours, Min, each on a little card
/// split by a hairline, as the app's flip clock is. The widget's timeline
/// turns it over on each whole minute; there are no seconds to watch.
///
/// On paper a card is photo paper, the white a print's border is, with a
/// hairline round it and a print's soft shadow under it. The app's clock
/// sits on the atmosphere's card color, which on the widget's small page
/// was all but the paper itself (Fall's is the floor with a little less
/// tone): the digits looked typed on the page, not set on cards. In the
/// dark room it's black boxed in the room's gray, as it was.
struct WidgetClock: View {
    @Environment(\.colorScheme) private var colorScheme
    let remaining: TimeInterval

    var body: some View {
        let left = Countdown.clock(remaining)
        HStack(alignment: .top, spacing: 5) {
            unit(left.days, "Days")
            colon
            unit(left.hours, "Hours")
            colon
            unit(left.minutes, "Min")
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(left.days) days, \(left.hours) hours, \(left.minutes) minutes to go")
    }

    private func unit(_ value: Int, _ name: String) -> some View {
        let dark = colorScheme == .dark
        let shape = RoundedRectangle(cornerRadius: 4, style: .continuous)
        return VStack(spacing: 3) {
            Text(String(format: "%02d", value))
                .font(.system(size: 19, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .frame(width: 36, height: 30)
                .background {
                    shape.fill(dark ? Color.black : PrintStock.paper)
                        .shadow(color: .black.opacity(dark ? 0 : 0.16), radius: 1.5, x: 0, y: 1)
                }
                .overlay(Rectangle().fill(DarkRoom.line(dark ? 0.18 : 0.22)).frame(height: 0.5))
                .overlay(shape.strokeBorder(DarkRoom.line(dark ? 1 : 0.34), lineWidth: dark ? 1 : 0.75))
            Text(name)
                .font(.handFixed(9, bold: true))
                .textCase(.uppercase)
                .lineLimit(1)
                .fixedSize()
                .foregroundStyle(DarkRoom.ink.opacity(dark ? 0.55 : 0.7))
        }
    }

    private var colon: some View {
        Text(":")
            .font(.system(size: 16, weight: .semibold, design: .rounded))
            .foregroundStyle(DarkRoom.ink.opacity(colorScheme == .dark ? 0.5 : 0.62))
            .frame(height: 30)
    }
}

private extension Image {
    /// On a tinted home screen (iOS 18 and up) a widget's pictures are
    /// flattened to the tint unless they ask to keep their color.
    @ViewBuilder
    func fullColorInWidget() -> some View {
        if #available(iOS 18, *) {
            widgetAccentedRenderingMode(.fullColor)
        } else {
            self
        }
    }
}

extension Font {
    /// The system's rounded face at a size that doesn't grow, for the
    /// widget's names and labels.
    static func uiFixed(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }

    /// The hand at a size that doesn't grow: a widget's room is fixed.
    static func handFixed(_ size: CGFloat, bold: Bool = false) -> Font {
        let name = bold ? "Noteworthy-Bold" : "Noteworthy-Light"
        if UIFont(name: name, size: size) != nil {
            return .custom(name, fixedSize: size)
        }
        return .system(size: size, weight: bold ? .semibold : .regular, design: .rounded)
    }
}

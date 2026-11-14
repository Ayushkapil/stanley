import SwiftUI

// Stanley's surfaces and type, shared by every screen (Quiet Warmth, build
// 44). One spectrum: the more personal the content, the more handmade it
// looks; the more functional the screen, the more it's plain iOS. Photos are
// always the hero. Three kinds of surface:
//   - a card (`card()`): white, a warm hairline, the faintest shadow. In the
//     dark there are no cards and content sits on the black.
//   - paper (`creamPaper()`): cream, grained, the same in the dark. Only for
//     things a person made by hand: a note, a letter, a journal page.
//   - glass (`glass(in:)`): a translucent surface for something you press
//     that sits over a photo or the page.
// Three kinds of type: a hand (`Font.hand`) only for a person's own words,
// the serif only for the World tab and the week's question, and the system
// font (rounded for names of things and buttons) for everything else.

/// A rule: ink, thin, edge to edge. A heavy one under a masthead. In the
/// dark room, every rule is the same barely-there gray.
struct Rule: View {
    var weight: CGFloat = 0.5

    var body: some View {
        Rectangle()
            .fill(DarkRoom.line(weight > 1 ? 0.75 : 0.3))
            .frame(height: weight)
            .accessibilityHidden(true)
    }
}

extension View {
    /// Small capitals, tracked, in the secondary ink: a dateline, a section's
    /// label, the line under a masthead.
    /// They follow Dynamic Type (the HCI audit, build 32): at a fixed 10pt
    /// they were the one text in Stanley that never grew, and they carry
    /// real information (the date, when answers open, what a section is).
    func smallCaps(_ size: CGFloat = 10) -> some View {
        modifier(SmallCaps(size: size))
    }

    /// A quiet label: small, in the secondary color, the system font. What
    /// most of the small capitals became (build 44); those are kept for a
    /// masthead's dateline and Settings' section heads.
    func quietLabel() -> some View {
        font(.footnote).foregroundStyle(.secondary)
    }

    /// The week's question, and any question the circle is asked: serif
    /// italic, the one place outside the World tab the serif goes.
    func questionType(_ style: Font.TextStyle = .title3) -> some View {
        font(.system(style, design: .serif).italic())
    }

    /// A button written out in words on a page (Answer, Keep it, Not now):
    /// the system's rounded face.
    func wordButton(_ style: Font.TextStyle = .callout, bold: Bool = true) -> some View {
        font(.system(style, design: .rounded).weight(bold ? .semibold : .regular))
    }

    /// A main page of the journal: the paper edge to edge, its own masthead
    /// instead of a navigation bar, and a strip of the page under the status
    /// bar so the paper slides beneath the clock instead of through it.
    func journalPage() -> some View { modifier(JournalPage()) }

    /// A photo, the way every photo in Stanley sits on its page: cut with
    /// 8pt corners; in daylight a warm hairline and the faintest shadow; in
    /// the dark nothing at all, the image on black. `tilt` is for the
    /// album in the Journal tab only (daylight only); Today's are straight.
    func asPrint(corner: CGFloat = PhotoCut.corner, tilt: Double = 0) -> some View {
        modifier(PhotoCardStyle(corner: corner, tilt: tilt))
    }

    /// A card: something set apart on the page. White with a warm hairline
    /// and a soft shadow in daylight. In the dark there are no cards: the
    /// content sits straight on the black at the page's own margin, with
    /// only its vertical room. The padding is the card's own, so the dark
    /// can drop it.
    func card(h: CGFloat = 18, v: CGFloat = 16, corner: CGFloat = 12) -> some View {
        modifier(CardStyle(h: h, v: v, corner: corner))
    }

    /// Paper: cream, grained, a little lifted, for the things a person made
    /// by hand (a letter, a journal page, the day's slip). It keeps its
    /// materiality in the dark: the same cream under a lamp, with dark ink
    /// on it, so everything inside is drawn as in daylight.
    func creamPaper(corner: CGFloat = 4, tilt: Double = 0) -> some View {
        modifier(CreamPaper(corner: corner, tilt: tilt))
    }

    /// Whatever's drawn on cream paper by something that draws its own
    /// paper (an envelope): dark ink, and everything inside resolved as in
    /// daylight, in either room.
    func onCream() -> some View {
        foregroundStyle(Cream.ink, Cream.ink.opacity(0.62), Cream.ink.opacity(0.4))
            .environment(\.colorScheme, .light)
    }

    /// Glass: a translucent surface for something you press. The material
    /// with a wash over it (white at 85% in daylight, white at 8% in the
    /// dark) and a thin edge. Glass casts no shadow.
    func glass<S: InsettableShape>(in shape: S) -> some View {
        modifier(Glass(shape: shape))
    }
}

/// How a photo is cut, everywhere.
enum PhotoCut {
    static let corner: CGFloat = 8
}

/// Cream paper, and the ink on it.
enum Cream {
    private static let day = UIColor(red: 0.992, green: 0.972, blue: 0.925, alpha: 1)   // #FDF8EC
    private static let lamp = UIColor(red: 0.925, green: 0.895, blue: 0.83, alpha: 1)   // under a lamp

    static let paper = Color(UIColor { $0.userInterfaceStyle == .dark ? lamp : day })

    /// The paper for a room said outright. Anything drawn `onCream()` is
    /// resolved as in daylight, so an envelope that fills itself with
    /// `paper` came out brighter in the dark than the letter beside it;
    /// it asks for the room it's really in.
    static func paper(_ scheme: ColorScheme) -> Color {
        Color(scheme == .dark ? lamp : day)
    }
    static let ink = Color(red: 0.16, green: 0.14, blue: 0.11)
}

private struct SmallCaps: ViewModifier {
    @ScaledMetric private var size: CGFloat

    init(size: CGFloat) {
        _size = ScaledMetric(wrappedValue: size, relativeTo: .caption2)
    }

    func body(content: Content) -> some View {
        content
            .font(.system(size: size, weight: .semibold))
            .tracking(size * 0.11)
            .textCase(.uppercase)
            .foregroundStyle(.secondary)
    }
}

private struct JournalPage: ViewModifier {
    @AppStorage("stanley.atmosphere") private var raw = "auto"

    func body(content: Content) -> some View {
        content
            .atmosphereWash()
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .top, spacing: 0) {
                Color.clear
                    .frame(height: 0)
                    .background(alignment: .bottom) {
                        Atmosphere.resolve(raw).palette.floor.ignoresSafeArea(edges: .top)
                    }
            }
    }
}

/// A page's masthead: its name, large, and a line under it in small
/// capitals, with whatever the page needs to hand (Edit) at the end of the
/// name where a navigation bar's button would be. The name is SF Rounded,
/// medium; the Journal tab's is in a hand, because that page is the
/// person's own. One hairline beneath (it was the paper's double rule).
struct JournalMasthead<Trailing: View>: View {
    let title: String
    var line: String = Date.now.formatted(.dateTime.weekday(.wide).month(.wide).day().year())
    var hand = false
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .lastTextBaseline) {
                Text(title)
                    .font(hand ? .hand(36, bold: true, relativeTo: .largeTitle) : .pageTitle)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 12)
                trailing()
            }
            Text(line)
                .smallCaps()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            OfflineLine()
            Rule(weight: 0.5)
                .padding(.top, 4)
        }
        .padding(.top, 8)
        // Room under the rule before the page begins (build 22).
        .padding(.bottom, 10)
    }
}

/// Said under a masthead's dateline while Stanley can't be reached, in the
/// dateline's own small capitals: the page shows what it last had, and
/// catches up by itself (`AppState.checkConnection`). Nothing to tap, and no
/// alert: being offline isn't something anyone has to dismiss.
struct OfflineLine: View {
    @Environment(AppState.self) private var state

    var body: some View {
        Group {
            if state.offline {
                HStack(spacing: 6) {
                    Image(systemName: "wifi.slash")
                    Text("Offline · it all catches up when you're back")
                }
                .smallCaps()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Offline. Stanley catches up by itself when you're back online.")
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: state.offline)
    }
}

extension JournalMasthead where Trailing == EmptyView {
    init(title: String, line: String = Date.now.formatted(.dateTime.weekday(.wide).month(.wide).day().year()), hand: Bool = false) {
        self.init(title: title, line: line, hand: hand) { EmptyView() }
    }
}

/// A section of a page: a quiet label over its name. The name is SF
/// Rounded; in the Journal tab it's in a hand (`hand`), because that page
/// is the person's own. No rules: the space above it does the dividing.
struct JournalSectionHead<Trailing: View>: View {
    var label: String?
    let title: String
    var hand = false
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                if let label {
                    Text(label)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Text(title)
                    .font(hand ? .hand(24, bold: true, relativeTo: .title2) : .sectionTitle)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .accessibilityAddTraits(.isHeader)
            }
            Spacer(minLength: 8)
            trailing()
        }
    }
}

extension JournalSectionHead where Trailing == EmptyView {
    init(label: String? = nil, title: String, hand: Bool = false) {
        self.init(label: label, title: title, hand: hand) { EmptyView() }
    }
}

private struct PhotoCardStyle: ViewModifier {
    @AppStorage("stanley.atmosphere") private var raw = "auto"
    @Environment(\.colorScheme) private var colorScheme
    let corner: CGFloat
    let tilt: Double

    func body(content: Content) -> some View {
        let dark = DarkRoom.isDark(colorScheme)
        let shape = RoundedRectangle(cornerRadius: corner, style: .continuous)
        content
            .clipShape(shape)
            // The dark room hangs the photo itself: no edge, no lift, no lean.
            .overlay {
                if !dark {
                    shape.strokeBorder(Atmosphere.resolve(raw).palette.edge, lineWidth: 0.5)
                }
            }
            .shadow(color: .black.opacity(dark ? 0 : 0.06), radius: 4, y: 1)
            .rotationEffect(.degrees(dark ? 0 : tilt))
    }
}

private struct CardStyle: ViewModifier {
    @AppStorage("stanley.atmosphere") private var raw = "auto"
    @Environment(\.colorScheme) private var colorScheme
    let h: CGFloat
    let v: CGFloat
    let corner: CGFloat

    func body(content: Content) -> some View {
        let palette = Atmosphere.resolve(raw).palette
        let shape = RoundedRectangle(cornerRadius: corner, style: .continuous)
        if DarkRoom.isDark(colorScheme) {
            content.padding(.vertical, min(v, 8))
        } else {
            content
                .padding(.horizontal, h)
                .padding(.vertical, v)
                .background {
                    shape.fill(palette.card)
                        .overlay(shape.strokeBorder(palette.edge, lineWidth: 0.5))
                        .shadow(color: .black.opacity(0.04), radius: 4, y: 1)
                }
        }
    }
}

private struct CreamPaper: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    let corner: CGFloat
    let tilt: Double

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: corner, style: .continuous)
        content
            .foregroundStyle(Cream.ink, Cream.ink.opacity(0.62), Cream.ink.opacity(0.4))
            // Ink on paper, whatever the room: everything inside is drawn
            // as it is in daylight.
            .environment(\.colorScheme, .light)
            .background {
                ZStack {
                    shape.fill(Cream.paper)
                    PaperGrainView(strength: 0.4)
                        .environment(\.colorScheme, .light)
                        .clipShape(shape)
                }
                .overlay(shape.strokeBorder(.black.opacity(0.07), lineWidth: 0.5))
                .shadow(color: .black.opacity(colorScheme == .dark ? 0 : 0.08), radius: 5, y: 2)
            }
            .rotationEffect(.degrees(tilt))
    }
}

private struct Glass<S: InsettableShape>: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    let shape: S

    func body(content: Content) -> some View {
        let dark = colorScheme == .dark
        content.background {
            shape
                .fill(.ultraThinMaterial)
                .overlay(shape.fill(.white.opacity(dark ? 0.08 : 0.85)))
                .overlay(shape.strokeBorder(.white.opacity(dark ? 0.10 : 0.15), lineWidth: 0.5))
                .overlay {
                    // On a white page a white edge is no edge: a warm
                    // hairline in daylight so the shape can be found.
                    if !dark { shape.strokeBorder(Color(red: 0.91, green: 0.90, blue: 0.88), lineWidth: 0.5) }
                }
        }
    }
}

/// Who and when, under a photo: a first name and the time, small, in the
/// system font and the secondary color (they were in a hand until build
/// 44; a hand is for a person's own words, not a label). A tap on it opens
/// their profile.
struct PrintByline: View {
    let owner: UserBrief
    let time: Date
    /// A tiny drawn plane after the time: the countdown's, on a photo posted
    /// on the day itself (build 35; an emoji until build 36). Off everywhere
    /// else.
    var plane = false
    var onOwner: (() -> Void)?

    var body: some View {
        let full = owner.displayName
        let first = full.split(separator: " ").first.map(String.init) ?? full
        Button { onOwner?() } label: {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(first)
                    .font(.footnote.weight(.semibold))
                Text(time, format: .dateTime.hour().minute())
                    .font(.footnote)
                if plane {
                    Image(systemName: "airplane")
                        .font(.system(size: 10, weight: .light))
                        .accessibilityHidden(true)
                }
            }
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(onOwner == nil)
        .accessibilityLabel("\(full), \(time.formatted(date: .omitted, time: .shortened))")
        .accessibilityHint(onOwner == nil ? "" : "Opens their profile")
    }
}

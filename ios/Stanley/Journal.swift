import SwiftUI

// The journal's visual language (build 20), shared by Today, Held, You and
// Settings so they sit on the same paper as the World tab's morning paper:
// ink on a grained page, thin rules where other apps draw boxes, a masthead
// with a dateline in small capitals, a person's own hand for anything they'd
// write themselves, and photos as prints laid on the page rather than cards.
// The paper keeps the serif; the journal keeps the hand.

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

    /// A main page of the journal: the paper edge to edge, its own masthead
    /// instead of a navigation bar, and a strip of the page under the status
    /// bar so the paper slides beneath the clock instead of through it.
    func journalPage() -> some View { modifier(JournalPage()) }

    /// A photo as a print laid on the page: a border of photo paper, corners
    /// barely rounded, a soft shadow where it lifts off the page, and a
    /// little off square. In the dark room (build 24) there is no print: the
    /// photo itself, cut with a small radius, straight, on black.
    func asPrint(border: CGFloat = 7, tilt: Double = 0) -> some View {
        modifier(PrintPaper(border: border, tilt: tilt))
    }

    /// A face pasted in as a print, when there's a photo of them. An initial
    /// on photo paper is a gray square in a gray square, so a face without
    /// a photo is left as it is, only a little crooked.
    @ViewBuilder
    func pastedFace(_ url: String?, border: CGFloat = 4, tilt: Double = 0) -> some View {
        if url != nil {
            asPrint(border: border, tilt: tilt)
        } else {
            rotationEffect(.degrees(tilt))
        }
    }

    /// Something tucked into the journal rather than written in it: a sheet
    /// of its own paper, edged in a hairline of ink.
    /// `fold` dog-ears its top-right corner by that many points (build 39).
    func paperInsert(tilt: Double = 0, fold: CGFloat = 0) -> some View {
        modifier(PaperInsert(tilt: tilt, fold: fold))
    }
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

/// A page's masthead, the journal's answer to the paper's: the page's name
/// in a hand, a double rule, the dateline in small capitals, a hairline.
/// Whatever the page needs to hand (Edit, Rested) sits at the end of the
/// title, where a navigation bar's button would have been.
struct JournalMasthead<Trailing: View>: View {
    let title: String
    var line: String = Date.now.formatted(.dateTime.weekday(.wide).month(.wide).day().year())
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .lastTextBaseline) {
                Text(title)
                    .font(.hand(40, bold: true, relativeTo: .largeTitle))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 12)
                trailing()
            }
            VStack(spacing: 2) {
                Rule(weight: 1.5)
                Rule(weight: 0.5)
            }
            Text(line)
                .smallCaps()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            OfflineLine()
            Rule(weight: 0.5)
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
        .animation(.easeInOut(duration: 0.3), value: state.offline)
    }
}

extension JournalMasthead where Trailing == EmptyView {
    init(title: String, line: String = Date.now.formatted(.dateTime.weekday(.wide).month(.wide).day().year())) {
        self.init(title: title, line: line) { EmptyView() }
    }
}

/// A section of a page: its label in small capitals and its name in a hand,
/// between a heavy rule and a hairline, the way the paper heads "Near
/// Bloomington". Anything at the end of the name (a face) sits inside the
/// rules with it.
struct JournalSectionHead<Trailing: View>: View {
    var label: String?
    let title: String
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Rule(weight: 1.5)
            if let label {
                Text(label).smallCaps()
                    .padding(.top, 2)
            }
            HStack(alignment: .center) {
                Text(title)
                    .font(.hand(26, bold: true, relativeTo: .title2))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                trailing()
            }
            Rule(weight: 0.5)
        }
    }
}

extension JournalSectionHead where Trailing == EmptyView {
    init(label: String? = nil, title: String) {
        self.init(label: label, title: title) { EmptyView() }
    }
}

private struct PrintPaper: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    let border: CGFloat
    let tilt: Double

    func body(content: Content) -> some View {
        let dark = DarkRoom.isDark(colorScheme)
        content
            // The dark room hangs the photo itself: no paper, no lift, no lean.
            .clipShape(RoundedRectangle(cornerRadius: dark ? DarkRoom.photoCorner : 0, style: .continuous))
            .padding(dark ? 0 : border)
            .background(dark ? .clear : PrintStock.paper, in: RoundedRectangle(cornerRadius: 2.5, style: .continuous))
            .shadow(color: .black.opacity(dark ? 0 : 0.16), radius: 5, x: 0.5, y: 2.5)
            .rotationEffect(.degrees(dark ? 0 : tilt))
    }
}

private struct PaperInsert: ViewModifier {
    @AppStorage("stanley.atmosphere") private var raw = "auto"
    @Environment(\.colorScheme) private var colorScheme
    let tilt: Double
    var fold: CGFloat = 0

    func body(content: Content) -> some View {
        let shape = SlipShape(fold: fold)
        let dark = DarkRoom.isDark(colorScheme)
        content
            .background {
                // In the dark room there's no sheet of paper to tuck in: the
                // same black, boxed in a rule, straight.
                ZStack {
                    shape.fill(dark ? .clear : Atmosphere.resolve(raw).palette.floor)
                    shape.fill(dark ? .clear : Atmosphere.resolve(raw).palette.card)
                    PaperGrainView(strength: 0.45)
                        .clipShape(shape)
                }
                .overlay(shape.stroke(dark ? DarkRoom.line(1) : DarkRoom.line(0.16), lineWidth: dark ? 1 : 0.5))
                .overlay(alignment: .topTrailing) {
                    if fold > 0 { FoldedCorner().frame(width: fold, height: fold) }
                }
                .shadow(color: .black.opacity(dark ? 0 : 0.1), radius: 6, y: 2)
            }
            .rotationEffect(.degrees(dark ? 0 : tilt))
    }
}

/// Who and when, written in ink beneath a print the way you'd write on an
/// album page: a first name and the time, in a hand. A tap on it opens their
/// profile.
struct PrintByline: View {
    let owner: UserBrief
    let time: Date
    var size: CGFloat = 18
    /// A tiny drawn plane after the time: the countdown's, on a photo posted
    /// on the day itself (build 35; an emoji until build 36). Off everywhere
    /// else.
    var plane = false
    var onOwner: (() -> Void)?

    var body: some View {
        let full = owner.displayName
        let first = full.split(separator: " ").first.map(String.init) ?? full
        Button { onOwner?() } label: {
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Text(first)
                    .font(.hand(size, bold: true, relativeTo: .subheadline))
                    .foregroundStyle(.primary)
                Text(time, format: .dateTime.hour().minute())
                    .font(.hand(size - 3, relativeTo: .subheadline))
                    .foregroundStyle(.secondary)
                if plane {
                    Image(systemName: "airplane")
                        .font(.system(size: size - 8, weight: .light))
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
            }
            .lineLimit(1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(onOwner == nil)
        .accessibilityLabel("\(full), \(time.formatted(date: .omitted, time: .shortened))")
        .accessibilityHint(onOwner == nil ? "" : "Opens their profile")
    }
}

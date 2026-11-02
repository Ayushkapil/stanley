import SwiftUI

// The journal's visual language (build 20), shared by Today, Held, You and
// Settings so they sit on the same paper as the World tab's morning paper:
// ink on a grained page, thin rules where other apps draw boxes, a masthead
// with a dateline in small capitals, a person's own hand for anything they'd
// write themselves, and photos as prints laid on the page rather than cards.
// The paper keeps the serif; the journal keeps the hand.

/// A rule: ink, thin, edge to edge. A heavy one under a masthead.
struct Rule: View {
    var weight: CGFloat = 0.5

    var body: some View {
        Rectangle()
            .fill(.primary.opacity(weight > 1 ? 0.75 : 0.3))
            .frame(height: weight)
            .accessibilityHidden(true)
    }
}

extension View {
    /// Small capitals, tracked, in the secondary ink: a dateline, a section's
    /// label, the line under a masthead.
    func smallCaps(_ size: CGFloat = 10) -> some View {
        font(.system(size: size, weight: .semibold))
            .tracking(size * 0.11)
            .textCase(.uppercase)
            .foregroundStyle(.secondary)
    }

    /// A main page of the journal: the paper edge to edge, its own masthead
    /// instead of a navigation bar, and a strip of the page under the status
    /// bar so the paper slides beneath the clock instead of through it.
    func journalPage() -> some View { modifier(JournalPage()) }

    /// A photo as a print laid on the page: a border of photo paper, corners
    /// barely rounded, a soft shadow where it lifts off the page, and a
    /// little off square.
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
    func paperInsert(tilt: Double = 0) -> some View { modifier(PaperInsert(tilt: tilt)) }
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
            Rule(weight: 0.5)
        }
        .padding(.top, 8)
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

/// Photo paper: warm white in daylight; in the dark a step down, as if under
/// a lamp, so a print doesn't glare off a black page (the sticky note does
/// the same).
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

private struct PrintPaper: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    let border: CGFloat
    let tilt: Double

    func body(content: Content) -> some View {
        content
            .padding(border)
            .background(PrintStock.paper, in: RoundedRectangle(cornerRadius: 2.5, style: .continuous))
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.55 : 0.16), radius: 5, x: 0.5, y: 2.5)
            .rotationEffect(.degrees(tilt))
    }
}

private struct PaperInsert: ViewModifier {
    @AppStorage("stanley.atmosphere") private var raw = "auto"
    @Environment(\.colorScheme) private var colorScheme
    let tilt: Double

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 3, style: .continuous)
        content
            .background {
                ZStack {
                    shape.fill(Atmosphere.resolve(raw).palette.floor)
                    shape.fill(Atmosphere.resolve(raw).palette.card)
                    PaperGrainView(strength: colorScheme == .dark ? 0.28 : 0.45)
                        .clipShape(shape)
                }
                .overlay(shape.strokeBorder(.primary.opacity(0.16), lineWidth: 0.5))
                .shadow(color: .black.opacity(colorScheme == .dark ? 0.5 : 0.1), radius: 6, y: 2)
            }
            .rotationEffect(.degrees(tilt))
    }
}

/// Album corners: four little paper mounts, the kind a print is slipped
/// into, each just over a corner of what it holds. Laid over a print as an
/// overlay; with nothing under them, they mark where one was. Black on a
/// light page; on a dark page, the gray of old card, or they'd vanish.
struct PhotoCorners: View {
    var size: CGFloat = 16

    private static let mountColor = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(white: 0.52, alpha: 1) : UIColor(white: 0.13, alpha: 1)
    })

    var body: some View {
        Color.clear
            .overlay(alignment: .topLeading) { mount(0) }
            .overlay(alignment: .topTrailing) { mount(90) }
            .overlay(alignment: .bottomTrailing) { mount(180) }
            .overlay(alignment: .bottomLeading) { mount(270) }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private func mount(_ degrees: Double) -> some View {
        Mount()
            .fill(Self.mountColor)
            .overlay(Mount().stroke(.white.opacity(0.12), lineWidth: 0.5))
            .frame(width: size, height: size)
            .rotationEffect(.degrees(degrees))
            .shadow(color: .black.opacity(0.25), radius: 1, x: 0.5, y: 0.5)
            .padding(-size * 0.22)
    }

    /// The right angle at the top leading corner, the long side across it.
    private struct Mount: Shape {
        func path(in rect: CGRect) -> Path {
            Path { p in
                p.move(to: rect.origin)
                p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
                p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
                p.closeSubpath()
            }
        }
    }
}

/// Who and when, written in ink beneath a print the way you'd write on an
/// album page: a first name and the time, in a hand. A tap on it opens their
/// profile.
struct PrintByline: View {
    let owner: UserBrief
    let time: Date
    var size: CGFloat = 18
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

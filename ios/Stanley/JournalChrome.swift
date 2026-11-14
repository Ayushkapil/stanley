import SwiftUI

// The Journal's chrome (build 53, from the brief of 2026-11-14): one look
// for everything on every Journal screen that is pressed and isn't paper.
// Glass for chrome only: a circle of material with a thin white edge. A
// page gets none of it, no blur, no sheen, no stroke. In the dark, where
// material over black goes muddy, the fill is a little white and the edge
// carries the shape.

/// A circle of glass. 34pt for the bar's marks, 61pt for the "+".
struct GlassCircle<Label: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("stanley.atmosphere") private var raw = "auto"
    let size: CGFloat
    @ViewBuilder let label: () -> Label

    var body: some View {
        let dark = colorScheme == .dark
        ZStack {
            if dark {
                Circle().fill(Color.white.opacity(0.08))
                Circle().strokeBorder(TextTone.onPhoto.opacity(0.55), lineWidth: 0.5)
            } else {
                // By day, on cream: the material whitened a little, edged
                // in the palette's own hairline, where white would vanish.
                Circle().fill(.ultraThinMaterial)
                Circle().fill(Color.white.opacity(0.35))
                Circle().strokeBorder(Atmosphere.resolve(raw).palette.edge, lineWidth: 0.5)
            }
            label()
        }
        .frame(width: size, height: size)
        // Lifted a little off paper in daylight, where a white edge alone
        // would vanish into the page.
        .shadow(color: .black.opacity(dark ? 0 : 0.1), radius: 3, x: 0, y: 1)
    }
}

/// A mark of the bar: a glyph in a 34pt glass circle, in a 44pt target.
struct ChromeButton: View {
    let symbol: String
    let label: String
    var hint = ""
    var tint: Color
    /// A sealed letter is waiting: a dot of red.
    var dot = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            GlassCircle(size: 34) {
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(tint)
            }
            .overlay(alignment: .topTrailing) {
                if dot {
                    Circle()
                        .fill(Ink.red.color)
                        .overlay(Circle().strokeBorder(.white.opacity(0.9), lineWidth: 1.2))
                        .frame(width: 9, height: 9)
                        .offset(x: 1, y: -1)
                }
            }
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityHint(hint)
    }
}

/// The "+", larger than it was: a 32pt plus drawn at a 1.6pt stroke in a
/// 61pt glass circle.
struct PlusGlass: View {
    let tint: Color

    var body: some View {
        GlassCircle(size: 61) {
            ZStack {
                Capsule().frame(width: 32, height: 1.6)
                Capsule().frame(width: 1.6, height: 32)
            }
            .foregroundStyle(tint)
        }
        .frame(width: 61, height: 61)
        .contentShape(Circle())
    }
}

/// Letters, the week (on Sunday evening) and Prompts as one control (build
/// 57): a single capsule of glass with the glyphs inside it, a hairline
/// between each, each part a 44pt target. The red dot stays on Letters.
struct ChromeCapsule: View {
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("stanley.atmosphere") private var raw = "auto"
    let tint: Color
    let sealed: Bool
    let ready: Bool
    let prompts: Bool
    let week: ThisWeek?
    let openLetters: () -> Void
    let openPrompts: () -> Void
    let openWeek: () -> Void

    private struct Part: Identifiable {
        let id: String
        let symbol: String
        let label: String
        let hint: String
        var dot = false
        let action: () -> Void
    }

    private func parts(_ now: Date) -> [Part] {
        var all = [Part(
            id: "letters", symbol: "envelope", label: "Letters",
            hint: ready ? "A letter is ready to open" : sealed ? "A sealed letter is waiting for its day" : "",
            dot: sealed, action: openLetters
        )]
        if let week, week.reflection == nil, ReflectionWindow.isOpen(now) {
            all.append(Part(id: "week", symbol: "moon", label: "How was your week?", hint: "Write this week's reflection", action: openWeek))
        }
        if prompts {
            all.append(Part(
                id: "prompts", symbol: "questionmark.bubble", label: "Prompts",
                hint: "Your circle's questions and what everyone said", action: openPrompts
            ))
        }
        return all
    }

    var body: some View {
        let dark = colorScheme == .dark
        let edge = dark ? TextTone.onPhoto.opacity(0.55) : Atmosphere.resolve(raw).palette.edge
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let parts = parts(context.date)
            HStack(spacing: 0) {
                ForEach(Array(parts.enumerated()), id: \.element.id) { at, part in
                    if at > 0 {
                        Rectangle().fill(edge).frame(width: 0.5, height: 18)
                            .accessibilityHidden(true)
                    }
                    Button(action: part.action) {
                        Image(systemName: part.symbol)
                            .font(.system(size: 15, weight: .regular))
                            .foregroundStyle(tint)
                            .overlay(alignment: .topTrailing) {
                                if part.dot {
                                    Circle()
                                        .fill(Ink.red.color)
                                        .overlay(Circle().strokeBorder(BookPaper.page, lineWidth: 1.2))
                                        .frame(width: 8, height: 8)
                                        .offset(x: 5, y: -3)
                                }
                            }
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(part.label)
                    .accessibilityHint(part.hint)
                }
            }
            .padding(.horizontal, 2)
            .frame(height: 34)
            .background {
                ZStack {
                    if dark {
                        Capsule().fill(Color.white.opacity(0.08))
                    } else {
                        Capsule().fill(.ultraThinMaterial)
                        Capsule().fill(Color.white.opacity(0.35))
                    }
                    Capsule().strokeBorder(edge, lineWidth: 0.5)
                }
                .shadow(color: .black.opacity(dark ? 0 : 0.1), radius: 3, x: 0, y: 1)
            }
            .frame(height: 44)
            .accessibilityElement(children: .contain)
        }
    }
}

/// Along the top of an open book: back at the left, "Mine" and "Ours"
/// (with a shared journal beside it); and on the date's line under it, at
/// the right, the capsule of Letters and Prompts, its right edge on the
/// writing's margin. On the covers only the date's line, its edges on the
/// card's (`JournalCovers`).
struct JournalTopBar: View {
    let layout: BookLayout
    let tint: Color
    var back: (() -> Void)?
    let sealed: Bool
    let ready: Bool
    let prompts: Bool
    let week: ThisWeek?
    let openLetters: () -> Void
    let openPrompts: () -> Void
    let openWeek: () -> Void
    /// In a book with a shared journal beside it: "Mine" and "Ours", the
    /// one open in the accent (build 51's switch, kept in the bar).
    var ours: Bool? = nil
    var pick: (Bool) -> Void = { _ in }
    /// Where the capsule's line is, and its right edge: by default the
    /// page's date line and the writing's margin.
    var lineY: CGFloat?
    var rightEdge: CGFloat?
    /// On the covers: words at the left of the capsule's line.
    var leading: AnyView?
    var leftEdge: CGFloat?

    var body: some View {
        ZStack(alignment: .topLeading) {
            if back != nil || ours != nil {
                HStack(spacing: 2) {
                    if let back {
                        ChromeButton(symbol: "chevron.left", label: "Back", hint: "Back to the covers", tint: tint, action: back)
                    }
                    Spacer(minLength: 0)
                    if let ours {
                        word("Mine", on: !ours) { pick(false) }
                        word("Ours", on: ours) { pick(true) }
                    }
                    Spacer(minLength: 0)
                    // Balancing the back button, so the words sit centered.
                    Color.clear.frame(width: 44, height: 44)
                }
                .padding(.leading, layout.left - 5)
                .padding(.trailing, layout.width - layout.right - 5)
                .frame(width: layout.width, height: 44)
                .offset(y: layout.barY - 22)
            }
            let right = rightEdge ?? layout.right
            let left = leftEdge ?? layout.left
            HStack(spacing: 0) {
                if let leading { leading }
                Spacer(minLength: 0)
                ChromeCapsule(
                    tint: tint, sealed: sealed, ready: ready, prompts: prompts, week: week,
                    openLetters: openLetters, openPrompts: openPrompts, openWeek: openWeek
                )
            }
            .frame(width: max(0, right - left), height: 44)
            .offset(x: left, y: (lineY ?? layout.headY) - 22)
        }
    }

    private func word(_ name: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(name)
                .font(.system(.subheadline, design: .rounded).weight(on ? .semibold : .regular))
                .foregroundStyle(on ? tint : TextTone.secondary)
                .frame(minWidth: 46, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(name == "Mine" ? "My journal" : "The shared journal")
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// Under the tab bar on the Journal tab: material, with a hairline along
/// its top edge. In daylight the material is laid over a wash of the
/// page's paper: iOS 26's bar takes its light or dark from what's beneath
/// it, and over a dark cover photo it went dark and the selected tab's ink
/// vanished (the trouble of builds 31 and 39).
struct TabBarGlass: View {
    @Environment(\.colorScheme) private var colorScheme
    let height: CGFloat
    /// What it's a frosted wash of: the page's paper in a book, the room's
    /// floor on the covers.
    var base: Color = BookPaper.page

    var body: some View {
        let dark = colorScheme == .dark
        Rectangle()
            .fill(dark ? Color.black.opacity(0.35) : base.opacity(0.82))
            .overlay(Rectangle().fill(.ultraThinMaterial))
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(colorScheme == .dark ? Color.white.opacity(0.18) : Color.black.opacity(0.12))
                    .frame(height: 0.5)
            }
            .frame(height: height)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// A journal's notice while Stanley is open (build 57): words on a capsule
/// of glass sliding down from the top, "Aryan wrote in Anti mosquito",
/// never a number or a word of the page. A tap opens the page; it goes by
/// itself after seven seconds, or with a swipe up.
struct JournalBanner: View {
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("stanley.atmosphere") private var raw = "auto"
    let notice: Push.JournalNotice
    let open: () -> Void
    let dismiss: () -> Void

    var body: some View {
        let dark = colorScheme == .dark
        let palette = Atmosphere.resolve(raw).palette
        Button(action: open) {
            HStack(spacing: 10) {
                Image(systemName: "book.closed")
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(palette.accent)
                Text(notice.text)
                    .font(.system(.subheadline, design: .rounded).weight(.medium))
                    .foregroundStyle(TextTone.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 52)
            .background {
                ZStack {
                    if dark {
                        Capsule().fill(Color.black.opacity(0.6))
                        Capsule().fill(.ultraThinMaterial)
                    } else {
                        Capsule().fill(.ultraThinMaterial)
                        Capsule().fill(Color.white.opacity(0.5))
                    }
                    Capsule().strokeBorder(dark ? TextTone.onPhoto.opacity(0.4) : palette.edge, lineWidth: 0.5)
                }
                .shadow(color: .black.opacity(dark ? 0.4 : 0.12), radius: 12, y: 4)
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .gesture(DragGesture(minimumDistance: 10).onEnded { if $0.translation.height < -10 { dismiss() } })
        .accessibilityLabel(notice.text)
        .accessibilityHint("Opens the page")
        .task {
            try? await Task.sleep(for: .seconds(7))
            dismiss()
        }
    }
}

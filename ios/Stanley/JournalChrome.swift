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
    let size: CGFloat
    @ViewBuilder let label: () -> Label

    var body: some View {
        let dark = colorScheme == .dark
        ZStack {
            if dark {
                Circle().fill(Color.white.opacity(0.08))
            } else {
                Circle().fill(.ultraThinMaterial)
            }
            Circle().strokeBorder(Color.white.opacity(0.55), lineWidth: 0.5)
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

/// Along the top of every Journal screen: back at the left (in an open
/// book), and Letters, the week (on Sunday evening) and Prompts at the
/// right. Glass circles over whatever is beneath.
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

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            HStack(spacing: 2) {
                if let back {
                    ChromeButton(symbol: "chevron.left", label: "Back", hint: "Back to the covers", tint: tint, action: back)
                }
                Spacer(minLength: 0)
                ChromeButton(
                    symbol: "envelope", label: "Letters",
                    hint: ready ? "A letter is ready to open" : sealed ? "A sealed letter is waiting for its day" : "",
                    tint: tint, dot: sealed, action: openLetters
                )
                if let week, week.reflection == nil, ReflectionWindow.isOpen(context.date) {
                    ChromeButton(symbol: "moon", label: "How was your week?", hint: "Write this week's reflection", tint: tint, action: openWeek)
                }
                if prompts {
                    ChromeButton(
                        symbol: "questionmark.bubble", label: "Prompts",
                        hint: "Your circle's questions and what everyone said", tint: tint, action: openPrompts
                    )
                }
            }
            // Each outer circle's edge on the writing's margin.
            .padding(.leading, layout.left - 5)
            .padding(.trailing, layout.width - layout.right - 5)
            .frame(width: layout.width, height: 44)
            .offset(y: layout.barY - 22)
        }
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

    var body: some View {
        let dark = colorScheme == .dark
        Rectangle()
            .fill(dark ? Color.black.opacity(0.35) : BookPaper.page.opacity(0.82))
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

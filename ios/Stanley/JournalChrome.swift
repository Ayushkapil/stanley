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

/// The Journal tab's toolbar (the Duo brief, "Rework the Journal cover
/// screen to Apple's iPhone Duo guidance"; it replaces build 57's capsule
/// and build 54's glass circles). Letters and the week's moon on Sunday
/// evening are real toolbar items, each a title and a symbol, grouped and
/// spaced by the system: a bar along the top on an iPhone and the inner
/// display upright, a rail down the side on the outer display and the
/// inner one turned. In a book, back to the covers at the leading end and
/// "Mine" and "Ours" in the middle. Letters keeps its mark while a letter
/// is sealed, at a high visibility priority so it outlasts the others when
/// the bar is short of room. A mark, never a number.
///
/// Prompts was an item here until build 63: in the Duo's cover turned on
/// its side the rail has one slot, and Letters, the item that carries
/// something, went into the overflow with it whatever its priority. The
/// prompts are on the page being written now (`PromptLine`).
struct JournalToolbar: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    let opened: Bool
    /// A cover is open, between the deck and its pages (build 76): back
    /// puts it into the deck.
    var coverOpen = false
    var closeCover: () -> Void = {}
    let ours: Bool
    let hasOurs: Bool
    let sealed: Bool
    let ready: Bool
    let week: ThisWeek?
    let tint: Color
    let back: () -> Void
    let pick: (Bool) -> Void
    let openLetters: () -> Void
    let openWeek: () -> Void

    /// The tint, settled for this screen's light or dark: the bar's glass
    /// resolves a color that changes with the room in a context of its
    /// own, and at night drew the glyphs in the day's ink.
    private var ink: Color { settled(tint) }

    private func settled(_ color: Color) -> Color {
        let style: UIUserInterfaceStyle = colorScheme == .dark ? .dark : .light
        return Color(UIColor(color).resolvedColor(with: UITraitCollection(userInterfaceStyle: style)))
    }

    /// Sunday evening's moon is showing: the week's reflection is open
    /// and not yet written.
    private var weekShowing: Bool {
        guard let week else { return false }
        return week.reflection == nil && ReflectionWindow.isOpen(.now)
    }

    func body(content: Content) -> some View {
        if #available(iOS 27.0, *) {
            // Letters never goes into the overflow (build 63). On the Duo's
            // cover turned on its side the rail has one slot; two items
            // there both went behind "…" whatever their priority. Pinned,
            // Letters keeps its place and the system folds the tab rail
            // instead. Pinned only beside the moon: pinned on its own, the
            // bar wasn't drawn at all (iOS 27.1, the Duo simulator), and
            // alone it needs no pin, being the one item in the one slot.
            content.toolbar {
                bookItems
                lettersItem(weekShowing ? .topBarPinnedTrailing : .topBarTrailing)
                    .visibilityPriority(.high)
                weekItem
            }
        } else {
            content.toolbar {
                bookItems
                lettersItem(.topBarTrailing)
                weekItem
            }
        }
    }

    @ToolbarContentBuilder
    private var bookItems: some ToolbarContent {
        if !opened && coverOpen {
            ToolbarItem(placement: .topBarLeading) {
                Button(action: closeCover) {
                    Label("Journals", systemImage: "chevron.left")
                        .foregroundStyle(ink)
                }
                .tint(ink)
                .accessibilityHint("Back to the journals")
            }
        }
        if opened {
            ToolbarItem(placement: .topBarLeading) {
                Button(action: back) {
                    Label("Covers", systemImage: "chevron.left")
                        .foregroundStyle(ink)
                }
                .tint(ink)
                .accessibilityHint("Back to the covers")
            }
            if hasOurs {
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 4) {
                        word("Mine", on: !ours) { pick(false) }
                        word("Ours", on: ours) { pick(true) }
                    }
                }
            }
        }
    }

    @ToolbarContentBuilder
    private func lettersItem(_ placement: ToolbarItemPlacement) -> some ToolbarContent {
        ToolbarItem(placement: placement) {
            Button(action: openLetters) {
                Label("Letters", systemImage: "envelope")
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(ink)
            }
            .tint(ink)
            // A mark while one is sealed: a presence, not a count.
            .badge(sealed ? Text(verbatim: "\u{2022}") : nil)
            .accessibilityValue(ready ? "A letter is ready to open" : sealed ? "A sealed letter is waiting for its day" : "")
        }
    }

    @ToolbarContentBuilder
    private var weekItem: some ToolbarContent {
        if weekShowing {
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: openWeek) {
                    Label("How was your week?", systemImage: "moon")
                        .symbolRenderingMode(.monochrome)
                        .foregroundStyle(ink)
                }
                .tint(ink)
                .accessibilityHint("Write this week's reflection")
            }
        }
    }

    private func word(_ name: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(name)
                .font(.system(.subheadline, design: .rounded).weight(on ? .semibold : .regular))
                .foregroundStyle(on ? ink : settled(TextTone.secondary))
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
/// of glass sliding down from the top, "Aryan wrote you a page" or "Aryan
/// sent you a letter" (build 59; build 57's "wrote in" a circle is gone),
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
                Image(systemName: notice.isLetter ? "envelope" : "book.closed")
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

import PhotosUI
import SwiftUI

// The opened cover (build 76, from the brief of 2026-11-16, "Build the
// opened-cover state"): between the deck and the pages. A tap on a cover in
// the deck grows it here, one card moving and changing shape
// (`matchedGeometryEffect`, a spring of 0.45 and 0.82), the room behind it
// staying as it was. The grown cover keeps its photo, title, small capitals
// and foot; an edit button at its top right; under it a glass panel with
// "Last written" (a date) and, on your own journal, "This week" (your last
// five days from the mood store); then Open. A tap on the cover opens it
// too. Dragging down puts it back, following the finger, the card shrinking
// into its place in the deck.
//
// Made your own here: your journal's photo (from your library; once chosen,
// nothing automatic replaces it until "Use Automatic Photo"), its name, and
// the colour of its field while it has no photo. A circle's journal takes
// the circle's name, renamed by its organizer alone; it has no chosen photo
// (a product decision, 2026-11-16). The brief's "Use most kept photo" isn't
// here: a cover never says anything about anyone's keeps.

struct OpenedCover: View {
    @Environment(AppState.self) private var state
    @Environment(\.horizontalSizeClass) private var sizeClass
    @AppStorage("stanley.atmosphere") private var raw = "auto"
    let journal: CoverJournal
    let namespace: Namespace.ID
    /// The card grows from the deck (off under Reduce Motion: it fades).
    let hero: Bool
    /// Where its card sits in the deck, to shrink back into.
    let slot: CGRect?
    let room: CGSize
    let insets: EdgeInsets
    let open: () -> Void
    let close: () -> Void
    let rename: () -> Void
    let setSwatch: (CoverField.Swatch) -> Void
    let openDays: () -> Void

    @State private var drag: CGFloat = 0
    @State private var appeared = false
    @State private var picking = false
    @State private var picked: PhotosPickerItem?
    @State private var uploading = false
    @AccessibilityFocusState private var focused: Bool

    private var palette: Atmosphere.Palette { Atmosphere.resolve(raw).palette }
    private var mine: Bool { journal.circleId == nil }
    private var showsWeek: Bool { mine && state.moodsAvailable }

    /// How tall what's under the cover is: the panel, the button and the
    /// room between them.
    private var detailsHeight: CGFloat { (showsWeek ? 124 : 52) + 16 + 52 }

    /// The least the details beside the cover may be across.
    private static let detailsMin: CGFloat = 300

    private struct Layout {
        let card: CGRect
        let details: CGRect
    }

    /// The grown cover about 348 points tall and the page's width, the
    /// details under it; on its side, the cover at the left and the details
    /// beside it.
    private var layout: Layout {
        let area = CGRect(
            x: insets.leading + 20, y: insets.top + 12,
            width: max(200, room.width - insets.leading - insets.trailing - 40),
            height: max(200, room.height - insets.top - 12 - 16)
        )
        if area.width > area.height * 1.15 {
            // The details keep room enough for their words in one line each
            // (on the Duo's cover on its side the room is narrow); the
            // cover takes what's left, no wider than a little over tall.
            let height = min(348, area.height)
            let width = max(180, min(height * 1.1, area.width - 24 - Self.detailsMin))
            let card = CGRect(x: area.minX, y: area.midY - height / 2, width: width, height: height)
            let x = card.maxX + 24
            let details = CGRect(
                x: x, y: area.midY - detailsHeight / 2,
                width: min(420, area.maxX - x), height: detailsHeight
            )
            return Layout(card: card, details: details)
        }
        let width = min(area.width, sizeClass == .regular ? 520 : area.width)
        let height = min(348, max(200, area.height - detailsHeight - 16))
        let card = CGRect(x: area.midX - width / 2, y: area.minY, width: width, height: height)
        let details = CGRect(x: card.minX, y: card.maxY + 16, width: width, height: detailsHeight)
        return Layout(card: card, details: details)
    }

    /// How far it's been dragged back toward the deck, 0 to 1.
    private func progress(_ grown: CGRect) -> CGFloat {
        guard drag > 0 else { return 0 }
        let distance = slot.map { $0.midY - grown.midY } ?? 0
        return min(1, drag / max(220, distance))
    }

    private func lerp(_ a: CGRect, _ b: CGRect, _ t: CGFloat) -> CGRect {
        CGRect(
            x: a.minX + (b.minX - a.minX) * t, y: a.minY + (b.minY - a.minY) * t,
            width: a.width + (b.width - a.width) * t, height: a.height + (b.height - a.height) * t
        )
    }

    var body: some View {
        let layout = self.layout
        let p = progress(layout.card)
        // Following the finger back into the deck; without a place to go
        // back to, it only moves down.
        let card = slot.map { lerp(layout.card, $0, p) } ?? layout.card.offsetBy(dx: 0, dy: drag)
        let detailsShown = (appeared ? 1 : 0) * max(0, 1 - p * 1.6)
        ZStack(alignment: .topLeading) {
            Color.clear
                .frame(width: room.width, height: room.height)
                .contentShape(Rectangle())
            CoverCard(journal: journal, open: open, rename: journal.canRename ? rename : nil, hint: OpenedCoverWords.openHint)
                .modifier(Hero(id: journal.id, namespace: namespace, on: hero))
                .frame(width: card.width, height: card.height)
                .accessibilityFocused($focused)
                .overlay(alignment: .topTrailing) {
                    if hasEdits {
                        editButton
                            .padding(10 * CoverCard.scale(card.size))
                            .opacity(detailsShown)
                    }
                }
                .position(x: card.midX, y: card.midY)
            details
                .frame(width: layout.details.width)
                .position(x: layout.details.midX, y: layout.details.midY + (appeared ? 0 : 12) + drag * 0.3)
                .opacity(detailsShown)
        }
        .frame(width: room.width, height: room.height, alignment: .topLeading)
        .gesture(
            DragGesture(minimumDistance: 10)
                .onChanged { value in drag = max(0, value.translation.height) }
                .onEnded { value in
                    if drag > 110 || value.predictedEndTranslation.height > 280 {
                        close()
                    } else {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { drag = 0 }
                    }
                }
        )
        .accessibilityAction(.escape) { close() }
        .onAppear {
            withAnimation(.easeOut(duration: 0.28).delay(hero ? 0.18 : 0)) { appeared = true }
            // VoiceOver lands on the grown cover, and says where it is.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                focused = true
                UIAccessibility.post(notification: .screenChanged, argument: nil)
            }
        }
        .photosPicker(isPresented: $picking, selection: $picked, matching: .images, preferredItemEncoding: .current)
        .onChange(of: picked) { _, item in
            guard let item else { return }
            picked = nil
            Task { await choose(item) }
        }
    }

    // MARK: the edit button

    private var canChoosePhoto: Bool { mine && state.journalCoverAvailable }

    private var hasEdits: Bool {
        canChoosePhoto || journal.canRename || journal.cover == nil || journal.chosen
    }

    private var editButton: some View {
        Menu {
            if canChoosePhoto {
                Button { picking = true } label: {
                    Label(OpenedCoverWords.changePhoto, systemImage: "photo.on.rectangle")
                }
            }
            if journal.canRename {
                Button(action: rename) {
                    Label(OpenedCoverWords.rename, systemImage: "character.cursor.ibeam")
                }
            }
            // Only where there's no photo to cover it.
            if journal.cover == nil {
                Picker(selection: Binding(get: { journal.swatch ?? .caramel }, set: setSwatch)) {
                    ForEach(CoverField.Swatch.allCases) { swatch in
                        Text(swatch.name).tag(swatch)
                    }
                } label: {
                    Label(OpenedCoverWords.coverColour, systemImage: "paintpalette")
                }
                .pickerStyle(.menu)
            }
            if journal.chosen {
                Button {
                    Task { await state.useAutomaticCover() }
                } label: {
                    Label(OpenedCoverWords.automaticPhoto, systemImage: "arrow.uturn.backward")
                }
            }
        } label: {
            GlassCircle(size: 36) {
                if uploading {
                    ProgressView().controlSize(.small).tint(TextTone.onPhoto)
                } else {
                    Image(systemName: "pencil")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(journal.cover == nil && CoverField.ink(for: journal.id, dark: false, swatch: journal.swatch) == .dark
                            ? palette.accent : TextTone.onPhoto)
                }
            }
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
        }
        .accessibilityLabel(OpenedCoverWords.edit)
    }

    private func choose(_ item: PhotosPickerItem) async {
        uploading = true
        defer { uploading = false }
        guard let photo = await LibraryPhoto.load(item, longestSide: 2048),
              let jpeg = photo.image.jpegData(compressionQuality: 0.88) else { return }
        await state.chooseJournalCover(jpeg: jpeg)
    }

    // MARK: under the cover

    private var details: some View {
        VStack(spacing: 16) {
            panel
            WideButton(title: OpenedCoverWords.open, action: open)
                .accessibilityHint(OpenedCoverWords.openHint)
        }
    }

    private var panel: some View {
        VStack(spacing: 0) {
            HStack {
                Text(OpenedCoverWords.lastWritten)
                    .foregroundStyle(TextTone.primary)
                Spacer(minLength: 12)
                Text(OpenedCoverWords.lastWritten(journal.lastDay))
                    .foregroundStyle(TextTone.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .font(.system(.subheadline, design: .rounded))
            .frame(minHeight: 52)
            .accessibilityElement(children: .combine)
            if showsWeek {
                Rectangle()
                    .fill(palette.edge)
                    .frame(height: 0.5)
                week
            }
        }
        .padding(.horizontal, 18)
        .glass(in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    /// Your last five days, oldest first and today last: each a bubble in
    /// as much ink as its mark, its letter under it. A tap anywhere on it
    /// opens the month's sheet.
    private var week: some View {
        let days = OpenedCoverWords.lastFiveDays()
        return HStack(alignment: .center) {
            Text(OpenedCoverWords.thisWeek)
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(TextTone.primary)
                .lineLimit(1)
                .fixedSize()
            Spacer(minLength: 8)
            HStack(spacing: 6) {
                ForEach(days, id: \.day) { entry in
                    let level = state.moods[LocalDay.text(of: entry.day)]
                    Button(action: openDays) {
                        VStack(spacing: 5) {
                            ZStack {
                                Circle().strokeBorder(TextTone.primary.opacity(0.45), lineWidth: 0.8)
                                if let level { Circle().fill(TextTone.primary.opacity(MarkSheet.shade(level))) }
                            }
                            .frame(width: 15, height: 15)
                            Text(entry.letter)
                                .font(.system(size: 11, weight: .medium, design: .rounded))
                                .foregroundStyle(TextTone.secondary)
                        }
                        .frame(minWidth: 24, minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(level.map { MarkSheet.spokenBubble(entry.day, $0) }
                        ?? "\(MarkSheet.spokenDay(entry.day)), \(MarkSheet.notMarked)")
                    .accessibilityHint(OpenedCoverWords.weekHint)
                }
            }
        }
        .frame(minHeight: 72)
        .contentShape(Rectangle())
        .onTapGesture(perform: openDays)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(OpenedCoverWords.thisWeek)
    }
}

/// The card's growing from the deck, where motion is welcome.
private struct Hero: ViewModifier {
    let id: String
    let namespace: Namespace.ID
    let on: Bool

    func body(content: Content) -> some View {
        if on {
            content.matchedGeometryEffect(id: id, in: namespace, isSource: true)
        } else {
            content
        }
    }
}

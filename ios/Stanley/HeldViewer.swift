import SwiftUI

// A held photo, opened (build 39). A tap on a print in the album lifts it
// off the page and up to the whole screen, over the dark; what was written
// about it sits beneath. Swipe sideways for the next one, pinch to look
// closer, and swipe down, tap the dark, or Close to put it back.
//
// The lift is the system's zoom transition (iOS 18 and up): the print
// grows from where it lies and goes back to it, on a spring, and a drag
// down takes it back by hand. On iOS 17 it opens as an ordinary cover.

/// One page of the opened album: a memory, and whose it's from.
struct HeldPage: Identifiable, Hashable {
    let memory: Memory
    let friend: UserBrief
    var id: String { memory.id }
}

extension AppState {
    /// Everything in Held that has a picture, in the album's own order.
    var heldPages: [HeldPage] {
        threads.flatMap { thread in
            thread.memories
                .filter { !$0.isTombstone && $0.urls != nil }
                .map { HeldPage(memory: $0, friend: thread.friend) }
        }
    }
}

extension View {
    /// Where an opened print grows from, and goes back to.
    @ViewBuilder
    func heroSource(_ id: String, in album: Namespace.ID?) -> some View {
        if #available(iOS 18, *), let album {
            matchedTransitionSource(id: id, in: album)
        } else {
            self
        }
    }

    /// The opened print's side of the same lift.
    @ViewBuilder
    func heroZoom(from id: String, in album: Namespace.ID) -> some View {
        if #available(iOS 18, *) {
            navigationTransition(.zoom(sourceID: id, in: album))
        } else {
            self
        }
    }
}

/// A print gives a little under the thumb before it lifts: down to 97%, and
/// back on a spring.
struct PressedPrint: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.22, dampingFraction: 0.85), value: configuration.isPressed)
    }
}

/// The opened album: every held photo a page, the one tapped first.
struct HeldViewer: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss
    /// The page in view. The album behind follows it, so a print goes back
    /// to its own place whichever one is showing at the end.
    @Binding var current: String
    @State private var position: String?
    /// The photo in view is pinched in: sideways swipes move it, not the page.
    @State private var zoomed = false

    var body: some View {
        let pages = state.heldPages
        ZStack(alignment: .topTrailing) {
            // The dark. A tap on it, anywhere beside the photo or its
            // words, puts the print back.
            Color.black
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { dismiss() }
                .accessibilityHidden(true)
            // The pages run edge to edge and keep clear of the screen's safe
            // edges themselves. Left to itself, the paging scroll view pushed
            // its pages down by the top inset a second time, and the words
            // under the photo ran off the foot of the screen.
            GeometryReader { geo in
                let insets = geo.safeAreaInsets
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 0) {
                        ForEach(pages) { page in
                            HeldPageView(page: page, zoomed: page.id == current ? $zoomed : .constant(false)) {
                                dismiss()
                            }
                            .padding(.top, insets.top)
                            .padding(.bottom, insets.bottom)
                            .frame(
                                width: geo.size.width,
                                height: geo.size.height + insets.top + insets.bottom
                            )
                            // The dark around the photo and its words: a
                            // tap there puts the print back.
                            .background {
                                Color.clear
                                    .contentShape(Rectangle())
                                    .onTapGesture { dismiss() }
                            }
                            .id(page.id)
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.paging)
                .scrollPosition(id: $position)
                .scrollDisabled(zoomed)
                .ignoresSafeArea()
            }
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(width: 44, height: 44)
                    .background(.white.opacity(0.12), in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .padding(.trailing, 14)
            .padding(.top, 6)
            .accessibilityLabel("Close")
        }
        // White ink on the dark, whatever the hour outside.
        .environment(\.colorScheme, .dark)
        .statusBarHidden()
        .onAppear { position = current }
        .onChange(of: position) { _, now in
            if let now, now != current {
                current = now
                zoomed = false
            }
        }
        // Let go of from somewhere else while it's open: nothing to show.
        .onChange(of: pages.isEmpty) { _, empty in if empty { dismiss() } }
    }
}

/// One held photo, large, with its words beneath: the caption in a hand,
/// where and when, when it was held and whose it is, and, on your own
/// photo, what you wrote about the day.
private struct HeldPageView: View {
    @Environment(AppState.self) private var state
    let page: HeldPage
    @Binding var zoomed: Bool
    let onClose: () -> Void

    private var memory: Memory { page.memory }

    private var whose: String {
        if let id = page.friend.id, id == state.myId { return "Yours" }
        let first = page.friend.displayName.split(separator: " ").first.map(String.init)
        return "From \(first ?? page.friend.displayName)"
    }

    /// "GRIFFY LAKE · 25 OCT 2026"
    private var whereAndWhen: String? {
        let place = memory.location.flatMap { $0.isEmpty ? nil : $0 }
        let taken = memory.takenAt?.formatted(date: .abbreviated, time: .omitted)
        let parts = [place, taken].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private var heldOn: String? {
        guard let held = memory.anchoredAt else { return nil }
        return "Held on \(held.formatted(date: .abbreviated, time: .omitted))"
    }

    var body: some View {
        VStack(spacing: 0) {
            if let urls = memory.urls, let url = state.api.absoluteURL(urls.image) {
                ZoomablePhoto(url: url, zoomed: $zoomed, onMiss: onClose)
                    .accessibilityLabel(memory.caption.flatMap { $0.isEmpty ? nil : "Held photo: \($0)" } ?? "Held photo")
            }
            words
                .opacity(zoomed ? 0 : 1)
                .animation(.easeOut(duration: 0.15), value: zoomed)
        }
        .padding(.top, 52)
    }

    /// What's written about it, beneath: as tall as its words, and the
    /// photo above gives up the room. A long journal entry shows its first
    /// lines here; the whole of it is under the print in the album.
    private var words: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let caption = memory.caption, !caption.isEmpty {
                // In a hand on your own photo; plain on anyone else's.
                Text(caption)
                    .font(whose == "Yours" ? .hand(21, bold: true, relativeTo: .title3) : .title3.weight(.medium))
                    .foregroundStyle(.white)
                    .lineLimit(3)
            }
            if let whereAndWhen {
                Text(whereAndWhen).font(.footnote).foregroundStyle(.secondary).lineLimit(1)
            }
            HStack(spacing: 6) {
                Image(systemName: "bookmark.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                Text([heldOn, whose].compactMap { $0 }.joined(separator: " · ")).font(.footnote).foregroundStyle(.secondary).lineLimit(1)
            }
            if let circle = memory.circleName, state.circles.count > 1 {
                CircleTag(name: circle)
            }
            if let note = memory.note, !note.isEmpty {
                Text(note)
                    .font(.hand(17, relativeTo: .callout))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .padding(.top, 2)
            }
            // Your own photo: what you wrote about the day (build 26).
            if let journal = memory.journal, !journal.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Rectangle().fill(.white.opacity(0.18)).frame(height: 0.5)
                        .padding(.vertical, 6)
                    Label("Only you see this", systemImage: "lock")
                        .labelStyle(.titleAndIcon)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(journal)
                        .font(.hand(18, relativeTo: .body))
                        .foregroundStyle(.white.opacity(0.92))
                        .lineLimit(7)
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: 560, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 22)
        .padding(.top, 14)
        .padding(.bottom, 12)
        .accessibilityElement(children: .combine)
    }
}

/// The photo, as large as the screen allows. Pinch to look closer (up to
/// four times), drag to move around while you're in, double-tap to go in
/// and out. A tap on the dark beside it closes.
private struct ZoomablePhoto: View {
    let url: URL
    @Binding var zoomed: Bool
    let onMiss: () -> Void
    @State private var scale: CGFloat = 1
    @State private var settledScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var settledOffset: CGSize = .zero

    var body: some View {
        GeometryReader { geo in
            let fitted = Self.fitted(in: geo.size)
            ZStack {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture(perform: onMiss)
                SignedImage(url: url) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    Rectangle().fill(.white.opacity(0.08))
                }
                .frame(width: fitted.width, height: fitted.height)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .scaleEffect(scale)
                .offset(offset)
                .onTapGesture(count: 2) { toggle(in: fitted) }
                .gesture(
                    MagnifyGesture()
                        .onChanged { value in
                            scale = min(4, max(1, settledScale * value.magnification))
                            offset = Self.held(offset, in: fitted, at: scale)
                            zoomed = scale > 1.01
                        }
                        .onEnded { _ in settle(in: fitted) }
                )
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            offset = Self.held(
                                CGSize(
                                    width: settledOffset.width + value.translation.width,
                                    height: settledOffset.height + value.translation.height
                                ),
                                in: fitted, at: scale
                            )
                        }
                        .onEnded { _ in settledOffset = offset },
                    // Only while it's pinched in: otherwise a sideways drag
                    // is the next photo, and a downward one puts it back.
                    including: scale > 1.01 ? .all : .subviews
                )
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .onChange(of: zoomed) { _, now in
            // The page moved on: this one goes back to its own size.
            if !now, scale != 1 { reset() }
        }
    }

    /// A 3:4 photo fitted inside the space, with a little margin.
    private static func fitted(in size: CGSize) -> CGSize {
        let width = min(size.width - 24, (size.height - 8) * PhotoShape.aspect)
        return CGSize(width: max(0, width), height: max(0, width / PhotoShape.aspect))
    }

    /// The offset, held so the photo never leaves its own frame empty.
    private static func held(_ offset: CGSize, in fitted: CGSize, at scale: CGFloat) -> CGSize {
        let reachX = fitted.width * (scale - 1) / 2
        let reachY = fitted.height * (scale - 1) / 2
        return CGSize(
            width: min(reachX, max(-reachX, offset.width)),
            height: min(reachY, max(-reachY, offset.height))
        )
    }

    private func settle(in fitted: CGSize) {
        if scale <= 1.01 {
            reset()
        } else {
            settledScale = scale
            settledOffset = offset
        }
    }

    private func toggle(in fitted: CGSize) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            if scale > 1.01 {
                reset()
            } else {
                scale = 2.5
                settledScale = 2.5
                zoomed = true
            }
        }
    }

    private func reset() {
        withAnimation(.spring(response: 0.28, dampingFraction: 0.85)) {
            scale = 1
            offset = .zero
        }
        settledScale = 1
        settledOffset = .zero
        zoomed = false
    }
}

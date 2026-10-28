import Photos
import SwiftUI
import UIKit

struct TodayFeedView: View {
    @Environment(AppState.self) private var state
    @State private var showCapture = false
    @State private var editingNote = false
    @Environment(\.horizontalSizeClass) private var hSizeClass
    private var density: Density { Density(hSizeClass) }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: density.feedSpacing) {
                    // The weekly mosaic sits at the very top (Part 2), Sun/Mon only.
                    if let mosaic = state.mosaic {
                        MosaicCard(mosaic: mosaic)
                    }
                    // Returned sits above the circle's own content, set apart.
                    if let item = state.returned {
                        ReturnedCard(item: item)
                    }
                    NoteBar(note: state.communityNote) { editingNote = true }
                    if let pending = state.queue.pending {
                        PendingCaptureCard(pending: pending)
                    }
                    if state.feedItems.isEmpty {
                        VStack(spacing: 8) {
                            Text("Nothing here right now.")
                                .foregroundStyle(.secondary)
                            Text("Photos live for six days, then they're gone.")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.top, 80)
                    }
                    ForEach(state.feedItems) { item in
                        if item.isMoment {
                            MomentCard(item: item)
                        } else if let photo = item.photo {
                            PhotoCard(photo: photo)
                        }
                    }
                }
                .padding()
            }
            .atmosphereWash()
            .navigationTitle("Today")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    // The day is claimed the moment the shutter closes, signal
                    // or not — so a queued capture closes the camera too.
                    Button { showCapture = true } label: { Image(systemName: "camera") }
                        .disabled(state.queue.isHoldingTheDay)
                }
            }
            .sheet(isPresented: $showCapture) { CaptureView() }
            .sheet(isPresented: $editingNote) { NoteEditor() }
            .refreshable {
                await state.refreshToday()
                await state.flushPendingCapture()
            }
            .task {
                await state.refreshToday()
                await state.flushPendingCapture()
            }
        }
    }
}

struct ViewedMember: Identifiable {
    let id: String
}

/// The image with its two gestures: double-tap to like (ephemeral, a heart),
/// press-and-hold to hold (permanent, a bookmark). Color deepens under the
/// thumb while held, with a soft settle on commit — never applause. Reused by
/// both standalone photos and the tiles inside a shared moment.
struct PhotoImageView: View {
    @Environment(AppState.self) private var state
    @Environment(\.colorScheme) private var colorScheme
    let photo: Photo
    var height: CGFloat = 320
    var cornerRadius: CGFloat = 16

    @State private var holdProgress: Double = 0
    @State private var settleScale: CGFloat = 1
    @State private var likeGlow: Double = 0

    private var fade: Double {
        let fadingStart = 1.0 / 3.0
        let t = min(1.0, max(0.0, (photo.decayProgress - fadingStart) / (1.0 - fadingStart)))
        return t * t * (3.0 - 2.0 * t)
    }

    private var opacityDrop: Double { colorScheme == .dark ? 0.62 : 0.82 }

    var body: some View {
        Group {
            if let urls = photo.urls, let url = state.api.absoluteURL(urls.image) {
                AsyncImage(url: url) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    Rectangle().fill(.quaternary)
                }
                .frame(maxWidth: .infinity)
                .frame(height: height)
                .clipped()
                .saturation(1.0 - 0.85 * fade)
                .opacity(1.0 - opacityDrop * fade)
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(Color.accentColor.opacity(0.38 * holdProgress))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(Color.pink.opacity(0.40 * likeGlow))
                        .blendMode(.plusLighter)
                        .allowsHitTesting(false)
                )
                .overlay(alignment: .topLeading) {
                    if photo.anchoredByMe { marker("bookmark.fill", .accentColor) }
                }
                .overlay(alignment: .bottomTrailing) {
                    // Personal state, never a public signal: this says "you
                    // liked this", only to you, and never how many did. Not a
                    // button either — the like is still the double-tap.
                    marker(photo.likedByMe ? "heart.fill" : "heart",
                           photo.likedByMe ? .pink : .white)
                        .opacity(photo.likedByMe ? 1 : 0.5)
                        .allowsHitTesting(false)
                        .accessibilityLabel(photo.likedByMe ? "You liked this" : "You haven't liked this")
                }
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
                .scaleEffect(settleScale)
                .contentShape(Rectangle())
                .onTapGesture(count: 2) { like() }
                .onLongPressGesture(minimumDuration: 0.45, maximumDistance: 30) {
                    hold()
                } onPressingChanged: { pressing in
                    withAnimation(.easeOut(duration: pressing ? 0.45 : 0.25)) {
                        holdProgress = pressing && !photo.anchoredByMe ? 1 : 0
                    }
                }
                .contextMenu {
                    Button { Task { await state.toggleLike(photo) } } label: {
                        Label(photo.likedByMe ? "Unlike" : "Like", systemImage: "heart")
                    }
                    Button { Task { await state.toggleAnchor(photo) } } label: {
                        Label(photo.anchoredByMe ? "Let go" : "Hold", systemImage: "bookmark")
                    }
                }
            }
        }
    }

    private func marker(_ systemName: String, _ tint: Color) -> some View {
        Image(systemName: systemName)
            .font(.footnote)
            .foregroundStyle(tint)
            .padding(6)
            .background(.ultraThinMaterial, in: Circle())
            .padding(8)
    }

    private func hold() {
        guard !photo.anchoredByMe else { return }
        withAnimation(.easeOut(duration: 0.2)) { holdProgress = 0 }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.6)) { settleScale = 0.97 }
        withAnimation(.spring(response: 0.45, dampingFraction: 0.7).delay(0.12)) { settleScale = 1 }
        Task { await state.hold(photo) }
    }

    private func like() {
        withAnimation(.easeOut(duration: 0.18)) { likeGlow = 1 }
        withAnimation(.easeIn(duration: 0.5).delay(0.18)) { likeGlow = 0 }
        Task { await state.toggleLike(photo) }
    }
}

struct PhotoCard: View {
    @Environment(AppState.self) private var state
    @Environment(\.horizontalSizeClass) private var hSizeClass
    private var density: Density { Density(hSizeClass) }
    let photo: Photo
    @State private var newComment = ""
    @State private var viewedMember: ViewedMember?
    @State private var showFaces = false
    @State private var showStories = false

    private var isMine: Bool { state.myId != nil && state.myId == photo.owner.id }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            PhotoImageView(photo: photo, height: density.feedPhotoHeight, cornerRadius: 12)
            actionRow
            comments
            commentField
        }
        // Same container as MomentCard: a photo in Today is one object, whether
        // it arrived alone or as part of a shared moment. Header (face, name,
        // time) and footer (caption, place, Held) live inside the card, never
        // loose on the feed background.
        .padding(density.cardPadding)
        .background(.quinary, in: RoundedRectangle(cornerRadius: density.cardCorner))
        .sheet(item: $viewedMember) { member in
            MemberProfileView(memberId: member.id)
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showFaces) {
            FacesSheet(photoId: photo.id)
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showStories) {
            PhotoStoriesView(photo: photo)
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Button {
                if let ownerId = photo.owner.id { viewedMember = ViewedMember(id: ownerId) }
            } label: {
                HStack(spacing: 8) {
                    AvatarView(url: photo.owner.avatarUrl, name: photo.owner.displayName, size: 28)
                    Text(photo.owner.displayName).font(.subheadline.weight(.medium))
                }
            }
            .buttonStyle(.plain)
            Spacer()
            Text(photo.takenAt, format: .dateTime.hour().minute())
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var actionRow: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                if let caption = photo.caption, !caption.isEmpty {
                    Text(caption).font(.body)
                }
                if let location = photo.location, !location.isEmpty {
                    Text(location).font(.footnote).italic().foregroundStyle(.secondary)
                }
                // 'Who was there' — faces as a memory detail, not tappable (Part 3).
                if !photo.tagged.isEmpty {
                    HStack(spacing: 6) {
                        FaceCluster(
                            faces: photo.tagged.map { (id: $0.id ?? $0.displayName, url: $0.avatarUrl, name: $0.displayName) },
                            size: 20
                        )
                        Text("with " + photo.tagged.map(\.displayName).joined(separator: ", "))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .padding(.top, 1)
                }
            }
            Spacer()
            if isMine {
                Button { showFaces = true } label: { Image(systemName: "person.2") }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }
            // Held: the keep gesture. Tap is the accessible path; press-and-hold
            // the photo is the primary one. No counts, ever (A2).
            Button { Task { await state.toggleAnchor(photo) } } label: {
                Image(systemName: photo.anchoredByMe ? "bookmark.fill" : "bookmark")
            }
            .buttonStyle(.plain)
            .foregroundStyle(photo.anchoredByMe ? Color.accentColor : Color.secondary)
            .accessibilityLabel(photo.anchoredByMe ? "Let go of this memory" : "Hold this memory")
        }
    }

    @ViewBuilder
    private var comments: some View {
        if let first = photo.comments.first {
            VStack(alignment: .leading, spacing: 4) {
                // Co-remembering, visible without digging: one line, the way
                // you'd overhear it.
                (Text(first.author.displayName).fontWeight(.medium)
                    + Text("  ") + Text(first.body))
                    .font(.callout)
                    .lineLimit(1)
                if photo.comments.count > 1 {
                    // "More", never "2 more" — the no-counts rule holds here too.
                    Button("More stories") { showStories = true }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .buttonStyle(.plain)
                }
            }
            .padding(.top, 2)
        }
    }

    private var commentField: some View {
        HStack {
            TextField("Add to the story…", text: $newComment)
                .textFieldStyle(.plain)
                .font(.callout)
            if !newComment.trimmingCharacters(in: .whitespaces).isEmpty {
                Button("Add") {
                    let body = newComment.trimmingCharacters(in: .whitespaces)
                    newComment = ""
                    Task { await state.comment(on: photo, body: body) }
                }
                .font(.callout)
            }
        }
    }
}

/// A shared moment (Part 3): one event, many phones. Header shows the place and
/// the faces who posted from it (never a count); the photos scroll horizontally,
/// each keeping its own like, Held, and decay.
struct MomentCard: View {
    @Environment(\.horizontalSizeClass) private var hSizeClass
    private var density: Density { Density(hSizeClass) }
    let item: FeedItem

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.location ?? "Shared moment")
                        .font(.subheadline.weight(.medium))
                    Text("from your circle")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if let members = item.members {
                    FaceCluster(
                        faces: members.map { (id: $0.id ?? $0.displayName, url: $0.avatarUrl, name: $0.displayName) },
                        size: 30
                    )
                }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(item.photos ?? []) { photo in
                        VStack(alignment: .leading, spacing: 4) {
                            PhotoImageView(photo: photo, height: density.momentTile, cornerRadius: 12)
                                .frame(width: density.momentTile)
                            Text(photo.owner.displayName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(width: density.momentTile)
                    }
                }
            }
        }
        .padding(density.cardPadding)
        .background(.quinary, in: RoundedRectangle(cornerRadius: density.cardCorner))
    }
}

/// The community note (Part 4), pinned at the top of Today. A shared line, not
/// a chat — tapping it just lets you set or replace it.
struct NoteBar: View {
    let note: CommunityNote?
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                Image(systemName: "pin")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                if let note {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(note.text).font(.callout)
                        Text("— \(note.author.displayName)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("Leave a note for the circle…")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quinary, in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }
}

struct NoteEditor: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""

    private let limit = 90

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("One line for the whole circle", text: $text, axis: .vertical)
                        .lineLimit(1...3)
                        .onChange(of: text) { _, new in
                            if new.count > limit { text = String(new.prefix(limit)) }
                        }
                } footer: {
                    Text("Everyone sees this line. It clears at the end of the day — it's a sticky note, not a chat.")
                }
            }
            .navigationTitle("Today's note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Set") {
                        let line = text.trimmingCharacters(in: .whitespacesAndNewlines)
                        Task { await state.setNote(line) }
                        dismiss()
                    }
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear { text = state.communityNote?.text ?? "" }
        }
    }
}

/// The one quiet Returned card (§14), set apart from circle content. Rescue is
/// time-critical (keep your own fading photo); anniversary and near-forgotten
/// resurface held memories. Two distinct exits: Rest (never again) and
/// Dismiss (not now).
/// The weekly mosaic (Part 2): the week's photos as one fleeting artifact.
/// View-only — no holds, likes, comments, or counts. Each tile shows its
/// owner's face. Appears Sun/Mon, gone Tuesday.
struct MosaicCard: View {
    @Environment(AppState.self) private var state
    @Environment(\.horizontalSizeClass) private var hSizeClass
    private var density: Density { Density(hSizeClass) }
    let mosaic: Mosaic
    @State private var selection = 0

    // Each photo gets real presence — roughly half the screen, a page in a
    // small photo book rather than a tile in a wall.
    private var carouselHeight: CGFloat { density.mosaicHeight }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header stays above the carousel.
            HStack(spacing: 8) {
                Image(systemName: "square.grid.2x2")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Your week").font(.subheadline.weight(.medium))
                    Text("Your week, all at once.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
            }

            // One photo at a time, swipeable — flipping through the week.
            TabView(selection: $selection) {
                ForEach(Array(mosaic.tiles.enumerated()), id: \.offset) { index, tile in
                    tilePhoto(tile).tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: carouselHeight)

            // The photographer and caption for the photo on screen.
            if mosaic.tiles.indices.contains(selection) {
                let tile = mosaic.tiles[selection]
                HStack(spacing: 8) {
                    AvatarView(url: tile.owner.avatarUrl, name: tile.owner.displayName, size: 26, circular: true)
                    VStack(alignment: .leading, spacing: 3) {
                        // Decorative editorial face (Didot) — a photo-book byline,
                        // not the app's standard type. Header/subtitle stay system.
                        Text(tile.owner.displayName ?? "departed")
                            .font(.mosaicDeco(20))
                        if let caption = tile.caption, !caption.isEmpty {
                            Text(caption)
                                .font(.mosaicDeco(16))
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                    Spacer()
                }
                .animation(.easeInOut(duration: 0.2), value: selection)
            }

            // Page dots — how many there are, and where you are.
            if mosaic.tiles.count > 1 {
                HStack(spacing: 6) {
                    ForEach(mosaic.tiles.indices, id: \.self) { i in
                        Circle()
                            .fill(i == selection ? Color.primary.opacity(0.7) : Color.secondary.opacity(0.3))
                            .frame(width: 6, height: 6)
                    }
                }
                .frame(maxWidth: .infinity)
                .animation(.easeInOut(duration: 0.2), value: selection)
            }
        }
        .padding(14)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))
    }

    private func tilePhoto(_ tile: MosaicTile) -> some View {
        Color.clear
            .overlay {
                if let url = state.api.absoluteURL(tile.image ?? tile.thumb) {
                    AsyncImage(url: url) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        Rectangle().fill(.quaternary)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .padding(.horizontal, 2)
            .padding(.bottom, 4)
    }
}

struct ReturnedCard: View {
    @Environment(AppState.self) private var state
    let item: ReturnedItem

    private var isRescue: Bool { item.source == "rescue" }

    private var heading: String {
        switch item.source {
        case "rescue": return "Fading soon"
        case "anniversary": return anniversaryLabel
        case "near_forgotten": return "You'd forgotten this one"
        default: return "Returned"
        }
    }

    private var subheading: String {
        switch item.source {
        case "rescue": return rescueSubheading
        case "anniversary": return "From the memories you've held."
        case "near_forgotten": return "From a while back."
        default: return ""
        }
    }

    // A rescue is always a last-light photo (~5–6 days old), so name the real
    // day — never "today", which can't be true here.
    private var rescueSubheading: String {
        guard let taken = item.photo.takenAt else { return "Your moment, fading." }
        return "Your moment from \(taken.formatted(.dateTime.weekday(.wide)))."
    }

    private var anniversaryLabel: String {
        guard let taken = item.photo.takenAt else { return "On this day" }
        let months = Calendar.current.dateComponents([.month], from: taken, to: Date()).month ?? 0
        if months >= 12 {
            let years = months / 12
            return years == 1 ? "A year ago" : "\(years) years ago"
        }
        return months <= 1 ? "One month ago" : "\(months) months ago"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 1) {
                    Text(heading).font(.subheadline.weight(.medium))
                    Text(subheading).font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
            }
            if let urls = item.photo.urls, let url = state.api.absoluteURL(urls.thumb) {
                AsyncImage(url: url) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    Rectangle().fill(.quaternary)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 180)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            if let caption = item.photo.caption, !caption.isEmpty {
                Text(caption).font(.callout)
            }
            if isRescue {
                Button {
                    Task { await state.keepReturned(photoId: item.photo.id) }
                } label: {
                    Label("Keep this", systemImage: "bookmark")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
            HStack {
                Button("Rest this memory") {
                    Task { await state.restReturned(photoId: item.photo.id) }
                }
                Spacer()
                Button("Dismiss") {
                    Task { await state.dismissReturned() }
                }
            }
            .font(.callout)
            .foregroundStyle(.secondary)
            .padding(.top, 2)
        }
        .padding(14)
        // Softer, distinct from circle cards: a thin material with an accent edge.
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(Color.accentColor.opacity(0.25), lineWidth: 1)
        )
    }
}

/// The whole thread, for when the card's one line isn't enough. Opened from
/// "More stories" — the photo, its caption, and every story on it, in the order
/// they were told. Adding one works here too.
struct PhotoStoriesView: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss
    let photo: Photo
    @State private var newComment = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    PhotoImageView(photo: photo, cornerRadius: 12)
                    if let caption = photo.caption, !caption.isEmpty {
                        Text(caption).font(.body)
                    }
                    ForEach(photo.comments) { comment in
                        (Text(comment.author.displayName).fontWeight(.medium)
                            + Text("  ") + Text(comment.body))
                            .font(.callout)
                    }
                    HStack {
                        TextField("Add to the story…", text: $newComment)
                            .textFieldStyle(.plain)
                            .font(.callout)
                        if !newComment.trimmingCharacters(in: .whitespaces).isEmpty {
                            Button("Add") {
                                let body = newComment.trimmingCharacters(in: .whitespaces)
                                newComment = ""
                                Task { await state.comment(on: photo, body: body) }
                            }
                            .font(.callout)
                        }
                    }
                    .padding(.top, 2)
                }
                .padding()
            }
            .navigationTitle(photo.owner.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

/// The photo that is waiting for a signal. Deliberately quiet: this is not an
/// error, just a moment that hasn't travelled yet. It sits where it will sit
/// once it lands, so nothing jumps when it does.
struct PendingCaptureCard: View {
    @Environment(AppState.self) private var state
    @Environment(\.horizontalSizeClass) private var hSizeClass
    private var density: Density { Density(hSizeClass) }
    let pending: PendingCapture

    private var image: UIImage? {
        guard let data = try? Data(contentsOf: pending.jpegURL) else { return nil }
        return UIImage(data: data)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(maxWidth: .infinity)
                    .frame(height: density.feedPhotoHeight)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    // Held back a little until it's real for everyone else.
                    .opacity(pending.rejection == nil ? 0.72 : 0.5)
            }
            if let caption = pending.caption, !caption.isEmpty {
                Text(caption).font(.body)
            }
            if let rejection = pending.rejection {
                Text(rejection)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                HStack {
                    Button("Save to Photos") { Task { await save() } }
                    Spacer()
                    Button("Discard", role: .destructive) { state.queue.clear() }
                }
                .font(.callout)
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
            } else {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.mini)
                    Text("Waiting to upload")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(density.cardPadding)
        .background(.quinary, in: RoundedRectangle(cornerRadius: density.cardCorner))
    }

    /// The last honest option for a photo that can never be posted: let its
    /// owner keep it. Stanley never writes to Photos otherwise.
    private func save() async {
        guard let image else { return }
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            state.errorMessage = "Stanley needs permission to add to your Photos library."
            return
        }
        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAsset(from: image)
            }
            state.flash = "Saved to Photos."
            state.queue.clear()
        } catch {
            state.errorMessage = "Couldn't save that to Photos."
        }
    }
}

import SwiftUI

struct TodayFeedView: View {
    @Environment(AppState.self) private var state
    @State private var showCapture = false

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 24) {
                    if let item = state.returned {
                        ReturnedCard(item: item)
                    }
                    if state.feed.isEmpty {
                        VStack(spacing: 8) {
                            Text("Nothing here right now.")
                                .foregroundStyle(.secondary)
                            Text("Photos live for six days, then they're gone.")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.top, 80)
                    }
                    ForEach(state.feed) { photo in
                        PhotoCard(photo: photo)
                    }
                }
                .padding()
            }
            .navigationTitle("Today")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showCapture = true
                    } label: {
                        Image(systemName: "camera")
                    }
                }
            }
            .sheet(isPresented: $showCapture) {
                CaptureView()
            }
            .refreshable { await state.refreshToday() }
            .task { await state.refreshToday() }
        }
    }
}

struct ViewedMember: Identifiable {
    let id: String
}

struct PhotoCard: View {
    @Environment(AppState.self) private var state
    @Environment(\.colorScheme) private var colorScheme
    let photo: Photo
    @State private var newComment = ""
    @State private var viewedMember: ViewedMember?
    @State private var showFaces = false

    // Press-and-hold feedback (Part 4): color deepens under the thumb, then a
    // soft settle on commit — never applause.
    @State private var holdProgress: Double = 0
    @State private var settleScale: CGFloat = 1
    // Warmth feedback (Part 5): a gentle glow on double-tap, not a burst.
    @State private var warmGlow: Double = 0

    private var isMine: Bool { state.myId != nil && state.myId == photo.owner.id }

    // The fade is ambient, never numeric (§8.1). decay_progress spans the whole
    // 144h public life, but LIVE (< 1/3) must render fully visible — so the
    // fade starts at the FADING boundary and eases (smoothstep) to "barely
    // visible" by the end of LAST_LIGHT. No countdowns anywhere.
    private var fade: Double {
        let fadingStart = 1.0 / 3.0  // 48h of 144h
        let t = min(1.0, max(0.0, (photo.decayProgress - fadingStart) / (1.0 - fadingStart)))
        return t * t * (3.0 - 2.0 * t)
    }

    // Fading toward black hides dark photos sooner than fading toward white
    // hides bright ones, so dark mode keeps a higher opacity floor (0.38 vs
    // 0.18) — the desaturation carries more of the "fading" feel there.
    private var opacityDrop: Double {
        colorScheme == .dark ? 0.62 : 0.82
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            photoImage
            actionRow
            comments
            commentField
        }
        .padding(.bottom, 8)
        .sheet(item: $viewedMember) { member in
            MemberProfileView(memberId: member.id)
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showFaces) {
            FacesSheet(photoId: photo.id)
                .presentationDetents([.medium, .large])
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Button {
                if let ownerId = photo.owner.id {
                    viewedMember = ViewedMember(id: ownerId)
                }
            } label: {
                HStack(spacing: 8) {
                    AvatarView(url: photo.owner.avatarUrl, name: photo.owner.displayName, size: 28)
                    Text(photo.owner.displayName)
                        .font(.subheadline.weight(.medium))
                }
            }
            .buttonStyle(.plain)
            Spacer()
            // Absolute time of day (Part 6), e.g. "1:06 AM" — not "2 hours ago".
            Text(photo.takenAt, format: .dateTime.hour().minute())
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var photoImage: some View {
        if let urls = photo.urls, let url = state.api.absoluteURL(urls.image) {
            AsyncImage(url: url) { image in
                image.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                Rectangle().fill(.quaternary)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 320)
            .clipped()
            .saturation(1.0 - 0.85 * fade)
            .opacity(1.0 - opacityDrop * fade)
            // Press-and-hold deepens a warm wash under the thumb.
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.orange.opacity(0.38 * holdProgress))
            )
            // Double-tap warmth: a soft glow, no burst.
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.yellow.opacity(0.45 * warmGlow))
                    .blendMode(.plusLighter)
                    .allowsHitTesting(false)
            )
            // Held marker: a small steady flame, top-leading. Warmth marker:
            // a small sun, top-trailing — shown only to me, my own state.
            .overlay(alignment: .topLeading) {
                if photo.anchoredByMe {
                    marker(systemName: "flame.fill", tint: .orange)
                }
            }
            .overlay(alignment: .topTrailing) {
                if photo.warmedByMe {
                    marker(systemName: "sun.min.fill", tint: .yellow)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .scaleEffect(settleScale)
            .contentShape(Rectangle())
            .onTapGesture(count: 2) { warm() }
            .onLongPressGesture(minimumDuration: 0.45, maximumDistance: 30) {
                hold()
            } onPressingChanged: { pressing in
                withAnimation(.easeOut(duration: pressing ? 0.45 : 0.25)) {
                    holdProgress = pressing && !photo.anchoredByMe ? 1 : 0
                }
            }
            // VoiceOver paths for gestures that can't be tapped out (no conflict
            // with the press-and-hold/double-tap above).
            .accessibilityAction(named: photo.warmedByMe ? "Cool" : "Warm") { warm() }
            .accessibilityAction(named: photo.anchoredByMe ? "Let go" : "Hold") {
                Task { await state.toggleAnchor(photo) }
            }
        }
    }

    private func marker(systemName: String, tint: Color) -> some View {
        Image(systemName: systemName)
            .font(.footnote)
            .foregroundStyle(tint)
            .padding(6)
            .background(.ultraThinMaterial, in: Circle())
            .padding(8)
    }

    private var actionRow: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                if let caption = photo.caption, !caption.isEmpty {
                    Text(caption).font(.body)
                }
                // a place as a remembered word, not a pin — never tappable
                if let location = photo.location, !location.isEmpty {
                    Text(location)
                        .font(.footnote)
                        .italic()
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            // Owner-only: peek at the warmth + keeping this gathered — faces.
            if isMine {
                Button { showFaces = true } label: {
                    Image(systemName: "person.2")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
            // Held: the keep gesture. Tap is the accessible path; press-and-hold
            // the photo is the primary one. No counts, ever (A2).
            Button {
                Task { await state.toggleAnchor(photo) }
            } label: {
                Image(systemName: photo.anchoredByMe ? "flame.fill" : "flame")
            }
            .buttonStyle(.plain)
            .foregroundStyle(photo.anchoredByMe ? .orange : .secondary)
            .accessibilityLabel(photo.anchoredByMe ? "Let go of this memory" : "Hold this memory")
        }
    }

    @ViewBuilder
    private var comments: some View {
        if !photo.comments.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(photo.comments) { comment in
                    // Story additions, flat and chronological (§8.3).
                    (Text(comment.author.displayName).fontWeight(.medium)
                        + Text("  ") + Text(comment.body))
                        .font(.callout)
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

    private func hold() {
        guard !photo.anchoredByMe else { return }
        withAnimation(.easeOut(duration: 0.2)) { holdProgress = 0 }
        // a soft settle, not a pop
        withAnimation(.spring(response: 0.35, dampingFraction: 0.6)) { settleScale = 0.97 }
        withAnimation(.spring(response: 0.45, dampingFraction: 0.7).delay(0.12)) { settleScale = 1 }
        Task { await state.hold(photo) }
    }

    private func warm() {
        withAnimation(.easeOut(duration: 0.18)) { warmGlow = 1 }
        withAnimation(.easeIn(duration: 0.5).delay(0.18)) { warmGlow = 0 }
        Task { await state.toggleWarmth(photo) }
    }
}

struct ReturnedCard: View {
    @Environment(AppState.self) private var state
    let item: ReturnedItem

    private var heading: String {
        switch item.source {
        case "anniversary": return "Returned · from this day"
        case "near_forgotten": return "Returned · nearly forgotten"
        case "rescue": return "Fading soon · yours"
        default: return "Returned"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(heading)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Rest this memory") {
                    Task { await state.restMemory(photoId: item.photo.id) }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            if let urls = item.photo.urls, let url = state.api.absoluteURL(urls.thumb) {
                AsyncImage(url: url) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    Rectangle().fill(.quaternary)
                }
                .frame(height: 140)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            if let caption = item.photo.caption, !caption.isEmpty {
                Text(caption).font(.callout)
            }
        }
        .padding(12)
        .background(.quinary, in: RoundedRectangle(cornerRadius: 16))
    }
}

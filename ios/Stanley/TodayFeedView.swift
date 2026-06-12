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

struct PhotoCard: View {
    @Environment(AppState.self) private var state
    let photo: Photo
    @State private var newComment = ""

    // The fade is ambient, never numeric (§8.1). decay_progress spans the whole
    // 144h public life, but LIVE (< 1/3) must render fully visible — so the
    // fade starts at the FADING boundary and eases (smoothstep) to "barely
    // visible" by the end of LAST_LIGHT. No countdowns anywhere.
    private var fade: Double {
        let fadingStart = 1.0 / 3.0  // 48h of 144h
        let t = min(1.0, max(0.0, (photo.decayProgress - fadingStart) / (1.0 - fadingStart)))
        return t * t * (3.0 - 2.0 * t)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(photo.owner.displayName)
                    .font(.subheadline.weight(.medium))
                Spacer()
                Text(photo.takenAt, format: .relative(presentation: .named))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let urls = photo.urls, let url = state.api.absoluteURL(urls.image) {
                AsyncImage(url: url) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    Rectangle().fill(.quaternary)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 320)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .saturation(1.0 - 0.85 * fade)
                .opacity(1.0 - 0.82 * fade)
            }
            HStack(alignment: .top) {
                if let caption = photo.caption, !caption.isEmpty {
                    Text(caption)
                        .font(.body)
                }
                Spacer()
                // Anchoring: a private act of keeping. No counts, ever (A2).
                Button {
                    Task { await state.toggleAnchor(photo) }
                } label: {
                    Image(systemName: photo.anchoredByMe ? "bookmark.fill" : "bookmark")
                }
                .buttonStyle(.plain)
                .foregroundStyle(photo.anchoredByMe ? Color.accentColor : Color.secondary)
            }
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
        .padding(.bottom, 8)
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

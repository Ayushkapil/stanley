import SwiftUI

/// The kept archive: memory threads per friend. Tombstones are honest —
/// "a memory was here" — never silently absent (§8.2).
struct MemoriesView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        NavigationStack {
            List {
                if state.threads.isEmpty {
                    Text("Nothing held yet. Press and hold a moment to keep it here — this is the one place nothing fades.")
                        .foregroundStyle(.secondary)
                        .listRowBackground(Color.clear)
                }
                ForEach(state.threads) { thread in
                    Section {
                        ForEach(thread.memories) { memory in
                            MemoryRow(memory: memory)
                        }
                    } header: {
                        HStack(spacing: 8) {
                            AvatarView(url: thread.friend.avatarUrl, name: thread.friend.displayName, size: 22)
                            Text(thread.friend.displayName)
                        }
                    }
                }
            }
            .navigationTitle("Held")
            .refreshable { await state.refreshMemories() }
            .task { await state.refreshMemories() }
        }
    }
}

struct MemoryRow: View {
    @Environment(AppState.self) private var state
    let memory: Memory

    private var heldTrace: String? {
        guard let taken = memory.takenAt else { return nil }
        return "held · \(taken.formatted(date: .abbreviated, time: .omitted))"
    }

    var body: some View {
        HStack(spacing: 12) {
            if memory.isTombstone {
                Image(systemName: "leaf")
                    .foregroundStyle(.secondary)
                    .frame(width: 56, height: 56)
                    .background(.quinary, in: RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 2) {
                    Text("A memory was here")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    if let date = memory.date {
                        Text(date)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            } else {
                if let urls = memory.urls, let url = state.api.absoluteURL(urls.thumb) {
                    AsyncImage(url: url) { image in
                        image.resizable().aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Rectangle().fill(.quaternary)
                    }
                    .frame(width: 56, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                VStack(alignment: .leading, spacing: 2) {
                    if let caption = memory.caption, !caption.isEmpty {
                        Text(caption).font(.callout).lineLimit(1)
                    } else if let takenAt = memory.takenAt {
                        Text(takenAt, style: .date).font(.callout)
                    }
                    if let location = memory.location, !location.isEmpty {
                        Text(location)
                            .font(.caption)
                            .italic()
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    if let note = memory.note, !note.isEmpty {
                        Text(note)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    if let heldTrace {
                        Text(heldTrace)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }
}

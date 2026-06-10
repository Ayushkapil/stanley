import SwiftUI

/// The kept archive: memory threads per friend. Tombstones are honest —
/// "a memory was here" — never silently absent (§8.2).
struct MemoriesView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        NavigationStack {
            List {
                if state.threads.isEmpty {
                    Text("Nothing kept yet. Anchor a moment to keep it here.")
                        .foregroundStyle(.secondary)
                        .listRowBackground(Color.clear)
                }
                ForEach(state.threads) { thread in
                    Section(thread.friend.displayName) {
                        ForEach(thread.memories) { memory in
                            MemoryRow(memory: memory)
                        }
                    }
                }
            }
            .navigationTitle("Kept")
            .refreshable { await state.refreshMemories() }
            .task { await state.refreshMemories() }
        }
    }
}

struct MemoryRow: View {
    @Environment(AppState.self) private var state
    let memory: Memory

    var body: some View {
        HStack(spacing: 12) {
            if memory.tombstone {
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
                    if let note = memory.note, !note.isEmpty {
                        Text(note)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }
}

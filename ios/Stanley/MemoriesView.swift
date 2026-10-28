import SwiftUI

/// The kept archive: memory threads per friend. Tombstones are honest —
/// "a memory was here" — never silently absent (§8.2).
struct MemoriesView: View {
    @Environment(AppState.self) private var state
    @Environment(\.horizontalSizeClass) private var hSizeClass
    private var density: Density { Density(hSizeClass) }

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
                            // The image leads — a kept moment is a picture first,
                            // words second. Tombstones stay quiet and compact.
                            MemoryCard(memory: memory)
                                .listRowSeparator(.hidden)
                                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 10, trailing: 16))
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    if !memory.isTombstone {
                                        Button {
                                            Task { await state.rest(photoId: memory.id) }
                                        } label: {
                                            Label("Rest this memory", systemImage: "moon.zzz")
                                        }
                                        .tint(.indigo)
                                    }
                                }
                        }
                    } header: {
                        HStack(spacing: 8) {
                            AvatarView(url: thread.friend.avatarUrl, name: thread.friend.displayName, size: 22)
                            Text(thread.friend.displayName)
                        }
                    }
                }
            }
            .atmosphereWash()
            .navigationTitle("Held")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    NavigationLink {
                        RestedView()
                    } label: {
                        Label("Rested", systemImage: "moon.zzz")
                    }
                }
            }
            .refreshable { await state.refreshMemories() }
            .task { await state.refreshMemories() }
        }
    }
}

/// Rested memories (§14): set never to resurface, but not deleted — still here,
/// each with a gentle "let it return" undo.
struct RestedView: View {
    @Environment(AppState.self) private var state
    @State private var memories: [Memory] = []
    @State private var loaded = false

    var body: some View {
        List {
            if loaded && memories.isEmpty {
                Text("Nothing rested. Memories you rest stay in Held but never resurface on their own.")
                    .foregroundStyle(.secondary)
                    .listRowBackground(Color.clear)
            }
            ForEach(memories) { memory in
                HStack(spacing: 12) {
                    MemoryRow(memory: memory)
                    Button("Let it return") {
                        Task {
                            await state.unrest(photoId: memory.id)
                            await reload()
                        }
                    }
                    .font(.caption)
                    .buttonStyle(.borderless)
                    .foregroundStyle(.tint)
                }
            }
        }
        .atmosphereWash()
        .navigationTitle("Rested")
        .navigationBarTitleDisplayMode(.inline)
        .task { await reload() }
    }

    private func reload() async {
        memories = await state.loadRested()
        loaded = true
    }
}

/// A kept memory as a large, image-first card (Held tab). The photo gets real
/// presence — full-saturation, most of the card — with the words beneath it.
struct MemoryCard: View {
    @Environment(AppState.self) private var state
    @Environment(\.horizontalSizeClass) private var hSizeClass
    private var density: Density { Density(hSizeClass) }
    let memory: Memory

    private var heldTrace: String? {
        guard let taken = memory.takenAt else { return nil }
        return "held · \(taken.formatted(date: .abbreviated, time: .omitted))"
    }

    var body: some View {
        if memory.isTombstone {
            // An honest absence stays small — a marker, not a monument.
            HStack(spacing: 12) {
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
            }
            .padding(.vertical, 2)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                if let urls = memory.urls, let url = state.api.absoluteURL(urls.image) {
                    Color.clear
                        .frame(height: density.heldPhotoHeight)
                        .overlay {
                            AsyncImage(url: url) { image in
                                image.resizable().aspectRatio(contentMode: .fill)
                            } placeholder: {
                                Rectangle().fill(.quaternary)
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                VStack(alignment: .leading, spacing: 2) {
                    if let caption = memory.caption, !caption.isEmpty {
                        Text(caption).font(.callout.weight(.medium))
                    } else if let takenAt = memory.takenAt {
                        Text(takenAt, style: .date).font(.callout.weight(.medium))
                    }
                    HStack(spacing: 6) {
                        if let location = memory.location, !location.isEmpty {
                            Text(location).italic()
                        }
                        if let heldTrace {
                            Text(heldTrace)
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    if let note = memory.note, !note.isEmpty {
                        Text(note)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
            }
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

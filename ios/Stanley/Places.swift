import Observation
import SwiftUI

/// The places someone has named on their photos, kept on this phone so the
/// next one is a tap away. It's a memory of what they typed: no GPS, no
/// location permission, no maps or places service. Stanley strips GPS at
/// ingest, and a place here is only ever the words a person chose.
///
/// Kept per account (keyed by user id), so a shared phone doesn't show one
/// person's places to another, and an expired sign-in doesn't lose them.
/// Deleting the account erases them. Nothing here is sent anywhere; a place
/// reaches the server only as the label on a photo, as it always did.
@MainActor
@Observable
final class PlaceBook {
    /// "Max 10 favorites": the cap, never shown as a number.
    static let favoriteLimit = 10
    /// How much typed history to keep for search. Recent shows the first five.
    static let historyLimit = 50
    static let recentCount = 5
    /// The server's limit on a place label.
    static let maxLength = 120

    private(set) var favorites: [String]
    /// Newest first, no repeats (ignoring case).
    private(set) var history: [String]
    private let key: String

    init(userId: String?) {
        key = "stanley.places.\(userId ?? "signed-out")"
        let defaults = UserDefaults.standard
        favorites = defaults.stringArray(forKey: key + ".favorites") ?? []
        history = defaults.stringArray(forKey: key + ".history") ?? []
    }

    /// The last few places typed, leaving out favorites, which are listed
    /// above them already.
    var recents: [String] {
        Array(history.filter { !isFavorite($0) }.prefix(Self.recentCount))
    }

    var favoritesFull: Bool { favorites.count >= Self.favoriteLimit }

    func isFavorite(_ place: String) -> Bool {
        favorites.contains { $0.caseInsensitiveCompare(place) == .orderedSame }
    }

    /// Star or unstar. Returns false, changing nothing, when starring would
    /// go past the limit.
    @discardableResult
    func toggleFavorite(_ place: String) -> Bool {
        let place = Self.tidy(place)
        guard !place.isEmpty else { return false }
        if isFavorite(place) {
            favorites.removeAll { $0.caseInsensitiveCompare(place) == .orderedSame }
        } else {
            guard !favoritesFull else { return false }
            favorites.append(place)
        }
        save()
        return true
    }

    /// A place was used on a photo: it goes to the top of the history.
    func remember(_ place: String) {
        let place = Self.tidy(place)
        guard !place.isEmpty else { return }
        history.removeAll { $0.caseInsensitiveCompare(place) == .orderedSame }
        history.insert(place, at: 0)
        if history.count > Self.historyLimit { history.removeLast(history.count - Self.historyLimit) }
        save()
    }

    /// Take a place out of the history. A favorite stays a favorite.
    func forget(_ place: String) {
        history.removeAll { $0.caseInsensitiveCompare(place) == .orderedSame }
        save()
    }

    /// The person's own places that contain what they've typed: favorites,
    /// then history, and within each, the ones that start with it first.
    func matches(_ query: String) -> [String] {
        let query = Self.tidy(query)
        guard !query.isEmpty else { return [] }
        var seen = Set<String>()
        let all = (favorites + history).filter { seen.insert($0.lowercased()).inserted }
        let hits = all.filter { $0.localizedCaseInsensitiveContains(query) }
        let starts = hits.filter { $0.lowercased().hasPrefix(query.lowercased()) }
        return starts + hits.filter { !starts.contains($0) }
    }

    func contains(_ place: String) -> Bool {
        (favorites + history).contains { $0.caseInsensitiveCompare(place) == .orderedSame }
    }

    /// Delete everything kept for one account, as part of deleting it.
    static func erase(userId: String) {
        let key = "stanley.places.\(userId)"
        UserDefaults.standard.removeObject(forKey: key + ".favorites")
        UserDefaults.standard.removeObject(forKey: key + ".history")
    }

    /// Trimmed, single-spaced, and no longer than the server will keep.
    static func tidy(_ place: String) -> String {
        let words = place.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return String(words.prefix(maxLength))
    }

    private func save() {
        UserDefaults.standard.set(favorites, forKey: key + ".favorites")
        UserDefaults.standard.set(history, forKey: key + ".history")
    }
}

/// The capture screen's place line. It looks like the other fields, but a
/// tap opens the picker instead of a keyboard; the clear button empties it.
struct PlaceField: View {
    @Binding var place: String
    let open: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button(action: open) {
                Text(place.isEmpty ? "Where was this? (a place, optional)" : place)
                    .foregroundStyle(place.isEmpty ? .secondary : .primary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Where was this")
            .accessibilityValue(place.isEmpty ? "No place" : place)
            if !place.isEmpty {
                Button { place = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Clear the place")
            }
        }
        .stanleyField()
    }
}

/// Pick a place: search what you've named before, favorites first, then
/// the last few you typed. Anything new can be typed and used as it is. A
/// star keeps a place among the favorites.
struct PlacePicker: View {
    /// Read from this phone's store when the picker opens. Every PlaceBook
    /// writes straight through, so the post that records the place later
    /// can use a book of its own.
    @State private var places: PlaceBook
    let onPick: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query: String
    @State private var full = false

    init(userId: String?, current: String, onPick: @escaping (String) -> Void) {
        _places = State(initialValue: PlaceBook(userId: userId))
        self.onPick = onPick
        _query = State(initialValue: current)
    }

    private var typed: String { PlaceBook.tidy(query) }

    var body: some View {
        NavigationStack {
            List {
                Group {
                    if full {
                        Section {
                            Text("Your favorites are full. Unstar one to make room.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    if typed.isEmpty {
                        browse
                    } else {
                        search
                    }
                }
                .atmosphereRows()
            }
            .atmosphereWash()
            .searchable(
                text: $query,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "A place, as you'd say it"
            )
            .onSubmit(of: .search) {
                if !typed.isEmpty { pick(typed) }
            }
            .navigationTitle("Where was this?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private var browse: some View {
        if !places.favorites.isEmpty {
            Section("Favorites") {
                ForEach(places.favorites, id: \.self) { row($0) }
            }
        }
        if !places.recents.isEmpty {
            Section("Recent") {
                ForEach(places.recents, id: \.self) { place in
                    row(place)
                        .swipeActions {
                            Button("Forget", role: .destructive) { places.forget(place) }
                        }
                }
            }
        }
        if places.favorites.isEmpty && places.recents.isEmpty {
            Section {
                Text("Places you name on your photos will be here next time. Star one to keep it close.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var search: some View {
        // Something new: use it exactly as typed.
        if !places.contains(typed) {
            Section {
                row(typed, title: "Use “\(typed)”")
            }
        }
        let found = places.matches(typed)
        if !found.isEmpty {
            Section("Your places") {
                ForEach(found, id: \.self) { row($0) }
            }
        }
    }

    /// A place to tap, with its star. Both are borderless buttons so each
    /// keeps its own target inside the list row.
    private func row(_ place: String, title: String? = nil) -> some View {
        let starred = places.isFavorite(place)
        return HStack {
            Button { pick(place) } label: {
                Text(title ?? place)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            Button {
                full = !places.toggleFavorite(place)
            } label: {
                Image(systemName: starred ? "star.fill" : "star")
            }
            .buttonStyle(.borderless)
            .tint(.accentColor)
            .accessibilityLabel(starred ? "Remove from favorites" : "Add to favorites")
        }
    }

    private func pick(_ place: String) {
        onPick(PlaceBook.tidy(place))
        dismiss()
    }
}

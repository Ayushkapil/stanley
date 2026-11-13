import SwiftUI
import UIKit
import WidgetKit

// What the app leaves for its home screen widget (build 40). Whenever Today
// has something new, the app writes a small snapshot of it, and a few of the
// circle's newest photos made small, into the App Group folder it shares
// with the widget (`WidgetSnapshot`), and asks the widget to look again. The
// widget never fetches anything itself.
//
// Photos and the note are left only while a Stanley widget is actually on
// the home screen. It's the widget that clears them out once they're stale;
// with no widget there'd be nobody to, and a photo taken back by whoever
// posted it would sit in the folder until the app was next opened.

/// Sits unseen behind the app and keeps the widget's folder up to date: it
/// writes whenever what the widget shows has changed, and once more as the
/// app leaves the screen, so the widget's day of freshness starts then.
struct WidgetFeeder: View {
    @Environment(AppState.self) private var state
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("stanley.atmosphere") private var atmosphere = "auto"
    @AppStorage("stanley.appLock") private var appLock = false

    var body: some View {
        let draft = WidgetFeed.Draft(state, atmosphere: atmosphere, locked: appLock)
        Color.clear
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
            .task(id: draft) { await WidgetFeed.leave(draft) }
            // Leaving, so the widget's day of freshness starts now; and coming
            // back, in case a widget was added or taken away meanwhile.
            .onChange(of: scenePhase) { _, phase in
                if phase != .inactive { Task { await WidgetFeed.leave(draft) } }
            }
    }
}

enum WidgetFeed {
    static let kind = "StanleyWidget"
    /// How many of the circle's newest photos are left for the widget. Its
    /// large size shows three; yours is added if it isn't among them.
    private static let newest = 3
    /// A picture's longest side in the folder: plenty for a print two inches
    /// wide, and small enough that a handful of them is nothing.
    private static let side: CGFloat = 480

    /// Everything the widget shows, gathered from the app as it stands.
    struct Draft: Equatable {
        struct Shot: Equatable {
            let id: String
            let name: String
            let mine: Bool
            let takenAt: Date
            /// The photo as Today shows it (already in memory, if it's been
            /// seen) and its small copy (fetched if it hasn't).
            let image: URL?
            let thumb: URL?
        }

        /// Nothing to write yet: signed in, but Today hasn't answered, so
        /// what's in the folder is still the best there is.
        let pending: Bool
        let signedIn: Bool
        let circleName: String?
        let atmosphere: String
        let locked: Bool
        let countdown: Countdown?
        let posted: Bool
        let note: WidgetSnapshot.Note?
        let shots: [Shot]

        @MainActor
        init(_ state: AppState, atmosphere: String, locked: Bool) {
            signedIn = state.signedIn
            pending = state.signedIn && (!state.checkedCircle || (state.circle != nil && !state.todayLoaded))
            circleName = state.circle?.name
            self.atmosphere = atmosphere
            self.locked = locked
            countdown = state.circle?.countdown
            posted = state.sharedToday != nil || state.holdsTheDay
            let today = WidgetSnapshot.day(.now)
            note = locked ? nil : state.notes.first.map {
                .init(text: $0.text, name: Self.first($0.author.displayName), day: today)
            }
            let photos = state.feedItems
                .flatMap { item in item.photo.map { [$0] } ?? item.photos ?? [] }
                .sorted { $0.takenAt > $1.takenAt }
            var picked = Array(photos.prefix(WidgetFeed.newest))
            if let mine = photos.first(where: { $0.owner.id == state.myId }),
               !picked.contains(where: { $0.id == mine.id }) {
                picked.append(mine)
            }
            shots = locked ? [] : picked.map { photo in
                Shot(
                    id: photo.id,
                    name: Self.first(photo.owner.displayName),
                    mine: state.myId != nil && photo.owner.id == state.myId,
                    takenAt: photo.takenAt,
                    image: photo.urls.flatMap { state.api.absoluteURL($0.image) },
                    thumb: photo.urls.flatMap { state.api.absoluteURL($0.thumb) }
                )
            }
        }

        private static func first(_ name: String) -> String {
            name.split(separator: " ").first.map(String.init) ?? name
        }
    }

    /// Write the draft into the shared folder and tell the widget. Signed
    /// out, the folder is emptied: nothing of anyone's stays behind.
    @MainActor
    static func leave(_ draft: Draft) async {
        guard !draft.pending else { return }
        guard draft.signedIn else {
            WidgetStore.prune(keeping: [])
            publish(.signedOut)
            return
        }
        // No widget on the home screen: nobody's photos or words are left
        // behind, only what the widget's own gallery preview needs.
        let wanted = await onHomeScreen()
        var kept: [WidgetSnapshot.Shot] = []
        for shot in wanted ? draft.shots : [] {
            let file = "\(shot.id).jpg"
            guard await picture(for: shot, named: file) else { continue }
            kept.append(.init(id: shot.id, file: file, name: shot.name, mine: shot.mine, takenAt: shot.takenAt))
        }
        // Overtaken by a newer draft while the pictures came down: that one
        // writes, not this.
        guard !Task.isCancelled else { return }
        WidgetStore.prune(keeping: Set(kept.map(\.file)))
        publish(WidgetSnapshot(
            writtenAt: .now,
            signedIn: true,
            circleName: draft.circleName,
            atmosphere: draft.atmosphere,
            countdown: draft.countdown,
            postedOn: draft.posted ? WidgetSnapshot.day(.now) : nil,
            note: wanted ? draft.note : nil,
            photos: kept,
            locked: draft.locked,
            withheld: wanted ? nil : true
        ))
    }

    /// Whether a Stanley widget is on the home screen (or in Today View)
    /// right now.
    @MainActor
    private static func onHomeScreen() async -> Bool {
        #if DEBUG
        if WidgetGallery.asked { return true }
        #endif
        return await withCheckedContinuation { done in
            WidgetCenter.shared.getCurrentConfigurations { result in
                let found = (try? result.get())?.contains { $0.kind == kind } ?? false
                done.resume(returning: found)
            }
        }
    }

    /// Store the snapshot, and have the widget read it if it says anything
    /// new (or the last one it read is getting old).
    private static func publish(_ snapshot: WidgetSnapshot) {
        let before = WidgetStore.read()
        WidgetStore.write(snapshot)
        var same = before
        same.writtenAt = snapshot.writtenAt
        if same != snapshot || snapshot.writtenAt.timeIntervalSince(before.writtenAt) > 15 * 60 {
            WidgetCenter.shared.reloadTimelines(ofKind: kind)
        }
    }

    /// Make sure the shot's small picture is in the folder: there already,
    /// or cut down from the photo Today has in memory, or fetched as the
    /// server's own small copy. False when it can't be had right now.
    private static func picture(for shot: Draft.Shot, named file: String) async -> Bool {
        guard let folder = WidgetStore.photos, let target = WidgetStore.photo(file) else { return false }
        if FileManager.default.fileExists(atPath: target.path) { return true }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var data: Data?
        if let image = shot.image.flatMap(PhotoMemory.image(for:)) {
            data = small(image).jpegData(compressionQuality: 0.82)
        } else if let thumb = shot.thumb,
                  let (fetched, response) = try? await URLSession.shared.data(from: thumb),
                  (response as? HTTPURLResponse)?.statusCode == 200,
                  UIImage(data: fetched) != nil {
            data = fetched
        }
        guard let data else { return false }
        // Readable while the phone is locked after its first unlock, as a
        // widget needs, and never copied off in a backup: it's a cache.
        do {
            try data.write(to: target, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            var url = target
            try? url.setResourceValues(values)
            return true
        } catch {
            return false
        }
    }

    private static func small(_ image: UIImage) -> UIImage {
        let longest = max(image.size.width, image.size.height) * image.scale
        guard longest > side else { return image }
        let ratio = side / longest
        let size = CGSize(
            width: (image.size.width * image.scale * ratio).rounded(),
            height: (image.size.height * image.scale * ratio).rounded()
        )
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }
}

#if DEBUG
/// The three sizes of the widget laid out on one screen, from whatever the
/// app last left in the shared folder, to be looked at on a simulator: a
/// Debug build launched with `STANLEY_WIDGET_GALLERY=1`. The home screen
/// draws the same views (`Shared/WidgetViews.swift`).
struct WidgetGallery: View {
    @Environment(AppState.self) private var state
    @State private var snapshot = WidgetStore.read()

    static var asked: Bool { ProcessInfo.processInfo.environment["STANLEY_WIDGET_GALLERY"] == "1" }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                HStack(spacing: 14) {
                    tile(.small, width: 158, height: 158)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("written \(snapshot.writtenAt.formatted(date: .omitted, time: .standard))")
                        Text("\(snapshot.photos.count) photos · \(snapshot.note == nil ? "no note" : "note")")
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                tile(.medium, width: 338, height: 158)
                tile(.large, width: 338, height: 354)
            }
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
        }
        .background(Color(white: 0.5).ignoresSafeArea())
        .task {
            // Today, as the app would load it, then what it left behind.
            await state.loadProfile()
            await state.loadCircle()
            await state.refreshToday()
            for _ in 0..<20 {
                try? await Task.sleep(for: .milliseconds(500))
                snapshot = WidgetStore.read()
            }
        }
    }

    private func tile(_ size: WidgetSize, width: CGFloat, height: CGFloat) -> some View {
        StanleyWidgetView(snapshot: snapshot, date: .now, size: size)
            .padding(16)
            .frame(width: width, height: height)
            .background(WidgetBackdrop(atmosphere: snapshot.atmosphere))
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}
#endif

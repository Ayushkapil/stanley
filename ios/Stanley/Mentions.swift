import SwiftUI
import UIKit

/// @mentions in stories (build 19): "remember when @Ben fell asleep in the
/// lounge". Typing @ in a story offers the circle's people; the one picked is
/// written into the story as `@[<user id>]`, which is what the server stores,
/// and every phone draws it back as that person's name, bold, in their own
/// watercolor tone, a tap away from their profile.
///
/// Quiet, like everything else: being mentioned sends nothing anywhere. The
/// person sees it when they read the story, as everyone in the circle does.
/// A mention isn't a who-was-there tag either; it's words in a story.
enum Mentions {
    /// How a mention is written in a story, on the server and in transit.
    static func token(_ userId: String) -> String { "@[\(userId)]" }

    /// One stretch of a story: plain words, or a person it mentions.
    enum Part: Hashable {
        case words(String)
        case person(String)
    }

    static func parts(_ body: String) -> [Part] {
        var parts: [Part] = []
        var rest = body[...]
        while let match = rest.firstMatch(of: /@\[([A-Za-z0-9_-]{1,64})\]/) {
            if match.range.lowerBound > rest.startIndex {
                parts.append(.words(String(rest[rest.startIndex..<match.range.lowerBound])))
            }
            parts.append(.person(String(match.output.1)))
            rest = rest[match.range.upperBound...]
        }
        if !rest.isEmpty { parts.append(.words(String(rest))) }
        return parts
    }

    /// The link a mentioned name carries, caught by the view that shows the
    /// story (`openURL`) to open that person's profile. Never leaves the app.
    static func link(_ userId: String) -> URL? { URL(string: "stanley-member://\(userId)") }

    /// The person a mention link points at, if it is one.
    static func person(in url: URL) -> String? {
        url.scheme == "stanley-member" ? url.host() : nil
    }
}

/// Ten watercolor tones for the people in a circle: soft coral, sage, dusty
/// blue, warm clay, muted gold, lavender, dusty rose, slate teal, olive and
/// plum. Muted, never primary. Each has a deeper light-mode ink, to read on
/// warm paper, and a paler dark-mode one, to read on black.
enum MentionInk {
    private static let tones: [(light: UInt32, dark: UInt32)] = [
        (0xC0604F, 0xE89A8B), // soft coral
        (0x5E8460, 0x9CC29C), // sage
        (0x56789E, 0x9AB7D6), // dusty blue
        (0xA8643E, 0xD9A07E), // warm clay
        (0x9C7C2A, 0xD6BD72), // muted gold
        (0x7D68A8, 0xB8A6DD), // lavender
        (0xA65C78, 0xDB9AB2), // dusty rose
        (0x3F7F80, 0x86C0BF), // slate teal
        (0x6E7A3A, 0xB2BC7C), // olive
        (0x8A4E7C, 0xC690BA), // plum
    ]

    static var count: Int { tones.count }

    static func color(_ index: Int) -> Color {
        let tone = tones[((index % count) + count) % count]
        return Color(UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? tone.dark : tone.light)
        })
    }
}

/// Whose tone is whose, per circle, kept on this phone, so the same person is
/// always the same color in that circle. Everyone in the roster is given one
/// the first time it's needed, in the order they joined, so the first ten
/// people never share a tone; after ten the tones come round again.
@MainActor
enum MentionTones {
    private static func key(_ circleId: String) -> String { "stanley.mentionTones.\(circleId)" }

    static func index(for userId: String, in circle: CircleInfo) -> Int {
        let defaults = UserDefaults.standard
        var map = (defaults.dictionary(forKey: key(circle.id)) as? [String: Int]) ?? [:]
        if let known = map[userId] { return known }
        let roster = (circle.members ?? []).sorted { $0.joinedAt < $1.joinedAt }.map(\.id)
        for id in roster + [userId] where map[id] == nil {
            let used = Set(map.values)
            map[id] = (0..<MentionInk.count).first { !used.contains($0) } ?? map.count % MentionInk.count
        }
        defaults.set(map, forKey: key(circle.id))
        return map[userId] ?? 0
    }
}

/// Who a mention in this circle is: their name, and their tone. Someone no
/// longer in the circle (or never in it) reads as "someone", in plain ink.
@MainActor
struct MentionDirectory {
    let circle: CircleInfo?

    func name(_ userId: String) -> String? {
        guard let member = circle?.members?.first(where: { $0.id == userId }) else { return nil }
        return member.displayName ?? "New member"
    }

    func color(_ userId: String) -> Color {
        guard let circle else { return .primary }
        return MentionInk.color(MentionTones.index(for: userId, in: circle))
    }

    /// The tone a story's writer's name is written in (build 39): their own
    /// in this circle, given the first time it's needed. Someone who isn't
    /// in the circle on screen (a photo held from another circle, or someone
    /// who has left) keeps the page's ink.
    func nameColor(_ userId: String?) -> Color {
        guard let userId, let circle, circle.members?.contains(where: { $0.id == userId }) == true else {
            return DarkRoom.ink
        }
        return MentionInk.color(MentionTones.index(for: userId, in: circle))
    }
}

/// The people a story being written could mention right now, and what
/// picking one does. The composer with the cursor in it fills this in;
/// whatever screen holds the composer shows it in a `MentionBar` along its
/// bottom edge, which sits right on top of the keyboard while it's up. (A
/// keyboard toolbar item, declared from inside a lazy list's cell, never
/// appeared.)
@MainActor
@Observable
final class MentionOffer {
    private(set) var people: [CircleMember] = []
    private var choose: ((CircleMember) -> Void)?
    private var owner: UUID?

    func offer(_ people: [CircleMember], from owner: UUID, choose: @escaping (CircleMember) -> Void) {
        self.people = people
        self.choose = choose
        self.owner = owner
    }

    /// Withdraw an offer, but only one's own: the composer that lost the
    /// cursor mustn't clear the one that just gained it.
    func withdraw(_ owner: UUID) {
        guard self.owner == owner else { return }
        people = []
        choose = nil
        self.owner = nil
    }

    func pick(_ member: CircleMember) { choose?(member) }
}

/// The people on offer, as a row of faces and first names in their tones,
/// along the bottom of the screen. Nothing at all when no one's on offer.
struct MentionBar: View {
    @Environment(AppState.self) private var state

    var body: some View {
        let people = state.mentionOffer.people
        if !people.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(people) { member in
                        Button { state.mentionOffer.pick(member) } label: {
                            HStack(spacing: 6) {
                                AvatarView(url: member.avatarUrl, name: member.displayName, size: 24)
                                Text(firstName(member))
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(tone(member.id))
                                    .lineLimit(1)
                            }
                            .padding(.leading, 4)
                            .padding(.trailing, 12)
                            .padding(.vertical, 5)
                            .glass(in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Mention \(member.displayName ?? "New member")")
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
            .background(.ultraThinMaterial)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private func firstName(_ member: CircleMember) -> String {
        let full = member.displayName ?? "New member"
        return full.split(separator: " ").first.map(String.init) ?? full
    }

    private func tone(_ id: String) -> Color {
        guard let circle = state.circle else { return .primary }
        return MentionInk.color(MentionTones.index(for: id, in: circle))
    }
}

/// Writing a story, with @ to mention someone: the field, an Add button once
/// there are words, and, while an @ is being typed, the circle's people on
/// offer in the `MentionBar` above the keyboard. The field shows "@Name";
/// what's sent is `@[id]`. Return sends too, as Add does.
struct StoryComposer: View {
    @Environment(AppState.self) private var state
    let photo: Photo
    /// The story once it's in, for a thread that shows it straight away.
    var onPosted: (Comment) -> Void = { _ in }
    @State private var text = ""
    @FocusState private var focused: Bool
    @State private var me = UUID()
    /// The mentions picked while writing: "@Name" as shown, and whose it is.
    @State private var picked: [String: String] = [:]

    /// What's being typed after an @ that starts a word, if anything.
    private var query: String? {
        guard let at = text.lastIndex(of: "@") else { return nil }
        if at > text.startIndex, !text[text.index(before: at)].isWhitespace { return nil }
        let typed = text[text.index(after: at)...]
        if typed.contains(where: \.isWhitespace) { return nil }
        return String(typed)
    }

    private var candidates: [CircleMember] {
        guard let query else { return [] }
        let q = query.lowercased()
        return (state.circle?.members ?? [])
            .filter { $0.id != state.myId }
            .filter { member in
                guard !q.isEmpty else { return true }
                let name = (member.displayName ?? "").lowercased()
                return name.hasPrefix(q) || name.split(separator: " ").contains { $0.hasPrefix(q) }
            }
            .prefix(8)
            .map { $0 }
    }

    var body: some View {
        HStack {
            // `storyField()`'s look, with the focus kept here, where the
            // picker needs it (one focus binding per field, not two).
            // In a hand: what you remember is yours to write (build 44).
            TextField("", text: $text, prompt: .fieldPrompt(StoryLine.prompt))
                .font(.hand(17, relativeTo: .callout))
                .textFieldStyle(.plain)
                .focused($focused)
                // Return used to close the keyboard and leave the words
                // sitting there unsent, which read as a story that wouldn't
                // post. It sends now, the way Add does.
                .submitLabel(.send)
                .onSubmit(send)
                .frame(minHeight: 32)
                .contentShape(Rectangle())
                .onTapGesture { focused = true }
            if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Button("Add", action: send)
                    .font(.system(.callout, design: .rounded).weight(.medium))
            }
        }
        .onChange(of: focused) { refreshOffer() }
        .onChange(of: text) { refreshOffer() }
        .onDisappear { state.mentionOffer.withdraw(me) }
    }

    /// Offer the people matching what's after the @, while this field has
    /// the cursor; otherwise take the offer back.
    private func refreshOffer() {
        let people = focused ? candidates : []
        if people.isEmpty {
            state.mentionOffer.withdraw(me)
        } else {
            withAnimation(.easeOut(duration: 0.18)) {
                state.mentionOffer.offer(people, from: me) { mention($0) }
            }
        }
    }

    /// Swap the "@que" being typed for the person's name, and remember whose.
    private func mention(_ member: CircleMember) {
        guard let at = text.lastIndex(of: "@") else { return }
        let shown = "@" + (member.displayName ?? "New member")
        text = String(text[..<at]) + shown + " "
        picked[shown] = member.id
    }

    /// Each "@Name" that was picked (and not since edited) goes as `@[id]`.
    /// The field clears at once; if the story doesn't go, the words come
    /// back (unless something new has been typed), so nothing is lost.
    private func send() {
        let typed = text, mentions = picked
        var body = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return }
        for (shown, id) in mentions.sorted(by: { $0.key.count > $1.key.count }) {
            let pattern = NSRegularExpression.escapedPattern(for: shown) + "(?![\\p{L}\\p{N}])"
            body = body.replacingOccurrences(of: pattern, with: Mentions.token(id), options: .regularExpression)
        }
        text = ""
        picked = [:]
        Task {
            if let story = await state.comment(on: photo, body: body) {
                onPosted(story)
            } else if text.isEmpty {
                text = typed
                picked = mentions
            }
        }
    }
}

private extension UIColor {
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

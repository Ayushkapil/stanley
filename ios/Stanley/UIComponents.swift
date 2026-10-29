import SwiftUI
import UIKit

extension Font {
    /// The profile's keepsake serif. Drop CormorantGaramond-Medium.ttf into the
    /// bundle (and UIAppFonts) and it's used automatically; until then this
    /// falls back to the system serif, which reads the same way.
    static func keepsake(_ size: CGFloat) -> Font {
        if UIFont(name: "CormorantGaramond-Medium", size: size) != nil {
            return .custom("CormorantGaramond-Medium", size: size)
        }
        return .system(size: size, design: .serif)
    }

    /// A decorative editorial display face for the weekly-mosaic captions —
    /// Instagram-deco in spirit. Prefers Didot, then Bodoni 72, then Georgia
    /// (all built into iOS — nothing bundled), finally the system serif.
    static func mosaicDeco(_ size: CGFloat) -> Font {
        for name in ["Didot", "BodoniSvtyTwoITCTT-Book", "Georgia"] {
            if UIFont(name: name, size: size) != nil {
                return .custom(name, size: size)
            }
        }
        return .system(size: size, design: .serif)
    }
}

/// A soft-cornered square face (Part 6) — avatars echo the memory tiles, never
/// circles. Falls back to an initial on a quiet tint when there's no avatar.
struct AvatarView: View {
    let url: String?
    let name: String?
    var size: CGFloat = 44
    // A single identity avatar is a soft square (echoes memory tiles, Part 6).
    // A presence *stack* uses circles — the universal "who's here" idiom — so it
    // never reads as a row of toggle chips.
    var circular: Bool = false

    @Environment(AppState.self) private var state

    private var initial: String {
        String(name?.trimmingCharacters(in: .whitespaces).first ?? "·").uppercased()
    }

    private var clip: AnyShape {
        circular
            ? AnyShape(Circle())
            : AnyShape(RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
    }

    var body: some View {
        Group {
            if let url, let resolved = state.api.absoluteURL(url) {
                AsyncImage(url: resolved) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    placeholder
                }
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size)
        .clipShape(clip)
        .overlay(clip.stroke(.separator, lineWidth: 0.5))
    }

    private var placeholder: some View {
        ZStack {
            Rectangle().fill(.quaternary)
            Text(initial)
                .font(.system(size: size * 0.4, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }
}

/// A "who's here" stack: overlapping circular avatars, tucked into each other so
/// the eye reads people, not buttons (and never a count). Faces, not numbers.
struct FaceCluster: View {
    let faces: [(id: String, url: String?, name: String?)]
    var size: CGFloat = 30

    var body: some View {
        HStack(spacing: -size * 0.42) {
            ForEach(faces, id: \.id) { face in
                AvatarView(url: face.url, name: face.name, size: size, circular: true)
                    .overlay(Circle().stroke(Color(.systemBackground), lineWidth: 2))
            }
        }
    }
}

/// The circle as faces, not a number (Part 6).
struct AvatarCluster: View {
    let members: [CircleMember]
    var size: CGFloat = 36
    /// A ceiling on faces, not a count of them. Overflow is silent — showing
    /// "+7" would be a tally, which is exactly what A2 forbids.
    var maxFaces: Int?

    private var shown: [CircleMember] {
        guard let maxFaces else { return members }
        return Array(members.prefix(maxFaces))
    }

    var body: some View {
        FaceCluster(
            faces: shown.map { (id: $0.id, url: $0.avatarUrl, name: $0.displayName) },
            size: size
        )
    }
}

/// Owner-only peek at who liked and who held a photo — faces, never a count.
/// The circle never sees this; the server enforces owner-only too.
struct FacesSheet: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss
    let photoId: String

    @State private var liked: [UserBrief] = []
    @State private var held: [HeldByEntry] = []
    @State private var loaded = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if held.isEmpty {
                        Text("No one yet.").foregroundStyle(.secondary)
                    }
                    ForEach(held, id: \.id) { entry in
                        FaceRow(face: entry.user, glyph: "bookmark.fill", tint: .accentColor)
                    }
                } header: {
                    Text("Held by")
                } footer: {
                    Text("Who kept this moment. Only you can see this.")
                }
                Section {
                    if liked.isEmpty {
                        Text("No likes yet.").foregroundStyle(.secondary)
                    }
                    ForEach(liked, id: \.id) { face in
                        FaceRow(face: face, glyph: "heart.fill", tint: .pink)
                    }
                } header: {
                    Text("Liked by")
                } footer: {
                    Text("Likes fade with the photo — when it leaves Today, this is gone for good.")
                }
            }
            .navigationTitle("Your circle's care")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .task {
                if !loaded {
                    held = await state.heldByFaces(photoId)
                    liked = await state.likeFaces(photoId)
                    loaded = true
                }
            }
        }
    }
}

/// One face in an owner-only list (who held / who liked).
struct FaceRow: View {
    let face: UserBrief
    let glyph: String
    let tint: Color

    var body: some View {
        HStack(spacing: 12) {
            AvatarView(url: face.avatarUrl, name: face.displayName, size: 36)
            Text(face.displayName)
            Spacer()
            Image(systemName: glyph).foregroundStyle(tint)
        }
    }
}

/// Share sheet for the exported memories zip.
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

extension String {
    /// Whitespace-only is the same as absent, for anything we show a person.
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

/// A text field that stays visible on any background, in either mode.
///
/// `.roundedBorder` draws a hairline bezel that all but disappears against a
/// dark background on real hardware — on device the capture fields read as
/// black rectangles with no edge, no padding and a placeholder you have to
/// hunt for. This draws its own fill and border from the semantic palette, so
/// the field has a shape of its own wherever it lands.
///
/// Only for fields on custom surfaces. Fields inside a `Form` or `List` get a
/// proper row background from the system already; boxing those would double
/// the chrome and stop them looking like iOS.
private struct StanleyFieldBox: ViewModifier {
    func body(content: Content) -> some View {
        content
            .textFieldStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(.quinary)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color(.separator), lineWidth: 1)
            )
    }
}

extension View {
    func stanleyField() -> some View { modifier(StanleyFieldBox()) }
    func storyField() -> some View { modifier(StoryField()) }
}

/// A field that belongs to the words around it, not to a form.
///
/// "Add to the story…" sits under a photo's stories the way a comment line
/// sits flat beneath a post: placeholder text at the card's own inner margin,
/// no box, no bezel. The card is the container. The row is taller than its
/// one line of text so it is easy to land on, without drawing anything to
/// show for it.
private struct StoryField: ViewModifier {
    @FocusState private var focused: Bool
    func body(content: Content) -> some View {
        content
            .textFieldStyle(.plain)
            .focused($focused)
            .frame(minHeight: 32)
            // The text is one line tall; the rest of the row only counts as
            // the field if we say so, and nothing drawn says where it begins.
            .contentShape(Rectangle())
            .onTapGesture { focused = true }
    }
}

extension Text {
    /// A placeholder you can actually read. The system's `placeholderText` is
    /// dim enough on an OLED panel to look like an empty box.
    static func fieldPrompt(_ string: String) -> Text {
        Text(string).foregroundColor(.secondary)
    }
}

/// The username rule, stated once on this side of the wire.
///
/// Mirrors `USERNAME_RE` in `routes/me.py` — `^(?![0-9])[a-z0-9._]{3,30}$` —
/// so the answer the field gives while you type is the answer the server will
/// give when you save. Shared by the name gate and the edit sheet; two copies
/// of a validation rule is one too many.
enum Username {
    enum Status { case idle, checking, invalid, taken, available }

    static func isLocallyValid(_ u: String) -> Bool {
        guard (3...30).contains(u.count) else { return false }
        guard let first = u.first, !(first.isASCII && first.isNumber) else { return false }
        return u.allSatisfy { c in c.isASCII && (c.isLowercase || c.isNumber || c == "." || c == "_") }
    }

    static let rule = "Three to thirty characters. Letters, numbers, . and _ — can't start with a number."

    @ViewBuilder
    static func footer(for status: Status) -> some View {
        switch status {
        case .idle:
            Text(rule)
        case .checking:
            Text("Checking…")
        case .invalid:
            Text(rule).foregroundStyle(.orange)
        case .taken:
            Text("That username is taken.").foregroundStyle(.orange)
        case .available:
            Text("Available.").foregroundStyle(.green)
        }
    }
}

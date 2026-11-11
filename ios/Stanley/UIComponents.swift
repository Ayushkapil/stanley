import SwiftUI
import UIKit

extension Font {
    /// Stanley's own voice for names and page titles: SF Rounded, warm and
    /// a little informal, the way a name is written on a page someone keeps.
    /// It was a serif until build 19; serif now belongs to the World tab
    /// alone (the morning paper), so personal pages and the paper never read
    /// as the same thing.
    static func keepsake(_ size: CGFloat, weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }

    /// Handwriting, for the words that are a person's own hand on the page:
    /// a name on a photo, a sticky note. Noteworthy is built into iOS; the
    /// system's rounded face stands in if it's ever missing. Scales with
    /// Dynamic Type from `size`.
    static func hand(_ size: CGFloat, bold: Bool = false, relativeTo style: Font.TextStyle = .body) -> Font {
        let name = bold ? "Noteworthy-Bold" : "Noteworthy-Light"
        if UIFont(name: name, size: size) != nil {
            return .custom(name, size: size, relativeTo: style)
        }
        return .system(style, design: .rounded).weight(bold ? .semibold : .regular)
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
    @AppStorage("stanley.atmosphere") private var raw = "auto"

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
                SignedImage(url: resolved) { image in
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
        // A thin ring in the atmosphere's accent round every face (build
        // 39; it was a half-point separator gray).
        .overlay(clip.stroke(Atmosphere.resolve(raw).palette.accent.opacity(0.7), lineWidth: 1).padding(0.5))
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

/// A screen's one action, as wide as the screen, in the atmosphere's accent
/// with its ink for the words: capture's Take photo and Post, and setup's
/// Continue. While it's working it holds a spinner in place of the words and
/// takes no second tap; disabled, it fades back.
struct WideButton: View {
    let title: String
    var systemImage: String?
    var busy = false
    let action: () -> Void
    @AppStorage("stanley.atmosphere") private var raw = "auto"
    @Environment(\.isEnabled) private var enabled

    var body: some View {
        let palette = Atmosphere.resolve(raw).palette
        Button(action: action) {
            ZStack {
                if busy {
                    ProgressView().tint(palette.ink)
                } else if let systemImage {
                    Label(title, systemImage: systemImage)
                } else {
                    Text(title)
                }
            }
            .font(.headline)
            .foregroundStyle(palette.ink)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(palette.accent, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .opacity(enabled || busy ? 1 : 0.4)
        }
        .buttonStyle(.plain)
        .disabled(busy)
        .accessibilityLabel(title)
        .accessibilityValue(busy ? "In progress" : "")
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
                Group {
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
                .atmosphereRows()
            }
            .atmosphereWash()
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

extension View {
    func storyField() -> some View { modifier(StoryField()) }
}

/// A field that belongs to the words around it, not to a form.
///
/// "What do you remember?" sits under a photo's stories the way a comment line
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

    /// The system's orange and green read at about 2:1 on the light paper,
    /// too faint to say "taken" (the QA audit, build 30). Deeper in daylight,
    /// the system's own in the dark.
    static let warning = Color(UIColor { $0.userInterfaceStyle == .dark
        ? .systemOrange : UIColor(red: 0.66, green: 0.30, blue: 0.02, alpha: 1) })
    static let fine = Color(UIColor { $0.userInterfaceStyle == .dark
        ? .systemGreen : UIColor(red: 0.11, green: 0.44, blue: 0.20, alpha: 1) })

    @ViewBuilder
    static func footer(for status: Status) -> some View {
        switch status {
        case .idle:
            Text(rule)
        case .checking:
            Text("Checking…")
        case .invalid:
            Text(rule).foregroundStyle(Self.warning)
        case .taken:
            Text("That username is taken.").foregroundStyle(Self.warning)
        case .available:
            Text("Available.").foregroundStyle(Self.fine)
        }
    }
}

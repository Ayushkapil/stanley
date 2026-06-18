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

    var body: some View {
        FaceCluster(
            faces: members.map { (id: $0.id, url: $0.avatarUrl, name: $0.displayName) },
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

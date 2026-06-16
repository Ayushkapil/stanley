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

    @Environment(AppState.self) private var state

    private var initial: String {
        String(name?.trimmingCharacters(in: .whitespaces).first ?? "·").uppercased()
    }

    var body: some View {
        let radius = size * 0.28
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
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(.separator, lineWidth: 0.5)
        )
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

/// The circle as faces, not a number (Part 6): overlapping soft squares.
struct AvatarCluster: View {
    let members: [CircleMember]
    var size: CGFloat = 36

    var body: some View {
        HStack(spacing: -size * 0.28) {
            ForEach(members) { member in
                AvatarView(url: member.avatarUrl, name: member.displayName, size: size)
                    .overlay(
                        RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                            .strokeBorder(Color(.systemBackground), lineWidth: 2)
                    )
            }
        }
    }
}

/// Owner-only peek at the warmth and keeping a photo gathered — faces, never a
/// count. The circle never sees this; the server enforces owner-only too.
struct FacesSheet: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss
    let photoId: String

    @State private var warmed: [UserBrief] = []
    @State private var held: [HeldByEntry] = []
    @State private var loaded = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if held.isEmpty {
                        Text("No one yet.").foregroundStyle(.secondary)
                    }
                    ForEach(held) { entry in
                        HStack(spacing: 12) {
                            AvatarView(url: entry.user.avatarUrl, name: entry.user.displayName, size: 36)
                            Text(entry.user.displayName)
                            Spacer()
                            Image(systemName: "flame.fill").foregroundStyle(.orange)
                        }
                    }
                } header: {
                    Text("Held by")
                } footer: {
                    Text("Who kept this moment. Only you can see this.")
                }
                Section {
                    if warmed.isEmpty {
                        Text("No warmth yet.").foregroundStyle(.secondary)
                    }
                    ForEach(warmed) { face in
                        HStack(spacing: 12) {
                            AvatarView(url: face.avatarUrl, name: face.displayName, size: 36)
                            Text(face.displayName)
                            Spacer()
                            Image(systemName: "sun.min.fill").foregroundStyle(.yellow)
                        }
                    }
                } header: {
                    Text("Warmth")
                } footer: {
                    Text("Warmth fades with the photo — when it leaves Today, this is gone for good.")
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
                    warmed = await state.warmthFaces(photoId)
                    loaded = true
                }
            }
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

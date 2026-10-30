import PhotosUI
import SwiftUI

/// A tappable avatar that lets you pick and crop a new one (Part 6). The crop
/// is a real pan/zoom over a square mask; the server also guarantees a square.
struct AvatarEditor: View {
    @Environment(AppState.self) private var state
    @State private var picked: PhotosPickerItem?
    @State private var toCrop: UIImage?

    var body: some View {
        // Read here, on the main actor; the picker's label closure isn't.
        let profile = state.profile
        PhotosPicker(selection: $picked, matching: .images, photoLibrary: .shared()) {
            ZStack(alignment: .bottomTrailing) {
                AvatarView(url: profile?.avatarUrl, name: profile?.displayName, size: 84)
                Image(systemName: "pencil.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.white, Color.accentColor)
                    .offset(x: 4, y: 4)
            }
        }
        .onChange(of: picked) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    toCrop = image
                }
                picked = nil
            }
        }
        .sheet(
            item: Binding(
                get: { toCrop.map { IdentifiableImage(image: $0) } },
                set: { _ in toCrop = nil }
            )
        ) { wrapped in
            AvatarCropView(image: wrapped.image) { jpeg in
                Task { await state.uploadAvatar(jpeg: jpeg) }
            }
        }
    }
}

private struct IdentifiableImage: Identifiable {
    let id = UUID()
    let image: UIImage
}

/// Square crop: pan and zoom the image within a square mask; "Use" rasterizes
/// exactly what's framed (WYSIWYG) via ImageRenderer.
struct AvatarCropView: View {
    let image: UIImage
    let onComplete: (Data) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @State private var displaySide: CGFloat = 300

    private func framed(side: CGFloat) -> some View {
        Image(uiImage: image)
            .resizable()
            .scaledToFill()
            .scaleEffect(scale)
            .offset(offset)
            .frame(width: side, height: side)
            .clipped()
    }

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                let side = min(geo.size.width, geo.size.height) - 32
                VStack {
                    Spacer()
                        .onAppear { displaySide = side }
                    framed(side: side)
                        .clipShape(RoundedRectangle(cornerRadius: side * 0.18, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: side * 0.18, style: .continuous)
                                .strokeBorder(.separator, lineWidth: 0.5)
                        )
                        .contentShape(Rectangle())
                        .gesture(
                            MagnificationGesture()
                                .onChanged { scale = max(1, lastScale * $0) }
                                .onEnded { _ in lastScale = scale }
                        )
                        .simultaneousGesture(
                            DragGesture()
                                .onChanged {
                                    offset = CGSize(
                                        width: lastOffset.width + $0.translation.width,
                                        height: lastOffset.height + $0.translation.height
                                    )
                                }
                                .onEnded { _ in lastOffset = offset }
                        )
                    Text("Drag to move · pinch to zoom")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.top, 12)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            }
            .navigationTitle("Crop")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Use") { commit() }
                }
            }
        }
    }

    @MainActor
    private func commit() {
        // Render at the on-screen side so the crop is exactly what was framed.
        let renderer = ImageRenderer(content: framed(side: displaySide))
        renderer.scale = 3
        if let ui = renderer.uiImage, let jpeg = ui.jpegData(compressionQuality: 0.9) {
            onComplete(jpeg)
        }
        dismiss()
    }
}

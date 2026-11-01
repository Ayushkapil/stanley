import PhotosUI
import SwiftUI

/// Choose a photo of yourself, move and scale it into a square, and upload
/// it. One piece, shared by the You tab's face, the edit sheet's "Change
/// photo" and setup's last step, so all three behave the same.
///
/// The crop is its own full-screen step, the way iOS's own "Move and Scale"
/// is. It used to be a sheet, and two things broke it. A drag on the photo
/// also pulled at the sheet, so on a phone the photo slid away with the
/// sheet instead of moving in the frame. And the sheet's item was built
/// afresh, with a new identity, every time the view redrew, so the crop
/// could be thrown away and shown again partway through.
struct AvatarChooser<Label: View>: View {
    @Environment(AppState.self) private var state
    @State private var picked: PhotosPickerItem?
    @State private var cropping: Portrait?
    @ViewBuilder let label: () -> Label

    var body: some View {
        // Built here, on the main actor; the picker's label closure isn't.
        let content = label()
        PhotosPicker(selection: $picked, matching: .images, preferredItemEncoding: .current) {
            content
        }
        .onChange(of: picked) { _, item in
            guard let item else { return }
            picked = nil
            Task {
                if let photo = await LibraryPhoto.load(item, longestSide: 2048) {
                    cropping = Portrait(image: photo.image)
                } else {
                    state.surface(APIError.message("That photo couldn't be opened. Try another one."))
                }
            }
        }
        .fullScreenCover(item: $cropping) { portrait in
            AvatarCropView(image: portrait.image) { jpeg in
                Task { await state.uploadAvatar(jpeg: jpeg) }
            }
        }
    }
}

/// A photo waiting to be cropped. Made once, when it's picked, so its
/// identity holds for as long as the crop is on screen.
private struct Portrait: Identifiable {
    let id = UUID()
    let image: UIImage
}

/// Your own face on the You tab, with a pencil to say it can be changed.
struct AvatarEditor: View {
    @Environment(AppState.self) private var state
    @AppStorage("stanley.atmosphere") private var raw = "auto"

    var body: some View {
        let profile = state.profile
        let uploading = state.avatarUploading
        let palette = Atmosphere.resolve(raw).palette
        AvatarChooser {
            ZStack(alignment: .bottomTrailing) {
                AvatarView(url: profile?.avatarUrl, name: profile?.displayName, size: 84)
                    .overlay {
                        if uploading { ProgressView() }
                    }
                // The palette's ink on its accent: white on Auto's warm-white
                // accent in dark mode would vanish.
                Image(systemName: "pencil.circle.fill")
                    .font(.title3)
                    .foregroundStyle(palette.ink, palette.accent)
                    .offset(x: 4, y: 4)
            }
        }
        .accessibilityLabel(profile?.avatarUrl == nil ? "Add a photo of yourself" : "Change your photo")
    }
}

/// Move and scale: the photo under a soft-square window (an avatar's own
/// shape), dimmed outside it. Drag to move, pinch to zoom, or both at once,
/// with `Framing`, the same arithmetic as today's photo. Choose cuts exactly
/// the framed pixels out of the photo itself.
///
/// Cancel and Choose sit in a navigation bar's own corners, where Apple's own
/// picker puts them. They used to sit at the foot of the screen, where on
/// some phones they were too low to tap. A real navigation bar, not a row
/// drawn to look like one: on the Duo's cover the system keeps the bar's
/// trailing button clear of the front camera, which a drawn row sat under.
struct AvatarCropView: View {
    /// Upright, one point to a pixel, as `LibraryPhoto` reads it.
    let image: UIImage
    let onChoose: (Data) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var framing = Framing()
    @State private var moving = false
    /// The window's side, in points, as last laid out.
    @State private var side: CGFloat = 300

    /// The largest an avatar is sent. The server keeps less.
    private static let outputSide: CGFloat = 1024

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Move and Scale")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Choose") { choose() }
                            .fontWeight(.semibold)
                    }
                }
                .toolbarBackground(.black, for: .navigationBar)
                .toolbarBackground(.visible, for: .navigationBar)
        }
        .tint(.white)
        .preferredColorScheme(.dark)
    }

    private var content: some View {
        VStack(spacing: 0) {
            GeometryReader { geo in
                let side = min(geo.size.width - 40, geo.size.height - 40, 480)
                stage(side: side)
                    .frame(width: geo.size.width, height: geo.size.height)
                    .framing($framing, photo: image.size, window: CGSize(width: side, height: side), moving: $moving)
                    .onAppear { self.side = side }
                    .onChange(of: side) { _, new in
                        self.side = new
                        framing = framing.clamped(image.size, CGSize(width: new, height: new))
                    }
            }
            Text("Drag to move, pinch to zoom.")
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.6))
                .padding(.vertical, 14)
        }
        .background(Color.black.ignoresSafeArea())
    }

    private func stage(side: CGFloat) -> some View {
        let filled = Framing.covering(image.size, CGSize(width: side, height: side))
        let window = RoundedRectangle(cornerRadius: side * 0.28, style: .continuous)
        return ZStack {
            Image(uiImage: image)
                .resizable()
                .frame(width: filled.width * framing.zoom, height: filled.height * framing.zoom)
                .offset(framing.offset)
            // Everything outside the window, dimmed.
            Rectangle()
                .fill(.black.opacity(0.6))
                .overlay {
                    window
                        .frame(width: side, height: side)
                        .blendMode(.destinationOut)
                }
                .compositingGroup()
            if moving {
                ThirdsGuide()
                    .frame(width: side, height: side)
                    .clipShape(window)
            }
            window
                .strokeBorder(.white.opacity(0.75), lineWidth: 1)
                .frame(width: side, height: side)
        }
        .clipped()
        .accessibilityElement()
        .accessibilityLabel("Your photo, framed")
    }

    private func choose() {
        if let jpeg = Self.crop(image, side: side, framing: framing) {
            onChoose(jpeg)
        }
        dismiss()
    }

    /// The framed square, cut from the photo's own pixels and sent at no
    /// more than 1024 on a side.
    static func crop(_ image: UIImage, side: CGFloat, framing: Framing) -> Data? {
        guard let pixels = image.cgImage else { return nil }
        let size = CGSize(width: pixels.width, height: pixels.height)
        let rect = framing.crop(pixels: size, window: CGSize(width: side, height: side))
        guard !rect.isEmpty, let cut = pixels.cropping(to: rect) else { return nil }
        let out = min(rect.width, rect.height, outputSide)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let square = UIGraphicsImageRenderer(size: CGSize(width: out, height: out), format: format).image { _ in
            UIImage(cgImage: cut).draw(in: CGRect(x: 0, y: 0, width: out, height: out))
        }
        return square.jpegData(compressionQuality: 0.9)
    }
}

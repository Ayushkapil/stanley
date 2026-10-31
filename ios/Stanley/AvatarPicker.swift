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
/// shape), dimmed outside it. Drag to move, pinch to zoom, or both at once.
/// The photo always covers the window: it can't be zoomed out past filling
/// it or dragged off an edge, so a crop never has an empty corner. Choose
/// cuts exactly the framed pixels out of the photo itself, rather than
/// rendering what's on screen again.
struct AvatarCropView: View {
    /// Upright, one point to a pixel, as `LibraryPhoto` reads it.
    let image: UIImage
    let onChoose: (Data) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var zoom: CGFloat = 1
    @State private var offset: CGSize = .zero
    /// The zoom when the current pinch began.
    @State private var pinchStart: CGFloat?
    /// How far the current drag had gone at its last step.
    @State private var dragged: CGSize = .zero
    /// The window's side, in points, as last laid out.
    @State private var side: CGFloat = 300

    private static let maxZoom: CGFloat = 5
    /// The largest an avatar is sent. The server keeps less.
    private static let outputSide: CGFloat = 1024

    var body: some View {
        ZStack {
            GeometryReader { geo in
                let side = min(geo.size.width - 40, geo.size.height - 220, 480)
                stage(side: side)
                    .frame(width: geo.size.width, height: geo.size.height)
                    .contentShape(Rectangle())
                    .gesture(pinch(side: side))
                    .simultaneousGesture(drag(side: side))
                    .onAppear { self.side = side }
                    .onChange(of: side) { _, new in
                        self.side = new
                        offset = clamp(offset, side: new, zoom: zoom)
                    }
            }
            .ignoresSafeArea()
            VStack {
                Text("Move and Scale")
                    .font(.headline)
                    .padding(.top, 16)
                Spacer()
                HStack {
                    Button("Cancel") { dismiss() }
                    Spacer()
                    Button("Choose") { choose() }
                        .fontWeight(.semibold)
                }
                .font(.body)
                .padding(.horizontal, 24)
                .padding(.bottom, 12)
            }
            .foregroundStyle(.white)
        }
        .background(Color.black.ignoresSafeArea())
    }

    private func stage(side: CGFloat) -> some View {
        let filled = Self.filled(image.size, side: side)
        let window = RoundedRectangle(cornerRadius: side * 0.28, style: .continuous)
        return ZStack {
            Image(uiImage: image)
                .resizable()
                .frame(width: filled.width * zoom, height: filled.height * zoom)
                .offset(offset)
            // Everything outside the window, dimmed.
            Rectangle()
                .fill(.black.opacity(0.6))
                .overlay {
                    window
                        .frame(width: side, height: side)
                        .blendMode(.destinationOut)
                }
                .compositingGroup()
            window
                .strokeBorder(.white.opacity(0.75), lineWidth: 1)
                .frame(width: side, height: side)
        }
        .clipped()
        .accessibilityElement()
        .accessibilityLabel("Your photo, framed")
    }

    private func pinch(side: CGFloat) -> some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let start = pinchStart ?? zoom
                pinchStart = start
                let next = min(max(start * value.magnification, 1), Self.maxZoom)
                // Scale the offset with the photo, so what's in the middle of
                // the window stays in the middle.
                let ratio = next / zoom
                zoom = next
                offset = clamp(
                    CGSize(width: offset.width * ratio, height: offset.height * ratio),
                    side: side, zoom: next
                )
            }
            .onEnded { _ in pinchStart = nil }
    }

    /// Moves by each step of the drag rather than its total, so a drag and a
    /// pinch at the same time both move the same photo.
    private func drag(side: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let step = CGSize(
                    width: value.translation.width - dragged.width,
                    height: value.translation.height - dragged.height
                )
                dragged = value.translation
                offset = clamp(
                    CGSize(width: offset.width + step.width, height: offset.height + step.height),
                    side: side, zoom: zoom
                )
            }
            .onEnded { _ in dragged = .zero }
    }

    /// The photo's size on screen at zoom 1: just big enough to cover the
    /// window.
    private static func filled(_ size: CGSize, side: CGFloat) -> CGSize {
        let scale = side / max(1, min(size.width, size.height))
        return CGSize(width: size.width * scale, height: size.height * scale)
    }

    /// Keeps the photo over every part of the window.
    private func clamp(_ proposed: CGSize, side: CGFloat, zoom: CGFloat) -> CGSize {
        let filled = Self.filled(image.size, side: side)
        let x = max(0, (filled.width * zoom - side) / 2)
        let y = max(0, (filled.height * zoom - side) / 2)
        return CGSize(
            width: min(max(proposed.width, -x), x),
            height: min(max(proposed.height, -y), y)
        )
    }

    private func choose() {
        if let jpeg = Self.crop(image, side: side, zoom: zoom, offset: offset) {
            onChoose(jpeg)
        }
        dismiss()
    }

    /// The framed square, cut from the photo's own pixels and sent at no
    /// more than 1024 on a side.
    static func crop(_ image: UIImage, side: CGFloat, zoom: CGFloat, offset: CGSize) -> Data? {
        guard let pixels = image.cgImage else { return nil }
        let width = CGFloat(pixels.width), height = CGFloat(pixels.height)
        // Points on screen per pixel of the photo.
        let k = side / min(width, height) * zoom
        let edge = side / k
        let rect = CGRect(
            x: width / 2 - offset.width / k - edge / 2,
            y: height / 2 - offset.height / k - edge / 2,
            width: edge, height: edge
        )
        .integral
        .intersection(CGRect(x: 0, y: 0, width: width, height: height))
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

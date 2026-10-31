import CoreImage
import SwiftUI
import UIKit

/// Capture is a commitment (§8.4): one shot, a look at it (with a filter, if
/// you want one), then Post. There is no camera roll. On the simulator (no
/// camera) a stand-in frame is used so the flow stays testable end to end.
///
/// Laid out like composing a memory rather than filling in a form: the photo
/// first and largest, its looks right beneath it, then the words, the place
/// and who was there on one card, and one wide button at the foot of the
/// sheet that is always within reach.
struct CaptureView: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var hSizeClass
    private var density: Density { Density(hSizeClass) }
    @AppStorage("stanley.atmosphere") private var raw = "auto"
    @State private var caption = ""
    @State private var location = ""
    /// The place filled in from where the phone is, so its row can say so
    /// until the person changes it.
    @State private var suggestedPlace: String?
    @State private var tagged: Set<String> = []
    @State private var showCamera = false
    @State private var uploading = false
    /// The frame between the shutter and Post.
    @State private var shot: Shot?
    @State private var filter: PhotoFilter = .none
    /// The looks rendered so far for this shot, at preview size, so going
    /// back to one is instant.
    @State private var looks: [PhotoFilter: UIImage] = [:]
    @State private var pickingPlace = false

    private var members: [CircleMember] {
        (state.circle?.members ?? []).filter { $0.id != state.myId }
    }

    private static let corner: CGFloat = 20

    /// The photo's height in the sheet, before the shutter and after it.
    private static func photoHeight(_ density: Density) -> CGFloat {
        (density.feedPhotoHeight * 0.85).rounded()
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    if let shot {
                        preview(shot)
                        FilterPills(selection: $filter)
                            .padding(.top, 14)
                        details
                            .padding(.top, 24)
                    } else {
                        waiting
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 24)
                .readableWidth(density)
            }
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom) { footer }
            // A sheet sits outside the root's floor, so it paints its own:
            // the camera button should land on the same temperature as Today.
            .atmosphereWash()
            .navigationTitle("Today's photo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Not now") { dismiss() }
                }
            }
            .fullScreenCover(isPresented: $showCamera) {
                CameraPicker { image in took(image) }
                    .ignoresSafeArea()
            }
            .task(id: DevelopKey(shot: shot?.id, filter: filter)) { await develop() }
            .task(id: shot?.id) { await suggestPlace() }
            .sheet(isPresented: $pickingPlace) {
                PlacePicker(userId: state.myId, current: location) { location = $0 }
            }
        }
    }

    /// Before the shutter: an empty frame where the photo will be, holding
    /// the day's prompt, and the rule in a line beneath. Tapping the frame
    /// opens the camera, the same as the button.
    private var waiting: some View {
        VStack(spacing: 20) {
            Button(action: openCamera) {
                Color.clear
                    .frame(maxWidth: .infinity)
                    .frame(height: Self.photoHeight(density))
                    .cardSurface(corner: Self.corner)
                    .overlay {
                        VStack(spacing: 16) {
                            Image(systemName: "camera.aperture")
                                .font(.system(size: 40, weight: .light))
                                .foregroundStyle(.tertiary)
                            // The day's prompt — a whisper, not an instruction (Part 1).
                            Text(DailyPrompt.forToday())
                                .font(.callout)
                                .italic()
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 32)
                        }
                    }
                    .contentShape(RoundedRectangle(cornerRadius: Self.corner, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open the camera")
            VStack(spacing: 6) {
                Text("One photo. This is today's.")
                    .font(.headline)
                Text("No retakes. It fades in six days unless someone keeps it.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }

    /// The words, the place and who was there. The two fields share one card
    /// with a hairline between them, the way grouped rows do in Settings.
    private var details: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(spacing: 0) {
                ComposeRow(icon: "text.quote") {
                    TextField(
                        "", text: $caption, prompt: .fieldPrompt("A few words, if you like"), axis: .vertical
                    )
                    .lineLimit(1...5)
                }
                Divider().padding(.leading, 46)
                // A place name, as you'd say it. With location allowed, where
                // the phone is fills it in after the shutter; it stays the
                // person's to change or clear. Only the words are posted.
                ComposeRow(icon: location == suggestedPlace && !location.isEmpty ? "location.fill" : "mappin") {
                    PlaceField(place: $location) { pickingPlace = true }
                }
            }
            .cardSurface(corner: 16)
            if !members.isEmpty {
                WhoWasThere(members: members, selected: $tagged)
                    .padding(.horizontal, 4)
            }
        }
    }

    /// One wide button at the foot of the sheet, above the keyboard when it's
    /// up, on the sheet's own floor so the content scrolls away beneath it.
    private var footer: some View {
        Group {
            if let shot {
                WideButton(title: "Post", busy: uploading) { post(shot) }
            } else {
                WideButton(title: "Open camera", systemImage: "camera", busy: uploading, action: openCamera)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .readableWidth(density)
        .background(Atmosphere.resolve(raw).palette.floor.ignoresSafeArea())
    }

    private func openCamera() {
        #if targetEnvironment(simulator)
        took(Self.simulatorFrame())
        #else
        showCamera = true
        #endif
    }

    /// The shot with the chosen look: the full width of the sheet, cropped
    /// the way a card in Today crops it, and a little shorter than that card
    /// so the looks beneath it are in view without scrolling, even on the
    /// Duo's cover. A quiet placeholder of the same size stands in for the
    /// moment it takes to render. The frame owns the size and the photo fills
    /// it, as in Today, so a wide photo can't push the sheet wider.
    private func preview(_ shot: Shot) -> some View {
        Color.clear
            .frame(maxWidth: .infinity)
            .frame(height: Self.photoHeight(density))
            .overlay {
                if let image = looks[filter] ?? looks[.none] {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    Rectangle().fill(.quaternary)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: Self.corner, style: .continuous))
            .accessibilityElement()
            .accessibilityLabel(filter == .none ? "Your photo" : "Your photo, \(filter.label)")
    }

    /// After the shutter, offer where the phone is as the place. Asked here,
    /// in the moment it is for, the first time. Never over a place the
    /// person has already chosen.
    private func suggestPlace() async {
        guard shot != nil, location.isEmpty else { return }
        let whereabouts = state.whereabouts
        await whereabouts.ask()
        guard let place = await whereabouts.here()?.place, location.isEmpty else { return }
        location = place
        suggestedPlace = place
    }

    private func took(_ image: UIImage) {
        guard let source = FilterRenderer.upright(image) else {
            // CoreImage can't read this frame, so there's no preview to
            // offer. Post it as it was taken, the way capture always did.
            guard let jpeg = image.jpegData(compressionQuality: 0.9) else { return }
            uploading = true
            Task { await send(jpeg: jpeg, filter: .none) }
            return
        }
        looks = [:]
        filter = .none
        shot = Shot(original: image, source: source, preview: FilterRenderer.preview(of: source))
    }

    /// Renders the chosen look at preview size, off the main thread.
    private func develop() async {
        guard let shot, looks[filter] == nil else { return }
        let filter = self.filter
        let image = await Task.detached(priority: .userInitiated) {
            FilterRenderer.image(shot.preview, filter)
        }.value
        guard self.shot?.id == shot.id, let image else { return }
        looks[filter] = image
    }

    private func post(_ shot: Shot) {
        uploading = true
        let filter = self.filter
        Task {
            // The look goes into the pixels here, at full size. None sends
            // the frame exactly as the camera took it.
            let jpeg = await Task.detached(priority: .userInitiated) {
                filter == .none
                    ? shot.original.jpegData(compressionQuality: 0.9)
                    : FilterRenderer.jpeg(shot.source, filter)
            }.value
            guard let jpeg else {
                state.surface(APIError.message("That photo couldn't be prepared, and today is still open. Try again."))
                uploading = false
                return
            }
            await send(jpeg: jpeg, filter: filter)
        }
    }

    private func send(jpeg: Data, filter: PhotoFilter) async {
        do {
            try await state.capture(
                jpeg: jpeg,
                caption: caption.trimmingCharacters(in: .whitespaces),
                location: location.trimmingCharacters(in: .whitespaces),
                tagged: Array(tagged),
                filter: filter.serverName
            )
            // Posted, or kept to post later: either way the place was used,
            // so it's the first thing the picker offers next time.
            PlaceBook(userId: state.myId).remember(location)
            dismiss()
        } catch {
            state.surface(error)
        }
        uploading = false
    }

    #if targetEnvironment(simulator)
    /// The simulator has no camera. A photo saved as SampleCapture.jpg or
    /// SampleCapture.heic in the app's Documents folder stands in for one,
    /// so the filters can be tried on a real picture. Otherwise the frame is
    /// generated.
    private static func simulatorFrame() -> UIImage {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        for name in ["SampleCapture.jpg", "SampleCapture.heic"] {
            if let sample = UIImage(contentsOfFile: documents.appendingPathComponent(name).path) {
                return sample
            }
        }
        let size = CGSize(width: 1080, height: 1440)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            let colors = [UIColor.systemIndigo.cgColor, UIColor.systemTeal.cgColor]
            let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: colors as CFArray,
                locations: [0, 1]
            )!
            ctx.cgContext.drawLinearGradient(
                gradient, start: .zero, end: CGPoint(x: 0, y: size.height), options: []
            )
            let text = Date().formatted(date: .abbreviated, time: .shortened)
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 64, weight: .medium),
                .foregroundColor: UIColor.white,
            ]
            text.draw(at: CGPoint(x: 80, y: size.height / 2), withAttributes: attrs)
        }
    }
    #endif
}

/// A frame between the shutter and Post: the photo as the camera gave it,
/// and the same photo upright for CoreImage, at full size and preview size.
private struct Shot {
    let id = UUID()
    let original: UIImage
    let source: CIImage
    let preview: CIImage
}

private struct DevelopKey: Equatable {
    let shot: UUID?
    let filter: PhotoFilter
}

/// A row on the compose card: a quiet glyph, then the field. The glyph sits
/// on the field's first line, however many lines the caption grows to. (A
/// baseline alignment would do it in principle, but a multi-line field
/// reports its baseline lower than its first line.)
private struct ComposeRow<Content: View>: View {
    let icon: String
    @ViewBuilder let content: Content
    @ScaledMetric(relativeTo: .body) private var line: CGFloat = 22

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(width: 20, height: line)
            content
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
    }
}

/// The sheet's one action, as wide as the sheet, in the atmosphere's accent
/// with its ink for the words. While a photo is on its way it holds a
/// spinner in place of the words and takes no second tap.
private struct WideButton: View {
    let title: String
    var systemImage: String?
    var busy = false
    let action: () -> Void
    @AppStorage("stanley.atmosphere") private var raw = "auto"

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
        }
        .buttonStyle(.plain)
        .disabled(busy)
        .accessibilityLabel(busy ? "Posting" : title)
    }
}

/// The four filters, and none, as a row of pills under the preview. A tap
/// shows the look at once; there is nothing to adjust. The pills are the
/// atmosphere's, like the picker in Settings.
struct FilterPills: View {
    @Binding var selection: PhotoFilter
    @AppStorage("stanley.atmosphere") private var raw = "auto"

    var body: some View {
        ViewThatFits(in: .horizontal) {
            row
            ScrollView(.horizontal, showsIndicators: false) { row }
        }
        .animation(.easeInOut(duration: 0.2), value: selection)
    }

    private var row: some View {
        HStack(spacing: 4) {
            ForEach(PhotoFilter.allCases) { filter in
                ChoicePill(
                    label: filter.label,
                    on: selection == filter,
                    palette: Atmosphere.resolve(raw).palette
                ) {
                    selection = filter
                }
            }
        }
    }
}

/// 'Who was there?' (Part 3): tap circle members present in the moment. A
/// memory detail — no notifications, no mentions.
struct WhoWasThere: View {
    let members: [CircleMember]
    @Binding var selected: Set<String>

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Who was there?")
                .font(.caption)
                .foregroundStyle(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(members) { member in
                        let on = selected.contains(member.id)
                        Button {
                            if on { selected.remove(member.id) } else { selected.insert(member.id) }
                        } label: {
                            VStack(spacing: 4) {
                                AvatarView(url: member.avatarUrl, name: member.displayName, size: 44)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 44 * 0.28, style: .continuous)
                                            .strokeBorder(Color.accentColor, lineWidth: on ? 2.5 : 0)
                                    )
                                    .opacity(on ? 1 : 0.7)
                                Text(member.displayName ?? "—")
                                    .font(.caption2)
                                    .foregroundStyle(on ? Color.accentColor : .secondary)
                                    .lineLimit(1)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }
}

struct CameraPicker: UIViewControllerRepresentable {
    let onCapture: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.allowsEditing = false
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker

        init(_ parent: CameraPicker) {
            self.parent = parent
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let image = info[.originalImage] as? UIImage {
                parent.onCapture(image)
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

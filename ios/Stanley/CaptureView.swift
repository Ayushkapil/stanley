import CoreImage
import SwiftUI
import UIKit

/// Capture is a commitment (§8.4): one shot, a look at it (with a filter, if
/// you want one), then Post. There is no camera roll. On the simulator (no
/// camera) a stand-in frame is used so the flow stays testable end to end.
struct CaptureView: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var hSizeClass
    private var density: Density { Density(hSizeClass) }
    @State private var caption = ""
    @State private var location = ""
    @State private var tagged: Set<String> = []
    @State private var showCamera = false
    @State private var uploading = false
    /// The frame between the shutter and Post.
    @State private var shot: Shot?
    @State private var filter: PhotoFilter = .none
    /// The looks rendered so far for this shot, at preview size, so going
    /// back to one is instant.
    @State private var looks: [PhotoFilter: UIImage] = [:]

    private var members: [CircleMember] {
        (state.circle?.members ?? []).filter { $0.id != state.myId }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    if let shot {
                        preview(shot)
                        FilterPills(selection: $filter)
                    } else {
                        Text("One photo. This is today's.")
                            .font(.headline)
                        // The day's prompt — a whisper, not an instruction (Part 1).
                        Text(DailyPrompt.forToday())
                            .font(.callout)
                            .italic()
                            .foregroundStyle(.tertiary)
                            .multilineTextAlignment(.center)
                        Text("No retakes. It fades in six days unless someone keeps it.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    TextField("", text: $caption, prompt: .fieldPrompt("A few words, if you like"))
                        .stanleyField()
                    // a typed place name, as you'd say it — never GPS, never a map
                    TextField("", text: $location, prompt: .fieldPrompt("Where was this? (a place, optional)"))
                        .stanleyField()
                    if !members.isEmpty {
                        WhoWasThere(members: members, selected: $tagged)
                    }
                    if uploading {
                        ProgressView()
                    } else if let shot {
                        Button {
                            post(shot)
                        } label: {
                            Text("Post").accentInk()
                        }
                        .buttonStyle(.borderedProminent)
                    } else {
                        #if targetEnvironment(simulator)
                        Button {
                            took(Self.simulatorFrame())
                        } label: {
                            Text("Capture (simulator frame)").accentInk()
                        }
                        .buttonStyle(.borderedProminent)
                        #else
                        Button {
                            showCamera = true
                        } label: {
                            Label("Open camera", systemImage: "camera").accentInk()
                        }
                        .buttonStyle(.borderedProminent)
                        #endif
                    }
                }
                .padding()
            }
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
        }
    }

    /// The shot with the chosen look, as the circle will see it, or a quiet
    /// placeholder of the same shape for the moment it takes to render.
    private func preview(_ shot: Shot) -> some View {
        Group {
            if let image = looks[filter] ?? looks[.none] {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                Rectangle()
                    .fill(.quaternary)
                    .aspectRatio(shot.aspect, contentMode: .fit)
            }
        }
        .frame(maxHeight: density.feedPhotoHeight)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .accessibilityElement()
        .accessibilityLabel(filter == .none ? "Your photo" : "Your photo, \(filter.label)")
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

    var aspect: CGFloat { source.extent.width / max(1, source.extent.height) }
}

private struct DevelopKey: Equatable {
    let shot: UUID?
    let filter: PhotoFilter
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

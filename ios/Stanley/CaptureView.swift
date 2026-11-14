import CoreImage
import CoreLocation
import PhotosUI
import SwiftUI
import UIKit

/// Capture is a commitment (§8.4): one photo, a look at it, then Post. The photo is taken with the camera or chosen
/// from the library (since build 16; the library picker needs no Photos
/// permission), and either way it's today's one: the day law is the same.
/// On the simulator (no camera) a stand-in frame is used so the flow stays
/// testable end to end.
///
/// The photo is the hero (build 44): first and largest, cut as it will be
/// in Today, with as little around it as there can be. Where it was is
/// right under it, then the words (in your hand: they're yours) and who was
/// there, and one wide button at the foot of the sheet that is always
/// within reach. The four filters were removed in build 44: a photo posts
/// as it was taken, cropped to its frame.
/// With today's photo already posted in this circle, the sheet says so, warmly,
/// instead of offering a camera whose photo would be refused.
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
    @State private var showLibrary = false
    @State private var libraryItem: PhotosPickerItem?
    /// A library photo is being read.
    @State private var opening = false
    @State private var uploading = false
    /// The frame between the shutter and Post.
    @State private var shot: Shot?
    /// The shot at preview size, once rendered.
    @State private var look: UIImage?
    @State private var pickingPlace = false
    /// Where the photo sits in its frame, which is what's posted.
    @State private var framing = Framing()
    /// The frame's size on screen, as last laid out.
    @State private var window: CGSize = .zero
    @State private var moving = false
    /// The photo has been moved or zoomed at least once, so the hint goes.
    @State private var framed = false
    /// The sheet's height between the navigation bar and the footer, and
    /// the height of everything under the photo once it's taken (build 31):
    /// the photo gives up height so the place, the words and who
    /// was there all sit above Post without scrolling.
    @State private var viewport: CGFloat = 0
    @State private var below: CGFloat = 0
    @FocusState private var writing: Bool
    /// Asked before a framed, unposted photo is thrown away (build 32).
    @State private var confirmDiscard = false

    private var members: [CircleMember] {
        (state.circle?.members ?? []).filter { $0.id != state.myId }
    }

    /// Nothing round the frame (a print's paper border until build 44).
    private static let border: CGFloat = 0

    /// The photo's frame in the sheet, before the shutter and after it: a
    /// print, `PhotoShape` inside its paper border, the shape of every photo
    /// in Today, as wide as the sheet allows and no taller than
    /// `capturePhotoMaxHeight`, so the place and the words beneath it are in
    /// view without scrolling, even on the Duo's cover. Centered when the
    /// height is what limits it. The border is outside the frame, so the
    /// frame, which is the crop, stays exactly 3:4. Never tilted: it's being
    /// framed by hand.
    private func photoFrame<Content: View>(
        maxHeight: CGFloat? = nil, @ViewBuilder _ content: () -> Content
    ) -> some View {
        let maxHeight = maxHeight ?? density.capturePhotoMaxHeight
        return content()
            .aspectRatio(PhotoShape.aspect, contentMode: .fit)
            .asPrint()
            .frame(maxWidth: maxHeight * PhotoShape.aspect + 2 * Self.border)
            .frame(maxWidth: .infinity)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    if let shot {
                        preview(shot)
                        VStack(spacing: 0) {
                            placeLine
                                .padding(.top, 12)
                            details
                                .padding(.top, 20)
                        }
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { below = $0 }
                    } else if let mine = state.sharedToday {
                        sharedPage(mine)
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
            // The room the sheet has to show, between the bar and Post (the
            // scroll view is laid out inside both). Not while the keyboard
            // is up, so the photo doesn't shrink under the words being typed.
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                if !writing { viewport = height }
            }
            .safeAreaInset(edge: .bottom) { footer }
            // A sheet sits outside the root's floor, so it paints its own:
            // the camera button should land on the same temperature as Today.
            .atmosphereWash()
            .navigationTitle("Today's photo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(spent ? "Done" : "Not now") {
                        if shot != nil { confirmDiscard = true } else { dismiss() }
                    }
                    .disabled(uploading)
                }
                // Each circle has its own day, so with more than one, the
                // sheet says whose day this photo is.
                if state.circles.count > 1, let name = state.circle?.name {
                    ToolbarItem(placement: .principal) {
                        VStack(spacing: 1) {
                            Text("Today's photo").font(.headline)
                            Text("for \(name)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
            }
            .fullScreenCover(isPresented: $showCamera) {
                CameraPicker { image in took(image) }
                    .ignoresSafeArea()
            }
            // The system's photo picker, out of process: Stanley sees only
            // the photo chosen, and needs no Photos permission for it.
            .photosPicker(
                isPresented: $showLibrary, selection: $libraryItem,
                matching: .images, preferredItemEncoding: .current
            )
            .onChange(of: libraryItem) { _, item in
                guard let item else { return }
                libraryItem = nil
                Task { await chose(item) }
            }
            .task(id: shot?.id) { await develop() }
            .task(id: shot?.id) { await suggestPlace() }
            .sheet(isPresented: $pickingPlace) {
                PlacePicker(userId: state.myId, current: location) { location = $0 }
            }
            .onAppear { Trail.note(.openedCamera) }
            // After the shutter, the sheet doesn't go with a stray swipe (the
            // HCI audit, build 32): a camera photo is in no library, so a
            // swipe down threw the moment away with its words and its place.
            // Not now asks first; while it's posting, nothing closes it.
            .interactiveDismissDisabled(shot != nil || uploading)
            .alert("Discard this photo?", isPresented: $confirmDiscard) {
                Button("Discard", role: .destructive) { dismiss() }
                Button("Keep It", role: .cancel) {}
            } message: {
                Text("It hasn't been posted. Today's photo is still yours to take.")
            }
        }
    }

    /// Before the shutter: an empty frame where the photo will be, holding
    /// the day's prompt, and the rule in a line beneath. Tapping the frame
    /// opens the camera, the same as the button.
    private var waiting: some View {
        VStack(spacing: 0) {
            Button(action: openCamera) {
                photoFrame(maxHeight: fittedPhotoHeight) {
                    // Where the photo will be: a quiet shape.
                    Rectangle()
                        .fill(.primary.opacity(0.05))
                        .overlay {
                            VStack(spacing: 16) {
                                if opening {
                                    ProgressView()
                                } else {
                                    Image(systemName: "camera.aperture")
                                        .font(.system(size: 40, weight: .light))
                                        .foregroundStyle(.tertiary)
                                }
                                // The day's prompt — a whisper, not an instruction (Part 1).
                                Text(DailyPrompt.forToday())
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, 24)
                            }
                        }
                        .contentShape(Rectangle())
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open the camera")
            VStack(spacing: 6) {
                Text("One photo. This is today's.")
                    .font(.sectionTitle)
                Text("From the camera or your library. It fades in six days unless someone keeps it.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 22)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { below = $0 }
        }
    }

    /// Today's photo is already posted in this circle. The day is doing what
    /// it does, so it's said warmly, with the photo itself, rather than
    /// refused after a new one has been framed and written up.
    private func sharedPage(_ photo: Photo) -> some View {
        VStack(spacing: 26) {
            Color.clear
                .aspectRatio(PhotoShape.aspect, contentMode: .fit)
                .frame(width: 150)
                .overlay {
                    if let urls = photo.urls, let url = state.api.absoluteURL(urls.thumb) {
                        SignedImage(url: url) { image in
                            image.resizable().aspectRatio(contentMode: .fill)
                        } placeholder: {
                            Rectangle().fill(.quaternary)
                        }
                    }
                }
                .asPrint()
                .padding(.top, 30)
                .accessibilityLabel("Today's photo")
            VStack(spacing: 10) {
                Text("Today's moment is out there.")
                    .font(.system(.title2, design: .rounded).weight(.semibold))
                    .multilineTextAlignment(.center)
                Text("Come back tomorrow.")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
    }

    /// Today's photo is posted here and nothing new is being framed.
    private var spent: Bool { shot == nil && state.sharedToday != nil }

    /// Where it was, right under the photo, where pilot users looked for it
    /// (lower down it was out of sight on the Duo's cover).
    /// A place name, as you'd say it. With location allowed, where the phone
    /// is fills it in after the shutter; for a library photo, where the photo
    /// was taken. A filled place shows a pencil, because it's still the
    /// person's to change, and a tap anywhere on the line opens the picker:
    /// here, favorites, recents, search. Only the words are posted.
    private var placeLine: some View {
        let suggested = !location.isEmpty && location == suggestedPlace
        return HStack(spacing: 8) {
            Button { pickingPlace = true } label: {
                HStack(spacing: 10) {
                    Image(systemName: suggested ? "location.fill" : "mappin.and.ellipse")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 22)
                    Text(location.isEmpty ? "Add a place" : location)
                        .font(.body)
                        .foregroundStyle(location.isEmpty ? .secondary : .primary)
                        .lineLimit(1)
                    if !location.isEmpty {
                        Image(systemName: "pencil")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    if location.isEmpty {
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                }
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Where was this")
            .accessibilityValue(location.isEmpty ? "No place" : location)
            .accessibilityHint("Opens your places")
            if !location.isEmpty {
                Button { location = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.body)
                        .foregroundStyle(.tertiary)
                        .frame(width: 32, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear the place")
            }
        }
        .frame(height: 48)
        // A hairline under it, not a box round it.
        .overlay(alignment: .bottom) { Rule(weight: 0.5) }
    }

    /// The words and who was there.
    /// The words, written by hand on a ruled line, and who was there.
    /// The photo's height, before the shutter and after: whatever's left once
    /// what's under it has its room (the rule's two lines before; the place,
    /// the words and who was there after), so none of it starts
    /// under the footer (the QA audit found "In your words" under Post).
    /// Never taller than before, and never smaller than a photo you can
    /// frame by hand; a large circle's names can still scroll past that.
    private var fittedPhotoHeight: CGFloat {
        let most = density.capturePhotoMaxHeight
        guard viewport > 0, below > 0 else { return most }
        // The page's own top and bottom padding, and the print's border.
        let room = viewport - below - 8 - 24 - 2 * Self.border - 8
        return min(most, max(260, room.rounded(.down)))
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                // The caption is the person's own: in a hand, the
                // placeholder too.
                TextField(
                    "", text: $caption,
                    prompt: Text("In your words…").font(.hand(20, relativeTo: .body)).foregroundColor(.secondary),
                    axis: .vertical
                )
                .font(.hand(20, relativeTo: .body))
                .lineLimit(1...5)
                .focused($writing)
                .padding(.vertical, 6)
                .accessibilityLabel("Caption, in your words")
                Rule(weight: 0.5)
            }
            if !members.isEmpty {
                WhoWasThere(members: members, selected: $tagged)
            }
        }
    }

    /// The action at the foot of the sheet, above the keyboard when it's up,
    /// on the sheet's own floor so the content scrolls away beneath it.
    /// Before the photo, two ways to it: the camera, and under it the
    /// library. After, Post.
    @ViewBuilder
    private var footer: some View {
        if !spent { actions }
    }

    private var actions: some View {
        Group {
            if let shot {
                WideButton(title: "Post", busy: uploading) { post(shot) }
            } else {
                VStack(spacing: 2) {
                    WideButton(title: "Take photo", systemImage: "camera", busy: uploading, action: openCamera)
                    Button { showLibrary = true } label: {
                        Label("Choose from library", systemImage: "photo.on.rectangle")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.accentColor)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(uploading || opening)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .readableWidth(density)
        .background(Atmosphere.resolve(raw).palette.floor.ignoresSafeArea())
    }

    private func openCamera() {
        #if targetEnvironment(simulator)
        // Stanley takes this frame itself, so it plays the shutter itself.
        // The real camera plays its own (`Shutter`).
        Shutter.play()
        took(Self.simulatorFrame())
        #else
        showCamera = true
        #endif
    }

    /// The shot with the chosen look, in the frame it will be posted in:
    /// `PhotoShape`, exactly what Today shows. A photo of another shape (most
    /// library photos) fills the frame and can be dragged to choose what's
    /// in it; any photo can be pinched in closer. A quiet placeholder of the
    /// same size stands in for the moment it takes to render. The frame owns
    /// the size, so a wide photo can't push the sheet wider.
    private func preview(_ shot: Shot) -> some View {
        let photo = shot.source.extent.size
        let filled = Framing.covering(photo, window)
        let movable = framing.canMove(photo, window)
        return photoFrame(maxHeight: fittedPhotoHeight) {
            Color.clear
                .overlay {
                    if let image = look {
                        Image(uiImage: image)
                            .resizable()
                            .frame(width: filled.width * framing.zoom, height: filled.height * framing.zoom)
                            .offset(framing.offset)
                    } else {
                        Rectangle().fill(.quaternary)
                    }
                }
                .overlay {
                    if moving { ThirdsGuide() }
                }
                .overlay(alignment: .bottom) {
                    if movable && !framed {
                        Text("Drag to frame it")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(.black.opacity(0.35), in: Capsule())
                            .padding(.bottom, 12)
                            .allowsHitTesting(false)
                            .transition(.opacity)
                    }
                }
                .onGeometryChange(for: CGSize.self) { $0.size } action: { size in
                    window = size
                    framing = framing.clamped(photo, size)
                }
                .framing($framing, photo: photo, window: window, moving: $moving)
        }
        .onChange(of: moving) { _, now in
            if now { withAnimation(.easeOut(duration: 0.2)) { framed = true } }
        }
        .accessibilityElement()
        .accessibilityLabel("Your photo")
        .accessibilityHint(movable ? "Drag to choose what's in the frame" : "")
    }

    /// After the shutter, offer where the phone is as the place, asking for
    /// location here, in the moment it's for, the first time. A library
    /// photo is offered where it was taken, if it says, and never where the
    /// phone is: it could be from anywhere. Never over a place the person
    /// has already chosen.
    private func suggestPlace() async {
        guard let shot, location.isEmpty else { return }
        let place: String?
        if shot.fromLibrary {
            guard let taken = shot.takenAt else { return }
            place = await Whereabouts.place(at: taken)
        } else {
            let whereabouts = state.whereabouts
            await whereabouts.ask()
            place = await whereabouts.here()?.place
        }
        guard let place, location.isEmpty else { return }
        location = place
        suggestedPlace = place
    }

    /// A photo chosen from the library, read upright and at no more than
    /// 4096 pixels on its longest side: plenty for the server, which keeps
    /// less, and well under its upload limit.
    private func chose(_ item: PhotosPickerItem) async {
        opening = true
        defer { opening = false }
        guard let photo = await LibraryPhoto.load(item, longestSide: 4096) else {
            state.surface(APIError.message("That photo couldn't be opened. Try another one."))
            return
        }
        took(photo.image, library: photo)
    }

    private func took(_ image: UIImage, library: LibraryPhoto? = nil) {
        guard let source = PhotoRenderer.upright(image) else {
            // CoreImage can't read this frame, so there's no preview to
            // offer. Post it as it was taken, the way capture always did.
            guard let jpeg = image.jpegData(compressionQuality: 0.9) else { return }
            uploading = true
            Task { await send(jpeg: jpeg) }
            return
        }
        look = nil
        framing = Framing()
        framed = false
        shot = Shot(
            original: image, source: source, preview: PhotoRenderer.preview(of: source),
            fromLibrary: library != nil, takenAt: library?.location
        )
    }

    /// Renders the shot at preview size, off the main thread.
    private func develop() async {
        guard let shot, look == nil else { return }
        let image = await Task.detached(priority: .userInitiated) {
            PhotoRenderer.image(shot.preview)
        }.value
        guard self.shot?.id == shot.id, let image else { return }
        look = image
    }

    private func post(_ shot: Shot) {
        uploading = true
        let pixels = shot.source.extent.size
        // What's in the frame, in the photo's own pixels. Nil when the frame
        // takes the whole photo, as it does a camera shot left as it was.
        let crop: CGRect? = framing.isWhole(pixels: pixels, window: window)
            ? nil : framing.crop(pixels: pixels, window: window)
        Task {
            // The frame is cut from the photo at full size: what was on
            // screen is what's posted. Uncropped, the frame goes exactly as
            // the camera took it.
            let jpeg = await Task.detached(priority: .userInitiated) {
                crop == nil
                    ? shot.original.jpegData(compressionQuality: 0.9)
                    : PhotoRenderer.jpeg(shot.source, crop: crop)
            }.value
            guard let jpeg else {
                state.surface(APIError.message(APIError.photoNotPosted))
                uploading = false
                return
            }
            await send(jpeg: jpeg)
        }
    }

    private func send(jpeg: Data) async {
        do {
            let posted = try await state.capture(
                jpeg: jpeg,
                caption: caption.trimmingCharacters(in: .whitespaces),
                location: location.trimmingCharacters(in: .whitespaces),
                tagged: Array(tagged)
            )
            // Posted, or kept to post later: either way the place was used,
            // so it's the first thing the picker offers next time.
            PlaceBook(userId: state.myId).remember(location)
            // Up for everyone: success. Kept for later isn't that yet.
            if posted { Haptics.posted() }
            dismiss()
        } catch {
            state.surface(error)
        }
        uploading = false
    }

    #if targetEnvironment(simulator)
    /// The simulator has no camera. A photo saved as SampleCapture.jpg or
    /// SampleCapture.heic in the app's Documents folder stands in for one,
    /// so capture can be tried on a real picture. Otherwise the frame is
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

/// A frame between the shutter and Post: the photo as the camera (or the
/// library) gave it, and the same photo upright for CoreImage, at full size
/// and preview size.
private struct Shot {
    let id = UUID()
    let original: UIImage
    let source: CIImage
    let preview: CIImage
    var fromLibrary = false
    /// Where a library photo was taken, from its own metadata.
    var takenAt: CLLocation?
}

/// 'Who was there?' (Part 3): tap circle members present in the moment. A
/// memory detail — no notifications, no mentions.
struct WhoWasThere: View {
    let members: [CircleMember]
    @Binding var selected: Set<String>

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Who was there?")
                .quietLabel()
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
                                    .font(.caption)
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

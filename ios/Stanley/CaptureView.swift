import SwiftUI
import UIKit

/// Capture is a commitment (§8.4): the shot uploads on confirmation; there is
/// no retake, no roll. On the simulator (no camera) a stand-in frame is
/// generated so the flow stays testable end to end.
struct CaptureView: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss
    @State private var caption = ""
    @State private var location = ""
    @State private var tagged: Set<String> = []
    @State private var showCamera = false
    @State private var uploading = false

    private var members: [CircleMember] {
        (state.circle?.members ?? []).filter { $0.id != state.myId }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
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
                } else {
                    #if targetEnvironment(simulator)
                    Button {
                        upload(jpeg: Self.simulatorFrame())
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
                Spacer()
            }
            .padding()
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
                CameraPicker { image in
                    if let jpeg = image.jpegData(compressionQuality: 0.9) {
                        upload(jpeg: jpeg)
                    }
                }
                .ignoresSafeArea()
            }
        }
    }

    private func upload(jpeg: Data) {
        uploading = true
        Task {
            do {
                try await state.capture(
                    jpeg: jpeg,
                    caption: caption.trimmingCharacters(in: .whitespaces),
                    location: location.trimmingCharacters(in: .whitespaces),
                    tagged: Array(tagged)
                )
                dismiss()
            } catch {
                state.surface(error)
            }
            uploading = false
        }
    }

    #if targetEnvironment(simulator)
    private static func simulatorFrame() -> Data {
        let size = CGSize(width: 1080, height: 1440)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { ctx in
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
        return image.jpegData(compressionQuality: 0.9)!
    }
    #endif
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

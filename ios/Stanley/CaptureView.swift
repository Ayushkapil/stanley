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
    @State private var showCamera = false
    @State private var uploading = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Text("One photo. This is today's.")
                    .font(.headline)
                Text("No retakes. It fades in six days unless someone keeps it.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                TextField("A few words, if you like", text: $caption)
                    .textFieldStyle(.roundedBorder)
                // a typed place name, as you'd say it — never GPS, never a map
                TextField("Where was this? (a place, optional)", text: $location)
                    .textFieldStyle(.roundedBorder)
                if uploading {
                    ProgressView()
                } else {
                    #if targetEnvironment(simulator)
                    Button("Capture (simulator frame)") {
                        upload(jpeg: Self.simulatorFrame())
                    }
                    .buttonStyle(.borderedProminent)
                    #else
                    Button {
                        showCamera = true
                    } label: {
                        Label("Open camera", systemImage: "camera")
                    }
                    .buttonStyle(.borderedProminent)
                    #endif
                }
                Spacer()
            }
            .padding()
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
                    location: location.trimmingCharacters(in: .whitespaces)
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

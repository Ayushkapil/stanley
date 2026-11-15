import SwiftUI
import UIKit

/// Stanley's own soft sheet before iOS's prompt (build 61): one line, then
/// Continue and Not now. Only Continue calls iOS. Presented by UIKit over
/// whatever is showing (a sheet included), as `Spoken` is, and held until
/// one of the two is chosen.
@MainActor
enum AskToNotifySheet {
    static func present(continue: @escaping () -> Void, notNow: @escaping () -> Void) {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        guard var top = scene?.keyWindow?.rootViewController else { return }
        while let presented = top.presentedViewController, !presented.isBeingDismissed {
            top = presented
        }
        // Something is already being said: this moment passes, unasked.
        if top is UIAlertController { return }
        var host: UIHostingController<AskToNotifyView>?
        let view = AskToNotifyView(
            choose: { yes in
                host?.dismiss(animated: true) { yes ? `continue`() : notNow() }
            }
        )
        let controller = UIHostingController(rootView: view)
        host = controller
        controller.isModalInPresentation = true
        if let sheet = controller.sheetPresentationController {
            sheet.detents = [.custom { _ in 230 }]
            sheet.prefersGrabberVisible = false
            sheet.preferredCornerRadius = 28
        }
        top.present(controller, animated: true)
    }
}

struct AskToNotifyView: View {
    @AppStorage("stanley.atmosphere") private var raw = "auto"
    let choose: (Bool) -> Void

    var body: some View {
        let palette = Atmosphere.resolve(raw).palette
        VStack(spacing: 18) {
            Image(systemName: "envelope")
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(palette.accent)
                .accessibilityHidden(true)
            Text(AskToNotify.line)
                .font(.system(.body, design: .rounded))
                .foregroundStyle(TextTone.primary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 12) {
                Button("Not now") { choose(false) }
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(TextTone.secondary)
                    .frame(maxWidth: .infinity, minHeight: 48)
                Button { choose(true) } label: {
                    Text("Continue")
                        .font(.system(.body, design: .rounded, weight: .semibold))
                        .foregroundStyle(palette.ink)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(palette.accent, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 28)
        .padding(.bottom, 12)
        .frame(maxWidth: 440)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(palette.floor.ignoresSafeArea())
    }
}

import AuthenticationServices
import SwiftUI

struct WelcomeView: View {
    @Environment(AppState.self) private var state
    @Environment(\.colorScheme) private var colorScheme
    @State private var devName = ""

    var body: some View {
        VStack(spacing: 28) {
            Spacer()
            Text("Welcome to Stanley")
                .font(.keepsake(34))
            Text("A small circle. One photo a day.\nMoments fade unless someone keeps them.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            SignInWithAppleButton(.signIn) { request in
                request.requestedScopes = [.fullName]
            } onCompletion: { result in
                handle(result)
            }
            .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
            .frame(width: 280, height: 48)

            #if DEBUG
            DevSignIn(devName: $devName)
            #endif

            Spacer()
        }
        .padding()
    }

    private func handle(_ result: Result<ASAuthorization, Error>) {
        if case let .failure(error) = result {
            // Backing out of the Apple sheet is not a failure; surface() knows.
            state.surface(error)
            return
        }
        guard case let .success(auth) = result,
              let cred = auth.credential as? ASAuthorizationAppleIDCredential,
              let tokenData = cred.identityToken,
              let token = String(data: tokenData, encoding: .utf8)
        else { return }
        let name = [cred.fullName?.givenName, cred.fullName?.familyName]
            .compactMap { $0 }
            .joined(separator: " ")
        Task { await state.appleSignIn(identityToken: token, name: name.isEmpty ? nil : name) }
    }
}

#if DEBUG
/// Developer-only sign-in, compiled out of release builds. Styled to sit
/// quietly beneath the real Apple button — same width and shape, muted tone.
private struct DevSignIn: View {
    @Environment(AppState.self) private var state
    @Binding var devName: String
    @State private var busy = false

    private let width: CGFloat = 280
    private let radius: CGFloat = 10

    private var canBegin: Bool {
        !devName.trimmingCharacters(in: .whitespaces).isEmpty && !busy
    }

    var body: some View {
        VStack(spacing: 12) {
            Text("developer sign-in")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .padding(.top, 8)

            TextField("Your name", text: $devName)
                .textFieldStyle(.plain)
                .textInputAutocapitalization(.words)
                .padding(.horizontal, 14)
                .frame(width: width, height: 48)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .strokeBorder(.separator, lineWidth: 0.5)
                )

            Button {
                busy = true
                Task {
                    await state.devSignIn(name: devName.trimmingCharacters(in: .whitespaces))
                    busy = false
                }
            } label: {
                Text("Begin")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(canBegin ? Color.primary : Color.secondary)
                    .frame(width: width, height: 48)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(!canBegin)
            .opacity(canBegin ? 1 : 0.6)
        }
        .padding(.top, 4)
    }
}
#endif

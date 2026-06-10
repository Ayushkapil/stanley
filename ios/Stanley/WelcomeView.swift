import SwiftUI

struct WelcomeView: View {
    @Environment(AppState.self) private var state
    @State private var name = ""
    @State private var busy = false

    var body: some View {
        VStack(spacing: 28) {
            Spacer()
            Text("One Day, One Photo")
                .font(.title.weight(.medium))
            Text("A small circle. One photo a day.\nMoments fade unless someone keeps them.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            TextField("Your name", text: $name)
                .textFieldStyle(.roundedBorder)
                .textInputAutocapitalization(.words)
                .frame(maxWidth: 260)
            Button {
                busy = true
                Task {
                    await state.devSignIn(name: name.trimmingCharacters(in: .whitespaces))
                    busy = false
                }
            } label: {
                Text("Begin")
                    .frame(maxWidth: 260)
            }
            .buttonStyle(.borderedProminent)
            .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || busy)
            Spacer()
            Text("pilot build · dev sign-in")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding()
    }
}

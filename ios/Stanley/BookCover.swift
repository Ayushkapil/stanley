import SwiftUI

// The journal's cover (build 45). The Journal tab opens to a book lying
// shut: its name written large in a hand, whose it is, and the months it
// covers. Cream card in daylight, deep charcoal in the dark, a shade down
// the left edge where the spine is. A tap opens it.

enum BookCover {
    /// A cover's height over its width.
    static let shape: CGFloat = 1.38
    static let defaultTitle = "My Journal"
    static let titleLimit = 60
}

/// The cover itself, drawn to whatever size it's given. Everything on it
/// is sized from its width, so it's the same cover lying on the Journal tab
/// and held up in the middle of the screen as the book opens.
struct BookCoverFace: View {
    @Environment(\.colorScheme) private var colorScheme
    let title: String?
    let name: String?
    let span: String
    /// A long press on the title, where the cover can be renamed.
    var onRename: (() -> Void)?

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let spine = w * 0.075
            let corner = w * 0.028
            let board = RoundedRectangle(cornerRadius: corner, style: .continuous)
            ZStack(alignment: .topLeading) {
                board.fill(BookPaper.cover)
                // The card's own tooth: a grain in daylight, and in the
                // dark the same specks barely catching the light.
                Image(uiImage: PaperGrain.tile)
                    .resizable(resizingMode: .tile)
                    .opacity(colorScheme == .dark ? 0.22 : 0.4)
                    .blendMode(colorScheme == .dark ? .screen : .normal)
                    .clipShape(board)
                // The spine: where the cover bends, a shade and a crease.
                HStack(spacing: 0) {
                    LinearGradient(
                        colors: [.black.opacity(colorScheme == .dark ? 0.5 : 0.16), .black.opacity(0.02)],
                        startPoint: .leading, endPoint: .trailing
                    )
                    .frame(width: spine)
                    Rectangle()
                        .fill(.black.opacity(colorScheme == .dark ? 0.35 : 0.08))
                        .frame(width: 0.8)
                    Rectangle()
                        .fill(.white.opacity(colorScheme == .dark ? 0.05 : 0.35))
                        .frame(width: 0.8)
                }
                .clipShape(board)
                // A plain ruled frame, as a bought journal has.
                RoundedRectangle(cornerRadius: corner * 0.6, style: .continuous)
                    .strokeBorder(BookPaper.coverInk.opacity(0.22), lineWidth: 0.6)
                    .padding(.leading, spine + w * 0.055)
                    .padding([.trailing, .vertical], w * 0.055)

                VStack(spacing: 0) {
                    Spacer().frame(height: h * 0.2)
                    Text(shownTitle)
                        .font(.custom(BookHand.font(10, bold: true).fontName, fixedSize: w * 0.125))
                        .foregroundStyle(BookPaper.coverInk)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                        .minimumScaleFactor(0.5)
                        .contentShape(Rectangle())
                        .modifier(LongPress(action: onRename))
                    if let name, !name.isEmpty {
                        Text(name)
                            .font(.custom(BookHand.font(10).fontName, fixedSize: w * 0.064))
                            .foregroundStyle(BookPaper.coverInk.opacity(0.78))
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                            .padding(.top, h * 0.02)
                    }
                    Spacer(minLength: 0)
                    Text(span)
                        .font(.system(size: w * 0.031, weight: .semibold))
                        .tracking(w * 0.004)
                        .textCase(.uppercase)
                        .foregroundStyle(BookPaper.coverInk.opacity(0.6))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Spacer().frame(height: h * 0.12)
                }
                .padding(.leading, spine + w * 0.1)
                .padding(.trailing, w * 0.1)
                .frame(width: w, height: h)
            }
            .overlay(board.strokeBorder(.black.opacity(colorScheme == .dark ? 0 : 0.10), lineWidth: 0.5))
            .overlay(board.strokeBorder(.white.opacity(colorScheme == .dark ? 0.09 : 0), lineWidth: 0.5))
            // It has some thickness: it sits a little off the page. As one
            // thing: left to itself the shadow fell from the lettering too.
            .compositingGroup()
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.6 : 0.16), radius: w * 0.035, x: w * 0.008, y: w * 0.022)
        }
    }

    private var shownTitle: String {
        let given = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return given.isEmpty ? BookCover.defaultTitle : given
    }
}

private struct LongPress: ViewModifier {
    let action: (() -> Void)?

    func body(content: Content) -> some View {
        if let action {
            content.onLongPressGesture(minimumDuration: 0.45, perform: action)
        } else {
            content
        }
    }
}

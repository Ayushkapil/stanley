import SwiftUI

/// Seasonal atmosphere (Part 5): an ambient color-temperature shift, never a
/// skin. It tints accents, the tab bar, card edges, and a faint background
/// wash — and nothing else. It never affects feed order, visibility, or any
/// functionality. Every palette is chosen to read in both light and dark mode.
enum Atmosphere: String, CaseIterable, Identifiable {
    case auto, spring, warm, fall, cool, rain
    var id: String { rawValue }

    var label: String {
        switch self {
        case .auto: return "Auto"
        case .spring: return "Spring"
        case .warm: return "Warm"
        case .fall: return "Fall"
        case .cool: return "Cool"
        case .rain: return "Rain"
        }
    }

    /// Accent + a very faint background wash. Opacities stay low so the wash is
    /// a whisper in light mode and a glow in dark mode.
    var palette: (accent: Color, wash: Color) {
        switch self {
        case .spring: return (Color(red: 0.36, green: 0.62, blue: 0.44), Color(red: 0.36, green: 0.62, blue: 0.44).opacity(0.06))
        case .warm:   return (Color(red: 0.84, green: 0.60, blue: 0.22), Color(red: 0.90, green: 0.62, blue: 0.20).opacity(0.07))
        case .fall:   return (Color(red: 0.80, green: 0.42, blue: 0.20), Color(red: 0.80, green: 0.40, blue: 0.18).opacity(0.07))
        case .cool:   return (Color(red: 0.38, green: 0.52, blue: 0.70), Color(red: 0.40, green: 0.52, blue: 0.70).opacity(0.06))
        case .rain:   return (Color(red: 0.46, green: 0.53, blue: 0.60), Color(red: 0.42, green: 0.48, blue: 0.55).opacity(0.08))
        case .auto:   return Atmosphere.seasonNow.palette
        }
    }

    /// The current real-world season as a concrete atmosphere, by hemisphere.
    static var seasonNow: Atmosphere {
        let month = Calendar.current.component(.month, from: Date())
        let northern = !isSouthernHemisphere(TimeZone.current.identifier)
        // Northern mapping; southern is shifted by six months.
        let m = northern ? month : ((month + 5) % 12) + 1
        switch m {
        case 3...5: return .spring
        case 6...8: return .warm
        case 9...11: return .fall
        default: return .cool   // Dec–Feb
        }
    }

    /// Coarse hemisphere guess from the timezone identifier's region.
    static func isSouthernHemisphere(_ tz: String) -> Bool {
        let south = [
            "Australia/", "Pacific/Auckland", "Pacific/Chatham", "Antarctica/",
            "America/Argentina", "America/Sao_Paulo", "America/Santiago",
            "America/La_Paz", "America/Asuncion", "America/Montevideo", "America/Lima",
            "Africa/Johannesburg", "Africa/Windhoek", "Africa/Maputo", "Africa/Harare",
            "Indian/", "Pacific/Fiji", "Pacific/Port_Moresby",
        ]
        return south.contains { tz.hasPrefix($0) || tz == $0 }
    }

    static func resolve(_ raw: String) -> Atmosphere {
        Atmosphere(rawValue: raw) ?? .auto
    }
}

/// Apply the faint seasonal wash behind a scrolling surface.
struct AtmosphereWash: ViewModifier {
    @AppStorage("stanley.atmosphere") private var raw = "auto"
    func body(content: Content) -> some View {
        content
            .scrollContentBackground(.hidden)
            .background(Atmosphere.resolve(raw).palette.wash.ignoresSafeArea())
    }
}

extension View {
    func atmosphereWash() -> some View { modifier(AtmosphereWash()) }
}

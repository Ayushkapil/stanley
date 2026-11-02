import AudioToolbox
import os
import UIKit

/// What the hand feels, kept to the deliberate social gestures: liking,
/// holding, posting, sealing the circle's note, and pulling a page to
/// refresh it. Nothing for scrolling, switching tabs or moving between
/// screens, which would turn every touch into a buzz. Each is the lightest
/// that still says "done": a light tap for the small things, a medium one
/// for keeping a memory, and the system's success for a photo that's up.
/// iOS stays in charge: with System Haptics off in Settings, these are
/// silent.
@MainActor
enum Haptics {
    /// The double-tap heart appearing.
    static func liked() { impact(.light, "liked") }

    /// A press-and-hold that keeps a photo: the bookmark filling.
    static func held() { impact(.medium, "held") }

    /// A pull that refreshes a page, as it lets go.
    static func refreshed() { impact(.light, "refreshed") }

    /// The circle's note, set and on the board.
    static func noteSealed() { impact(.light, "note sealed") }

    /// Today's photo is up: posted, not merely queued for later.
    static func posted() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        log.debug("haptic: posted")
    }

    private static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle, _ what: String) {
        UIImpactFeedbackGenerator(style: style).impactOccurred()
        log.debug("haptic: \(what, privacy: .public)")
    }
}

/// Debug level, so a simulator run, which has no haptic engine and no
/// speaker check, can show which gestures fired. Not kept by the system.
private let log = Logger(subsystem: "com.ayushkapileshwar.stanley", category: "haptics")

/// The camera's shutter, for a frame Stanley takes itself. The system
/// camera (`CameraPicker`) plays its own at the moment of capture, so
/// playing it again when the photo comes back, after Use Photo, would be a
/// second click seconds late. A library photo is chosen, not taken, so it
/// gets none. A system sound, so the ring/silent switch silences it.
enum Shutter {
    /// "photoShutter.caf", the camera's own.
    private static let sound: SystemSoundID = 1108

    static func play() {
        AudioServicesPlaySystemSound(sound)
        log.debug("sound: shutter")
    }
}

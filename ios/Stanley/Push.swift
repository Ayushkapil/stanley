import UIKit
import UserNotifications

/// The two notices Stanley can send (the last-light notice and the evening
/// note), and the phone's side of reaching it: permission, and the APNs token
/// the server pushes to.
///
/// Permission is asked when someone turns a notice on, in Settings, not at
/// first launch: both are off by default, and a prompt for something nobody
/// has asked for is the opposite of quiet. Once allowed, the phone registers
/// with APNs at every launch (a token can change) and hands the token to
/// `onToken`, which sends it to the server.
@MainActor
final class Push: NSObject, UNUserNotificationCenterDelegate {
    static let shared = Push()

    /// Set by the app: where a fresh token goes.
    var onToken: ((String) -> Void)?
    /// The last token APNs gave this phone, for removing it on sign-out.
    private(set) var token: String?

    func authorization() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    /// Asks iOS, once; after that iOS answers from what the person chose.
    /// Words only: Stanley's notices make no sound and set no badge.
    func requestPermission() async -> Bool {
        let granted = (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert])) ?? false
        if granted { UIApplication.shared.registerForRemoteNotifications() }
        return granted
    }

    /// At launch: register again if notifications are allowed, so the server
    /// has this phone's current token. Asks nothing.
    func refresh() async {
        let status = await authorization()
        if status == .authorized || status == .provisional {
            UIApplication.shared.registerForRemoteNotifications()
        }
    }

    func received(_ deviceToken: Data) {
        let hex = deviceToken.map { String(format: "%02x", $0) }.joined()
        token = hex
        onToken?(hex)
    }

    /// Which APNs the token is for: a build run from Xcode gets sandbox
    /// tokens, TestFlight and the App Store get production ones.
    nonisolated static var environment: String {
        #if DEBUG
        "sandbox"
        #else
        "production"
        #endif
    }

    // A notice that arrives while Stanley is open still shows, quietly.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list]
    }
}

/// UIKit's half of push: the token arrives through the app delegate.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = Push.shared
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Task { @MainActor in Push.shared.received(deviceToken) }
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        // No token, no push: the notices are still logged on the server, and
        // the next launch tries again. Nothing to tell anyone.
    }
}

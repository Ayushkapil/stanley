import SwiftUI
import UIKit
import UserNotifications

/// The app delegate exists for push alone: APNs hands its device token to a
/// delegate, and a tapped notification arrives at one. It owns the AppState so
/// both can reach it from the very first moment — including a launch that a
/// tap started.
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    let state = AppState()

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        Task { await state.refreshNotificationRegistration() }
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        Task { await state.registerDevice(token) }
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        // No signal, or a build without the push entitlement. Nothing to tell
        // anyone: the notices simply can't reach this phone yet.
    }

    /// Every notice Stanley sends is about Today: someone's new moment, the
    /// evening digest, your own photo's last light.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        await MainActor.run { state.tab = .today }
    }
}

extension AppState {
    /// Ask iOS for permission — only ever because the person just turned a
    /// notice on, never at launch. Alerts only: a badge is a count, and Stanley
    /// doesn't call for attention with a sound.
    func enableNotifications() async {
        let center = UNUserNotificationCenter.current()
        let granted = (try? await center.requestAuthorization(options: [.alert])) ?? false
        guard granted else { return }
        await MainActor.run { UIApplication.shared.registerForRemoteNotifications() }
    }

    /// Tokens change, so re-register at every launch — but only when
    /// permission was already given. This never prompts.
    func refreshNotificationRegistration() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        guard settings.authorizationStatus == .authorized else { return }
        await MainActor.run { UIApplication.shared.registerForRemoteNotifications() }
    }

    /// Tell the server this phone can be reached, as whoever is signed in. A
    /// token that arrives before sign-in is kept and sent once someone is.
    func registerDevice(_ token: String) async {
        deviceToken = token
        guard signedIn else { return }
        _ = try? await api.send("POST", "/me/push_token", json: ["token": token]) as Empty
    }

    /// True when iOS has been told not to let Stanley notify at all.
    static func notificationsBlocked() async -> Bool {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus == .denied
    }
}

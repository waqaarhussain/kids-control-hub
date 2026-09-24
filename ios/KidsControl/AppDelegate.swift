import UIKit

final class AppDelegate: NSObject, UIApplicationDelegate {
    static var pendingPushToken: String?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        application.registerForRemoteNotifications()
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
        Self.pendingPushToken = token
        Task { @MainActor in
            await ControlStore.shared.uploadPushTokenIfPossible(token)
        }
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        Task { @MainActor in
            ControlStore.shared.setNotice("Push registration failed: \(error.localizedDescription)")
        }
    }

    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        Task { @MainActor in
            do {
                try await ControlStore.shared.syncAndApply(silent: true)
                completionHandler(.newData)
            } catch {
                completionHandler(.failed)
            }
        }
    }
}

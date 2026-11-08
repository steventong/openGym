import UIKit
import UserNotifications
import HealthKitUI

@MainActor
final class OpenGYMAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    let store = WorkoutActivityRuntime.store

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        WorkoutActivityDiagnostics.record("app.launched", WorkoutActivityDiagnostics.environment())
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func applicationProtectedDataDidBecomeAvailable(_ application: UIApplication) {
        WorkoutActivityDiagnostics.record("app.protected_data.available", WorkoutActivityDiagnostics.environment())
    }

    func applicationProtectedDataWillBecomeUnavailable(_ application: UIApplication) {
        WorkoutActivityDiagnostics.record("app.protected_data.unavailable", WorkoutActivityDiagnostics.environment())
    }

    func applicationWillTerminate(_ application: UIApplication) {
        WorkoutActivityDiagnostics.record("app.terminating", WorkoutActivityDiagnostics.environment())
    }

    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        if #available(iOS 26.0, *), options.shouldHandleActiveWorkoutRecovery { store.workoutHealth.retry() }
        return configuration
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        if notification.request.identifier == "opengym.workout.rest"
            || notification.request.content.userInfo["openGymWorkout"] as? Bool == true {
            center.removeDeliveredNotifications(withIdentifiers: [notification.request.identifier])
            Task { @MainActor in WorkoutActivityDiagnostics.record("reminder.foreground_delivery") }
            completionHandler([.sound])
            return
        }
        completionHandler([.banner, .list, .sound])
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        Task { @MainActor in
            if response.notification.request.content.userInfo["openGymWorkout"] as? Bool == true {
                WorkoutActivityDiagnostics.record("reminder.opened")
                self.store.selectedTab = 2
            }
            completionHandler()
        }
    }
}

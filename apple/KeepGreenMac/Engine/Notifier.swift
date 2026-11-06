import Foundation
import KeepGreenKit
import UserNotifications

/// Short notes when work hours start or end, lunch begins, or a boost runs out. Same rules as the Windows app.
@MainActor
final class Notifier {
    private let presenter = NotificationPresenter()

    init() {
        UNUserNotificationCenter.current().delegate = presenter
    }

    /// Posts a note for a state change, if that change deserves one.
    func presenceChanged(from previous: PresenceDecision, to current: PresenceDecision, detail: String) {
        var message: String?
        if previous.isBoosted && !current.isBoosted {
            message = "Your boost has ended. \(detail)"
        } else if current.isActive && [.offSchedule, .dayOff, .onBreak].contains(previous.state) {
            message = "Work hours started. KeepGreen is keeping you available."
        } else if previous.isActive && [.offSchedule, .dayOff].contains(current.state) {
            message = "Work hours are over. \(detail)"
        } else if previous.isActive && current.state == .onBreak {
            message = "Lunch break. \(detail)"
        }

        if let message = message {
            post(title: "KeepGreen", body: message)
        }
    }

    /// Asks for permission the first time it is needed; afterwards macOS answers without asking again.
    func post(title: String, body: String) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }

            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
            UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
        }
    }
}

/// Shows KeepGreen's notes even while its menu is open (macOS hides them for the active app otherwise).
final class NotificationPresenter: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list])
    }
}

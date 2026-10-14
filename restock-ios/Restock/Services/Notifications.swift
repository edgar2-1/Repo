import UserNotifications
import RestockKit

/// Local notifications only: nothing is sent to a server.
enum Notifications {
    static func requestPermission() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    static func sync(_ reminders: [Reminder], enabled: Bool) async {
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        guard enabled else { return }
        for r in reminders {
            let content = UNMutableNotificationContent()
            content.title = r.title
            content.body = r.body
            content.sound = .default
            var when = DateComponents()
            when.hour = r.hour
            when.minute = r.minute
            if r.repeatsWeekly {
                when.weekday = r.day.weekday + 1
            } else {
                when.year = r.day.year; when.month = r.day.month; when.day = r.day.day
            }
            let trigger = UNCalendarNotificationTrigger(dateMatching: when, repeats: r.repeatsWeekly)
            try? await center.add(UNNotificationRequest(identifier: r.id, content: content, trigger: trigger))
        }
    }

    static func setBadge(_ count: Int) async {
        try? await UNUserNotificationCenter.current().setBadgeCount(count)
    }
}

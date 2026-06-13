import Foundation
import Combine
import UserNotifications

final class NotificationScheduler: ObservableObject {
    func requestAuthorization() async throws {
        try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])
    }

    func scheduleNightlyReminder(profile: UserProfile) async throws {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["nightly-summary-reminder"])

        let content = UNMutableNotificationContent()
        content.title = "记录今天的饮食和运动"
        content.body = "打开健身助手，同步健康数据并生成明天建议。"
        content.sound = .default

        var components = DateComponents()
        components.hour = profile.reminderHour
        components.minute = profile.reminderMinute

        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        let request = UNNotificationRequest(identifier: "nightly-summary-reminder", content: content, trigger: trigger)
        try await center.add(request)
    }
}

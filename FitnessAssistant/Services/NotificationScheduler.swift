import Foundation
import Combine
import UserNotifications

final class NotificationScheduler: ObservableObject {
    private let nightlyReminderID = "nightly-summary-reminder"
    private let weighInReminderID = "daily-weigh-in-reminder"

    func requestAuthorization() async throws {
        try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])
    }

    func scheduleDailyReminders(profile: UserProfile) async throws {
        try await scheduleDailyReminders(nightlyHour: profile.reminderHour, nightlyMinute: profile.reminderMinute)
    }

    func scheduleDailyReminders(nightlyHour: Int, nightlyMinute: Int) async throws {
        try await scheduleNightlyReminder(hour: nightlyHour, minute: nightlyMinute)
        try await scheduleWeighInReminder()
    }

    func scheduleNightlyReminder(profile: UserProfile) async throws {
        try await scheduleNightlyReminder(hour: profile.reminderHour, minute: profile.reminderMinute)
    }

    func scheduleNightlyReminder(hour: Int, minute: Int) async throws {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [nightlyReminderID])

        let content = UNMutableNotificationContent()
        content.title = "记录今天的饮食和运动"
        content.body = "打开健身助手，同步健康数据并生成明天建议。"
        content.sound = .default

        var components = DateComponents()
        components.hour = hour
        components.minute = minute

        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        let request = UNNotificationRequest(identifier: nightlyReminderID, content: content, trigger: trigger)
        try await center.add(request)
    }

    func scheduleWeighInReminder(hour: Int = 8, minute: Int = 0) async throws {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [weighInReminderID])

        let content = UNMutableNotificationContent()
        content.title = "该称体重了"
        content.body = "用体脂秤同步到 Apple 健康，健身助手会读取今天的体重、体脂率和 BMI。"
        content.sound = .default

        var components = DateComponents()
        components.hour = hour
        components.minute = minute

        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        let request = UNNotificationRequest(identifier: weighInReminderID, content: content, trigger: trigger)
        try await center.add(request)
    }
}

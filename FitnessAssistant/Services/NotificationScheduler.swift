import Foundation
import Combine
import UserNotifications

final class NotificationScheduler: ObservableObject {
    private let nightlyReminderID = "nightly-summary-reminder"
    private let weighInReminderID = "daily-weigh-in-reminder"
    private let waterReminderID = "afternoon-water-reminder"
    private let weeklyReviewReminderID = "weekly-review-reminder"

    func requestAuthorization() async throws {
        try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])
    }

    func scheduleDailyReminders(profile: UserProfile) async throws {
        try await scheduleDailyReminders(nightlyHour: profile.reminderHour, nightlyMinute: profile.reminderMinute)
    }

    func scheduleDailyReminders(nightlyHour: Int, nightlyMinute: Int) async throws {
        try await scheduleNightlyReminder(hour: nightlyHour, minute: nightlyMinute)
        try await scheduleWeighInReminder()
        try await scheduleWaterReminder()
        try await scheduleWeeklyReviewReminder()
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

    /// 午后喝水提醒（默认 15:00）。多喝水帮助代谢与排钠，也补齐喝水维度的记录习惯。
    func scheduleWaterReminder(hour: Int = 15, minute: Int = 0) async throws {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [waterReminderID])

        let content = UNMutableNotificationContent()
        content.title = "喝水了吗？"
        content.body = "下午来一杯水，在「数据 → 今日打卡」一键 +250ml。"
        content.sound = .default

        var components = DateComponents()
        components.hour = hour
        components.minute = minute

        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        let request = UNNotificationRequest(identifier: waterReminderID, content: content, trigger: trigger)
        try await center.add(request)
    }

    /// 每周复盘提醒（默认周一 09:00）。以周趋势为主，提醒打开教练做上周复盘并校准下一步。
    func scheduleWeeklyReviewReminder(weekday: Int = 2, hour: Int = 9, minute: Int = 0) async throws {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [weeklyReviewReminderID])

        let content = UNMutableNotificationContent()
        content.title = "本周复盘"
        content.body = "打开 AI 教练，看看上周的体重均值趋势和热量缺口，定下本周的调整。"
        content.sound = .default

        var components = DateComponents()
        components.weekday = weekday   // 1=周日, 2=周一
        components.hour = hour
        components.minute = minute

        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        let request = UNNotificationRequest(identifier: weeklyReviewReminderID, content: content, trigger: trigger)
        try await center.add(request)
    }
}

import Foundation
import SwiftData

/// 体重唯一写入口：把某一天的体重写到 `UserProfile`（仅当天）与当天 `DayLog`（不存在则创建），
/// 杜绝原先「分散写三张表、写入组合不一致、漏写某张表」的问题。
///
/// 调用方负责校验数值范围（如 30...250）。本方法只做一致写入，不做校验。
enum WeightWriter {
    @discardableResult
    static func record(
        _ kg: Double,
        on date: Date = .now,
        profile: UserProfile,
        context: ModelContext,
        dayLogs: [DayLog]
    ) -> DayLog {
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: date)

        if calendar.isDateInToday(date) {
            profile.currentWeightKg = kg
            profile.updatedAt = .now
        }

        let log = dayLogs.first { calendar.isDate($0.date, inSameDayAs: day) } ?? {
            let created = DayLog(date: day)
            context.insert(created)
            return created
        }()
        log.weightKg = kg
        log.updatedAt = .now
        return log
    }
}

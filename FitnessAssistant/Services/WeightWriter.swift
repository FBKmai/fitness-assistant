import Foundation
import SwiftData

/// 体重唯一写入口：把某一天的体重一致地写到 `UserProfile`（仅当天）、当天 `DailyCheckIn`
/// 与当天 `DailySummary`（若存在），杜绝原先各入口「写入组合不一致、漏写某张表」的问题。
///
/// 调用方负责校验数值范围（如 30...250）。本方法只做一致写入，不做校验。
enum WeightWriter {
    @discardableResult
    static func record(
        _ kg: Double,
        on date: Date = .now,
        profile: UserProfile,
        context: ModelContext,
        summaries: [DailySummary],
        checkIns: [DailyCheckIn]
    ) -> DailyCheckIn {
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: date)

        if calendar.isDateInToday(date) {
            profile.currentWeightKg = kg
            profile.updatedAt = .now
        }

        if let summary = summaries.first(where: { calendar.isDate($0.date, inSameDayAs: day) }) {
            summary.weightKg = kg
        }

        let checkIn = checkIns.first { calendar.isDate($0.date, inSameDayAs: day) } ?? {
            let created = DailyCheckIn(date: day)
            context.insert(created)
            return created
        }()
        checkIn.weightKg = kg
        checkIn.updatedAt = .now
        return checkIn
    }
}

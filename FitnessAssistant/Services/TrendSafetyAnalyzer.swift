import Foundation

enum TrendSafetyAnalyzer {
    static func weightAnomaly(
        proposedKg: Double,
        on date: Date,
        dayLogs: [DayLog]
    ) -> String? {
        let calendar = Calendar.current
        let recent = dayLogs
            .filter { $0.weightKg > 0 && $0.date < calendar.dayInterval(containing: date).end }
            .sorted { $0.date > $1.date }
            .prefix(7)
            .map(\.weightKg)
            .sorted()
        guard recent.count >= 3 else { return nil }
        let median = median(recent)
        let threshold = max(3, median * 0.04)
        let difference = abs(proposedKg - median)
        guard difference > threshold else { return nil }
        return "该体重与近 7 次中位数 \(String(format: "%.1f", median)) kg 相差 \(String(format: "%.1f", difference)) kg，请确认是否输入错误。"
    }

    static func alerts(dayLogs: [DayLog], currentWeightKg: Double) -> [SafetyAlert] {
        let logs = dayLogs.sorted { $0.date > $1.date }
        var result: [SafetyAlert] = []

        let recentSleep = logs.prefix(2).compactMap(\.sleepHours)
        if recentSleep.count == 2, recentSleep.allSatisfy({ $0 < 6 }) {
            result.append(SafetyAlert(
                severity: .caution,
                message: "连续 2 天睡眠不足 6 小时，今天应降低训练强度并优先恢复。"
            ))
        }

        let recentSeven = Array(logs.prefix(7))
        let weights = recentSeven.filter { $0.weightKg > 0 }.sorted { $0.date < $1.date }
        if weights.count >= 2,
           let first = weights.first?.weightKg,
           let last = weights.last?.weightKg,
           first - last > max(currentWeightKg, 1) * 0.01 {
            result.append(SafetyAlert(
                severity: .caution,
                message: "近 7 天体重下降超过当前体重的 1%，请检查摄入、训练表现与恢复。"
            ))
        }

        let largeDeficitDays = recentSeven.filter { $0.calorieDeficit > 750 }.count
        if largeDeficitDays >= 3 {
            result.append(SafetyAlert(
                severity: .high,
                message: "近 7 天有 \(largeDeficitDays) 天热量缺口超过 750 kcal，不建议继续扩大缺口。"
            ))
        }

        return result
    }

    static func weightTrend(
        dayLogs: [DayLog],
        targetWeightKg: Double,
        currentWeightKg: Double,
        calendar: Calendar = .current
    ) -> WeightTrendSummary {
        let points = dayLogs
            .filter { $0.weightKg > 0 }
            .sorted { $0.date < $1.date }

        let seven = Array(points.suffix(7))
        let sevenAverage = average(seven.map(\.weightKg))
        let rate14 = weeklyRate(points: Array(points.suffix(14)))
        let rate28 = weeklyRate(points: Array(points.suffix(28)))
        let usableRate = rate28 ?? rate14
        let completeDays = points.suffix(14).filter { $0.intakeCalories > 0 }.count
        let plateau = points.suffix(14).count >= 14
            && completeDays >= 10
            && abs(rate14 ?? .greatestFiniteMagnitude) < 0.15

        var range: ClosedRange<Date>?
        if targetWeightKg > 0,
           currentWeightKg > targetWeightKg,
           let usableRate,
           usableRate < -0.05 {
            let weeks = (currentWeightKg - targetWeightKg) / abs(usableRate)
            let centralDays = Int((weeks * 7).rounded())
            let uncertainty = max(7, Int(Double(centralDays) * 0.25))
            let lower = calendar.date(byAdding: .day, value: max(1, centralDays - uncertainty), to: .now)
            let upper = calendar.date(byAdding: .day, value: centralDays + uncertainty, to: .now)
            if let lower, let upper { range = lower...upper }
        }

        let confidence: String
        if points.count >= 28, rate28 != nil {
            confidence = "较高"
        } else if points.count >= 14, rate14 != nil {
            confidence = "中等"
        } else {
            confidence = "较低"
        }

        return WeightTrendSummary(
            sevenDayAverage: sevenAverage,
            fourteenDayRateKgPerWeek: rate14,
            twentyEightDayRateKgPerWeek: rate28,
            predictedTargetDateRange: range,
            confidence: confidence,
            isPlateau: plateau
        )
    }

    private static func weeklyRate(points: [DayLog]) -> Double? {
        guard points.count >= 4,
              let first = points.first,
              let last = points.last else { return nil }
        let days = last.date.timeIntervalSince(first.date) / 86_400
        guard days >= 3 else { return nil }
        return (last.weightKg - first.weightKg) / days * 7
    }

    private static func average(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    private static func median(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let middle = values.count / 2
        if values.count.isMultiple(of: 2) {
            return (values[middle - 1] + values[middle]) / 2
        }
        return values[middle]
    }
}

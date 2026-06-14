import Foundation

struct DailyEnergyComputation {
    var intakeCalories: Double
    var activeCalories: Double
    var restingCalories: Double
    var totalBurnCalories: Double
    var calorieDeficit: Double
}

struct FatLossAnalysis: Codable {
    var energyStatus: String
    var energyMessage: String
    var recommendedDeficitLowerBound: Double
    var recommendedDeficitUpperBound: Double
    var proteinTargetLowerGrams: Double
    var proteinTargetUpperGrams: Double
    var fatMinimumGrams: Double
    var proteinStatus: String
    var fatStatus: String
    var sevenDayAverageDeficit: Double?
    var sevenDayWeightChangeKg: Double?
    var dataQualityScore: Double
    var dataQualityNotes: [String]
    var warnings: [String]
    var nextActions: [String]
}

enum CalorieCalculator {
    static func bmr(profile: UserProfile) -> Double {
        let weight = max(profile.currentWeightKg, 1)
        let height = max(profile.heightCm, 1)
        let age = max(profile.age, 1)
        let base = 10 * weight + 6.25 * height - 5 * Double(age)

        switch profile.gender {
        case .male:
            return base + 5
        case .female:
            return base - 161
        case .unspecified:
            return base - 78
        }
    }

    static func compute(
        intakeCalories: Double,
        healthKitActiveCalories: Double,
        manualActiveCalories: Double,
        healthKitRestingCalories: Double?,
        profile: UserProfile
    ) -> DailyEnergyComputation {
        let activeCalories = max(0, healthKitActiveCalories) + max(0, manualActiveCalories)
        // HealthKit's basal energy for the current day is often only the amount accumulated so far.
        // For the daily deficit target, use a stable full-day BMR estimate instead.
        _ = healthKitRestingCalories
        let restingCalories = max(0, bmr(profile: profile))
        let totalBurn = restingCalories + activeCalories
        let deficit = totalBurn - max(0, intakeCalories)

        return DailyEnergyComputation(
            intakeCalories: max(0, intakeCalories),
            activeCalories: activeCalories,
            restingCalories: restingCalories,
            totalBurnCalories: totalBurn,
            calorieDeficit: deficit
        )
    }
}

enum FatLossAnalyzer {
    static func analyze(snapshot: DailySnapshot) -> FatLossAnalysis {
        let weight = max(snapshot.weightKg, 1)
        let bmr = max(snapshot.bmr, 1)
        let totalBurn = max(snapshot.totalBurnCalories, bmr + max(snapshot.activeCalories, 0))
        let intake = max(snapshot.intakeCalories, 0)
        let deficit = snapshot.calorieDeficit
        let lowerBound = max(250, totalBurn * 0.10)
        let upperBound = min(max(lowerBound + 100, totalBurn * 0.25), 750)
        let intakeFloor = minimumIntakeFloor(gender: snapshot.gender, bmr: bmr)

        let proteinLower = weight * 1.6
        let proteinUpper = weight * 2.2
        let fatMinimum = weight * 0.6

        var warnings: [String] = []
        var nextActions: [String] = []
        let energyStatus: String
        let energyMessage: String

        if intake == 0 && snapshot.meals.isEmpty {
            energyStatus = "记录不足"
            energyMessage = "今天还没有确认饮食记录，暂时不能可靠判断热量缺口。"
            warnings.append("先补全今天已经吃过的餐食，再生成建议会更准确。")
        } else if intake < intakeFloor {
            energyStatus = "摄入过低"
            energyMessage = "今天摄入低于建议下限，继续扩大缺口可能影响训练状态和坚持度。"
            warnings.append("今天不要再用少吃硬凑缺口，下一餐应补足蛋白质、蔬菜和适量主食。")
        } else if deficit < 0 {
            energyStatus = "热量盈余"
            energyMessage = "今天目前处于热量盈余，减脂目标需要靠后续饮食或活动拉回。"
            nextActions.append("下一餐选择高蛋白、低油烹饪，并减少额外零食和含糖饮料。")
        } else if deficit < lowerBound {
            energyStatus = "缺口偏小"
            energyMessage = "今天热量缺口低于按当前消耗估算的减脂区间。"
            nextActions.append("优先通过晚餐控油、增加蔬菜和保持活动量来补足缺口。")
        } else if deficit <= upperBound {
            energyStatus = "缺口合适"
            energyMessage = "今天热量缺口处在相对稳妥的减脂区间。"
            nextActions.append("保持当前节奏，下一餐不要因为已达标而极端少吃。")
        } else {
            energyStatus = "缺口偏大"
            energyMessage = "今天热量缺口已经偏大，继续压低摄入可能降低恢复质量。"
            warnings.append("建议把后续饮食重心放在蛋白质、微量营养和训练恢复上。")
        }

        let proteinStatus: String
        if snapshot.proteinGrams <= 0 {
            proteinStatus = "未记录"
            nextActions.append("补录或确认蛋白质来源，例如蛋、奶、鱼虾、瘦肉、豆制品。")
        } else if snapshot.proteinGrams < proteinLower * 0.8 {
            proteinStatus = "明显不足"
            warnings.append("今天蛋白质明显不足，减脂期可能影响饱腹感和肌肉保留。")
            nextActions.append("下一餐补 \(Int((proteinLower - snapshot.proteinGrams).rounded()))g 左右蛋白质。")
        } else if snapshot.proteinGrams < proteinLower {
            proteinStatus = "略低"
            nextActions.append("下一餐加一份低脂蛋白，把全天蛋白质补到 \(Int(proteinLower.rounded()))g 以上。")
        } else if snapshot.proteinGrams <= proteinUpper {
            proteinStatus = "达标"
        } else {
            proteinStatus = "偏高"
        }

        let fatStatus: String
        if snapshot.fatGrams <= 0 {
            fatStatus = "未记录"
        } else if snapshot.fatGrams < fatMinimum * 0.8 {
            fatStatus = "偏低"
            warnings.append("今天脂肪摄入偏低，长期过低不利于饮食可持续性。")
        } else {
            fatStatus = "基本合理"
        }

        let averageDeficit = average(snapshot.recentDays.map(\.calorieDeficit))
        let weightChange = recentWeightChange(snapshot.recentDays)
        if let averageDeficit {
            if averageDeficit > upperBound * 1.2 {
                warnings.append("近几天平均热量缺口偏大，建议安排更容易坚持的饮食节奏。")
            } else if averageDeficit < lowerBound * 0.6 {
                nextActions.append("近几天平均缺口偏小，可以先从减少高油零食或增加步行量开始。")
            }
        }
        if let weightChange {
            if weightChange < -weight * 0.01 {
                warnings.append("近几天体重下降较快，注意恢复、睡眠和力量训练表现。")
            } else if weightChange > 0.3, let averageDeficit, averageDeficit >= lowerBound {
                nextActions.append("体重短期上升但缺口存在，优先观察水分波动和记录误差。")
            }
        }

        let quality = dataQuality(snapshot: snapshot)
        warnings.append(contentsOf: quality.warnings)
        if nextActions.isEmpty {
            nextActions.append("下一餐保持高蛋白、足量蔬菜和适量主食，按训练安排微调碳水。")
        }

        return FatLossAnalysis(
            energyStatus: energyStatus,
            energyMessage: energyMessage,
            recommendedDeficitLowerBound: lowerBound,
            recommendedDeficitUpperBound: upperBound,
            proteinTargetLowerGrams: proteinLower,
            proteinTargetUpperGrams: proteinUpper,
            fatMinimumGrams: fatMinimum,
            proteinStatus: proteinStatus,
            fatStatus: fatStatus,
            sevenDayAverageDeficit: averageDeficit,
            sevenDayWeightChangeKg: weightChange,
            dataQualityScore: quality.score,
            dataQualityNotes: quality.notes,
            warnings: Array(Set(warnings)).sorted(),
            nextActions: Array(Set(nextActions)).sorted()
        )
    }

    private static func minimumIntakeFloor(gender: String, bmr: Double) -> Double {
        let genderFloor: Double
        if gender.contains("女") {
            genderFloor = 1200
        } else if gender.contains("男") {
            genderFloor = 1500
        } else {
            genderFloor = 1300
        }
        return min(max(genderFloor, bmr * 0.75), bmr * 0.95)
    }

    private static func average(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    private static func recentWeightChange(_ days: [DayTrend]) -> Double? {
        let points = days
            .filter { ($0.weightKg ?? 0) > 0 }
            .sorted { $0.date < $1.date }
        guard let first = points.first?.weightKg, let last = points.last?.weightKg, points.count >= 2 else {
            return nil
        }
        return last - first
    }

    private static func dataQuality(snapshot: DailySnapshot) -> (score: Double, notes: [String], warnings: [String]) {
        var score = 1.0
        var notes: [String] = []
        var warnings: [String] = []

        if snapshot.recentDays.count < 3 {
            score -= 0.20
            notes.append("近 7 天历史不足 3 天，趋势判断可信度较低。")
        }
        if snapshot.meals.isEmpty {
            score -= 0.20
            notes.append("今天没有确认餐食，摄入判断不完整。")
        }
        if let confidence = snapshot.averageMealConfidence {
            if confidence < 0.45 {
                score -= 0.20
                notes.append("餐食 AI 置信度偏低，建议手动核对份量。")
            } else if confidence < 0.65 {
                score -= 0.10
                notes.append("餐食 AI 置信度一般，热量可能有偏差。")
            }
        } else if !snapshot.meals.isEmpty {
            score -= 0.10
            notes.append("部分餐食缺少置信度，建议核对热量和营养素。")
        }
        if (snapshot.unconfirmedMealCount ?? 0) > 0 {
            score -= 0.10
            notes.append("存在未确认餐食，今日摄入可能被低估。")
        }
        if snapshot.activeCalories <= 0 {
            score -= 0.15
            notes.append("今天没有活动消耗数据，缺口判断会偏保守。")
        }
        if snapshot.weightKg <= 0 {
            score -= 0.15
            notes.append("缺少体重数据，蛋白目标和趋势判断会受影响。")
        }
        if score < 0.65 {
            warnings.append("今天的数据质量一般，建议先补齐饮食、体重或运动数据后再做严格判断。")
        }

        return (min(max(score, 0), 1), notes, warnings)
    }
}

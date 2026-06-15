import Foundation
import Combine
import HealthKit

struct HealthWorkout: Identifiable, Hashable {
    var id: String
    var startDate: Date
    var endDate: Date
    var activityName: String
    var durationMinutes: Double
    var activeCalories: Double
}

struct HealthBodyMetrics: Hashable {
    var weightKg: Double? = nil
    var bodyFatPercentage: Double? = nil
    var bodyMassIndex: Double? = nil
    var measuredAt: Date? = nil

    var hasAnyValue: Bool {
        weightKg != nil || bodyFatPercentage != nil || bodyMassIndex != nil
    }
}

struct HealthSnapshot {
    var date: Date
    var steps: Double
    var activeEnergyKcal: Double
    var basalEnergyKcal: Double?
    var sleepHours: Double?
    var workouts: [HealthWorkout]
    var bodyMetrics: HealthBodyMetrics
}

@MainActor
final class HealthKitService: ObservableObject {
    @Published private(set) var isAvailable = HKHealthStore.isHealthDataAvailable()
    @Published private(set) var authorizationStatusDescription = "未授权"
    @Published private(set) var lastSyncDate: Date?

    private let healthStore = HKHealthStore()

    private var readTypes: Set<HKObjectType> {
        var types = Set<HKObjectType>()
        if let step = HKQuantityType.quantityType(forIdentifier: .stepCount) { types.insert(step) }
        if let active = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) { types.insert(active) }
        if let bodyMass = HKQuantityType.quantityType(forIdentifier: .bodyMass) { types.insert(bodyMass) }
        if let bodyFat = HKQuantityType.quantityType(forIdentifier: .bodyFatPercentage) { types.insert(bodyFat) }
        if let bodyMassIndex = HKQuantityType.quantityType(forIdentifier: .bodyMassIndex) { types.insert(bodyMassIndex) }
        if let sleep = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis) { types.insert(sleep) }
        types.insert(HKObjectType.workoutType())
        return types
    }

    func requestAuthorization() async throws {
        guard isAvailable else {
            authorizationStatusDescription = "当前设备不支持 HealthKit"
            return
        }

        _ = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Bool, Error>) in
            healthStore.requestAuthorization(toShare: nil, read: readTypes) { success, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: success)
                }
            }
        }
        authorizationStatusDescription = "已请求授权"
        await enableBodyMetricBackgroundDelivery()
    }

    func fetchSnapshot(for date: Date = .now) async throws -> HealthSnapshot {
        guard isAvailable else {
            return HealthSnapshot(
                date: date,
                steps: 0,
                activeEnergyKcal: 0,
                basalEnergyKcal: nil,
                sleepHours: nil,
                workouts: [],
                bodyMetrics: HealthBodyMetrics()
            )
        }

        let interval = Calendar.current.dayInterval(containing: date)
        async let stepsValue = quantitySum(.stepCount, unit: .count(), start: interval.start, end: interval.end)
        async let activeEnergyValue = quantitySum(.activeEnergyBurned, unit: .kilocalorie(), start: interval.start, end: interval.end)
        async let workoutValues = workouts(start: interval.start, end: interval.end)
        async let bodyMetricsValue = bodyMetrics(start: interval.start, end: interval.end)
        async let sleepHoursValue = sleepHours(start: interval.start, end: interval.end)

        let stepCount = try await stepsValue
        let activeEnergy = try await activeEnergyValue
        let workouts = try await workoutValues
        let bodyMetrics = try await bodyMetricsValue
        let sleepHours = try await sleepHoursValue

        let snapshot = HealthSnapshot(
            date: date,
            steps: stepCount,
            activeEnergyKcal: activeEnergy,
            basalEnergyKcal: nil,
            sleepHours: sleepHours,
            workouts: workouts,
            bodyMetrics: bodyMetrics
        )
        lastSyncDate = .now
        authorizationStatusDescription = "最近同步 \(DateFormatter.shortTime.string(from: .now))"
        return snapshot
    }

    private func quantitySum(
        _ identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        start: Date,
        end: Date
    ) async throws -> Double {
        guard let type = HKQuantityType.quantityType(forIdentifier: identifier) else { return 0 }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [.strictStartDate])

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, result, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let value = result?.sumQuantity()?.doubleValue(for: unit) ?? 0
                continuation.resume(returning: value)
            }
            healthStore.execute(query)
        }
    }

    private func workouts(start: Date, end: Date) async throws -> [HealthWorkout] {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [.strictStartDate])
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: HKObjectType.workoutType(), predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: [sort]) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let workouts = (samples as? [HKWorkout] ?? []).map { workout in
                    HealthWorkout(
                        id: workout.uuid.uuidString,
                        startDate: workout.startDate,
                        endDate: workout.endDate,
                        activityName: workout.workoutActivityType.localizedTitle,
                        durationMinutes: workout.duration / 60,
                        activeCalories: workout.totalEnergyBurned?.doubleValue(for: .kilocalorie()) ?? 0
                    )
                }
                continuation.resume(returning: workouts)
            }
            healthStore.execute(query)
        }
    }

    private func bodyMetrics(start: Date, end: Date) async throws -> HealthBodyMetrics {
        async let weight = latestQuantity(.bodyMass, unit: .gramUnit(with: .kilo), start: start, end: end)
        async let bodyFat = latestQuantity(.bodyFatPercentage, unit: .percent(), start: start, end: end)
        async let bodyMassIndex = latestQuantity(.bodyMassIndex, unit: .count(), start: start, end: end)

        let weightReading = try await weight
        let bodyFatReading = try await bodyFat
        let bodyMassIndexReading = try await bodyMassIndex
        let measuredAt = [weightReading?.date, bodyFatReading?.date, bodyMassIndexReading?.date]
            .compactMap(\.self)
            .max()

        return HealthBodyMetrics(
            weightKg: weightReading?.value,
            bodyFatPercentage: bodyFatReading.map { normalizedPercent($0.value) },
            bodyMassIndex: bodyMassIndexReading?.value,
            measuredAt: measuredAt
        )
    }

    private func sleepHours(start: Date, end: Date) async throws -> Double? {
        guard let type = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis) else { return nil }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [.strictStartDate])
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: [sort]) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let seconds = (samples as? [HKCategorySample] ?? [])
                    .filter { isAsleep($0.value) }
                    .reduce(0) { $0 + $1.endDate.timeIntervalSince($1.startDate) }
                continuation.resume(returning: seconds > 0 ? seconds / 3600 : nil)
            }
            healthStore.execute(query)
        }
    }

    private func latestQuantity(
        _ identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        start: Date,
        end: Date
    ) async throws -> (value: Double, date: Date)? {
        guard let type = HKQuantityType.quantityType(forIdentifier: identifier) else { return nil }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [.strictStartDate])
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<(value: Double, date: Date)?, Error>) in
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: 1, sortDescriptors: [sort]) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let sample = samples?.first as? HKQuantitySample else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: (sample.quantity.doubleValue(for: unit), sample.endDate))
            }
            healthStore.execute(query)
        }
    }

    private func enableBodyMetricBackgroundDelivery() async {
        for identifier in [HKQuantityTypeIdentifier.bodyMass, .bodyFatPercentage, .bodyMassIndex] {
            guard let type = HKQuantityType.quantityType(forIdentifier: identifier) else { continue }
            _ = try? await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Bool, Error>) in
                healthStore.enableBackgroundDelivery(for: type, frequency: .daily) { success, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: success)
                    }
                }
            }
        }
    }

    private func normalizedPercent(_ value: Double) -> Double {
        value <= 1 ? value * 100 : value
    }
}

private func isAsleep(_ value: Int) -> Bool {
    value == HKCategoryValueSleepAnalysis.asleep.rawValue
        || value == HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue
        || value == HKCategoryValueSleepAnalysis.asleepCore.rawValue
        || value == HKCategoryValueSleepAnalysis.asleepDeep.rawValue
        || value == HKCategoryValueSleepAnalysis.asleepREM.rawValue
}

private extension HKWorkoutActivityType {
    var localizedTitle: String {
        switch self {
        case .running: "跑步"
        case .walking: "步行"
        case .cycling: "骑行"
        case .traditionalStrengthTraining: "力量训练"
        case .functionalStrengthTraining: "功能力量"
        case .swimming: "游泳"
        case .yoga: "瑜伽"
        case .highIntensityIntervalTraining: "高强度间歇"
        case .coreTraining: "核心训练"
        case .elliptical: "椭圆机"
        case .rowing: "划船"
        case .stairClimbing: "爬楼"
        default: "运动"
        }
    }
}

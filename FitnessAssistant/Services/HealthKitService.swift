import Foundation
import HealthKit

struct HealthWorkout: Identifiable, Hashable {
    var id: String
    var startDate: Date
    var endDate: Date
    var activityName: String
    var durationMinutes: Double
    var activeCalories: Double
}

struct HealthSnapshot {
    var date: Date
    var steps: Double
    var activeEnergyKcal: Double
    var basalEnergyKcal: Double?
    var bodyMassKg: Double?
    var workouts: [HealthWorkout]
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
        if let basal = HKQuantityType.quantityType(forIdentifier: .basalEnergyBurned) { types.insert(basal) }
        if let bodyMass = HKQuantityType.quantityType(forIdentifier: .bodyMass) { types.insert(bodyMass) }
        types.insert(HKObjectType.workoutType())
        return types
    }

    func requestAuthorization() async throws {
        guard isAvailable else {
            authorizationStatusDescription = "当前设备不支持 HealthKit"
            return
        }

        try await withCheckedThrowingContinuation { continuation in
            healthStore.requestAuthorization(toShare: nil, read: readTypes) { success, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: success)
                }
            }
        }
        authorizationStatusDescription = "已请求授权"
    }

    func fetchSnapshot(for date: Date = .now) async throws -> HealthSnapshot {
        guard isAvailable else {
            return HealthSnapshot(date: date, steps: 0, activeEnergyKcal: 0, basalEnergyKcal: nil, bodyMassKg: nil, workouts: [])
        }

        let interval = Calendar.current.dayInterval(containing: date)
        async let stepsValue = quantitySum(.stepCount, unit: .count(), start: interval.start, end: interval.end)
        async let activeEnergyValue = quantitySum(.activeEnergyBurned, unit: .kilocalorie(), start: interval.start, end: interval.end)
        async let basalEnergyValue = quantitySum(.basalEnergyBurned, unit: .kilocalorie(), start: interval.start, end: interval.end)
        async let bodyMassValue = latestQuantity(.bodyMass, unit: .gramUnit(with: .kilo), before: interval.end)
        async let workoutValues = workouts(start: interval.start, end: interval.end)

        let stepCount = try await stepsValue
        let activeEnergy = try await activeEnergyValue
        let basalEnergy = try await basalEnergyValue
        let bodyMass = try await bodyMassValue
        let workouts = try await workoutValues

        let snapshot = HealthSnapshot(
            date: date,
            steps: stepCount,
            activeEnergyKcal: activeEnergy,
            basalEnergyKcal: basalEnergy > 0 ? basalEnergy : nil,
            bodyMassKg: bodyMass,
            workouts: workouts
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

    private func latestQuantity(
        _ identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        before end: Date
    ) async throws -> Double? {
        guard let type = HKQuantityType.quantityType(forIdentifier: identifier) else { return nil }
        let predicate = HKQuery.predicateForSamples(withStart: nil, end: end, options: [.strictEndDate])
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: 1, sortDescriptors: [sort]) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let value = (samples?.first as? HKQuantitySample)?.quantity.doubleValue(for: unit)
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

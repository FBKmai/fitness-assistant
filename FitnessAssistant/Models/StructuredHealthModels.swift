import Foundation
import SwiftData

enum CorrectionSource: String, Codable {
    case user
    case coachProposal
    case importFile
}

/// 数据更正审计。业务表保存当前有效值，本表保存更正前后值与原因。
@Model
final class DataCorrection {
    var id: UUID
    var entityType: String
    var entityID: String
    var fieldName: String
    var oldValue: String
    var newValue: String
    var effectiveDate: Date
    var reason: String
    var sourceRaw: String
    var isActive: Bool
    var createdAt: Date
    var reversedAt: Date?

    init(
        id: UUID = UUID(),
        entityType: String,
        entityID: String,
        fieldName: String,
        oldValue: String,
        newValue: String,
        effectiveDate: Date,
        reason: String,
        source: CorrectionSource,
        isActive: Bool = true,
        createdAt: Date = .now,
        reversedAt: Date? = nil
    ) {
        self.id = id
        self.entityType = entityType
        self.entityID = entityID
        self.fieldName = fieldName
        self.oldValue = oldValue
        self.newValue = newValue
        self.effectiveDate = effectiveDate
        self.reason = reason
        self.sourceRaw = source.rawValue
        self.isActive = isActive
        self.createdAt = createdAt
        self.reversedAt = reversedAt
    }

    var source: CorrectionSource {
        get { CorrectionSource(rawValue: sourceRaw) ?? .user }
        set { sourceRaw = newValue.rawValue }
    }
}

struct TrainingSetRecord: Codable, Identifiable, Hashable {
    var id: UUID
    var exerciseName: String
    var setNumber: Int
    var weightKg: Double
    var repetitions: Int
    var rpe: Double?
    var note: String

    init(
        id: UUID = UUID(),
        exerciseName: String,
        setNumber: Int,
        weightKg: Double,
        repetitions: Int,
        rpe: Double? = nil,
        note: String = ""
    ) {
        self.id = id
        self.exerciseName = exerciseName
        self.setNumber = setNumber
        self.weightKg = weightKg
        self.repetitions = repetitions
        self.rpe = rpe
        self.note = note
    }
}

/// 一次训练会话。HealthKit 训练与手动动作组都归档在这里。
@Model
final class TrainingSession {
    var id: UUID
    var date: Date
    var title: String
    var sourceRaw: String
    var durationMinutes: Double
    var activeCalories: Double
    var healthKitWorkoutID: String?
    var averageHeartRate: Double?
    var maxHeartRate: Double?
    var setsJSON: String
    var note: String
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        date: Date = .now,
        title: String,
        source: ExerciseSource = .manual,
        durationMinutes: Double = 0,
        activeCalories: Double = 0,
        healthKitWorkoutID: String? = nil,
        averageHeartRate: Double? = nil,
        maxHeartRate: Double? = nil,
        sets: [TrainingSetRecord] = [],
        note: String = "",
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.date = date
        self.title = title
        self.sourceRaw = source.rawValue
        self.durationMinutes = durationMinutes
        self.activeCalories = activeCalories
        self.healthKitWorkoutID = healthKitWorkoutID
        self.averageHeartRate = averageHeartRate
        self.maxHeartRate = maxHeartRate
        self.setsJSON = Self.encode(sets)
        self.note = note
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var source: ExerciseSource {
        get { ExerciseSource(rawValue: sourceRaw) ?? .manual }
        set { sourceRaw = newValue.rawValue }
    }

    var sets: [TrainingSetRecord] {
        get { Self.decode(setsJSON) }
        set { setsJSON = Self.encode(newValue) }
    }

    var totalVolumeKg: Double {
        sets.reduce(0) { $0 + max(0, $1.weightKg) * Double(max(0, $1.repetitions)) }
    }

    private static func encode(_ values: [TrainingSetRecord]) -> String {
        guard let data = try? JSONEncoder().encode(values) else { return "[]" }
        return String(data: data, encoding: .utf8) ?? "[]"
    }

    private static func decode(_ json: String) -> [TrainingSetRecord] {
        guard let data = json.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([TrainingSetRecord].self, from: data)) ?? []
    }
}

enum RestingEnergySource: String, Codable {
    case healthKit
    case bmrEstimate

    var title: String {
        switch self {
        case .healthKit: "Apple 健康"
        case .bmrEstimate: "BMR 估算"
        }
    }
}

struct SafetyAlert: Identifiable, Hashable {
    enum Severity: String {
        case info
        case caution
        case high
    }

    var id: String { "\(severity.rawValue)-\(message)" }
    var severity: Severity
    var message: String
}

struct WeightTrendSummary {
    var sevenDayAverage: Double?
    var fourteenDayRateKgPerWeek: Double?
    var twentyEightDayRateKgPerWeek: Double?
    var predictedTargetDateRange: ClosedRange<Date>?
    var confidence: String
    var isPlateau: Bool
}

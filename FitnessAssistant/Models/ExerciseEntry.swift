import Foundation
import SwiftData

@Model
final class ExerciseEntry {
    var id: UUID
    var date: Date
    var sourceRaw: String
    var workoutType: String
    var durationMinutes: Double
    var activeCalories: Double
    var steps: Double
    var healthKitWorkoutID: String?
    var averageHeartRate: Double? = nil
    var maxHeartRate: Double? = nil
    var trainingSessionID: UUID? = nil
    var createdAt: Date

    init(
        id: UUID = UUID(),
        date: Date = .now,
        source: ExerciseSource = .manual,
        workoutType: String = "",
        durationMinutes: Double = 0,
        activeCalories: Double = 0,
        steps: Double = 0,
        healthKitWorkoutID: String? = nil,
        averageHeartRate: Double? = nil,
        maxHeartRate: Double? = nil,
        trainingSessionID: UUID? = nil,
        createdAt: Date = .now
    ) {
        self.id = id
        self.date = date
        self.sourceRaw = source.rawValue
        self.workoutType = workoutType
        self.durationMinutes = durationMinutes
        self.activeCalories = activeCalories
        self.steps = steps
        self.healthKitWorkoutID = healthKitWorkoutID
        self.averageHeartRate = averageHeartRate
        self.maxHeartRate = maxHeartRate
        self.trainingSessionID = trainingSessionID
        self.createdAt = createdAt
    }

    var source: ExerciseSource {
        get { ExerciseSource(rawValue: sourceRaw) ?? .manual }
        set { sourceRaw = newValue.rawValue }
    }
}

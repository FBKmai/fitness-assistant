import Foundation
import SwiftData

enum CoachScenario: String, CaseIterable, Codable, Identifiable {
    case mealBefore
    case mealAfter
    case workoutBefore
    case workoutAfter
    case dailyReview
    case weeklyReview
    case foodDecision
    case weightTrend
    case recoverySafety
    case general

    var id: String { rawValue }

    var title: String {
        switch self {
        case .mealBefore: "饭前建议"
        case .mealAfter: "饭后复盘"
        case .workoutBefore: "练前安排"
        case .workoutAfter: "练后恢复"
        case .dailyReview: "每日复盘"
        case .weeklyReview: "周复盘"
        case .foodDecision: "能不能吃"
        case .weightTrend: "体重趋势"
        case .recoverySafety: "恢复与安全"
        case .general: "综合建议"
        }
    }
}

enum CoachMessageRole: String, Codable {
    case user
    case assistant
}

enum CoachSuggestedRecordKind: String, Codable {
    case meal
    case exercise
    case checkIn
}

struct CoachMemoryPatch: Codable, Hashable {
    var profileSummary: String?
    var foodPreferences: [String]
    var avoidances: [String]
    var trainingPreferences: [String]
    var healthNotes: [String]
    var rules: [String]

    init(
        profileSummary: String? = nil,
        foodPreferences: [String] = [],
        avoidances: [String] = [],
        trainingPreferences: [String] = [],
        healthNotes: [String] = [],
        rules: [String] = []
    ) {
        self.profileSummary = profileSummary
        self.foodPreferences = foodPreferences
        self.avoidances = avoidances
        self.trainingPreferences = trainingPreferences
        self.healthNotes = healthNotes
        self.rules = rules
    }

    var isEmpty: Bool {
        (profileSummary?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
            && foodPreferences.isEmpty
            && avoidances.isEmpty
            && trainingPreferences.isEmpty
            && healthNotes.isEmpty
            && rules.isEmpty
    }

    enum CodingKeys: String, CodingKey {
        case profileSummary
        case foodPreferences
        case avoidances
        case trainingPreferences
        case healthNotes
        case rules
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        profileSummary = try container.decodeIfPresent(String.self, forKey: .profileSummary)
        foodPreferences = try container.decodeIfPresent([String].self, forKey: .foodPreferences) ?? []
        avoidances = try container.decodeIfPresent([String].self, forKey: .avoidances) ?? []
        trainingPreferences = try container.decodeIfPresent([String].self, forKey: .trainingPreferences) ?? []
        healthNotes = try container.decodeIfPresent([String].self, forKey: .healthNotes) ?? []
        rules = try container.decodeIfPresent([String].self, forKey: .rules) ?? []
    }
}

struct CoachSuggestedRecord: Codable, Identifiable, Hashable {
    var id: UUID
    var kind: CoachSuggestedRecordKind
    var title: String
    var note: String
    var date: Date?

    var mealTypeRaw: String?
    var textDescription: String?
    var totalCalories: Double?
    var proteinGrams: Double?
    var carbsGrams: Double?
    var fatGrams: Double?

    var workoutType: String?
    var durationMinutes: Double?
    var activeCalories: Double?
    var steps: Double?

    var weightKg: Double?
    var bodyFatPercentage: Double?
    var bodyMassIndex: Double?
    var sleepHours: Double?
    var waterMl: Double?
    var hungerLevel: Int?
    var mood: String?
    var symptoms: String?

    init(
        id: UUID = UUID(),
        kind: CoachSuggestedRecordKind,
        title: String,
        note: String = "",
        date: Date? = nil,
        mealTypeRaw: String? = nil,
        textDescription: String? = nil,
        totalCalories: Double? = nil,
        proteinGrams: Double? = nil,
        carbsGrams: Double? = nil,
        fatGrams: Double? = nil,
        workoutType: String? = nil,
        durationMinutes: Double? = nil,
        activeCalories: Double? = nil,
        steps: Double? = nil,
        weightKg: Double? = nil,
        bodyFatPercentage: Double? = nil,
        bodyMassIndex: Double? = nil,
        sleepHours: Double? = nil,
        waterMl: Double? = nil,
        hungerLevel: Int? = nil,
        mood: String? = nil,
        symptoms: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.note = note
        self.date = date
        self.mealTypeRaw = mealTypeRaw
        self.textDescription = textDescription
        self.totalCalories = totalCalories
        self.proteinGrams = proteinGrams
        self.carbsGrams = carbsGrams
        self.fatGrams = fatGrams
        self.workoutType = workoutType
        self.durationMinutes = durationMinutes
        self.activeCalories = activeCalories
        self.steps = steps
        self.weightKg = weightKg
        self.bodyFatPercentage = bodyFatPercentage
        self.bodyMassIndex = bodyMassIndex
        self.sleepHours = sleepHours
        self.waterMl = waterMl
        self.hungerLevel = hungerLevel
        self.mood = mood
        self.symptoms = symptoms
    }

    enum CodingKeys: String, CodingKey {
        case id
        case kind
        case title
        case note
        case date
        case mealTypeRaw
        case textDescription
        case totalCalories
        case proteinGrams
        case carbsGrams
        case fatGrams
        case workoutType
        case durationMinutes
        case activeCalories
        case steps
        case weightKg
        case bodyFatPercentage
        case bodyMassIndex
        case sleepHours
        case waterMl
        case hungerLevel
        case mood
        case symptoms
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        kind = try container.decode(CoachSuggestedRecordKind.self, forKey: .kind)
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? kind.rawValue
        note = try container.decodeIfPresent(String.self, forKey: .note) ?? ""
        date = try Self.decodeDateIfPresent(container, forKey: .date)
        mealTypeRaw = try container.decodeIfPresent(String.self, forKey: .mealTypeRaw)
        textDescription = try container.decodeIfPresent(String.self, forKey: .textDescription)
        totalCalories = try container.decodeIfPresent(Double.self, forKey: .totalCalories)
        proteinGrams = try container.decodeIfPresent(Double.self, forKey: .proteinGrams)
        carbsGrams = try container.decodeIfPresent(Double.self, forKey: .carbsGrams)
        fatGrams = try container.decodeIfPresent(Double.self, forKey: .fatGrams)
        workoutType = try container.decodeIfPresent(String.self, forKey: .workoutType)
        durationMinutes = try container.decodeIfPresent(Double.self, forKey: .durationMinutes)
        activeCalories = try container.decodeIfPresent(Double.self, forKey: .activeCalories)
        steps = try container.decodeIfPresent(Double.self, forKey: .steps)
        weightKg = try container.decodeIfPresent(Double.self, forKey: .weightKg)
        bodyFatPercentage = try container.decodeIfPresent(Double.self, forKey: .bodyFatPercentage)
        bodyMassIndex = try container.decodeIfPresent(Double.self, forKey: .bodyMassIndex)
        sleepHours = try container.decodeIfPresent(Double.self, forKey: .sleepHours)
        waterMl = try container.decodeIfPresent(Double.self, forKey: .waterMl)
        hungerLevel = try container.decodeIfPresent(Int.self, forKey: .hungerLevel)
        mood = try container.decodeIfPresent(String.self, forKey: .mood)
        symptoms = try container.decodeIfPresent(String.self, forKey: .symptoms)
    }

    private static func decodeDateIfPresent(
        _ container: KeyedDecodingContainer<CodingKeys>,
        forKey key: CodingKeys
    ) throws -> Date? {
        if let date = try? container.decodeIfPresent(Date.self, forKey: key) {
            return date
        }
        if let timestamp = try? container.decodeIfPresent(Double.self, forKey: key) {
            return Date(timeIntervalSince1970: timestamp)
        }
        guard let text = try container.decodeIfPresent(String.self, forKey: key) else { return nil }
        if let date = ISO8601DateFormatter().date(from: text) {
            return date
        }
        return DateFormatter.csvDateTime.date(from: text) ?? DateFormatter.csvDate.date(from: text)
    }

    var mealType: MealType {
        MealType(rawValue: mealTypeRaw ?? "") ?? .other
    }

    func makeMealEntry(defaultDate: Date = .now) -> MealEntry? {
        guard kind == .meal else { return nil }
        let calories = max(0, totalCalories ?? 0)
        return MealEntry(
            date: date ?? defaultDate,
            mealType: mealType,
            textDescription: textDescription ?? title,
            estimatedItems: [
                MealFoodItem(
                    name: title,
                    calories: calories,
                    proteinGrams: max(0, proteinGrams ?? 0),
                    carbsGrams: max(0, carbsGrams ?? 0),
                    fatGrams: max(0, fatGrams ?? 0),
                    note: note
                )
            ],
            totalCalories: calories,
            proteinGrams: max(0, proteinGrams ?? 0),
            carbsGrams: max(0, carbsGrams ?? 0),
            fatGrams: max(0, fatGrams ?? 0),
            confidence: 0.6,
            isConfirmed: true
        )
    }

    func makeExerciseEntry(defaultDate: Date = .now) -> ExerciseEntry? {
        guard kind == .exercise else { return nil }
        return ExerciseEntry(
            date: date ?? defaultDate,
            source: .manual,
            workoutType: workoutType ?? title,
            durationMinutes: max(0, durationMinutes ?? 0),
            activeCalories: max(0, activeCalories ?? 0),
            steps: max(0, steps ?? 0)
        )
    }
}

struct CoachReplyResult: Codable {
    var replyText: String
    var scenario: CoachScenario
    var suggestedRecords: [CoachSuggestedRecord]
    var memoryPatch: CoachMemoryPatch?
    var riskLevel: String

    init(
        replyText: String,
        scenario: CoachScenario = .general,
        suggestedRecords: [CoachSuggestedRecord] = [],
        memoryPatch: CoachMemoryPatch? = nil,
        riskLevel: String = "normal"
    ) {
        self.replyText = replyText
        self.scenario = scenario
        self.suggestedRecords = suggestedRecords
        self.memoryPatch = memoryPatch
        self.riskLevel = riskLevel
    }

    enum CodingKeys: String, CodingKey {
        case replyText
        case scenario
        case suggestedRecords
        case memoryPatch
        case riskLevel
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        replyText = try container.decodeIfPresent(String.self, forKey: .replyText) ?? ""
        scenario = try container.decodeIfPresent(CoachScenario.self, forKey: .scenario) ?? .general
        suggestedRecords = try container.decodeIfPresent([CoachSuggestedRecord].self, forKey: .suggestedRecords) ?? []
        memoryPatch = try container.decodeIfPresent(CoachMemoryPatch.self, forKey: .memoryPatch)
        riskLevel = try container.decodeIfPresent(String.self, forKey: .riskLevel) ?? "normal"
    }
}

struct CoachProfileSnapshot: Codable, Hashable {
    var goal: String
    var targetDailyDeficitKcal: Double
    var heightCm: Double
    var weightKg: Double
    var bodyFatPercentage: Double?
    var bodyMassIndex: Double?
    var gender: String
    var age: Int
    var bmr: Double
}

struct CoachDailyMetrics: Codable, Hashable {
    var date: Date
    var intakeCalories: Double
    var activeCalories: Double
    var restingCalories: Double
    var totalBurnCalories: Double
    var calorieDeficit: Double
    var proteinGrams: Double
    var carbsGrams: Double
    var fatGrams: Double
    var confirmedMealCount: Int
    var unconfirmedMealCount: Int
    var workoutCount: Int
    var steps: Double
    var weightKg: Double?
    var bodyFatPercentage: Double?
    var bodyMassIndex: Double?
    var sleepHours: Double?
    var waterMl: Double?
    var hungerLevel: Int?
    var mood: String
    var symptoms: String
    var note: String
}

struct CoachMealSnapshot: Codable, Hashable {
    var id: UUID
    var date: Date
    var mealType: String
    var textDescription: String
    var totalCalories: Double
    var proteinGrams: Double
    var carbsGrams: Double
    var fatGrams: Double
    var isConfirmed: Bool
}

struct CoachExerciseSnapshot: Codable, Hashable {
    var id: UUID
    var date: Date
    var source: String
    var workoutType: String
    var durationMinutes: Double
    var activeCalories: Double
    var steps: Double
    var isDailyHealthAggregate: Bool
}

struct CoachDaySummarySnapshot: Codable, Hashable {
    var date: Date
    var intakeCalories: Double
    var activeCalories: Double
    var calorieDeficit: Double
    var weightKg: Double?
    var proteinGrams: Double
    var carbsGrams: Double
    var fatGrams: Double
    var sleepHours: Double?
    var waterMl: Double?
}

struct CoachTrainingPlanSnapshot: Codable, Hashable {
    var id: UUID
    var title: String
    var goal: String
    var dailyCalories: Double
    var proteinGrams: Double
    var carbsGrams: Double
    var fatGrams: Double
    var trainingDaysPerWeek: Int
    var summary: String
    var updatedAt: Date
}

struct CoachMemorySnapshot: Codable, Hashable {
    var profileSummary: String
    var foodPreferences: [String]
    var avoidances: [String]
    var trainingPreferences: [String]
    var healthNotes: [String]
    var rules: [String]
}

struct CoachContextSnapshot: Codable {
    var requestedAt: Date
    var profile: CoachProfileSnapshot
    var today: CoachDailyMetrics
    var todayMeals: [CoachMealSnapshot]
    var todayExercises: [CoachExerciseSnapshot]
    var recentMeals: [CoachMealSnapshot]
    var recentExercises: [CoachExerciseSnapshot]
    var recent7Days: [CoachDaySummarySnapshot]
    var recent30Days: [CoachDaySummarySnapshot]
    var foodOptions: [FoodOptionSnapshot]
    var trainingPlans: [CoachTrainingPlanSnapshot]
    var memory: CoachMemorySnapshot?
    var analysis: FatLossAnalysis
    var dataQualityNotes: [String]
}

@Model
final class CoachChatSession {
    var id: UUID
    var title: String
    var lastMessageText: String
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        title: String = "AI 教练",
        lastMessageText: String = "",
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.title = title
        self.lastMessageText = lastMessageText
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

@Model
final class CoachChatMessage {
    var id: UUID
    var sessionID: UUID
    var roleRaw: String
    var text: String
    var scenarioRaw: String
    var riskLevel: String
    var contextJSON: String
    var suggestedRecordsJSON: String
    var memoryPatchJSON: String
    var createdAt: Date

    init(
        id: UUID = UUID(),
        sessionID: UUID,
        role: CoachMessageRole,
        text: String,
        scenario: CoachScenario = .general,
        riskLevel: String = "normal",
        context: CoachContextSnapshot? = nil,
        suggestedRecords: [CoachSuggestedRecord] = [],
        memoryPatch: CoachMemoryPatch? = nil,
        createdAt: Date = .now
    ) {
        self.id = id
        self.sessionID = sessionID
        self.roleRaw = role.rawValue
        self.text = text
        self.scenarioRaw = scenario.rawValue
        self.riskLevel = riskLevel
        self.contextJSON = Self.encode(context)
        self.suggestedRecordsJSON = Self.encode(suggestedRecords)
        self.memoryPatchJSON = Self.encode(memoryPatch)
        self.createdAt = createdAt
    }

    var role: CoachMessageRole {
        get { CoachMessageRole(rawValue: roleRaw) ?? .assistant }
        set { roleRaw = newValue.rawValue }
    }

    var scenario: CoachScenario {
        get { CoachScenario(rawValue: scenarioRaw) ?? .general }
        set { scenarioRaw = newValue.rawValue }
    }

    var suggestedRecords: [CoachSuggestedRecord] {
        get { Self.decode([CoachSuggestedRecord].self, from: suggestedRecordsJSON) ?? [] }
        set { suggestedRecordsJSON = Self.encode(newValue) }
    }

    var memoryPatch: CoachMemoryPatch? {
        get { Self.decode(CoachMemoryPatch.self, from: memoryPatchJSON) }
        set { memoryPatchJSON = Self.encode(newValue) }
    }

    private static func encode<T: Encodable>(_ value: T?) -> String {
        guard let value, let data = try? JSONEncoder().encode(value) else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }

    private static func decode<T: Decodable>(_ type: T.Type, from json: String) -> T? {
        guard !json.isEmpty, let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}

@Model
final class CoachMemory {
    var id: UUID
    var profileSummary: String
    var foodPreferencesJSON: String
    var avoidancesJSON: String
    var trainingPreferencesJSON: String
    var healthNotesJSON: String
    var rulesJSON: String
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        profileSummary: String = "",
        foodPreferences: [String] = [],
        avoidances: [String] = [],
        trainingPreferences: [String] = [],
        healthNotes: [String] = [],
        rules: [String] = [],
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.profileSummary = profileSummary
        self.foodPreferencesJSON = Self.encode(foodPreferences)
        self.avoidancesJSON = Self.encode(avoidances)
        self.trainingPreferencesJSON = Self.encode(trainingPreferences)
        self.healthNotesJSON = Self.encode(healthNotes)
        self.rulesJSON = Self.encode(rules)
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var foodPreferences: [String] {
        get { Self.decode(foodPreferencesJSON) }
        set { foodPreferencesJSON = Self.encode(newValue) }
    }

    var avoidances: [String] {
        get { Self.decode(avoidancesJSON) }
        set { avoidancesJSON = Self.encode(newValue) }
    }

    var trainingPreferences: [String] {
        get { Self.decode(trainingPreferencesJSON) }
        set { trainingPreferencesJSON = Self.encode(newValue) }
    }

    var healthNotes: [String] {
        get { Self.decode(healthNotesJSON) }
        set { healthNotesJSON = Self.encode(newValue) }
    }

    var rules: [String] {
        get { Self.decode(rulesJSON) }
        set { rulesJSON = Self.encode(newValue) }
    }

    var snapshot: CoachMemorySnapshot {
        CoachMemorySnapshot(
            profileSummary: profileSummary,
            foodPreferences: foodPreferences,
            avoidances: avoidances,
            trainingPreferences: trainingPreferences,
            healthNotes: healthNotes,
            rules: rules
        )
    }

    func apply(_ patch: CoachMemoryPatch?) {
        guard let patch, !patch.isEmpty else { return }
        if let summary = patch.profileSummary?.trimmingCharacters(in: .whitespacesAndNewlines), !summary.isEmpty {
            profileSummary = summary
        }
        foodPreferences = Self.merged(foodPreferences, patch.foodPreferences)
        avoidances = Self.merged(avoidances, patch.avoidances)
        trainingPreferences = Self.merged(trainingPreferences, patch.trainingPreferences)
        healthNotes = Self.merged(healthNotes, patch.healthNotes)
        rules = Self.merged(rules, patch.rules)
        updatedAt = .now
    }

    private static func merged(_ old: [String], _ new: [String]) -> [String] {
        var result: [String] = []
        for item in old + new {
            let trimmed = item.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !result.contains(trimmed) else { continue }
            result.append(trimmed)
        }
        return Array(result.suffix(30))
    }

    private static func encode(_ values: [String]) -> String {
        guard let data = try? JSONEncoder().encode(values) else { return "[]" }
        return String(data: data, encoding: .utf8) ?? "[]"
    }

    private static func decode(_ json: String) -> [String] {
        guard let data = json.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([String].self, from: data)) ?? []
    }
}

@Model
final class DailyCheckIn {
    var id: UUID
    var date: Date
    var weightKg: Double
    var bodyFatPercentage: Double?
    var bodyMassIndex: Double?
    var sleepHours: Double?
    var waterMl: Double?
    var hungerLevel: Int?
    var mood: String
    var symptoms: String
    var note: String
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        date: Date = Calendar.current.startOfDay(for: .now),
        weightKg: Double = 0,
        bodyFatPercentage: Double? = nil,
        bodyMassIndex: Double? = nil,
        sleepHours: Double? = nil,
        waterMl: Double? = nil,
        hungerLevel: Int? = nil,
        mood: String = "",
        symptoms: String = "",
        note: String = "",
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.date = Calendar.current.startOfDay(for: date)
        self.weightKg = weightKg
        self.bodyFatPercentage = bodyFatPercentage
        self.bodyMassIndex = bodyMassIndex
        self.sleepHours = sleepHours
        self.waterMl = waterMl
        self.hungerLevel = hungerLevel
        self.mood = mood
        self.symptoms = symptoms
        self.note = note
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    func apply(_ suggestion: CoachSuggestedRecord) {
        if let weightKg = suggestion.weightKg { self.weightKg = weightKg }
        if let bodyFatPercentage = suggestion.bodyFatPercentage { self.bodyFatPercentage = bodyFatPercentage }
        if let bodyMassIndex = suggestion.bodyMassIndex { self.bodyMassIndex = bodyMassIndex }
        if let sleepHours = suggestion.sleepHours { self.sleepHours = sleepHours }
        if let waterMl = suggestion.waterMl { self.waterMl = waterMl }
        if let hungerLevel = suggestion.hungerLevel { self.hungerLevel = hungerLevel }
        if let mood = suggestion.mood { self.mood = mood }
        if let symptoms = suggestion.symptoms { self.symptoms = symptoms }
        if !suggestion.note.isEmpty { note = suggestion.note }
        updatedAt = .now
    }
}

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
    case foodAlias
}

enum RecordProposalAction: String, Codable {
    case create
    case update
    case remember
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
    var action: RecordProposalAction
    var kind: CoachSuggestedRecordKind
    var title: String
    var note: String
    var date: Date?
    var existingRecordID: String?
    var oldValueSummary: String?

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
    var targetFoodOptionID: UUID?
    var aliases: [String]

    init(
        id: UUID = UUID(),
        action: RecordProposalAction = .create,
        kind: CoachSuggestedRecordKind,
        title: String,
        note: String = "",
        date: Date? = nil,
        existingRecordID: String? = nil,
        oldValueSummary: String? = nil,
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
        symptoms: String? = nil,
        targetFoodOptionID: UUID? = nil,
        aliases: [String] = []
    ) {
        self.id = id
        self.action = action
        self.kind = kind
        self.title = title
        self.note = note
        self.date = date
        self.existingRecordID = existingRecordID
        self.oldValueSummary = oldValueSummary
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
        self.targetFoodOptionID = targetFoodOptionID
        self.aliases = aliases
    }

    enum CodingKeys: String, CodingKey {
        case id
        case action
        case kind
        case title
        case note
        case date
        case existingRecordID
        case oldValueSummary
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
        case targetFoodOptionID
        case aliases
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        action = try container.decodeIfPresent(RecordProposalAction.self, forKey: .action) ?? .create
        kind = try container.decode(CoachSuggestedRecordKind.self, forKey: .kind)
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? kind.rawValue
        note = try container.decodeIfPresent(String.self, forKey: .note) ?? ""
        date = try Self.decodeDateIfPresent(container, forKey: .date)
        existingRecordID = try container.decodeIfPresent(String.self, forKey: .existingRecordID)
        oldValueSummary = try container.decodeIfPresent(String.self, forKey: .oldValueSummary)
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
        targetFoodOptionID = try container.decodeIfPresent(UUID.self, forKey: .targetFoodOptionID)
        aliases = try container.decodeIfPresent([String].self, forKey: .aliases) ?? []
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

/// 新版教练协议名称；保留旧类型名以兼容历史消息 JSON 和迁移。
typealias RecordProposal = CoachSuggestedRecord

/// 已被「自动记账」写入的记录引用：用于在气泡里渲染「✓ 已记录 · 撤销 / 编辑」，
/// 并保留被写入实体的类型与 id 以支持撤销/编辑。饮食、运动的 create 提案会自动写入并落到这里。
struct AppliedRecordRef: Codable, Identifiable, Hashable {
    var id: UUID            // 原提案 id
    var kindRaw: String     // CoachSuggestedRecordKind
    var title: String
    var entityType: String  // "MealEntry" / "ExerciseEntry"
    var entityID: String    // 被写入实体的 UUID 字符串
    var macroSummary: String

    var kind: CoachSuggestedRecordKind { CoachSuggestedRecordKind(rawValue: kindRaw) ?? .meal }

    init(
        id: UUID,
        kind: CoachSuggestedRecordKind,
        title: String,
        entityType: String,
        entityID: String,
        macroSummary: String = ""
    ) {
        self.id = id
        self.kindRaw = kind.rawValue
        self.title = title
        self.entityType = entityType
        self.entityID = entityID
        self.macroSummary = macroSummary
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

    var proposals: [RecordProposal] {
        get { suggestedRecords }
        set { suggestedRecords = newValue }
    }

    enum CodingKeys: String, CodingKey {
        case replyText
        case scenario
        case suggestedRecords
        case proposals
        case memoryPatch
        case riskLevel
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        replyText = try container.decodeIfPresent(String.self, forKey: .replyText) ?? ""
        scenario = try container.decodeIfPresent(CoachScenario.self, forKey: .scenario) ?? .general
        let proposals = try container.decodeIfPresent(
            [CoachSuggestedRecord].self,
            forKey: .proposals
        )
        let legacyRecords = try container.decodeIfPresent(
            [CoachSuggestedRecord].self,
            forKey: .suggestedRecords
        )
        suggestedRecords = proposals ?? legacyRecords ?? []
        memoryPatch = try container.decodeIfPresent(CoachMemoryPatch.self, forKey: .memoryPatch)
        riskLevel = try container.decodeIfPresent(String.self, forKey: .riskLevel) ?? "normal"
    }

    // CodingKeys 含计算属性 `proposals`，无法合成 Encodable，需手写 encode。
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(replyText, forKey: .replyText)
        try container.encode(scenario, forKey: .scenario)
        try container.encode(suggestedRecords, forKey: .suggestedRecords)
        try container.encodeIfPresent(memoryPatch, forKey: .memoryPatch)
        try container.encode(riskLevel, forKey: .riskLevel)
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
    var fiberGrams: Double? = nil
    var vegetableGrams: Double? = nil
    var restingEnergySource: String? = nil
    var restingHeartRate: Double? = nil
    var averageHeartRate: Double? = nil
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

struct CoachTrainingSessionSnapshot: Codable, Hashable {
    var id: UUID
    var date: Date
    var title: String
    var durationMinutes: Double
    var activeCalories: Double
    var averageHeartRate: Double?
    var maxHeartRate: Double?
    var totalVolumeKg: Double
    var setCount: Int
}

struct CoachMemorySnapshot: Codable, Hashable {
    var profileSummary: String
    var foodPreferences: [String]
    var avoidances: [String]
    var trainingPreferences: [String]
    var healthNotes: [String]
    var rules: [String]
}

struct CoachDailyCarryover: Codable, Hashable {
    var summary: String
    var importantNotes: [String]
    var foodWarnings: [String]
    var trainingWarnings: [String]
    var nextDayFocus: [String]

    init(
        summary: String = "",
        importantNotes: [String] = [],
        foodWarnings: [String] = [],
        trainingWarnings: [String] = [],
        nextDayFocus: [String] = []
    ) {
        self.summary = summary
        self.importantNotes = importantNotes
        self.foodWarnings = foodWarnings
        self.trainingWarnings = trainingWarnings
        self.nextDayFocus = nextDayFocus
    }

    var isEmpty: Bool {
        summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && importantNotes.isEmpty
            && foodWarnings.isEmpty
            && trainingWarnings.isEmpty
            && nextDayFocus.isEmpty
    }

    enum CodingKeys: String, CodingKey {
        case summary
        case importantNotes
        case foodWarnings
        case trainingWarnings
        case nextDayFocus
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        summary = try container.decodeIfPresent(String.self, forKey: .summary) ?? ""
        importantNotes = try container.decodeIfPresent([String].self, forKey: .importantNotes) ?? []
        foodWarnings = try container.decodeIfPresent([String].self, forKey: .foodWarnings) ?? []
        trainingWarnings = try container.decodeIfPresent([String].self, forKey: .trainingWarnings) ?? []
        nextDayFocus = try container.decodeIfPresent([String].self, forKey: .nextDayFocus) ?? []
    }
}

struct CoachDailyCarryoverSnapshot: Codable, Hashable {
    var date: Date
    var summary: String
    var importantNotes: [String]
    var foodWarnings: [String]
    var trainingWarnings: [String]
    var nextDayFocus: [String]
}

/// 某一天的「按天分组」饮食：当天逐餐 + 当天合计 + 当天体重/睡眠/喝水。
/// 用来替代扁平的 recentMeals，让教练永远清楚「哪顿属于哪天」。
struct CoachDayDiet: Codable, Hashable {
    var date: Date
    var meals: [CoachMealSnapshot]
    var intakeCalories: Double
    var proteinGrams: Double
    var carbsGrams: Double
    var fatGrams: Double
    var weightKg: Double?
    var sleepHours: Double?
    var waterMl: Double?
}

struct CoachContextSnapshot: Codable {
    var requestedAt: Date
    var profile: CoachProfileSnapshot
    var today: CoachDailyMetrics
    var todayMeals: [CoachMealSnapshot]
    var todayExercises: [CoachExerciseSnapshot]
    var recentMeals: [CoachMealSnapshot]
    var recentExercises: [CoachExerciseSnapshot]
    /// 近 7–14 天「按天分组」的逐餐饮食（今天不含在内，今天看 todayMeals）。可选以兼容旧消息快照。
    var recentDailyDiets: [CoachDayDiet]? = nil
    var recent7Days: [CoachDaySummarySnapshot]
    var recent30Days: [CoachDaySummarySnapshot]
    var foodOptions: [FoodOptionSnapshot]
    var trainingPlans: [CoachTrainingPlanSnapshot]
    var memory: CoachMemorySnapshot?
    var recentCarryovers: [CoachDailyCarryoverSnapshot]
    var trainingPerformance: [CoachTrainingSessionSnapshot]? = nil
    var safetyAlerts: [String]? = nil
    var analysis: FatLossAnalysis
    var dataQualityNotes: [String]
}

@Model
final class CoachChatSession {
    var id: UUID
    var title: String
    var dayDate: Date = Calendar.current.startOfDay(for: .now)
    var lastMessageText: String
    var isArchived: Bool = false
    var carryoverEnabled: Bool = true
    var carryoverJSON: String = ""
    var compressedAt: Date? = nil
    /// 日内滚动压缩：把同一天较早的对话压成「今日早些时候要点」，避免长对话超窗丢精度。新增字段带默认值。
    var intradayDigest: String = ""
    /// intradayDigest 已覆盖的（今日）消息条数。
    var intradayDigestCount: Int = 0
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        title: String = "AI 教练",
        dayDate: Date = Calendar.current.startOfDay(for: .now),
        lastMessageText: String = "",
        isArchived: Bool = false,
        carryoverEnabled: Bool = true,
        carryover: CoachDailyCarryover? = nil,
        compressedAt: Date? = nil,
        intradayDigest: String = "",
        intradayDigestCount: Int = 0,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.title = title
        self.dayDate = Calendar.current.startOfDay(for: dayDate)
        self.lastMessageText = lastMessageText
        self.isArchived = isArchived
        self.carryoverEnabled = carryoverEnabled
        self.carryoverJSON = Self.encode(carryover)
        self.compressedAt = compressedAt
        self.intradayDigest = intradayDigest
        self.intradayDigestCount = intradayDigestCount
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var carryover: CoachDailyCarryover? {
        get { Self.decode(CoachDailyCarryover.self, from: carryoverJSON) }
        set { carryoverJSON = Self.encode(newValue) }
    }

    var carryoverSnapshot: CoachDailyCarryoverSnapshot? {
        guard carryoverEnabled, let carryover, !carryover.isEmpty else { return nil }
        return CoachDailyCarryoverSnapshot(
            date: Calendar.current.startOfDay(for: dayDate),
            summary: carryover.summary,
            importantNotes: carryover.importantNotes,
            foodWarnings: carryover.foodWarnings,
            trainingWarnings: carryover.trainingWarnings,
            nextDayFocus: carryover.nextDayFocus
        )
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
final class CoachChatMessage {
    var id: UUID
    var sessionID: UUID
    var roleRaw: String
    var text: String
    var scenarioRaw: String
    var riskLevel: String
    var contextJSON: String
    var suggestedRecordsJSON: String
    /// 已自动写入的记录（饮食/运动 create），用于内联「✓ 已记录 · 撤销/编辑」。新增字段带默认值便于轻量迁移。
    var appliedRecordsJSON: String = ""
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

    var appliedRecords: [AppliedRecordRef] {
        get { Self.decode([AppliedRecordRef].self, from: appliedRecordsJSON) ?? [] }
        set { appliedRecordsJSON = Self.encode(newValue) }
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

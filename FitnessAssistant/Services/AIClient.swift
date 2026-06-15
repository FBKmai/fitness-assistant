import Foundation
import Combine

enum AIClientError: LocalizedError {
    case missingAPIKey
    case invalidBaseURL
    case emptyResponse
    case invalidResponse(Int, String)
    case invalidJSON(String)
    case transport(String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            "请先在设置中填写 API Key"
        case .invalidBaseURL:
            "AI Base URL 无效"
        case .emptyResponse:
            "AI 没有返回内容"
        case .invalidResponse(let status, let body):
            "AI 请求失败：HTTP \(status) \(body)"
        case .invalidJSON(let content):
            "AI 返回的 JSON 无法解析：\(content)"
        case .transport(let message):
            message
        }
    }
}

final class AIClient: ObservableObject {
    private let keychain: KeychainStore
    private let session: URLSession

    init(keychain: KeychainStore = .shared, session: URLSession = .shared) {
        self.keychain = keychain
        self.session = session
    }

    func estimateMeal(text: String, imageData: Data?, settings: AISettings, bodyContext: String? = nil) async throws -> MealEstimate {
        try await estimateMeal(text: text, imageDataList: imageData.map { [$0] } ?? [], settings: settings, bodyContext: bodyContext)
    }

    func estimateMeal(text: String, imageDataList: [Data], settings: AISettings, bodyContext: String? = nil) async throws -> MealEstimate {
        let systemPrompt = """
        你是一个营养记录助手。根据用户的文字或餐食照片估算热量和三大营养素。
        只返回 JSON，不要使用 markdown。所有数值使用 kcal 或克。
        JSON 格式：
        {
          "items": [{"name": "食物名", "calories": 0, "proteinGrams": 0, "carbsGrams": 0, "fatGrams": 0, "note": "估算依据"}],
          "totalCalories": 0,
          "proteinGrams": 0,
          "carbsGrams": 0,
          "fatGrams": 0,
          "confidence": 0.0,
          "summary": "一句中文总结"
        }
        """

        let baseText = text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "请根据图片估算这餐的热量。"
            : text
        // 附上身体资料，辅助模型判断份量（作用有限，仅供参考）。
        let userText = bodyContext.map { "\(baseText)\n\n（用户身体资料，仅供份量判断参考：\($0)）" } ?? baseText

        let userContent: ChatContent
        if imageDataList.isEmpty {
            userContent = .text(userText)
        } else {
            var parts: [ChatContentPart] = [.text(userText)]
            parts += imageDataList.map { imageData in
                .imageURL("data:image/jpeg;base64,\(imageData.base64EncodedString())")
            }
            userContent = .parts(parts)
        }

        // 带图走视觉模型（MiMo），纯文字走文字模型（DeepSeek），各用各自的 Base URL 和 Key。
        let isVision = !imageDataList.isEmpty
        let content = try await complete(
            model: isVision ? settings.visionModelName : settings.modelName,
            baseURL: isVision ? settings.visionBaseURL : settings.baseURL,
            apiKeychainKey: isVision ? settings.visionAPIKeychainKey : settings.apiKeychainKey,
            messages: [
                ChatMessage(role: "system", content: .text(systemPrompt)),
                ChatMessage(role: "user", content: userContent)
            ],
            temperature: 0.2,
            jsonMode: true,
            maxTokens: 4000
        )

        return try AIResponseParser.decodeJSONObject(MealEstimate.self, from: content)
    }

    func estimateFoodOption(
        name: String,
        kind: FoodOptionKind,
        sourceDescription: String,
        imageDataList: [Data],
        settings: AISettings,
        bodyContext: String? = nil
    ) async throws -> FoodOptionEstimate {
        let systemPrompt = """
        你是一个中文营养标签和餐食图片识别助手。用户正在建立一个常吃食物选项卡，类型可能是单品或套餐。
        请根据食物照片、营养成分表照片、包装文字或用户补充描述，估算固定份量的热量、三大营养素、每个组成食物的大概分量，并给出减脂推荐指数。
        套餐必须拆成多个定量组成食物；单品也要给出一条 components。
        推荐指数范围 0-100，越适合减脂期日常选择分数越高。判断时考虑热量密度、蛋白质、脂肪、精制碳水、饱腹感和可持续性。
        如果图片或营养表不清楚，要在 summary 或 recommendationReason 里说明不确定性，并降低 confidence。
        只返回 JSON，不要使用 markdown。所有数值使用 kcal 或克。
        JSON 格式：
        {
          "name": "选项卡名称",
          "kind": "single 或 combo",
          "portionDescription": "总份量描述，例如 1 份约 350g",
          "components": [
            {"name": "食物名", "portionDescription": "约 100g", "calories": 0, "proteinGrams": 0, "carbsGrams": 0, "fatGrams": 0, "note": "估算依据"}
          ],
          "totalCalories": 0,
          "proteinGrams": 0,
          "carbsGrams": 0,
          "fatGrams": 0,
          "confidence": 0.0,
          "recommendationScore": 0,
          "recommendationReason": "为什么推荐或不推荐",
          "summary": "一句中文总结"
        }
        """

        let title = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let source = sourceDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        let baseText = """
        选项卡类型：\(kind.title)（raw=\(kind.rawValue)）
        \(title.isEmpty ? "" : "用户填写名称：\(title)")
        \(source.isEmpty ? "请根据上传图片或营养表估算。" : "用户补充描述：\(source)")
        """
        let userText = bodyContext.map { "\(baseText)\n\n（用户身体资料，仅供推荐指数判断参考：\($0)）" } ?? baseText

        let userContent: ChatContent
        if imageDataList.isEmpty {
            userContent = .text(userText)
        } else {
            var parts: [ChatContentPart] = [.text(userText)]
            parts += imageDataList.map { imageData in
                .imageURL("data:image/jpeg;base64,\(imageData.base64EncodedString())")
            }
            userContent = .parts(parts)
        }

        let isVision = !imageDataList.isEmpty
        let content = try await complete(
            model: isVision ? settings.visionModelName : settings.modelName,
            baseURL: isVision ? settings.visionBaseURL : settings.baseURL,
            apiKeychainKey: isVision ? settings.visionAPIKeychainKey : settings.apiKeychainKey,
            messages: [
                ChatMessage(role: "system", content: .text(systemPrompt)),
                ChatMessage(role: "user", content: userContent)
            ],
            temperature: 0.2,
            jsonMode: true,
            maxTokens: 4000
        )

        return try AIResponseParser.decodeJSONObject(FoodOptionEstimate.self, from: content)
    }

    func generateTrainingPlan(input: TrainingPlanInput, settings: AISettings) async throws -> TrainingPlanResult {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let inputData = try encoder.encode(input)
        let inputJSON = String(data: inputData, encoding: .utf8) ?? "{}"

        let systemPrompt = """
        你是世界顶级的健身与运动学教练。下面的 JSON 是用户的身体数据（性别、年龄、身高、体重、体脂率、BMI、基础代谢 bmr、目标 goal、近 7 天训练次数 recentWeeklyWorkouts、日均步数 avgDailySteps）以及手填的训练与饮食信息（活动水平 activityLevel、每周训练天数 trainingDaysPerWeek、训练经验 trainingExperience、训练偏好 trainingTypePreference、忌口/饮食偏好 dietPreference、目标体重 targetWeightKg、期望周期 targetWeeks、睡眠 sleepHours、补充说明 extraNote）。
        请用以下方法论制定一份个性化的减脂或增肌方案：
        1. 算 BMR：默认 Mifflin-St Jeor；若提供体脂率，用 Katch-McArdle（基于去脂体重）并与前者取一个保守中间值。
        2. 算 TDEE = BMR × 活动系数（结合 activityLevel 与训练频率）。
        3. 定热量与三大营养素：减脂在 TDEE 基础上制造 15%~25% 缺口（约 300~500 kcal/天）；增肌制造 10%~20% 盈余（约 200~400 kcal/天）；蛋白质 1.6~2.2 g/kg（减脂期取上限保肌），脂肪 0.6~1.0 g/kg 且不低于总热量 20%，碳水用剩余热量补足。每日摄入不要压到 BMR 以下。
        4. 评估目标可行性：合理减脂速度每周 0.5%~1% 体重，增肌更慢。若用户的目标体重/周期不现实或不健康，要在 realisticGoalNote 里直说，并给出现实的预期。
        5. 训练安排：按 trainingDaysPerWeek 给出每周 7 天的安排（练什么/休息），减脂期强调大重量保肌 + 步数（NEAT），避免过量 HIIT 影响恢复；每个训练日给出具体动作（复合动作打头）、组数、次数。
        6. 饮食结构：给出推荐食材与可落地的餐次示例（尊重 dietPreference 的忌口），蔬菜管够。
        7. 监测与调整：说明如何用一周体重均值校准并微调。
        建议要现实、可执行、个性化，不提供医疗诊断，不建议极端节食。
        只返回 JSON，不要使用 markdown。所有数值使用 kcal 或克。
        JSON 格式：
        {
          "realisticGoalNote": "目标可行性评估，必要时纠正不现实的预期",
          "bmr": 0,
          "tdee": 0,
          "dailyCalories": 0,
          "proteinGrams": 0,
          "carbsGrams": 0,
          "fatGrams": 0,
          "macroNote": "三大营养素分配的说明",
          "weeklySchedule": [
            {"dayLabel": "周一", "focus": "力量 A", "exercises": [{"name": "深蹲", "sets": "3~4 组", "reps": "6~12 次", "note": "复合动作打头"}], "cardio": "练后 15min 坡度快走", "note": ""}
          ],
          "trainingPrinciples": "训练要点与原则",
          "dietStructure": "推荐食材与饮食结构",
          "mealExamples": [
            {"title": "工作日早餐", "content": "水煮蛋 2~3 个 + 红薯 150g", "calories": 0}
          ],
          "monitoringAdvice": "如何监测与调整",
          "summary": "一句话总结这份计划的核心"
        }
        """

        let content = try await complete(
            model: settings.modelName,
            baseURL: settings.baseURL,
            apiKeychainKey: settings.apiKeychainKey,
            messages: [
                ChatMessage(role: "system", content: .text(systemPrompt)),
                ChatMessage(role: "user", content: .text(inputJSON))
            ],
            temperature: 0.4,
            jsonMode: true,
            maxTokens: 3500
        )

        return try AIResponseParser.decodeJSONObject(TrainingPlanResult.self, from: content)
    }

    func generateDailyAdvice(snapshot: DailySnapshot, settings: AISettings) async throws -> DailyAdvice {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let snapshotData = try encoder.encode(snapshot)
        let snapshotJSON = String(data: snapshotData, encoding: .utf8) ?? "{}"

        let systemPrompt = """
        你是一个中文健身饮食监督助手。下面的 JSON 包含用户的身体数据（身高、体重、体脂率、BMI、性别、年龄、基础代谢 bmr）、
        当天摄入/消耗/热量差、三大营养素合计、每餐与运动记录、近 7 天趋势 recentDays（每天的热量缺口和体重），
        以及 analysis 字段中的本地规则化减脂判断（缺口范围、蛋白目标、风险提醒和数据质量）。
        请综合这些数据为用户生成第二天建议：
        1. 结合身高、体重、体脂率、BMI、年龄、性别与 bmr 判断当天摄入是否过低或过高；
        2. 结合三大营养素点评蛋白质、碳水、脂肪是否合理（减脂期重点关注蛋白质是否充足）；
        3. 结合 recentDays 趋势说明最近进展（热量缺口是否稳定、体重变化方向）；若数据不足则说明无法判断趋势。
        4. 优先尊重 analysis 的风险和数据质量判断，不要建议极端节食或用过量运动弥补饮食。
        5. 热量差公式是：基础代谢 bmr + 活动消耗 activeCalories - 摄入 intakeCalories；targetDailyDeficitKcal 只用于判断是否达标，不参与热量差计算。
        6. todayMealAdvice 要包含今天剩余早餐/午餐/晚餐安排建议，snackAdvice 要单独给零嘴建议。
        目标是减脂，建议要现实、可执行、个性化，不提供医疗诊断。
        只返回 JSON，不要使用 markdown。
        JSON 格式：
        {
          "summary": "当天情况总结",
          "todayMealAdvice": "今天剩余三餐或下一餐怎么安排",
          "snackAdvice": "今天零嘴或加餐建议",
          "tomorrowDietAdvice": "第二天饮食建议",
          "tomorrowExerciseAdvice": "第二天运动建议",
          "recoveryAdvice": "恢复和注意事项"
        }
        """

        let content = try await complete(
            model: settings.modelName,
            baseURL: settings.baseURL,
            apiKeychainKey: settings.apiKeychainKey,
            messages: [
                ChatMessage(role: "system", content: .text(systemPrompt)),
                ChatMessage(role: "user", content: .text(snapshotJSON))
            ],
            temperature: 0.4,
            jsonMode: true,
            maxTokens: 2000
        )

        return try AIResponseParser.decodeJSONObject(DailyAdvice.self, from: content)
    }

    func generateMealAdvice(snapshot: MealAdviceSnapshot, settings: AISettings) async throws -> MealAdviceResponse {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let snapshotData = try encoder.encode(snapshot)
        let snapshotJSON = String(data: snapshotData, encoding: .utf8) ?? "{}"

        let systemPrompt = """
        你是一个中文减脂饮食教练。用户刚保存了一条饮食记录，JSON 中包含这一顿的餐别、吃饭时间、热量和三大营养素，
        以及今天所有已记录饮食、今日热量差、目标缺口和本地规则化 analysis。
        请评价这一顿是否适合减脂，并给出下一顿怎么吃的建议。
        要具体、直接、可执行；不要空泛鼓励，不提供医疗诊断，不建议极端节食。
        只返回 JSON，不要使用 markdown。
        JSON 格式：
        {
          "mealReview": "对刚保存这顿的评价",
          "nextMealAdvice": "下一顿具体怎么吃",
          "snackAdvice": "零嘴或加餐建议",
          "caution": "风险、记录误差或需要补充的数据"
        }
        """

        let content = try await complete(
            model: settings.modelName,
            baseURL: settings.baseURL,
            apiKeychainKey: settings.apiKeychainKey,
            messages: [
                ChatMessage(role: "system", content: .text(systemPrompt)),
                ChatMessage(role: "user", content: .text(snapshotJSON))
            ],
            temperature: 0.4,
            jsonMode: true,
            maxTokens: 1800
        )

        return try AIResponseParser.decodeJSONObject(MealAdviceResponse.self, from: content)
    }

    func generateDietCoachReply(context: DietCoachSnapshot, history: [DietCoachTurn], settings: AISettings) async throws -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let contextData = try encoder.encode(context)
        let contextJSON = String(data: contextData, encoding: .utf8) ?? "{}"

        let timeFormatter = DateFormatter()
        timeFormatter.locale = Locale(identifier: "zh_CN")
        timeFormatter.dateFormat = "yyyy年M月d日 EEEE HH:mm"
        let nowText = timeFormatter.string(from: context.requestedAt)

        let systemPrompt = """
        你是一个中文减脂饮食顾问。用户会问“现在这一餐怎么吃”一类问题，并可能继续追问来调整这一餐。
        当前时间是【\(nowText)】，请据此判断现在大概是哪一餐（早/午/晚/加餐）。
        下面的 JSON（context）包含：用户身体资料（含体重、体脂率、BMI，如 Apple 健康当天有数据）、今日已吃 todayMeals、今日运动消耗 todayWorkouts、最近几天饮食 recentMeals、最近几天消耗 recentWorkouts、近 7 天趋势 recentDays、用户勾选的候选食物选项卡 selectedFoodOptions、以及本地规则化判断 analysis。
        请结合今日已吃、最近饮食与最近消耗，判断蛋白质是否够、热量缺口是否过大或过小，回答用户“现在这一餐”具体怎么吃。
        要具体到可执行的食物组合和份量范围，例如“1 份掌心大小鸡胸/鱼/豆腐 + 半碗到一碗米饭 + 2 拳蔬菜”。
        如果 selectedFoodOptions 不为空，请判断这些候选这一餐是否合理，指出如何调整份量或替换搭配。
        只回答“这一餐”怎么吃：不要给运动前后补给安排，不要给今天剩余整天的计划，不要长篇大论。
        如果用户接着追问（例如想换成面食、想少吃点），基于之前的对话和上下文调整这一餐的建议。
        不提供医疗诊断，不建议极端节食。若数据不足，简要说明不确定性即可。
        用自然中文回答，不要返回 JSON，也不要使用 markdown 代码块。

        上下文数据（context）：
        \(contextJSON)
        """

        var messages: [ChatMessage] = [ChatMessage(role: "system", content: .text(systemPrompt))]
        messages += history.map { turn in
            ChatMessage(role: turn.role.rawValue, content: .text(turn.text))
        }

        let content = try await complete(
            model: settings.modelName,
            baseURL: settings.baseURL,
            apiKeychainKey: settings.apiKeychainKey,
            messages: messages,
            temperature: 0.5,
            jsonMode: false,
            maxTokens: 1200
        )

        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func generateCoachReply(
        context: CoachContextSnapshot,
        recentMessages: [CoachChatMessage],
        imageDataList: [Data] = [],
        settings: AISettings
    ) async throws -> CoachReplyResult {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let contextData = try encoder.encode(context)
        let contextJSON = String(data: contextData, encoding: .utf8) ?? "{}"

        let timeFormatter = DateFormatter()
        timeFormatter.locale = Locale(identifier: "zh_CN")
        timeFormatter.dateFormat = "yyyy年M月d日 EEEE HH:mm"
        let nowText = timeFormatter.string(from: context.requestedAt)

        let systemPrompt = """
        你是用户的长期中文健身减脂 AI 教练，不是一次性问答机器人。你必须综合完整上下文给出可执行建议，风格直接、具体、像一个持续跟进的教练。
        当前时间是【\(nowText)】。下面的 context JSON 包含用户档案、今日状态、近 7/30 天趋势、饮食、训练、食物选项、训练计划和长期教练记忆。

        你需要覆盖这些场景：
        1. 饭前：判断这一餐怎么吃、吃多少、是否需要补蛋白/碳水/蔬菜。
        2. 饭后：评价刚吃的东西、估算影响、给下一餐或明天的补救方向。
        3. 训练前：结合睡眠、饥饿、感冒/疲劳、当前时间和训练安排，判断是否能练、练前吃什么。
        4. 训练后：结合心率/消耗/运动类型，给练后餐、补水和恢复建议。
        5. 食物判断：给红灯/黄灯/绿灯，解释热量、蛋白、脂肪、碳水、钠、水肿和饱腹感。
        6. 外卖点单：给可直接照抄的点单方案和必须避开的配料/酱料。
        7. 每日/每周复盘：算热量缺口、蛋白是否达标、体重波动是否是水分、是否接近平台期。
        8. 恢复安全：遇到感冒、青鼻涕、睡眠不足、过度高心率或药物问题时保守处理，不提供医疗诊断，不建议带病高强度训练。

        重要规则：
        - 不要极端节食，不要建议用过量运动抵消饮食。
        - 体重短期上涨时优先解释水分、钠、糖原、食物残渣和炎症锁水，不制造焦虑。
        - 建议必须具体到食物组合、份量范围、训练强度或下一步动作。
        - 当用户问“吃什么/这一餐怎么吃/现在怎么吃/点什么外卖”时：context.foodOptions 里的食物选项只是参考，可以从中挑，也可以另行推荐任何更合适的食物或搭配，不要局限于这些选项。
        - 给“吃什么”建议时，必须结合今日和最近的活动消耗（today.activeCalories、recentExercises）与热量缺口（today.calorieDeficit、recent7Days 趋势）来决定份量和热量，并在 replyText 里说明你是基于哪些活动/热量数据给的。
        - 推荐具体食物或搭配时，把每个推荐放进 suggestedRecords（kind=meal，填 textDescription 与 totalCalories/proteinGrams/carbsGrams/fatGrams），方便用户一键采纳保存为饮食记录；这既适用于“刚吃了”的记录，也适用于“建议吃”的推荐。
        - 如果用户明显是在记录“刚练完/今早体重/睡眠/喝水”，在 suggestedRecords 里给出对应的可保存记录。
        - 只有当信息稳定、未来也有用时，才写 memoryPatch，比如常吃食物、忌口、训练偏好、健康注意点。
        - 只返回 JSON，不要使用 markdown。

        JSON 格式：
        {
          "replyText": "自然中文回复正文",
          "scenario": "mealBefore | mealAfter | workoutBefore | workoutAfter | dailyReview | weeklyReview | foodDecision | weightTrend | recoverySafety | general",
          "riskLevel": "normal | caution | high",
          "suggestedRecords": [
            {
              "kind": "meal | exercise | checkIn",
              "title": "记录标题",
              "note": "记录说明",
              "date": "ISO8601 时间，可省略",
              "mealTypeRaw": "breakfast | lunch | dinner | snack | other",
              "textDescription": "餐食描述",
              "totalCalories": 0,
              "proteinGrams": 0,
              "carbsGrams": 0,
              "fatGrams": 0,
              "workoutType": "运动类型",
              "durationMinutes": 0,
              "activeCalories": 0,
              "steps": 0,
              "weightKg": 0,
              "bodyFatPercentage": 0,
              "bodyMassIndex": 0,
              "sleepHours": 0,
              "waterMl": 0,
              "hungerLevel": 0,
              "mood": "心情",
              "symptoms": "身体不适"
            }
          ],
          "memoryPatch": {
            "profileSummary": "可选，长期画像摘要",
            "foodPreferences": ["常吃或偏好的食物"],
            "avoidances": ["忌口或应少碰的食物"],
            "trainingPreferences": ["训练偏好"],
            "healthNotes": ["长期健康/恢复注意点"],
            "rules": ["长期遵循的教练规则"]
          }
        }

        context:
        \(contextJSON)
        """

        let sortedMessages = Array(recentMessages
            .sorted { $0.createdAt < $1.createdAt }
            .suffix(16))
        var messages: [ChatMessage] = [ChatMessage(role: "system", content: .text(systemPrompt))]
        for message in sortedMessages {
            if !imageDataList.isEmpty, message.id == sortedMessages.last?.id, message.role == .user {
                var parts = [ChatContentPart.text(message.text)]
                parts += imageDataList.map { imageData in
                    ChatContentPart.imageURL("data:image/jpeg;base64,\(imageData.base64EncodedString())")
                }
                messages.append(ChatMessage(role: message.role.rawValue, content: .parts(parts)))
            } else {
                messages.append(ChatMessage(role: message.role.rawValue, content: .text(message.text)))
            }
        }

        let isVision = !imageDataList.isEmpty

        let content = try await complete(
            model: isVision ? settings.visionModelName : settings.modelName,
            baseURL: isVision ? settings.visionBaseURL : settings.baseURL,
            apiKeychainKey: isVision ? settings.visionAPIKeychainKey : settings.apiKeychainKey,
            messages: messages,
            temperature: 0.45,
            jsonMode: true,
            maxTokens: 2600
        )

        var result = try AIResponseParser.decodeJSONObject(CoachReplyResult.self, from: content)
        if result.replyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            result.replyText = "AI 返回了空回复，请补充问题后重试。"
        }
        return result
    }

    func testConnection(settings: AISettings) async throws -> String {
        let content = try await complete(
            model: settings.modelName,
            baseURL: settings.baseURL,
            apiKeychainKey: settings.apiKeychainKey,
            messages: [
                ChatMessage(role: "system", content: .text("You are a connectivity test endpoint. Reply with exactly OK.")),
                ChatMessage(role: "user", content: .text("Reply OK."))
            ],
            temperature: 0,
            jsonMode: false,
            maxTokens: 32,
            timeout: 30
        )
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "OK" : trimmed
    }

    /// 详细诊断：依次验证「文字模型 · DeepSeek」和「视觉模型 · MiMo」两套配置
    /// （二者 Base URL / Key / 模型各自独立），把每一步实时回调出来，不抛异常。
    @MainActor
    func diagnose(settings: AISettings, onLine: @escaping (String) -> Void) async {
        onLine("【文字模型 · DeepSeek】")
        await diagnoseEndpoint(
            baseURL: settings.baseURL,
            model: settings.modelName,
            apiKeychainKey: settings.apiKeychainKey,
            onLine: onLine
        )
        onLine("")
        onLine("【视觉模型 · MiMo】")
        await diagnoseEndpoint(
            baseURL: settings.visionBaseURL,
            model: settings.visionModelName,
            apiKeychainKey: settings.visionAPIKeychainKey,
            onLine: onLine
        )
    }

    /// 对单个 OpenAI 兼容端点做一次最小连通性请求，每一步通过 onLine 回调。
    @MainActor
    private func diagnoseEndpoint(
        baseURL: String,
        model: String,
        apiKeychainKey: String,
        onLine: @escaping (String) -> Void
    ) async {
        onLine("Base URL：\(baseURL)")
        onLine("模型：\(model)")

        let apiKey: String?
        do {
            apiKey = try keychain.read(apiKeychainKey)
        } catch {
            onLine("❌ 读取 Keychain 失败：\(error.localizedDescription)")
            return
        }
        guard let apiKey, !apiKey.isEmpty else {
            onLine("❌ Keychain（\(apiKeychainKey)）中没有 API Key。请在上方输入后先点「保存」，或重新输入再测。")
            return
        }
        onLine("API Key：\(apiKey)（长度 \(apiKey.count)）")

        guard let url = chatCompletionsURL(from: baseURL) else {
            onLine("❌ Base URL 无效，无法拼接请求地址。")
            return
        }
        onLine("请求地址：\(url.absoluteString)")

        let isMiMo = baseURL.localizedCaseInsensitiveContains("xiaomimimo")
        let disableThinking = baseURL.localizedCaseInsensitiveContains("deepseek")
        onLine("关闭思考模式：\(disableThinking ? "是" : "否")")

        let requestBody = ChatRequest(
            model: model,
            messages: [
                ChatMessage(role: "system", content: .text("You are a connectivity test endpoint. Reply with exactly OK.")),
                ChatMessage(role: "user", content: .text("Reply OK."))
            ],
            temperature: 0,
            responseFormat: nil,
            maxTokens: isMiMo ? nil : 64,
            maxCompletionTokens: isMiMo ? 64 : nil,
            thinking: disableThinking ? ThinkingConfig(type: "disabled") : nil
        )

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue(apiKey, forHTTPHeaderField: "api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        do {
            let body = try JSONEncoder().encode(requestBody)
            request.httpBody = body
            onLine("请求体：\(String(data: body, encoding: .utf8) ?? "(编码失败)")")
        } catch {
            onLine("❌ 请求体编码失败：\(error.localizedDescription)")
            return
        }

        onLine("⏳ 正在发送请求（超时 30 秒）…")
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            let nsError = error as NSError
            onLine("❌ 网络请求失败：\(Self.transportMessage(for: error))")
            onLine("   错误详情：domain=\(nsError.domain) code=\(nsError.code)")
            return
        }

        if let http = response as? HTTPURLResponse {
            onLine("✅ 已收到响应，HTTP 状态码：\(http.statusCode)")
        } else {
            onLine("⚠️ 收到响应，但不是标准 HTTP 响应。")
        }
        let bodyText = String(data: data, encoding: .utf8) ?? "(返回内容无法解码为 UTF-8)"
        onLine("原始返回：\(bodyText)")
    }

    private func complete(
        model: String,
        baseURL: String,
        apiKeychainKey: String,
        messages: [ChatMessage],
        temperature: Double,
        jsonMode: Bool,
        maxTokens: Int,
        timeout: TimeInterval = 120
    ) async throws -> String {
        guard let apiKey = try keychain.read(apiKeychainKey), !apiKey.isEmpty else {
            throw AIClientError.missingAPIKey
        }

        guard let url = chatCompletionsURL(from: baseURL) else {
            throw AIClientError.invalidBaseURL
        }

        // DeepSeek 的 deepseek-v4 系列默认开启 thinking(思考)模式：会先生成大段 reasoning_content
        // 再产出正文，导致响应缓慢容易超时，仅当 Base URL 指向 DeepSeek 时显式关闭。
        let disableThinking = baseURL.localizedCaseInsensitiveContains("deepseek")
        // 小米 MiMo 用 max_completion_tokens 而非 max_tokens。
        let isMiMo = baseURL.localizedCaseInsensitiveContains("xiaomimimo")
        let requestBody = ChatRequest(
            model: model,
            messages: messages,
            temperature: temperature,
            responseFormat: jsonMode ? ChatResponseFormat(type: "json_object") : nil,
            maxTokens: isMiMo ? nil : maxTokens,
            maxCompletionTokens: isMiMo ? maxTokens : nil,
            thinking: disableThinking ? ThinkingConfig(type: "disabled") : nil
        )
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        // Authorization 适配 DeepSeek/OpenAI；api-key 适配小米 MiMo。两者同时下发，互不影响。
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue(apiKey, forHTTPHeaderField: "api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(requestBody)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw AIClientError.transport(Self.transportMessage(for: error))
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIClientError.emptyResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw AIClientError.invalidResponse(httpResponse.statusCode, body)
        }

        let decoded = try JSONDecoder().decode(ChatResponse.self, from: data)
        let message = decoded.choices.first?.message
        if let content = message?.content, !content.isEmpty {
            return content
        }
        // 正文为空但有思考内容：模型仍在思考模式且回复被 token 上限截断在推理阶段。
        if let reasoning = message?.reasoningContent, !reasoning.isEmpty {
            throw AIClientError.transport("AI 只返回了思考内容、没有正式回答，通常是模型处于思考(thinking)模式且回复被 token 上限截断，请调大 token 上限或确认模型后重试。")
        }
        throw AIClientError.emptyResponse
    }

    private func chatCompletionsURL(from baseURL: String) -> URL? {
        var trimmedBaseURL = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedBaseURL.localizedCaseInsensitiveContains("://") {
            trimmedBaseURL = "https://\(trimmedBaseURL)"
        }
        while trimmedBaseURL.hasSuffix("/") {
            trimmedBaseURL.removeLast()
        }
        if trimmedBaseURL.hasSuffix("/chat/completions") {
            return URL(string: trimmedBaseURL)
        }
        return URL(string: "\(trimmedBaseURL)/chat/completions")
    }

    private static func transportMessage(for error: Error) -> String {
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            switch nsError.code {
            case NSURLErrorSecureConnectionFailed,
                NSURLErrorServerCertificateHasBadDate,
                NSURLErrorServerCertificateUntrusted,
                NSURLErrorServerCertificateHasUnknownRoot,
                NSURLErrorServerCertificateNotYetValid,
                NSURLErrorClientCertificateRejected,
                NSURLErrorClientCertificateRequired:
                return "TLS错误导致安全连接失败。请确认 Base URL 正确、不要带空格，并检查手机时间和网络代理。"
            case NSURLErrorCannotFindHost:
                return "无法找到 AI 服务域名。请检查 Base URL，例如 DeepSeek 用 https://api.deepseek.com、MiMo 用 https://api.xiaomimimo.com/v1。"
            case NSURLErrorCannotConnectToHost, NSURLErrorNetworkConnectionLost, NSURLErrorNotConnectedToInternet:
                return "无法连接 AI 服务。请检查网络、代理或稍后重试。"
            case NSURLErrorTimedOut:
                return "AI 请求超时。模型推理较慢或网络不稳定时可稍后重试，也可检查代理设置。"
            default:
                break
            }
        }
        return error.localizedDescription
    }
}

private struct ChatRequest: Encodable {
    var model: String
    var messages: [ChatMessage]
    var temperature: Double
    var responseFormat: ChatResponseFormat?
    var maxTokens: Int?
    var maxCompletionTokens: Int?
    var thinking: ThinkingConfig?

    enum CodingKeys: String, CodingKey {
        case model
        case messages
        case temperature
        case responseFormat = "response_format"
        case maxTokens = "max_tokens"
        case maxCompletionTokens = "max_completion_tokens"
        case thinking
    }
}

private struct ChatResponseFormat: Encodable {
    var type: String
}

// DeepSeek 思考模式开关：{"type": "disabled"} 关闭思考，{"type": "enabled"} 开启。
private struct ThinkingConfig: Encodable {
    var type: String
}

private struct ChatMessage: Encodable {
    var role: String
    var content: ChatContent
}

private enum ChatContent: Encodable {
    case text(String)
    case parts([ChatContentPart])

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .text(let text):
            try container.encode(text)
        case .parts(let parts):
            try container.encode(parts)
        }
    }
}

private struct ChatContentPart: Encodable {
    var type: String
    var text: String?
    var imageURL: ImageURL?

    enum CodingKeys: String, CodingKey {
        case type
        case text
        case imageURL = "image_url"
    }

    static func text(_ value: String) -> ChatContentPart {
        ChatContentPart(type: "text", text: value, imageURL: nil)
    }

    static func imageURL(_ value: String) -> ChatContentPart {
        ChatContentPart(type: "image_url", text: nil, imageURL: ImageURL(url: value))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        try container.encodeIfPresent(text, forKey: .text)
        try container.encodeIfPresent(imageURL, forKey: .imageURL)
    }
}

private struct ImageURL: Encodable {
    var url: String
}

private struct ChatResponse: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable {
            var content: String?
            var reasoningContent: String?

            enum CodingKeys: String, CodingKey {
                case content
                case reasoningContent = "reasoning_content"
            }
        }

        var message: Message
    }

    var choices: [Choice]
}

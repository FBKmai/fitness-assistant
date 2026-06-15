import PhotosUI
import SwiftData
import SwiftUI

struct CoachHomeView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var aiClient: AIClient

    @Query private var profiles: [UserProfile]
    @Query private var settings: [AISettings]
    @Query(sort: \MealEntry.date, order: .reverse) private var meals: [MealEntry]
    @Query(sort: \FoodOption.updatedAt, order: .reverse) private var foodOptions: [FoodOption]
    @Query(sort: \ExerciseEntry.date, order: .reverse) private var exercises: [ExerciseEntry]
    @Query(sort: \DailySummary.date, order: .reverse) private var summaries: [DailySummary]
    @Query(sort: \TrainingPlan.updatedAt, order: .reverse) private var trainingPlans: [TrainingPlan]
    @Query(sort: \DailyCheckIn.date, order: .reverse) private var checkIns: [DailyCheckIn]
    @Query(sort: \CoachMemory.updatedAt, order: .reverse) private var memories: [CoachMemory]
    @Query(sort: \CoachChatSession.updatedAt, order: .reverse) private var sessions: [CoachChatSession]
    @Query(sort: \CoachChatMessage.createdAt, order: .forward) private var allMessages: [CoachChatMessage]

    @State private var input = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showContext = false
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var imageDataList: [Data] = []
    @FocusState private var inputFocused: Bool

    private let bottomID = "coach-bottom"

    private var profile: UserProfile? { profiles.first }
    private var aiSettings: AISettings? { settings.first }
    private var session: CoachChatSession? { sessions.first }
    private var memory: CoachMemory? { memories.first }

    private var messages: [CoachChatMessage] {
        guard let session else { return [] }
        return allMessages.filter { $0.sessionID == session.id }
    }

    private var currentContext: CoachContextSnapshot? {
        guard let profile else { return nil }
        return CoachContextBuilder.build(
            profile: profile,
            checkIns: checkIns,
            meals: meals,
            exercises: exercises,
            summaries: summaries,
            foodOptions: foodOptions,
            trainingPlans: trainingPlans,
            memory: memory
        )
    }

    private var canSend: Bool {
        !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !isLoading
            && profile != nil
            && aiSettings != nil
    }

    /// 目标缺口优先取最新训练计划算出的缺口（TDEE − 每日目标热量），与「今日」页同口径。
    private var deficitTarget: Double {
        if let planTarget = trainingPlans.first?.targetDailyDeficitKcal, planTarget > 0 {
            return planTarget
        }
        return profile?.targetDailyDeficitKcal ?? 0
    }

    private func deficitTint(_ deficit: Double) -> Color {
        deficitTarget > 0 && deficit >= deficitTarget ? .deficitReached : .deficitShort
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            statusCard
                            quickActions
                            contextCard

                            if messages.isEmpty {
                                emptyCoachHint
                            } else {
                                ForEach(messages) { message in
                                    CoachChatBubble(message: message) { record in
                                        saveSuggestedRecord(record, from: message)
                                    }
                                }
                            }

                            if isLoading {
                                HStack(spacing: 8) {
                                    ProgressView()
                                    Text("AI 教练正在结合全部数据分析…")
                                        .font(.callout)
                                        .foregroundStyle(.secondary)
                                }
                            }

                            if let errorMessage {
                                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            }

                            Color.clear.frame(height: 1).id(bottomID)
                        }
                        .padding()
                    }
                    .onChange(of: messages.count) { _, _ in
                        withAnimation { proxy.scrollTo(bottomID, anchor: .bottom) }
                    }
                    .onChange(of: isLoading) { _, _ in
                        withAnimation { proxy.scrollTo(bottomID, anchor: .bottom) }
                    }
                    .background(Color(.systemGroupedBackground))
                }

                inputBar
            }
            .navigationTitle("AI 教练")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        input = "请结合今天和最近 7 天的数据，帮我做一次每日复盘，并告诉我明天怎么吃、怎么练。"
                    } label: {
                        Image(systemName: "doc.text.magnifyingglass")
                    }
                    .accessibilityLabel("生成复盘问题")
                }
            }
            .onAppear { ensureSession() }
            .onChange(of: photoItems) { _, newValue in
                Task { await loadImages(from: newValue) }
            }
        }
    }

    @ViewBuilder
    private var statusCard: some View {
        if let context = currentContext {
            let deficit = context.today.calorieDeficit
            let tint = deficitTint(deficit)
            VStack(alignment: .leading, spacing: AppMetrics.tileSpacing) {
                HStack(spacing: AppMetrics.tileSpacing) {
                    MetricTile(title: "摄入", value: context.today.intakeCalories.kcalValue, systemImage: "fork.knife")
                    MetricTile(title: "热量差", value: deficit.signedKcalValue, systemImage: "plusminus", highlighted: true, tint: tint)
                }
                HStack(spacing: AppMetrics.tileSpacing) {
                    MetricTile(title: "活动", value: context.today.activeCalories.kcalValue, systemImage: "flame")
                    MetricTile(title: "基础", value: context.today.restingCalories.kcalValue, systemImage: "bed.double")
                }
                if deficitTarget > 0 {
                    MetricProgressBar(title: "距每日缺口目标 \(Int(deficitTarget)) kcal", current: deficit, target: deficitTarget, tint: tint)
                        .padding(.top, 2)
                }
                HStack(spacing: 14) {
                    Label("蛋白 \(Int(context.today.proteinGrams.rounded())) g", systemImage: "circle.hexagongrid")
                    if let sleep = context.today.sleepHours {
                        Label("睡眠 \(String(format: "%.1f", sleep)) 小时", systemImage: "moon.zzz")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                if !context.today.symptoms.isEmpty {
                    Label(context.today.symptoms, systemImage: "cross.case")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        } else {
            Text("请先完成资料设置。")
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 8)
        }
    }

    private var quickActions: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                quickButton("现在怎么吃", "现在这一餐怎么吃？食物选项只是参考，也可以另外推荐。请结合我今天已经吃的、最近的运动消耗和热量趋势给具体份量。")
                quickButton("刚吃完复盘", "我刚吃完这一餐，请帮我判断这顿对减脂的影响，并给下一步补救建议。")
                quickButton("练前安排", "我准备去训练，现在适合练吗？练前要不要吃点什么？")
                quickButton("每日复盘", "请做今天的完整复盘，指出热量缺口、蛋白、睡眠和明天安排。")
                quickButton("能不能吃", "我现在想吃这个，帮我按红灯/黄灯/绿灯判断。")
            }
            .padding(.horizontal, 1)
        }
    }

    private func quickButton(_ title: String, _ prompt: String) -> some View {
        Button(title) {
            input = prompt
            inputFocused = true
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .font(.caption)
    }

    private var contextCard: some View {
        DisclosureGroup(isExpanded: $showContext) {
            if let context = currentContext {
                VStack(alignment: .leading, spacing: 8) {
                    LabeledContent("目标", value: "\(context.profile.goal) · 每日缺口 \(Int(context.profile.targetDailyDeficitKcal)) kcal")
                    LabeledContent("今日记录", value: "\(context.today.confirmedMealCount) 餐 · \(context.today.workoutCount) 次训练")
                    LabeledContent("近 7 天", value: "\(context.recent7Days.count) 天趋势")
                    LabeledContent("食物选项", value: "\(context.foodOptions.count) 个")
                    LabeledContent("训练计划", value: "\(context.trainingPlans.count) 个")
                    if let memory = context.memory {
                        LabeledContent("长期记忆", value: "\(memory.foodPreferences.count + memory.trainingPreferences.count + memory.rules.count) 条")
                    }
                    if !context.dataQualityNotes.isEmpty {
                        Text(context.dataQualityNotes.joined(separator: "；"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.callout)
                .padding(.top, 4)
            } else {
                Text("缺少用户资料，暂时无法构建上下文。")
                    .foregroundStyle(.secondary)
            }
        } label: {
            Label("AI 将读取的上下文", systemImage: "chart.bar.doc.horizontal")
                .font(.subheadline.weight(.semibold))
        }
        .padding(12)
        .background(Color.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppMetrics.cardCornerRadius))
    }

    private var emptyCoachHint: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: "bubble.left.and.text.bubble.right")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("从这里和 AI 教练长期对话")
                .font(.headline)
            Text("可以问饭前饭后、外卖点单、训练前后、体重波动、睡眠恢复、感冒能不能练。AI 会结合本地饮食、运动、训练计划和长期记忆给建议。")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 24)
    }

    private var inputBar: some View {
        VStack(spacing: 6) {
            if !imageDataList.isEmpty {
                HStack {
                    Label("已选择 \(imageDataList.count) 张图片", systemImage: "photo.on.rectangle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("清除") {
                        photoItems = []
                        imageDataList = []
                    }
                    .font(.caption)
                }
                .padding(.horizontal, 12)
            }

            HStack(alignment: .bottom, spacing: 10) {
                PhotosPicker(selection: $photoItems, maxSelectionCount: 3, matching: .images) {
                    Image(systemName: "photo.badge.plus")
                        .font(.system(size: 24))
                }
                .disabled(isLoading)

                TextField("问教练：现在怎么吃、刚练完怎么补、这个能不能吃…", text: $input, axis: .vertical)
                    .lineLimit(1...4)
                    .focused($inputFocused)
                    .padding(8)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                Button {
                    Task { await send() }
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 30))
                }
                .disabled(!canSend)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .background(.bar)
    }

    @discardableResult
    private func ensureSession() -> CoachChatSession {
        if let session { return session }
        let newSession = CoachChatSession()
        modelContext.insert(newSession)
        try? modelContext.save()
        return newSession
    }

    @MainActor
    private func send() async {
        guard profile != nil, let settings = aiSettings else {
            errorMessage = "请先在设置里完善身体资料并保存 AI 配置。"
            return
        }
        guard let context = currentContext else {
            errorMessage = "无法构建教练上下文，请先保存基础资料。"
            return
        }
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        let activeSession = ensureSession()
        input = ""
        inputFocused = false
        showContext = false
        errorMessage = nil

        let userMessage = CoachChatMessage(sessionID: activeSession.id, role: .user, text: text)
        modelContext.insert(userMessage)
        activeSession.lastMessageText = text
        activeSession.updatedAt = .now
        try? modelContext.save()

        isLoading = true
        defer { isLoading = false }

        var recent = messages
        if !recent.contains(where: { $0.id == userMessage.id }) {
            recent.append(userMessage)
        }
        let attachedImages = imageDataList
        do {
            let result = try await aiClient.generateCoachReply(
                context: context,
                recentMessages: recent,
                imageDataList: attachedImages,
                settings: settings
            )
            insertAssistantMessage(result, context: context, session: activeSession)
            applyMemoryPatch(result.memoryPatch)
            imageDataList = []
            photoItems = []
        } catch {
            AppLog.error("教练回复失败：\(error.localizedDescription)", category: "AI教练")
            errorMessage = "AI 暂时不可用：\(error.localizedDescription)"
        }
    }

    private func insertAssistantMessage(_ result: CoachReplyResult, context: CoachContextSnapshot, session: CoachChatSession) {
        let assistantMessage = CoachChatMessage(
            sessionID: session.id,
            role: .assistant,
            text: result.replyText,
            scenario: result.scenario,
            riskLevel: result.riskLevel,
            context: context,
            suggestedRecords: result.suggestedRecords,
            memoryPatch: result.memoryPatch
        )
        modelContext.insert(assistantMessage)
        session.lastMessageText = result.replyText
        session.updatedAt = .now
        try? modelContext.save()
    }

    private func applyMemoryPatch(_ patch: CoachMemoryPatch?) {
        guard let patch, !patch.isEmpty else { return }
        let target = memory ?? CoachMemory()
        if memory == nil {
            modelContext.insert(target)
        }
        target.apply(patch)
        try? modelContext.save()
    }

    private func saveSuggestedRecord(_ record: CoachSuggestedRecord, from message: CoachChatMessage) {
        switch record.kind {
        case .meal:
            if let meal = record.makeMealEntry() {
                modelContext.insert(meal)
            }
        case .exercise:
            if let exercise = record.makeExerciseEntry() {
                modelContext.insert(exercise)
            }
        case .checkIn:
            let day = Calendar.current.startOfDay(for: record.date ?? .now)
            let checkIn = checkIns.first { Calendar.current.isDate($0.date, inSameDayAs: day) } ?? DailyCheckIn(date: day)
            if !checkIns.contains(where: { $0.id == checkIn.id }) {
                modelContext.insert(checkIn)
            }
            checkIn.apply(record)
            if let weight = record.weightKg, weight > 0, let profile {
                profile.currentWeightKg = weight
                profile.updatedAt = .now
            }
        }

        message.suggestedRecords = message.suggestedRecords.filter { $0.id != record.id }
        do {
            try modelContext.save()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func loadImages(from items: [PhotosPickerItem]) async {
        var loaded: [Data] = []
        for item in items {
            do {
                if let data = try await item.loadTransferable(type: Data.self) {
                    loaded.append(data)
                }
            } catch {
                errorMessage = "图片读取失败：\(error.localizedDescription)"
            }
        }
        imageDataList = loaded
    }
}

private struct CoachChatBubble: View {
    let message: CoachChatMessage
    var onSaveRecord: (CoachSuggestedRecord) -> Void

    var body: some View {
        VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 6) {
            if message.role == .assistant {
                assistantHeader
            }

            Text(attributedText)
                .font(.body)
                .textSelection(.enabled)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .padding(12)
                .background(message.role == .user ? Color.accentColor.opacity(0.16) : Color.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: AppMetrics.cardCornerRadius))

            if message.role == .assistant, !message.suggestedRecords.isEmpty {
                suggestedRecordsView
            }
        }
        .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)
    }

    /// 教练正文用 Markdown 渲染（保留换行），让加粗、分点等格式正常显示；解析失败则原样展示。
    private var attributedText: AttributedString {
        if let attributed = try? AttributedString(
            markdown: message.text,
            options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) {
            return attributed
        }
        return AttributedString(message.text)
    }

    private var assistantHeader: some View {
        HStack(spacing: 6) {
            Text(message.scenario.title)
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.accentColor.opacity(0.12))
                .clipShape(Capsule())
            if let risk = riskBadge {
                Label(risk.text, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(risk.color)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(risk.color.opacity(0.12))
                    .clipShape(Capsule())
            }
        }
    }

    private var riskBadge: (text: String, color: Color)? {
        switch message.riskLevel {
        case "caution": ("注意", Color.orange)
        case "high": ("高风险", Color.red)
        default: nil
        }
    }

    private var suggestedRecordsView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("可采纳 / 保存")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            ForEach(message.suggestedRecords) { record in
                Button {
                    onSaveRecord(record)
                } label: {
                    recordCard(record)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func recordCard(_ record: CoachSuggestedRecord) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: icon(for: record.kind))
                    .foregroundStyle(.secondary)
                Text(record.title)
                    .font(.subheadline.weight(.medium))
                Spacer()
                Image(systemName: "plus.circle.fill")
                    .foregroundStyle(Color.accentColor)
            }
            if record.kind == .meal, let macro = mealMacroText(record) {
                Text(macro)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if !record.note.isEmpty {
                Text(record.note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppMetrics.cardCornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: AppMetrics.cardCornerRadius)
                .strokeBorder(Color.accentColor.opacity(0.25), lineWidth: 1)
        )
    }

    private func mealMacroText(_ record: CoachSuggestedRecord) -> String? {
        var parts: [String] = []
        if let cal = record.totalCalories, cal > 0 { parts.append(cal.kcalText) }
        if let protein = record.proteinGrams, protein > 0 { parts.append("蛋白\(Int(protein.rounded()))g") }
        if let carbs = record.carbsGrams, carbs > 0 { parts.append("碳水\(Int(carbs.rounded()))g") }
        if let fat = record.fatGrams, fat > 0 { parts.append("脂肪\(Int(fat.rounded()))g") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func icon(for kind: CoachSuggestedRecordKind) -> String {
        switch kind {
        case .meal: "fork.knife"
        case .exercise: "figure.run"
        case .checkIn: "square.and.pencil"
        }
    }
}

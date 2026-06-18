import PhotosUI
import SwiftData
import SwiftUI
import UIKit

struct CoachHomeView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var aiClient: AIClient

    @Query private var profiles: [UserProfile]
    @Query private var settings: [AISettings]
    @Query(sort: \MealEntry.date, order: .reverse) private var meals: [MealEntry]
    @Query(sort: \FoodOption.updatedAt, order: .reverse) private var foodOptions: [FoodOption]
    @Query(sort: \ExerciseEntry.date, order: .reverse) private var exercises: [ExerciseEntry]
    @Query(sort: \DayLog.date, order: .reverse) private var dayLogs: [DayLog]
    @Query(sort: \TrainingPlan.updatedAt, order: .reverse) private var trainingPlans: [TrainingPlan]
    @Query(sort: \TrainingSession.date, order: .reverse) private var trainingSessions: [TrainingSession]
    @Query(sort: \DataCorrection.createdAt, order: .reverse) private var corrections: [DataCorrection]
    @Query(sort: \CoachMemory.updatedAt, order: .reverse) private var memories: [CoachMemory]
    @Query(sort: \CoachChatSession.updatedAt, order: .reverse) private var sessions: [CoachChatSession]
    @Query(sort: \CoachChatMessage.createdAt, order: .forward) private var allMessages: [CoachChatMessage]

    @State private var input = ""
    @State private var isLoading = false
    @State private var isCompressing = false
    @State private var errorMessage: String?
    @State private var carryoverErrorMessage: String?
    @State private var showingContextManager = false
    @State private var selectedDay = Calendar.current.startOfDay(for: .now)
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var imageDataList: [Data] = []
    @State private var pendingProposal: RecordProposal?
    @State private var editingMeal: MealEntry?
    @FocusState private var inputFocused: Bool

    private let bottomID = "coach-bottom"

    private var profile: UserProfile? { profiles.first }
    private var aiSettings: AISettings? { settings.first }
    private var todayStart: Date { Calendar.current.startOfDay(for: .now) }
    private var isSelectedToday: Bool { Calendar.current.isDate(selectedDay, inSameDayAs: todayStart) }
    private var session: CoachChatSession? { session(for: selectedDay) }
    private var memory: CoachMemory? { memories.first }

    private var messages: [CoachChatMessage] {
        guard let session else { return [] }
        return messages(for: session)
    }

    private var carryoverSnapshots: [CoachDailyCarryoverSnapshot] {
        sessions.compactMap(\.carryoverSnapshot)
    }

    private var currentContext: CoachContextSnapshot? {
        guard let profile else { return nil }
        return CoachContextBuilder.build(
            profile: profile,
            dayLogs: dayLogs,
            meals: meals,
            exercises: exercises,
            foodOptions: foodOptions,
            trainingPlans: trainingPlans,
            trainingSessions: trainingSessions,
            memory: memory,
            carryovers: carryoverSnapshots
        )
    }

    private var canSend: Bool {
        !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !isLoading
            && isSelectedToday
            && profile != nil
            && aiSettings != nil
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            if !isSelectedToday {
                                historicalNotice
                            }

                            if messages.isEmpty {
                                emptyCoachHint
                            } else {
                                ForEach(messages) { message in
                                    CoachChatBubble(
                                        message: message,
                                        onUndo: { ref in undoAppliedRecord(ref, from: message) },
                                        onEdit: { ref in editAppliedRecord(ref) },
                                        onSaveRecord: { record in saveSuggestedRecord(record, from: message) }
                                    )
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

                            if let carryoverErrorMessage {
                                Label(carryoverErrorMessage, systemImage: "exclamationmark.triangle.fill")
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
                    Menu {
                        Button {
                            input = "请结合今天和最近 7 天的数据，帮我做一次每日复盘，并告诉我明天怎么吃、怎么练。"
                            inputFocused = true
                        } label: {
                            Label("生成今日复盘", systemImage: "doc.text.magnifyingglass")
                        }
                        .disabled(!isSelectedToday)

                        Menu {
                            Button("今天") { selectedDay = todayStart }
                            ForEach(availableSessionDays, id: \.self) { day in
                                Button(DateFormatter.dateHeader.string(from: day)) { selectedDay = day }
                            }
                        } label: {
                            Label("历史对话", systemImage: "clock.arrow.circlepath")
                        }

                        Button {
                            showingContextManager = true
                        } label: {
                            Label("上下文与记忆", systemImage: "slider.horizontal.3")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityLabel("更多")
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("完成") {
                        dismissKeyboard()
                    }
                    .fontWeight(.semibold)
                }
            }
            .sheet(isPresented: $showingContextManager) {
                CoachContextManagerView(sessions: sessions, memory: memory)
            }
            .sheet(item: $editingMeal) { meal in
                MealEditorView(meal: meal)
            }
            .alert(item: $pendingProposal) { proposal in
                Alert(
                    title: Text(proposal.action == .update ? "确认更正" : "确认保存"),
                    message: Text(proposalConfirmationText(proposal)),
                    primaryButton: .default(Text("确认")) {
                        applyProposal(proposal)
                    },
                    secondaryButton: .cancel(Text("取消"))
                )
            }
            .onAppear {
                selectedDay = todayStart
                Task { await prepareTodaySession() }
            }
            .onChange(of: selectedDay) { _, newValue in
                dismissKeyboard()
                if Calendar.current.isDate(newValue, inSameDayAs: todayStart) {
                    ensureSession(for: todayStart)
                }
            }
            .onChange(of: photoItems) { _, newValue in
                Task { await loadImages(from: newValue) }
            }
        }
    }

    private var historicalNotice: some View {
        HStack(spacing: 8) {
            Label("历史对话只读", systemImage: "archivebox")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button("回到今天") {
                selectedDay = todayStart
            }
            .font(.caption.weight(.semibold))
        }
        .padding(10)
        .background(Color.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppMetrics.cardCornerRadius))
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

    private var emptyCoachHint: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: "bubble.left.and.text.bubble.right")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("像聊天一样记录和提问")
                .font(.headline)
            Text("随口说「早餐俩鸡蛋一杯豆浆」就会自动记账；也可以问现在怎么吃、这个能不能吃、刚练完怎么补。AI 会结合本地饮食、运动、体重趋势和长期记忆给建议。")
                .font(.callout)
                .foregroundStyle(.secondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    quickButton("现在怎么吃", "现在这一餐怎么吃？请结合我今天已经吃的、最近的运动消耗和热量趋势给具体份量。")
                    quickButton("这个能不能吃", "我现在想吃这个，帮我按红灯/黄灯/绿灯判断。")
                    quickButton("每日复盘", "请做今天的完整复盘，指出热量缺口、蛋白、睡眠和明天安排。")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 24)
    }

    private var inputBar: some View {
        VStack(spacing: 6) {
            if !isSelectedToday {
                HStack {
                    Label("历史对话只读", systemImage: "archivebox")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("回到今天") {
                        selectedDay = todayStart
                    }
                    .font(.caption.weight(.semibold))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            } else {
                if inputFocused {
                    HStack {
                        Spacer()
                        Button {
                            dismissKeyboard()
                        } label: {
                            Label("收起键盘", systemImage: "keyboard.chevron.compact.down")
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                    .padding(.horizontal, 12)
                }

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
        }
        .background(.bar)
    }

    @discardableResult
    private func ensureSession(for day: Date? = nil) -> CoachChatSession {
        let targetDay = Calendar.current.startOfDay(for: day ?? selectedDay)
        if let existing = session(for: targetDay) { return existing }
        let newSession = CoachChatSession(title: sessionTitle(for: targetDay), dayDate: targetDay)
        modelContext.insert(newSession)
        try? modelContext.save()
        return newSession
    }

    private func session(for day: Date) -> CoachChatSession? {
        let targetDay = Calendar.current.startOfDay(for: day)
        return sessions.first {
            !$0.isArchived && Calendar.current.isDate($0.dayDate, inSameDayAs: targetDay)
        }
    }

    private func messages(for session: CoachChatSession) -> [CoachChatMessage] {
        allMessages.filter { $0.sessionID == session.id }
    }

    private var availableSessionDays: [Date] {
        let days = sessions
            .filter { !$0.isArchived }
            .map { Calendar.current.startOfDay(for: $0.dayDate) }
            .filter { !Calendar.current.isDate($0, inSameDayAs: todayStart) }
        return Array(Set(days)).sorted(by: >)
    }

    private func sessionTitle(for day: Date) -> String {
        Calendar.current.isDateInToday(day) ? "今日教练" : "\(DateFormatter.csvDate.string(from: day)) 教练"
    }

    private func dismissKeyboard() {
        inputFocused = false
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    @MainActor
    private func prepareTodaySession() async {
        ensureSession(for: todayStart)
        await compressPastSessionsIfNeeded()
    }

    @MainActor
    private func compressPastSessionsIfNeeded() async {
        guard !isCompressing, let settings = aiSettings, currentContext != nil else { return }
        let pendingSessions = sessions
            .filter { $0.dayDate < todayStart && !$0.isArchived && $0.compressedAt == nil && !messages(for: $0).isEmpty }
            .sorted { $0.dayDate < $1.dayDate }
        guard !pendingSessions.isEmpty else { return }

        isCompressing = true
        carryoverErrorMessage = nil
        defer { isCompressing = false }

        for oldSession in pendingSessions {
            guard let context = currentContext else { continue }
            do {
                let carryover = try await aiClient.generateCoachDayCarryover(
                    session: oldSession,
                    messages: messages(for: oldSession),
                    context: context,
                    settings: settings
                )
                oldSession.carryover = carryover
                oldSession.carryoverEnabled = true
                oldSession.isArchived = true
                oldSession.compressedAt = .now
                oldSession.updatedAt = .now
                try modelContext.save()
            } catch {
                AppLog.error("教练每日对话压缩失败：\(error.localizedDescription)", category: "AI教练")
                carryoverErrorMessage = "昨日上下文整理失败，可在上下文管理里稍后重试。"
            }
        }
    }

    @MainActor
    private func send() async {
        guard isSelectedToday else {
            errorMessage = "历史对话只读，请回到今天继续提问。"
            return
        }
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
        // 长期记忆补丁直接合并（持久化记忆，不需要用户逐条确认）。
        applyMemoryPatch(result.memoryPatch)
        // 混合自动记账：饮食/运动的 create 提案立即写入，气泡内联「✓ 已记录·撤销/编辑」。
        autoApplyProposals(for: assistantMessage)
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

    /// 混合自动记账：饮食 / 运动的 `create` 提案立即写入并落到 `appliedRecords`；
    /// 体重（checkIn）与任意 `update`（更正旧数据）以及 foodAlias 仍留在 `suggestedRecords`，由用户确认。
    private func autoApplyProposals(for message: CoachChatMessage) {
        var remaining: [CoachSuggestedRecord] = []
        var applied = message.appliedRecords
        for record in message.suggestedRecords {
            let isAutoKind = record.kind == .meal || record.kind == .exercise
            if isAutoKind, record.action == .create, let ref = applyCreateRecord(record) {
                applied.append(ref)
            } else {
                remaining.append(record)
            }
        }
        message.suggestedRecords = remaining
        message.appliedRecords = applied
    }

    /// 写入一条饮食/运动 create 记录，返回用于内联展示与撤销的引用。
    private func applyCreateRecord(_ record: CoachSuggestedRecord) -> AppliedRecordRef? {
        switch record.kind {
        case .meal:
            guard let meal = record.makeMealEntry() else { return nil }
            modelContext.insert(meal)
            return AppliedRecordRef(
                id: record.id,
                kind: .meal,
                title: record.title,
                entityType: "MealEntry",
                entityID: meal.id.uuidString,
                macroSummary: appliedMealMacroText(record)
            )
        case .exercise:
            guard let exercise = record.makeExerciseEntry() else { return nil }
            modelContext.insert(exercise)
            return AppliedRecordRef(
                id: record.id,
                kind: .exercise,
                title: record.title,
                entityType: "ExerciseEntry",
                entityID: exercise.id.uuidString,
                macroSummary: appliedExerciseText(record)
            )
        default:
            return nil
        }
    }

    /// 撤销一条已自动写入的记录：删除对应实体并移除内联引用。
    private func undoAppliedRecord(_ ref: AppliedRecordRef, from message: CoachChatMessage) {
        switch ref.entityType {
        case "MealEntry":
            if let id = UUID(uuidString: ref.entityID), let meal = meals.first(where: { $0.id == id }) {
                modelContext.delete(meal)
            }
        case "ExerciseEntry":
            if let id = UUID(uuidString: ref.entityID), let exercise = exercises.first(where: { $0.id == id }) {
                modelContext.delete(exercise)
            }
        default:
            break
        }
        message.appliedRecords.removeAll { $0.id == ref.id }
        do {
            try modelContext.save()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// 编辑一条已自动写入的饮食记录（运动暂不支持编辑，可撤销后重记）。
    private func editAppliedRecord(_ ref: AppliedRecordRef) {
        guard ref.entityType == "MealEntry",
              let id = UUID(uuidString: ref.entityID),
              let meal = meals.first(where: { $0.id == id }) else { return }
        editingMeal = meal
    }

    private func appliedMealMacroText(_ record: CoachSuggestedRecord) -> String {
        var parts: [String] = []
        if let cal = record.totalCalories, cal > 0 { parts.append(cal.kcalText) }
        if let p = record.proteinGrams, p > 0 { parts.append("蛋白\(Int(p.rounded()))g") }
        if let c = record.carbsGrams, c > 0 { parts.append("碳水\(Int(c.rounded()))g") }
        if let f = record.fatGrams, f > 0 { parts.append("脂肪\(Int(f.rounded()))g") }
        return parts.joined(separator: " · ")
    }

    private func appliedExerciseText(_ record: CoachSuggestedRecord) -> String {
        var parts: [String] = []
        if let mins = record.durationMinutes, mins > 0 { parts.append("\(Int(mins.rounded())) 分钟") }
        if let cal = record.activeCalories, cal > 0 { parts.append(cal.kcalText) }
        return parts.joined(separator: " · ")
    }

    private func saveSuggestedRecord(_ record: CoachSuggestedRecord, from message: CoachChatMessage) {
        _ = message
        pendingProposal = record
    }

    private func applyProposal(_ record: RecordProposal) {
        switch record.kind {
        case .meal:
            if record.action == .update,
               let idText = record.existingRecordID,
               let id = UUID(uuidString: idText),
               let meal = meals.first(where: { $0.id == id }) {
                let oldValue = meal.textDescription
                meal.textDescription = record.textDescription ?? meal.textDescription
                meal.totalCalories = max(0, record.totalCalories ?? meal.totalCalories)
                meal.proteinGrams = max(0, record.proteinGrams ?? meal.proteinGrams)
                meal.carbsGrams = max(0, record.carbsGrams ?? meal.carbsGrams)
                meal.fatGrams = max(0, record.fatGrams ?? meal.fatGrams)
                meal.updatedAt = .now
                insertCorrection(
                    entityType: "MealEntry",
                    entityID: meal.id.uuidString,
                    fieldName: "meal",
                    oldValue: oldValue,
                    newValue: meal.textDescription,
                    date: meal.date,
                    reason: record.note
                )
            } else if let meal = record.makeMealEntry() {
                modelContext.insert(meal)
            }
        case .exercise:
            if record.action == .update,
               let idText = record.existingRecordID,
               let id = UUID(uuidString: idText),
               let exercise = exercises.first(where: { $0.id == id }) {
                let oldValue = "\(exercise.workoutType) \(exercise.activeCalories)"
                exercise.workoutType = record.workoutType ?? exercise.workoutType
                exercise.durationMinutes = max(0, record.durationMinutes ?? exercise.durationMinutes)
                exercise.activeCalories = max(0, record.activeCalories ?? exercise.activeCalories)
                exercise.steps = max(0, record.steps ?? exercise.steps)
                insertCorrection(
                    entityType: "ExerciseEntry",
                    entityID: exercise.id.uuidString,
                    fieldName: "exercise",
                    oldValue: oldValue,
                    newValue: "\(exercise.workoutType) \(exercise.activeCalories)",
                    date: exercise.date,
                    reason: record.note
                )
            } else if let exercise = record.makeExerciseEntry() {
                modelContext.insert(exercise)
            }
        case .checkIn:
            let day = Calendar.current.startOfDay(for: record.date ?? .now)
            let log = dayLogs.first { Calendar.current.isDate($0.date, inSameDayAs: day) } ?? DayLog(date: day)
            if !dayLogs.contains(where: { $0.id == log.id }) {
                modelContext.insert(log)
            }
            let oldWeight = log.weightKg
            log.apply(record)
            if record.action == .update, let newWeight = record.weightKg, oldWeight > 0 {
                insertCorrection(
                    entityType: "DayLog",
                    entityID: day.dayKey,
                    fieldName: "weightKg",
                    oldValue: String(oldWeight),
                    newValue: String(newWeight),
                    date: day,
                    reason: record.note.isEmpty ? "用户确认 AI 更正提案" : record.note
                )
                log.reportIsStale = true
            }
            // 体重写 DayLog（单源）；仅当天同步到档案 currentWeightKg。
            if let weight = record.weightKg, weight > 0, Calendar.current.isDateInToday(day), let profile {
                profile.currentWeightKg = weight
                profile.updatedAt = .now
            }
        case .foodAlias:
            guard record.action == .remember else { break }
            if let targetID = record.targetFoodOptionID,
               let option = foodOptions.first(where: { $0.id == targetID }) {
                option.addAliases(record.aliases)
            } else if let option = foodOptions.first(where: { $0.matches(record.title) }) {
                option.addAliases(record.aliases + [record.title])
            }
        }

        for message in allMessages where message.suggestedRecords.contains(where: { $0.id == record.id }) {
            message.suggestedRecords = message.suggestedRecords.filter { $0.id != record.id }
        }
        do {
            try modelContext.save()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func insertCorrection(
        entityType: String,
        entityID: String,
        fieldName: String,
        oldValue: String,
        newValue: String,
        date: Date,
        reason: String
    ) {
        modelContext.insert(DataCorrection(
            entityType: entityType,
            entityID: entityID,
            fieldName: fieldName,
            oldValue: oldValue,
            newValue: newValue,
            effectiveDate: date,
            reason: reason.isEmpty ? "用户确认 AI 更正提案" : reason,
            source: .coachProposal
        ))
    }

    private func proposalConfirmationText(_ proposal: RecordProposal) -> String {
        var lines: [String] = []
        if let old = proposal.oldValueSummary, !old.isEmpty {
            lines.append("原值：\(old)")
        }
        lines.append("新值：\(proposal.title)")
        if let weight = proposal.weightKg {
            lines.append("体重：\(String(format: "%.2f", weight)) kg")
            if let warning = TrendSafetyAnalyzer.weightAnomaly(
                proposedKg: weight,
                on: proposal.date ?? .now,
                dayLogs: dayLogs
            ) {
                lines.append("注意：\(warning)")
            }
        }
        if !proposal.note.isEmpty { lines.append(proposal.note) }
        return lines.joined(separator: "\n")
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

private struct CoachContextManagerView: View {
    @Environment(\.dismiss) private var dismiss

    let sessions: [CoachChatSession]
    let memory: CoachMemory?

    private var carryoverSessions: [CoachChatSession] {
        sessions
            .filter { $0.carryover != nil || $0.compressedAt != nil }
            .sorted { $0.dayDate > $1.dayDate }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("每日结转上下文") {
                    if carryoverSessions.isEmpty {
                        Text("还没有可管理的每日结转。第二天进入教练页后，会自动整理前一天对话。")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(carryoverSessions) { session in
                            CoachCarryoverEditor(session: session)
                        }
                    }
                }

                Section("长期记忆") {
                    if let memory {
                        CoachMemoryEditor(memory: memory)
                    } else {
                        Text("还没有长期记忆。AI 只有在确认某些信息未来也有用时，才会写入长期记忆。")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("上下文管理")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }
}

private struct CoachCarryoverEditor: View {
    @Environment(\.modelContext) private var modelContext

    let session: CoachChatSession

    @State private var enabled = true
    @State private var summary = ""
    @State private var importantNotes = ""
    @State private var foodWarnings = ""
    @State private var trainingWarnings = ""
    @State private var nextDayFocus = ""
    @State private var isExpanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            Toggle("带入后续教练上下文", isOn: $enabled)
            TextEditor(text: $summary)
                .frame(minHeight: 72)
                .overlay(alignment: .topLeading) {
                    if summary.isEmpty {
                        Text("摘要")
                            .foregroundStyle(.secondary)
                            .padding(.top, 8)
                            .allowsHitTesting(false)
                    }
                }
            labeledEditor("重要事实", text: $importantNotes)
            labeledEditor("饮食注意", text: $foodWarnings)
            labeledEditor("训练恢复注意", text: $trainingWarnings)
            labeledEditor("下一天跟进", text: $nextDayFocus)
            HStack {
                Button(role: .destructive) {
                    session.carryover = nil
                    session.carryoverEnabled = false
                    session.updatedAt = .now
                    try? modelContext.save()
                    load()
                } label: {
                    Label("删除结转", systemImage: "trash")
                }
                Spacer()
                Button {
                    save()
                } label: {
                    Label("保存", systemImage: "checkmark")
                }
                .buttonStyle(.borderedProminent)
            }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(DateFormatter.dateHeader.string(from: session.dayDate))
                    .font(.subheadline.weight(.semibold))
                Text(session.carryover?.summary.isEmpty == false ? session.carryover?.summary ?? "" : "暂无摘要")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .onAppear { load() }
    }

    private func labeledEditor(_ title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            TextEditor(text: text)
                .frame(minHeight: 56)
        }
    }

    private func load() {
        let carryover = session.carryover ?? CoachDailyCarryover()
        enabled = session.carryoverEnabled
        summary = carryover.summary
        importantNotes = Self.text(from: carryover.importantNotes)
        foodWarnings = Self.text(from: carryover.foodWarnings)
        trainingWarnings = Self.text(from: carryover.trainingWarnings)
        nextDayFocus = Self.text(from: carryover.nextDayFocus)
    }

    private func save() {
        session.carryover = CoachDailyCarryover(
            summary: summary.trimmingCharacters(in: .whitespacesAndNewlines),
            importantNotes: Self.lines(from: importantNotes),
            foodWarnings: Self.lines(from: foodWarnings),
            trainingWarnings: Self.lines(from: trainingWarnings),
            nextDayFocus: Self.lines(from: nextDayFocus)
        )
        session.carryoverEnabled = enabled
        session.updatedAt = .now
        try? modelContext.save()
    }

    private static func text(from values: [String]) -> String {
        values.joined(separator: "\n")
    }

    private static func lines(from text: String) -> [String] {
        text
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}

private struct CoachMemoryEditor: View {
    @Environment(\.modelContext) private var modelContext

    let memory: CoachMemory

    @State private var profileSummary = ""
    @State private var foodPreferences = ""
    @State private var avoidances = ""
    @State private var trainingPreferences = ""
    @State private var healthNotes = ""
    @State private var rules = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            labeledEditor("用户摘要", text: $profileSummary, minHeight: 72)
            labeledEditor("常吃/偏好", text: $foodPreferences)
            labeledEditor("忌口/避开", text: $avoidances)
            labeledEditor("训练偏好", text: $trainingPreferences)
            labeledEditor("健康注意", text: $healthNotes)
            labeledEditor("固定规则", text: $rules)
            Button {
                save()
            } label: {
                Label("保存长期记忆", systemImage: "checkmark")
            }
            .buttonStyle(.borderedProminent)
        }
        .onAppear { load() }
    }

    private func labeledEditor(_ title: String, text: Binding<String>, minHeight: CGFloat = 56) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            TextEditor(text: text)
                .frame(minHeight: minHeight)
        }
    }

    private func load() {
        profileSummary = memory.profileSummary
        foodPreferences = Self.text(from: memory.foodPreferences)
        avoidances = Self.text(from: memory.avoidances)
        trainingPreferences = Self.text(from: memory.trainingPreferences)
        healthNotes = Self.text(from: memory.healthNotes)
        rules = Self.text(from: memory.rules)
    }

    private func save() {
        memory.profileSummary = profileSummary.trimmingCharacters(in: .whitespacesAndNewlines)
        memory.foodPreferences = Self.lines(from: foodPreferences)
        memory.avoidances = Self.lines(from: avoidances)
        memory.trainingPreferences = Self.lines(from: trainingPreferences)
        memory.healthNotes = Self.lines(from: healthNotes)
        memory.rules = Self.lines(from: rules)
        memory.updatedAt = .now
        try? modelContext.save()
    }

    private static func text(from values: [String]) -> String {
        values.joined(separator: "\n")
    }

    private static func lines(from text: String) -> [String] {
        text
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}

private struct CoachChatBubble: View {
    let message: CoachChatMessage
    var onUndo: (AppliedRecordRef) -> Void
    var onEdit: (AppliedRecordRef) -> Void
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

            if message.role == .assistant, !message.appliedRecords.isEmpty {
                appliedRecordsView
            }

            if message.role == .assistant, !message.suggestedRecords.isEmpty {
                suggestedRecordsView
            }
        }
        .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)
    }

    private var appliedRecordsView: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(message.appliedRecords) { ref in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("已记录 · \(ref.title)")
                            .font(.caption.weight(.medium))
                        if !ref.macroSummary.isEmpty {
                            Text(ref.macroSummary)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    if ref.kind == .meal {
                        Button("编辑") { onEdit(ref) }
                            .font(.caption2)
                            .buttonStyle(.plain)
                            .foregroundStyle(Color.accentColor)
                    }
                    Button("撤销") { onUndo(ref) }
                        .font(.caption2)
                        .buttonStyle(.plain)
                        .foregroundStyle(.red)
                }
                .padding(10)
                .background(Color.green.opacity(0.10))
                .clipShape(RoundedRectangle(cornerRadius: AppMetrics.cardCornerRadius))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
            Text("待确认操作")
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
                Text(actionTitle(record.action))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(
                        record.action == .update
                            ? Color.orange
                            : Color.accentColor
                    )
                Spacer()
                Image(systemName: record.action == .update ? "pencil.circle.fill" : "checkmark.circle.fill")
                    .foregroundStyle(Color.accentColor)
            }
            if let old = record.oldValueSummary, !old.isEmpty {
                Text("原值：\(old)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
        case .foodAlias: "tag"
        }
    }

    private func actionTitle(_ action: RecordProposalAction) -> String {
        switch action {
        case .create: "新增"
        case .update: "更正"
        case .remember: "记住"
        }
    }
}

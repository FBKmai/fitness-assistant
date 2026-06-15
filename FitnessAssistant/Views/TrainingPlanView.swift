import SwiftData
import SwiftUI
import UIKit

// MARK: - 列表页（作为「运动」Tab 内的 push 目的地，复用父级 NavigationStack）

struct TrainingPlanListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \TrainingPlan.updatedAt, order: .reverse) private var plans: [TrainingPlan]

    @State private var showingEditor = false
    @State private var editingPlan: TrainingPlan?

    var body: some View {
        Group {
            if plans.isEmpty {
                ContentUnavailableView {
                    Label("还没有训练计划", systemImage: "figure.strengthtraining.traditional")
                } description: {
                    Text("根据你的身体数据和目标，让 AI 生成一份个性化的训练 + 营养方案。")
                } actions: {
                    Button {
                        showingEditor = true
                    } label: {
                        Label("制定训练计划", systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                }
            } else {
                List {
                    ForEach(plans) { plan in
                        Button {
                            editingPlan = plan
                        } label: {
                            TrainingPlanCard(plan: plan)
                        }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                delete(plan)
                            } label: {
                                Label("删除", systemImage: "trash")
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("训练计划")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingEditor = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("新建训练计划")
            }
        }
        .sheet(isPresented: $showingEditor) {
            TrainingPlanEditorView()
        }
        .sheet(item: $editingPlan) { plan in
            TrainingPlanEditorView(plan: plan)
        }
    }

    private func delete(_ plan: TrainingPlan) {
        modelContext.delete(plan)
        try? modelContext.save()
    }
}

// MARK: - 编辑/新建页（同一页负责新增与编辑，照 FoodOptionEditorView）

struct TrainingPlanEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var aiClient: AIClient
    @EnvironmentObject private var healthKitService: HealthKitService

    @Query private var settings: [AISettings]
    @Query private var profiles: [UserProfile]
    @Query(sort: \ExerciseEntry.date, order: .reverse) private var exercises: [ExerciseEntry]

    private let plan: TrainingPlan?

    // 基本
    @State private var title: String
    @State private var goal: FitnessGoal
    // 身体数据（自动可同步，亦可手改）
    @State private var weightKg: String
    @State private var bodyFat: String
    @State private var bmi: String
    // 目标与训练（手填）
    @State private var targetWeight: String
    @State private var targetWeeks: Int
    @State private var activityLevel: ActivityLevel
    @State private var trainingDaysPerWeek: Int
    @State private var trainingExperience: TrainingExperienceLevel
    @State private var trainingTypePreference: String
    @State private var sleepHours: String
    @State private var dietPreference: String
    @State private var extraNote: String
    // 结果
    @State private var result: TrainingPlanResult?
    // 状态
    @State private var isSyncing = false
    @State private var isGenerating = false
    @State private var errorMessage: String?
    @FocusState private var focusedField: FocusedField?

    private enum FocusedField: Hashable {
        case title
        case weight
        case bodyFat
        case bmi
        case targetWeight
        case trainingType
        case sleep
        case dietPreference
        case extraNote
    }

    init(plan: TrainingPlan? = nil) {
        self.plan = plan
        let input = plan?.input
        _title = State(initialValue: plan?.title ?? "")
        _goal = State(initialValue: plan?.goal ?? .fatLoss)
        _weightKg = State(initialValue: Self.numberText(input?.weightKg, decimals: 1))
        _bodyFat = State(initialValue: Self.numberText(input?.bodyFatPercentage, decimals: 1))
        _bmi = State(initialValue: Self.numberText(input?.bmi, decimals: 1))
        _targetWeight = State(initialValue: Self.numberText(input?.targetWeightKg, decimals: 1))
        _targetWeeks = State(initialValue: input?.targetWeeks ?? 0)
        _activityLevel = State(initialValue: input.flatMap { ActivityLevel(rawValue: $0.activityLevel) } ?? .sedentary)
        _trainingDaysPerWeek = State(initialValue: input?.trainingDaysPerWeek ?? 3)
        _trainingExperience = State(initialValue: input.flatMap { TrainingExperienceLevel(rawValue: $0.trainingExperience) } ?? .beginner)
        _trainingTypePreference = State(initialValue: input?.trainingTypePreference ?? "力量为主")
        _sleepHours = State(initialValue: Self.numberText(input?.sleepHours, decimals: 1))
        _dietPreference = State(initialValue: input?.dietPreference ?? "")
        _extraNote = State(initialValue: input?.extraNote ?? "")
        _result = State(initialValue: plan?.result)
    }

    private var profile: UserProfile? { profiles.first }

    /// 近 7 天的训练次数（排除步数日合计 daily-* 聚合项）。
    private var recentWeeklyWorkouts: Int {
        let sevenDaysAgo = Calendar.current.date(byAdding: .day, value: -7, to: .now) ?? .now
        return exercises.filter {
            $0.date >= sevenDaysAgo && !($0.healthKitWorkoutID?.hasPrefix("daily-") ?? false)
        }.count
    }

    /// 近 7 天的日均步数（来自每日步数合计 daily-* 项）。
    private var avgDailySteps: Double? {
        let sevenDaysAgo = Calendar.current.date(byAdding: .day, value: -7, to: .now) ?? .now
        let dailyEntries = exercises.filter {
            $0.date >= sevenDaysAgo && ($0.healthKitWorkoutID?.hasPrefix("daily-") ?? false) && $0.steps > 0
        }
        guard !dailyEntries.isEmpty else { return nil }
        return dailyEntries.reduce(0) { $0 + $1.steps } / Double(dailyEntries.count)
    }

    private var canGenerate: Bool {
        settings.first != nil && profile != nil && !isGenerating
    }

    private var canSave: Bool {
        result != nil && !isGenerating
    }

    private var defaultTitle: String { "\(goal.title)计划" }

    var body: some View {
        NavigationStack {
            Form {
                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                            .font(.callout)
                    }
                }

                basicSection
                bodyDataSection
                goalTrainingSection
                preferenceSection
                generateSection

                if result != nil {
                    resultSections
                }
            }
            .navigationTitle(plan == nil ? "新建训练计划" : "编辑训练计划")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismissKeyboard()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        dismissKeyboard()
                        save()
                    }
                    .disabled(!canSave)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("完成") {
                        dismissKeyboard()
                    }
                    .fontWeight(.semibold)
                }
            }
            .safeAreaInset(edge: .bottom) {
                if focusedField != nil {
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
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(.bar)
                }
            }
        }
    }

    // MARK: 输入区

    private var basicSection: some View {
        Section("基本信息") {
            TextField("计划名称，例如 减脂计划", text: $title)
                .focused($focusedField, equals: .title)

            Picker("目标", selection: $goal) {
                ForEach(FitnessGoal.allCases) { goal in
                    Text(goal.title).tag(goal)
                }
            }
            .pickerStyle(.segmented)

            if let profile {
                LabeledContent("身高", value: "\(Int(profile.heightCm)) cm")
                LabeledContent("年龄", value: "\(profile.age) 岁")
                LabeledContent("性别", value: profile.gender.title)
                LabeledContent("基础代谢", value: CalorieCalculator.bmr(profile: profile).kcalText)
            } else {
                Text("请先在「设置」完善个人资料，才能制定计划。")
                    .font(.callout)
                    .foregroundStyle(.orange)
            }
            LabeledContent("近 7 天训练", value: "\(recentWeeklyWorkouts) 次")
        }
    }

    private var bodyDataSection: some View {
        Section {
            Button {
                Task { await syncHealth() }
            } label: {
                if isSyncing {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("同步中…")
                    }
                } else {
                    Label("同步 Apple 健康数据", systemImage: "heart.fill")
                }
            }
            .disabled(isSyncing)

            TextField("体重 kg", text: $weightKg)
                .keyboardType(.decimalPad)
                .focused($focusedField, equals: .weight)
            TextField("体脂率 %（可选）", text: $bodyFat)
                .keyboardType(.decimalPad)
                .focused($focusedField, equals: .bodyFat)
            TextField("BMI（可选，留空自动估算）", text: $bmi)
                .keyboardType(.decimalPad)
                .focused($focusedField, equals: .bmi)
        } header: {
            Text("身体数据")
        } footer: {
            Text("点上方按钮可从 Apple 健康自动带入体重/体脂/BMI，也可手动修改。")
        }
    }

    private var goalTrainingSection: some View {
        Section("目标与训练") {
            TextField("目标体重 kg（可选）", text: $targetWeight)
                .keyboardType(.decimalPad)
                .focused($focusedField, equals: .targetWeight)

            Stepper(value: $targetWeeks, in: 0...52) {
                HStack {
                    Text("期望周期")
                    Spacer()
                    Text(targetWeeks == 0 ? "未设置" : "\(targetWeeks) 周")
                        .foregroundStyle(.secondary)
                }
            }

            Picker("日常活动水平", selection: $activityLevel) {
                ForEach(ActivityLevel.allCases) { level in
                    Text(level.title).tag(level)
                }
            }

            Stepper(value: $trainingDaysPerWeek, in: 1...7) {
                HStack {
                    Text("每周训练天数")
                    Spacer()
                    Text("\(trainingDaysPerWeek) 天")
                        .foregroundStyle(.secondary)
                }
            }

            Picker("训练经验", selection: $trainingExperience) {
                ForEach(TrainingExperienceLevel.allCases) { level in
                    Text(level.title).tag(level)
                }
            }

            TextField("训练偏好，例如 力量为主 / 力量+有氧", text: $trainingTypePreference)
                .focused($focusedField, equals: .trainingType)

            TextField("平均睡眠 小时（可选）", text: $sleepHours)
                .keyboardType(.decimalPad)
                .focused($focusedField, equals: .sleep)
        }
    }

    private var preferenceSection: some View {
        Section {
            placeholderEditor(
                text: $dietPreference,
                placeholder: "忌口、过敏、是否吃素、每天习惯几餐、能买到什么等。",
                field: .dietPreference
            )
            placeholderEditor(
                text: $extraNote,
                placeholder: "其他想让教练知道的情况，例如旧伤、工作强度、压力。",
                field: .extraNote
            )
        } header: {
            Text("饮食偏好与补充")
        }
    }

    private var generateSection: some View {
        Section {
            Button {
                Task { await generate() }
            } label: {
                if isGenerating {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("AI 制定中…")
                    }
                } else {
                    Label(result == nil ? "生成训练计划" : "重新生成", systemImage: "sparkles")
                }
            }
            .disabled(!canGenerate)
        } footer: {
            if settings.first == nil {
                Text("请先在「设置」保存 AI 配置。")
                    .foregroundStyle(.orange)
            }
        }
    }

    // MARK: 结果区

    @ViewBuilder
    private var resultSections: some View {
        if let result {
            if !result.realisticGoalNote.isEmpty {
                Section("目标评估") {
                    Text(result.realisticGoalNote)
                        .font(.callout)
                }
            }

            Section("每日热量与营养") {
                LabeledContent("基础代谢 BMR", value: result.bmr.kcalText)
                LabeledContent("总消耗 TDEE", value: result.tdee.kcalText)
                LabeledContent("每日目标热量", value: result.dailyCalories.kcalText)
                LabeledContent("目标缺口", value: max(0, result.tdee - result.dailyCalories).kcalText)
                LabeledContent("蛋白质", value: "\(Int(result.proteinGrams.rounded())) g")
                LabeledContent("碳水", value: "\(Int(result.carbsGrams.rounded())) g")
                LabeledContent("脂肪", value: "\(Int(result.fatGrams.rounded())) g")

                let ratio = macroRatio(result)
                MacroRatioBar(
                    proteinRatio: ratio.protein,
                    carbsRatio: ratio.carbs,
                    fatRatio: ratio.fat
                )
                HStack(spacing: 12) {
                    MacroLabel(name: "蛋白", grams: result.proteinGrams, color: .macroProtein)
                    MacroLabel(name: "碳水", grams: result.carbsGrams, color: .macroCarbs)
                    MacroLabel(name: "脂肪", grams: result.fatGrams, color: .macroFat)
                }
                if !result.macroNote.isEmpty {
                    Text(result.macroNote)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if !result.monitoringAdvice.isEmpty {
                Section("监测与调整") {
                    Text(result.monitoringAdvice)
                        .font(.callout)
                }
            }
        }
    }

    private func macroRatio(_ result: TrainingPlanResult) -> (protein: Double, carbs: Double, fat: Double) {
        let total = result.proteinGrams * 4 + result.carbsGrams * 4 + result.fatGrams * 9
        guard total > 0 else { return (0, 0, 0) }
        return (result.proteinGrams * 4 / total, result.carbsGrams * 4 / total, result.fatGrams * 9 / total)
    }

    // MARK: 行为

    private func dismissKeyboard() {
        focusedField = nil
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    @MainActor
    private func syncHealth() async {
        isSyncing = true
        errorMessage = nil
        defer { isSyncing = false }
        do {
            try await healthKitService.requestAuthorization()
            let snapshot = try await healthKitService.fetchSnapshot(for: .now)
            let metrics = snapshot.bodyMetrics
            if let weight = metrics.weightKg {
                weightKg = String(format: "%.1f", weight)
            }
            if let fat = metrics.bodyFatPercentage {
                bodyFat = String(format: "%.1f", fat)
            }
            if let bodyMassIndex = metrics.bodyMassIndex {
                bmi = String(format: "%.1f", bodyMassIndex)
            }
            if !metrics.hasAnyValue {
                errorMessage = "Apple 健康暂无体重/体脂/BMI 数据，可手动填写。"
            }
        } catch {
            AppLog.error("读取 Apple 健康身体数据失败：\(error.localizedDescription)", category: "训练计划")
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func generate() async {
        guard let aiSettings = settings.first else {
            errorMessage = "请先在「设置」保存 AI 配置"
            return
        }
        guard let profile else {
            errorMessage = "请先在「设置」完善个人资料"
            return
        }

        isGenerating = true
        errorMessage = nil
        defer { isGenerating = false }

        let input = buildInput(profile: profile)
        do {
            let generated = try await aiClient.generateTrainingPlan(input: input, settings: aiSettings)
            applyResult(generated)
        } catch {
            AppLog.error("生成训练计划失败：\(error.localizedDescription)", category: "训练计划")
            errorMessage = error.localizedDescription
        }
    }

    private func applyResult(_ generated: TrainingPlanResult) {
        result = generated
        if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            title = defaultTitle
        }
    }

    private func buildInput(profile: UserProfile) -> TrainingPlanInput {
        let weight = weightKg.doubleValue ?? profile.currentWeightKg
        return TrainingPlanInput(
            gender: profile.gender.title,
            age: profile.age,
            heightCm: profile.heightCm,
            weightKg: weight,
            bodyFatPercentage: bodyFat.doubleValue,
            bmi: resolvedBMI(weight: weight, profile: profile),
            bmr: CalorieCalculator.bmr(profile: profile),
            goal: goal.title,
            recentWeeklyWorkouts: recentWeeklyWorkouts,
            avgDailySteps: avgDailySteps,
            targetWeightKg: targetWeight.doubleValue,
            targetWeeks: targetWeeks == 0 ? nil : targetWeeks,
            activityLevel: activityLevel.title,
            trainingDaysPerWeek: trainingDaysPerWeek,
            trainingExperience: trainingExperience.title,
            trainingTypePreference: trainingTypePreference.trimmingCharacters(in: .whitespacesAndNewlines),
            dietPreference: dietPreference.trimmingCharacters(in: .whitespacesAndNewlines),
            sleepHours: sleepHours.doubleValue,
            extraNote: extraNote.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    private func resolvedBMI(weight: Double, profile: UserProfile) -> Double? {
        if let manual = bmi.doubleValue { return manual }
        let heightM = profile.heightCm / 100
        guard heightM > 0 else { return nil }
        return weight / (heightM * heightM)
    }

    private func save() {
        guard let finalResult = result else {
            errorMessage = "请先生成训练计划"
            return
        }
        guard let profile else {
            errorMessage = "请先在「设置」完善个人资料"
            return
        }

        let input = buildInput(profile: profile)
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let planTitle = trimmedTitle.isEmpty ? defaultTitle : trimmedTitle

        if let plan {
            plan.title = planTitle
            plan.goal = goal
            plan.input = input
            plan.result = finalResult
            plan.dailyCalories = finalResult.dailyCalories
            plan.proteinGrams = finalResult.proteinGrams
            plan.carbsGrams = finalResult.carbsGrams
            plan.fatGrams = finalResult.fatGrams
            plan.trainingDaysPerWeek = trainingDaysPerWeek
            plan.summary = finalResult.summary
            plan.updatedAt = .now
        } else {
            modelContext.insert(TrainingPlan(
                title: planTitle,
                goal: goal,
                input: input,
                result: finalResult,
                dailyCalories: finalResult.dailyCalories,
                proteinGrams: finalResult.proteinGrams,
                carbsGrams: finalResult.carbsGrams,
                fatGrams: finalResult.fatGrams,
                trainingDaysPerWeek: trainingDaysPerWeek,
                summary: finalResult.summary
            ))
        }

        do {
            try modelContext.save()
            dismiss()
        } catch {
            AppLog.error("保存训练计划失败：\(error.localizedDescription)", category: "训练计划")
            errorMessage = "保存训练计划失败：\(error.localizedDescription)"
        }
    }

    @ViewBuilder
    private func placeholderEditor(text: Binding<String>, placeholder: String, field: FocusedField) -> some View {
        TextEditor(text: text)
            .frame(minHeight: 80)
            .focused($focusedField, equals: field)
            .overlay(alignment: .topLeading) {
                if text.wrappedValue.isEmpty {
                    Text(placeholder)
                        .foregroundStyle(.secondary)
                        .padding(.top, 8)
                        .allowsHitTesting(false)
                }
            }
    }

    private static func numberText(_ value: Double?, decimals: Int) -> String {
        guard let value, value > 0 else { return "" }
        return String(format: "%.\(decimals)f", value)
    }
}

// MARK: - 列表卡片

struct TrainingPlanCard: View {
    let plan: TrainingPlan

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(plan.title.isEmpty ? "训练计划" : plan.title)
                    .font(.headline)
                    .lineLimit(1)
                Text(plan.goal.title)
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.secondary.opacity(0.12))
                    .clipShape(Capsule())
                Spacer()
                if plan.dailyCalories > 0 {
                    Text(plan.dailyCalories.kcalText)
                        .font(.subheadline.weight(.semibold))
                }
            }
            HStack(spacing: 12) {
                Label("\(plan.trainingDaysPerWeek) 天/周", systemImage: "calendar")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                MacroLabel(name: "蛋白", grams: plan.proteinGrams, color: .macroProtein)
                MacroLabel(name: "碳水", grams: plan.carbsGrams, color: .macroCarbs)
                MacroLabel(name: "脂肪", grams: plan.fatGrams, color: .macroFat)
            }
            if plan.macroEnergyTotal > 0 {
                MacroRatioBar(
                    proteinRatio: plan.proteinEnergyRatio,
                    carbsRatio: plan.carbsEnergyRatio,
                    fatRatio: plan.fatEnergyRatio
                )
            }
            if !plan.summary.isEmpty {
                Text(plan.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 6)
    }
}

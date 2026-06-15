import SwiftData
import SwiftUI

struct ExerciseView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ExerciseEntry.date, order: .reverse) private var exercises: [ExerciseEntry]
    @State private var showingNewEntry = false
    @State private var editingExercise: ExerciseEntry?

    /// 按「自然日」分组，日期倒序；组内再按时间倒序。
    private var groupedExercises: [(day: Date, exercises: [ExerciseEntry])] {
        let groups = Dictionary(grouping: exercises) { Calendar.current.startOfDay(for: $0.date) }
        return groups.keys.sorted(by: >).map { day in
            (day: day, exercises: (groups[day] ?? []).sorted { $0.date > $1.date })
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if exercises.isEmpty {
                    ContentUnavailableView {
                        Label("还没有运动记录", systemImage: "figure.run")
                    } description: {
                        Text("Apple 健康会自动同步活动数据，也可点击右上角 + 手动补录运动。")
                    } actions: {
                        NavigationLink {
                            TrainingPlanListView()
                        } label: {
                            Label("制定训练计划", systemImage: "figure.strengthtraining.traditional")
                        }
                        .buttonStyle(.borderedProminent)
                        Button {
                            showingNewEntry = true
                        } label: {
                            Label("手动补录", systemImage: "plus")
                        }
                        .buttonStyle(.bordered)
                    }
                } else {
                    List {
                        Section {
                            NavigationLink {
                                TrainingPlanListView()
                            } label: {
                                Label("训练计划制定", systemImage: "figure.strengthtraining.traditional")
                            }
                        }

                        ForEach(groupedExercises, id: \.day) { group in
                            Section(DateFormatter.dateHeader.string(from: group.day)) {
                                ForEach(group.exercises) { exercise in
                                    if exercise.source == .manual {
                                        Button {
                                            editingExercise = exercise
                                        } label: {
                                            ExerciseRow(exercise: exercise)
                                        }
                                        .buttonStyle(.plain)
                                        .swipeActions(edge: .trailing) {
                                            Button(role: .destructive) {
                                                delete(exercise)
                                            } label: {
                                                Label("删除", systemImage: "trash")
                                            }
                                        }
                                    } else {
                                        ExerciseRow(exercise: exercise)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("运动")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingNewEntry = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("手动补录运动")
                }
            }
            .sheet(isPresented: $showingNewEntry) {
                ManualExerciseEditorView()
            }
            .sheet(item: $editingExercise) { exercise in
                ManualExerciseEditorView(exercise: exercise)
            }
        }
    }

    private func delete(_ exercise: ExerciseEntry) {
        modelContext.delete(exercise)
        try? modelContext.save()
    }
}

/// 运动列表行：类型/热量 + 来源标签 + 时间 + 步数 + 时长。
private struct ExerciseRow: View {
    let exercise: ExerciseEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(exercise.workoutType.isEmpty ? "运动" : exercise.workoutType)
                    .font(.headline)
                Spacer()
                Text(exercise.activeCalories.kcalText)
                    .font(.headline)
            }
            HStack(spacing: 10) {
                sourceBadge
                Text(DateFormatter.shortTime.string(from: exercise.date))
                if exercise.steps > 0 {
                    Label("\(Int(exercise.steps.rounded()))", systemImage: "shoeprints.fill")
                }
                if exercise.durationMinutes > 0 {
                    Label("\(Int(exercise.durationMinutes.rounded())) 分钟", systemImage: "clock")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var sourceBadge: some View {
        let isHealth = exercise.source == .healthKit
        Label(exercise.source.title, systemImage: isHealth ? "heart.fill" : "hand.tap.fill")
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background((isHealth ? Color.pink : Color.blue).opacity(0.15), in: Capsule())
            .foregroundStyle(isHealth ? Color.pink : Color.blue)
    }
}

struct ManualExerciseEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    /// 非空表示编辑既有记录，nil 表示新增。
    private let editingExercise: ExerciseEntry?

    @State private var date: Date
    @State private var workoutType: String
    @State private var duration: String
    @State private var activeCalories: String
    @State private var steps: String
    @State private var errorMessage: String?

    private let presetTypes = ["快走", "跑步", "骑行", "力量训练", "游泳", "瑜伽", "椭圆机", "跳绳", "其他"]

    init(exercise: ExerciseEntry? = nil) {
        self.editingExercise = exercise
        _date = State(initialValue: exercise?.date ?? .now)
        _workoutType = State(initialValue: exercise?.workoutType ?? "快走")
        _duration = State(initialValue: Self.numberText(exercise?.durationMinutes, fallback: "30"))
        _activeCalories = State(initialValue: Self.numberText(exercise?.activeCalories, fallback: ""))
        _steps = State(initialValue: Self.numberText(exercise?.steps, fallback: ""))
    }

    private var isEditing: Bool { editingExercise != nil }

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

                Section {
                    DatePicker("时间", selection: $date)
                    HStack {
                        TextField("类型", text: $workoutType)
                        Menu {
                            ForEach(presetTypes, id: \.self) { type in
                                Button(type) { workoutType = type }
                            }
                        } label: {
                            Image(systemName: "chevron.down.circle")
                                .foregroundStyle(.secondary)
                        }
                    }
                    TextField("时长 分钟", text: $duration)
                        .keyboardType(.decimalPad)
                    TextField("活动热量 kcal", text: $activeCalories)
                        .keyboardType(.decimalPad)
                    TextField("步数", text: $steps)
                        .keyboardType(.numberPad)
                } header: {
                    Text("运动")
                } footer: {
                    if activeCalories.doubleValue == nil {
                        Text("请填写活动热量（kcal），用于计算今日热量差。")
                            .foregroundStyle(.orange)
                    }
                }
            }
            .navigationTitle(isEditing ? "编辑运动" : "补录运动")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .disabled(activeCalories.doubleValue == nil)
                }
            }
        }
    }

    private func save() {
        if let editingExercise {
            editingExercise.date = date
            editingExercise.workoutType = workoutType
            editingExercise.durationMinutes = duration.doubleValue ?? 0
            editingExercise.activeCalories = activeCalories.doubleValue ?? 0
            editingExercise.steps = steps.doubleValue ?? 0
        } else {
            modelContext.insert(ExerciseEntry(
                date: date,
                source: .manual,
                workoutType: workoutType,
                durationMinutes: duration.doubleValue ?? 0,
                activeCalories: activeCalories.doubleValue ?? 0,
                steps: steps.doubleValue ?? 0
            ))
        }

        do {
            try modelContext.save()
            dismiss()
        } catch {
            AppLog.error("保存运动记录失败：\(error.localizedDescription)", category: "运动")
            errorMessage = error.localizedDescription
        }
    }

    /// 编辑时把已有数值填入；新增时用 fallback（nil 或 0 视为未填）。
    private static func numberText(_ value: Double?, fallback: String) -> String {
        guard let value else { return fallback }
        return value > 0 ? String(format: "%.0f", value) : ""
    }
}

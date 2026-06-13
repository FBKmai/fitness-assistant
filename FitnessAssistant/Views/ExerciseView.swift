import SwiftData
import SwiftUI

struct ExerciseView: View {
    @Query(sort: \ExerciseEntry.date, order: .reverse) private var exercises: [ExerciseEntry]
    @State private var showingManualEntry = false

    var body: some View {
        NavigationStack {
            List {
                ForEach(exercises) { exercise in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(exercise.workoutType.isEmpty ? "运动" : exercise.workoutType)
                                .font(.headline)
                            Spacer()
                            Text(exercise.activeCalories.kcalText)
                                .font(.headline)
                        }
                        HStack {
                            Text(exercise.source.title)
                            Text(DateFormatter.csvDateTime.string(from: exercise.date))
                            if exercise.steps > 0 {
                                Text("\(Int(exercise.steps.rounded())) 步")
                            }
                            if exercise.durationMinutes > 0 {
                                Text("\(Int(exercise.durationMinutes.rounded())) 分钟")
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle("运动")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingManualEntry = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("手动补录运动")
                }
            }
            .sheet(isPresented: $showingManualEntry) {
                ManualExerciseEditorView()
            }
        }
    }
}

struct ManualExerciseEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var date = Date.now
    @State private var workoutType = "快走"
    @State private var duration = "30"
    @State private var activeCalories = ""
    @State private var steps = ""
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("运动") {
                    DatePicker("时间", selection: $date)
                    TextField("类型", text: $workoutType)
                    TextField("时长 分钟", text: $duration)
                        .keyboardType(.decimalPad)
                    TextField("活动热量 kcal", text: $activeCalories)
                        .keyboardType(.decimalPad)
                    TextField("步数", text: $steps)
                        .keyboardType(.numberPad)
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("补录运动")
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
        modelContext.insert(ExerciseEntry(
            date: date,
            source: .manual,
            workoutType: workoutType,
            durationMinutes: duration.doubleValue ?? 0,
            activeCalories: activeCalories.doubleValue ?? 0,
            steps: steps.doubleValue ?? 0
        ))

        do {
            try modelContext.save()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

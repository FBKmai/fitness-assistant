import PhotosUI
import SwiftData
import SwiftUI
import UIKit

struct MealsView: View {
    @Query(sort: \MealEntry.date, order: .reverse) private var meals: [MealEntry]
    @State private var showingEditor = false

    var body: some View {
        NavigationStack {
            List {
                ForEach(meals) { meal in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(DateFormatter.csvDateTime.string(from: meal.date))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(meal.totalCalories.kcalText)
                                .font(.headline)
                        }
                        Text(meal.textDescription.isEmpty ? "未填写描述" : meal.textDescription)
                            .lineLimit(2)
                        HStack {
                            Text("蛋白 \(meal.proteinGrams, specifier: "%.1f")g")
                            Text("碳水 \(meal.carbsGrams, specifier: "%.1f")g")
                            Text("脂肪 \(meal.fatGrams, specifier: "%.1f")g")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle("饮食")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingEditor = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("新增饮食")
                }
            }
            .sheet(isPresented: $showingEditor) {
                MealEditorView()
            }
        }
    }
}

struct MealEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var aiClient: AIClient

    @Query private var settings: [AISettings]

    @State private var textDescription = ""
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var imageData: Data?
    @State private var showingCamera = false
    @State private var totalCalories = ""
    @State private var proteinGrams = ""
    @State private var carbsGrams = ""
    @State private var fatGrams = ""
    @State private var confidence = 0.0
    @State private var items: [MealFoodItem] = []
    @State private var isEstimating = false
    @State private var errorMessage: String?

    private var canEstimate: Bool {
        !textDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || imageData != nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("记录") {
                    TextEditor(text: $textDescription)
                        .frame(minHeight: 96)
                    PhotosPicker(selection: $selectedPhoto, matching: .images) {
                        Label("从相册选择", systemImage: "photo")
                    }
                    Button {
                        showingCamera = true
                    } label: {
                        Label("拍照", systemImage: "camera")
                    }

                    if let imageData, let image = UIImage(data: imageData) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 220)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }

                Section("AI 估算") {
                    Button {
                        Task { await estimate() }
                    } label: {
                        Label(isEstimating ? "估算中" : "估算热量", systemImage: "sparkles")
                    }
                    .disabled(!canEstimate || isEstimating)

                    TextField("总热量 kcal", text: $totalCalories)
                        .keyboardType(.decimalPad)
                    TextField("蛋白质 g", text: $proteinGrams)
                        .keyboardType(.decimalPad)
                    TextField("碳水 g", text: $carbsGrams)
                        .keyboardType(.decimalPad)
                    TextField("脂肪 g", text: $fatGrams)
                        .keyboardType(.decimalPad)
                    LabeledContent("置信度", value: String(format: "%.0f%%", confidence * 100))
                }

                if !items.isEmpty {
                    Section("食物明细") {
                        ForEach(items) { item in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.name)
                                    .font(.headline)
                                Text("\(item.calories.kcalText)  蛋白 \(item.proteinGrams, specifier: "%.1f")g  碳水 \(item.carbsGrams, specifier: "%.1f")g  脂肪 \(item.fatGrams, specifier: "%.1f")g")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                if !item.note.isEmpty {
                                    Text(item.note)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("新增饮食")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("确认保存") { save() }
                        .disabled(totalCalories.doubleValue == nil)
                }
            }
            .onChange(of: selectedPhoto) { _, newValue in
                Task { await loadPhoto(newValue) }
            }
            .sheet(isPresented: $showingCamera) {
                CameraPicker { image in
                    imageData = ImageStorage.compressedJPEGData(from: image)
                }
            }
        }
    }

    @MainActor
    private func loadPhoto(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        do {
            if let data = try await item.loadTransferable(type: Data.self),
               let image = UIImage(data: data) {
                imageData = ImageStorage.compressedJPEGData(from: image)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func estimate() async {
        guard let aiSettings = settings.first else { return }
        isEstimating = true
        errorMessage = nil
        defer { isEstimating = false }

        do {
            let estimate = try await aiClient.estimateMeal(
                text: textDescription,
                imageData: imageData,
                settings: aiSettings
            )
            totalCalories = String(format: "%.0f", estimate.totalCalories)
            proteinGrams = String(format: "%.1f", estimate.proteinGrams)
            carbsGrams = String(format: "%.1f", estimate.carbsGrams)
            fatGrams = String(format: "%.1f", estimate.fatGrams)
            confidence = estimate.confidence
            items = estimate.items
            if textDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                textDescription = estimate.summary
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func save() {
        do {
            let photoFileName: String?
            if let imageData {
                photoFileName = try ImageStorage.saveMealPhoto(data: imageData)
            } else {
                photoFileName = nil
            }

            modelContext.insert(MealEntry(
                date: .now,
                textDescription: textDescription,
                photoLocalPath: photoFileName,
                estimatedItems: items,
                totalCalories: totalCalories.doubleValue ?? 0,
                proteinGrams: proteinGrams.doubleValue ?? 0,
                carbsGrams: carbsGrams.doubleValue ?? 0,
                fatGrams: fatGrams.doubleValue ?? 0,
                confidence: confidence,
                isConfirmed: true
            ))
            try modelContext.save()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

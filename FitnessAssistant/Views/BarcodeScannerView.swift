import SwiftData
import SwiftUI
import VisionKit

/// VisionKit 条码扫描封装。仅在支持的真机可用（模拟器 / 无相机或神经引擎的设备 isSupported=false）。
@available(iOS 16.0, *)
struct BarcodeScannerRepresentable: UIViewControllerRepresentable {
    var onScan: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let controller = DataScannerViewController(
            recognizedDataTypes: [.barcode()],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false,
            isHighlightingEnabled: true
        )
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: DataScannerViewController, context: Context) {
        try? uiViewController.startScanning()
    }

    static func dismantleUIViewController(_ uiViewController: DataScannerViewController, coordinator: Coordinator) {
        uiViewController.stopScanning()
    }

    func makeCoordinator() -> Coordinator { Coordinator(onScan: onScan) }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onScan: (String) -> Void
        private var handled = false
        init(onScan: @escaping (String) -> Void) { self.onScan = onScan }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            emit(addedItems)
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didTapOn item: RecognizedItem) {
            emit([item])
        }

        private func emit(_ items: [RecognizedItem]) {
            guard !handled else { return }
            for item in items {
                if case let .barcode(barcode) = item, let value = barcode.payloadStringValue, !value.isEmpty {
                    handled = true
                    onScan(value)
                    return
                }
            }
        }
    }
}

/// 扫码记餐：扫包装条码 → 命中已绑定该条码的食物卡 → 一键记入当天；未命中则提示去新建并绑定条码。
struct BarcodeQuickLogSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \FoodOption.updatedAt, order: .reverse) private var foodOptions: [FoodOption]

    let date: Date

    @State private var scannedCode: String?
    @State private var notFound = false
    @State private var loggedName: String?

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("扫码记餐")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("关闭") { dismiss() }
                    }
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        if let loggedName {
            resultState(
                icon: "checkmark.circle.fill",
                color: .green,
                title: "已记录",
                message: "已把「\(loggedName)」记入今天。"
            )
        } else if notFound, let scannedCode {
            VStack(spacing: 14) {
                Image(systemName: "barcode.viewfinder")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
                Text("未找到该条码对应的食物卡")
                    .font(.headline)
                Text("条码：\(scannedCode)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                Text("去「食物 → 常吃食物选项」拍营养成分表新建一张卡，在卡片里填入此条码；以后扫码即可一键记入。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("重新扫码") { reset() }
                    .buttonStyle(.bordered)
            }
            .padding()
        } else {
            scanner
        }
    }

    @ViewBuilder
    private var scanner: some View {
        if #available(iOS 16.0, *), DataScannerViewController.isSupported, DataScannerViewController.isAvailable {
            BarcodeScannerRepresentable { code in handle(code) }
                .overlay(alignment: .bottom) {
                    Text("对准包装上的条码")
                        .font(.caption)
                        .padding(8)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(.bottom, 24)
                }
        } else {
            ContentUnavailableView(
                "此设备不支持扫码",
                systemImage: "barcode.viewfinder",
                description: Text("请在真机上使用，或在「常吃食物选项」里手动选择。")
            )
        }
    }

    private func resultState(icon: String, color: Color, title: String, message: String) -> some View {
        VStack(spacing: 14) {
            Image(systemName: icon).font(.largeTitle).foregroundStyle(color)
            Text(title).font(.headline)
            Text(message).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button("完成") { dismiss() }.buttonStyle(.borderedProminent)
        }
        .padding()
    }

    private func handle(_ code: String) {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        scannedCode = trimmed
        if let option = foodOptions.first(where: { !$0.barcode.isEmpty && $0.barcode == trimmed }) {
            logMeal(option)
        } else {
            notFound = true
        }
    }

    private func logMeal(_ option: FoodOption) {
        let meal = MealEntry(
            date: date,
            mealType: Self.guessMealType(date),
            textDescription: option.name,
            foodOptionIDs: [option.id],
            estimatedItems: option.mealItems(),
            totalCalories: option.totalCalories,
            proteinGrams: option.proteinGrams,
            carbsGrams: option.carbsGrams,
            fatGrams: option.fatGrams,
            fiberGrams: option.fiberGrams,
            confidence: 0.8,
            isConfirmed: true
        )
        modelContext.insert(meal)
        do {
            try modelContext.save()
            loggedName = option.name
        } catch {
            AppLog.error("扫码记餐保存失败：\(error.localizedDescription)", category: "食物")
        }
    }

    private func reset() {
        scannedCode = nil
        notFound = false
    }

    static func guessMealType(_ date: Date) -> MealType {
        switch Calendar.current.component(.hour, from: date) {
        case 5..<10: return .breakfast
        case 10..<15: return .lunch
        case 15..<17: return .snack
        case 17..<22: return .dinner
        default: return .snack
        }
    }
}

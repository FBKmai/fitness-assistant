import Combine
import Foundation

/// 日志级别。
enum AppLogLevel: String, Codable {
    case error = "错误"
    case warning = "警告"
    case info = "信息"
}

/// 单条日志记录。
struct AppLogEntry: Codable, Identifiable {
    var id: UUID = UUID()
    var date: Date = .now
    var level: AppLogLevel
    var category: String
    var message: String
}

/// 全局调试日志存储：集中收集 App 运行时的报错（AI 调用、网络、数据保存等），
/// 持久化到本地文件，供「更多 → 调试日志」页面查看。单例，主线程访问。
@MainActor
final class AppLogStore: ObservableObject {
    static let shared = AppLogStore()

    @Published private(set) var entries: [AppLogEntry] = []

    /// 最多保留的条数，避免文件无限增长。
    private let maxEntries = 400
    private let fileURL: URL?

    private init() {
        let directory = try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        fileURL = directory?.appendingPathComponent("app_debug_log.json")
        load()
    }

    func add(_ entry: AppLogEntry) {
        entries.append(entry)
        if entries.count > maxEntries {
            entries.removeFirst(entries.count - maxEntries)
        }
        persist()
    }

    func clear() {
        entries.removeAll()
        persist()
    }

    /// 导出为纯文本（最新在最上面），便于复制发给开发者。
    var exportText: String {
        entries.reversed().map { entry in
            "[\(Self.timeFormatter.string(from: entry.date))] [\(entry.level.rawValue)] [\(entry.category)] \(entry.message)"
        }.joined(separator: "\n\n")
    }

    static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "MM-dd HH:mm:ss"
        return formatter
    }()

    private func load() {
        guard let fileURL, let data = try? Data(contentsOf: fileURL) else { return }
        if let decoded = try? JSONDecoder().decode([AppLogEntry].self, from: data) {
            entries = decoded
        }
    }

    private func persist() {
        guard let fileURL else { return }
        do {
            let data = try JSONEncoder().encode(entries)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            // 持久化失败不影响主流程，忽略即可。
        }
    }
}

/// 全局日志门面：可从任意线程 / actor 调用，内部自动切回主线程写入。
enum AppLog {
    static func error(_ message: String, category: String = "通用") {
        record(message, category: category, level: .error)
    }

    static func warning(_ message: String, category: String = "通用") {
        record(message, category: category, level: .warning)
    }

    static func info(_ message: String, category: String = "通用") {
        record(message, category: category, level: .info)
    }

    private static func record(_ message: String, category: String, level: AppLogLevel) {
        let entry = AppLogEntry(level: level, category: category, message: message)
        Task { @MainActor in
            AppLogStore.shared.add(entry)
        }
    }
}

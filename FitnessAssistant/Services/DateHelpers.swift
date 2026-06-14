import Foundation

extension Calendar {
    func dayInterval(containing date: Date) -> DateInterval {
        let start = startOfDay(for: date)
        let end = self.date(byAdding: .day, value: 1, to: start) ?? date
        return DateInterval(start: start, end: end)
    }

    func todayAt(hour: Int, minute: Int) -> Date {
        var components = dateComponents([.year, .month, .day], from: .now)
        components.hour = hour
        components.minute = minute
        return date(from: components) ?? .now
    }
}

extension DateFormatter {
    static let shortTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    static let csvDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    static let csvDateTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()

    /// 列表按天分组的分区标题，如「6月14日 周六」。
    static let dateHeader: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日 EEEE"
        return formatter
    }()
}

extension Date {
    var dayKey: String {
        DateFormatter.csvDate.string(from: self)
    }
}

extension String {
    var doubleValue: Double? {
        Double(replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespacesAndNewlines))
    }
}

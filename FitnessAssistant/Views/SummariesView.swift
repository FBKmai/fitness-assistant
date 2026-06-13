import SwiftData
import SwiftUI

struct SummariesView: View {
    @Query(sort: \DailySummary.date, order: .reverse) private var summaries: [DailySummary]

    var body: some View {
        NavigationStack {
            List {
                ForEach(summaries) { summary in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(DateFormatter.csvDate.string(from: summary.date))
                                .font(.headline)
                            Spacer()
                            Text(summary.calorieDeficit.signedKcalText)
                                .font(.headline)
                        }
                        HStack {
                            Text("摄入 \(summary.intakeCalories.kcalText)")
                            Text("消耗 \(summary.totalBurnCalories.kcalText)")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        Text(summary.adviceText)
                            .font(.body)
                            .lineLimit(5)
                    }
                    .padding(.vertical, 6)
                }
            }
            .navigationTitle("总结")
        }
    }
}

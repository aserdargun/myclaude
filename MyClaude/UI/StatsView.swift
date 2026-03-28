import SwiftUI

struct StatsView: View {
    let weeklyStats: WeeklyStats
    let todayStats: DailyStats

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Today
            SectionHeader(title: "Today", icon: "calendar")

            StatRow(label: "Tokens", value: formatTokens(todayStats.totalTokens))
            StatRow(label: "Events", value: "\(todayStats.eventCount)")
            StatRow(label: "Sessions", value: "\(todayStats.sessionCount)")

            Divider()

            // Weekly
            SectionHeader(title: "This Week", icon: "chart.bar")

            StatRow(label: "Total Tokens", value: formatTokens(weeklyStats.totalTokens))
            StatRow(label: "Total Events", value: "\(weeklyStats.totalEvents)")
            StatRow(label: "Sessions", value: "\(weeklyStats.totalSessions)")

            // Daily breakdown
            if !weeklyStats.dailyBreakdown.isEmpty {
                Divider()
                SectionHeader(title: "Daily Breakdown", icon: "list.bullet")

                ForEach(weeklyStats.dailyBreakdown) { day in
                    HStack {
                        Text(day.date.dayOfWeekString)
                            .font(.caption2)
                            .frame(width: 30, alignment: .leading)
                        Text(day.date.shortDateString)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .frame(width: 45, alignment: .leading)

                        ProgressBarView(
                            progress: maxDailyProgress(day.totalTokens),
                            color: .blue
                        )
                        .frame(height: 6)

                        Text(formatTokens(day.totalTokens))
                            .font(.caption2)
                            .frame(width: 50, alignment: .trailing)
                    }
                }
            }
        }
    }

    private func formatTokens(_ count: Int) -> String {
        if count >= 1_000_000 {
            return String(format: "%.1fM", Double(count) / 1_000_000)
        } else if count >= 1_000 {
            return String(format: "%.1fK", Double(count) / 1_000)
        }
        return "\(count)"
    }

    private func maxDailyProgress(_ tokens: Int) -> Double {
        let maxTokens = weeklyStats.dailyBreakdown.map(\.totalTokens).max() ?? 1
        guard maxTokens > 0 else { return 0 }
        return Double(tokens) / Double(maxTokens)
    }
}

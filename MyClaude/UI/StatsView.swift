import SwiftUI

struct StatsView: View {
    let weeklyStats: WeeklyStats
    let todayStats: DailyStats
    let todaySessionCount: Int
    let estimatedTodayPercent: Double?
    let estimatedWeeklyPercent: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Today
            SectionHeader(title: "Today", icon: "calendar")

            HStack {
                StatRow(label: "Tokens", value: formatTokens(todayStats.totalTokens))
                if let pct = estimatedTodayPercent {
                    Text("(\(Int(min(pct, 100)))%)")
                        .font(.caption2)
                        .foregroundStyle(.blue)
                }
            }
            StatRow(label: "Events", value: "\(todayStats.eventCount)")
            StatRow(label: "Sessions", value: "\(todaySessionCount)")

            Divider()

            // Weekly
            SectionHeader(title: "This Week", icon: "chart.bar")

            HStack {
                StatRow(label: "Total Tokens", value: formatTokens(weeklyStats.totalTokens))
                if let pct = estimatedWeeklyPercent {
                    Text("(\(Int(min(pct, 100)))%)")
                        .font(.caption2)
                        .foregroundStyle(.blue)
                }
            }
            StatRow(label: "Total Events", value: "\(weeklyStats.totalEvents)")
            StatRow(label: "Sessions", value: "\(weeklyStats.totalSessions)")

            // Daily breakdown (Sun to Sat)
            if !weeklyStats.dailyBreakdown.isEmpty {
                Divider()
                SectionHeader(title: "Daily Breakdown", icon: "list.bullet")

                ForEach(weeklyStats.dailyBreakdown) { day in
                    HStack(spacing: 4) {
                        Text(day.date.dayOfWeekString)
                            .font(.caption2)
                            .frame(width: 28, alignment: .leading)
                            .foregroundStyle(isToday(day.date) ? .primary : .secondary)
                        Text(day.date.shortDateString)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .frame(width: 45, alignment: .leading)

                        ProgressBarView(
                            progress: maxDailyProgress(day.totalTokens),
                            color: dayBarColor(day.date)
                        )
                        .frame(height: 6)

                        Text(formatTokens(day.totalTokens))
                            .font(.caption2)
                            .fontWeight(isToday(day.date) ? .semibold : .regular)
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

    private func isToday(_ date: Date) -> Bool {
        Calendar.current.isDateInToday(date)
    }

    private func dayBarColor(_ date: Date) -> Color {
        if isToday(date) {
            return .green
        }
        return .blue
    }
}

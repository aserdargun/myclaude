import SwiftUI

struct StatsView: View {
    let viewModel: UsageViewModel
    let hasCalibration: Bool

    @State private var weekOffset: Int = 0

    private var currentTokens: Int { viewModel.currentTokens }
    private var currentEventCount: Int { viewModel.currentEventCount }
    private var todayStats: DailyStats { viewModel.todayStats }
    private var todaySessionCount: Int { viewModel.todaySessionCount }

    private var displayedWeekStats: WeeklyStats {
        weekOffset == 0 ? viewModel.weeklyStats : viewModel.weeklyStats(for: weekOffset)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Session Usage — only show when there's local data.
            // When calibrated with 0 local events, session usage is already
            // shown via browser scraping in the CLAUDE section above.
            if currentTokens > 0 || currentEventCount > 0 || !hasCalibration {
                localHeader("Session Usage", icon: "chart.pie")

                StatRow(
                    label: hasCalibration ? "Local Tokens" : "Tokens",
                    value: formatTokens(currentTokens)
                )
                StatRow(
                    label: hasCalibration ? "Local Events" : "Events",
                    value: "\(currentEventCount)"
                )
            }

            // Today (only for current week view)
            if weekOffset == 0 {
                localHeader("Today", icon: "calendar")

                StatRow(label: "Tokens", value: formatTokens(todayStats.totalTokens))
                StatRow(label: "Events", value: "\(todayStats.eventCount)")
                StatRow(label: "Sessions", value: "\(todaySessionCount)")
            }

            // Weekly header with navigation
            HStack {
                localHeader(weekOffset == 0 ? "This Week" : "Week", icon: "chart.bar")
                Spacer()
                weekNavigationButtons
            }

            StatRow(label: "Total Tokens", value: formatTokens(displayedWeekStats.totalTokens))
            StatRow(label: "Total Events", value: "\(displayedWeekStats.totalEvents)")
            StatRow(label: "Sessions", value: "\(displayedWeekStats.totalSessions)")

            // Daily breakdown with navigation
            if !displayedWeekStats.dailyBreakdown.isEmpty {
                HStack {
                    localHeader("Daily Breakdown", icon: "list.bullet")
                    Spacer()
                    if weekOffset != 0 {
                        weekRangeLabel
                    }
                }

                ForEach(displayedWeekStats.dailyBreakdown) { day in
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

    // MARK: - Week Navigation

    private var weekNavigationButtons: some View {
        HStack(spacing: 4) {
            Button {
                weekOffset -= 1
                NotificationCenter.default.post(name: .panelContentDidChange, object: nil)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .disabled(!viewModel.hasDataForWeek(offset: weekOffset - 1))

            Button {
                weekOffset = 0
                NotificationCenter.default.post(name: .panelContentDidChange, object: nil)
            } label: {
                Text(weekOffset == 0 ? "Current" : "Today")
                    .font(.caption2)
                    .foregroundColor(weekOffset == 0 ? .gray : .blue)
            }
            .buttonStyle(.borderless)
            .disabled(weekOffset == 0)

            Button {
                weekOffset += 1
                NotificationCenter.default.post(name: .panelContentDidChange, object: nil)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .disabled(weekOffset >= 0)
        }
    }

    private var weekRangeLabel: some View {
        Group {
            if let first = displayedWeekStats.dailyBreakdown.first,
               let last = displayedWeekStats.dailyBreakdown.last {
                Text("\(first.date.shortDateString) – \(last.date.shortDateString)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: - Helpers

    private func localHeader(_ title: String, icon: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2)
            Text(title)
                .font(.caption)
                .fontWeight(.semibold)
        }
        .foregroundStyle(.secondary)
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
        let maxTokens = displayedWeekStats.dailyBreakdown.map(\.totalTokens).max() ?? 1
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

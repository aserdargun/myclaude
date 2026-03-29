import Foundation

final class UsageAggregator {
    private var allEvents: [UsageEvent] = []

    // MARK: - Add events

    func addEvents(_ events: [UsageEvent]) {
        allEvents.append(contentsOf: events)
        // Keep sorted
        allEvents.sort { $0.timestamp < $1.timestamp }
        // Prune events older than 30 days
        let cutoff = Date().addingTimeInterval(-30 * 24 * 3600)
        allEvents.removeAll { $0.timestamp < cutoff }
    }

    // MARK: - Session stats

    func currentSessionUsage(session: UsageSession?) -> Int {
        guard let session else { return 0 }
        return session.totalTokens
    }

    func currentSessionEventCount(session: UsageSession?) -> Int {
        guard let session else { return 0 }
        return session.eventCount
    }

    // MARK: - Weekly stats (Monday to Sunday)

    func weeklyStats() -> WeeklyStats {
        let calendar = calendar_sundayStart
        let weekRange = currentWeekRange(calendar: calendar)

        let weekEvents = allEvents.filter {
            $0.timestamp >= weekRange.start && $0.timestamp < weekRange.end
        }

        // Build all 7 days (Sun through Sat), filtering events per day by range
        var dailyBreakdown: [DailyStats] = []
        for dayOffset in 0..<7 {
            guard let dayDate = calendar.date(byAdding: .day, value: dayOffset, to: weekRange.start) else { continue }
            let dayStart = calendar.startOfDay(for: dayDate)
            guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else { continue }

            let dayEvents = weekEvents.filter {
                $0.timestamp >= dayStart && $0.timestamp < dayEnd
            }
            dailyBreakdown.append(DailyStats(
                date: dayStart,
                totalTokens: dayEvents.compactMap(\.tokens).reduce(0, +),
                weightedTokens: dayEvents.compactMap(\.weightedTokens).reduce(0, +),
                eventCount: dayEvents.count,
                sessionCount: countSessions(in: dayEvents)
            ))
        }

        return WeeklyStats(
            dailyBreakdown: dailyBreakdown,
            totalTokens: weekEvents.compactMap(\.tokens).reduce(0, +),
            weightedTokens: weekEvents.compactMap(\.weightedTokens).reduce(0, +),
            totalEvents: weekEvents.count,
            totalSessions: dailyBreakdown.map(\.sessionCount).reduce(0, +)
        )
    }

    // MARK: - Range query

    /// Returns (tokens, weightedTokens, eventCount) for events within a given time range.
    func usage(from start: Date, to end: Date) -> (tokens: Int, weightedTokens: Int, events: Int) {
        let rangeEvents = allEvents.filter { $0.timestamp >= start && $0.timestamp < end }
        let tokens = rangeEvents.compactMap(\.tokens).reduce(0, +)
        let weighted = rangeEvents.compactMap(\.weightedTokens).reduce(0, +)
        return (tokens, weighted, rangeEvents.count)
    }

    // MARK: - Daily stats

    func todayStats() -> DailyStats {
        let todayEvents = allEvents.filter { $0.timestamp >= Date().startOfDay }
        return DailyStats(
            date: Date().startOfDay,
            totalTokens: todayEvents.compactMap(\.tokens).reduce(0, +),
            weightedTokens: todayEvents.compactMap(\.weightedTokens).reduce(0, +),
            eventCount: todayEvents.count,
            sessionCount: countSessions(in: todayEvents)
        )
    }

    // MARK: - Private

    /// Calendar configured with Sunday as first day of week.
    private var calendar_sundayStart: Calendar {
        var cal = Calendar.current
        cal.firstWeekday = 1 // Sunday
        return cal
    }

    /// Returns the date range for the current week (Sunday 00:00 to next Sunday 00:00).
    private func currentWeekRange(calendar: Calendar) -> (start: Date, end: Date) {
        let today = calendar.startOfDay(for: Date())
        let weekday = calendar.component(.weekday, from: today) // 1=Sun, 2=Mon, ..., 7=Sat
        // Days since Sunday: Sun=0, Mon=1, ..., Sat=6
        let daysSinceSunday = weekday - 1
        let sunday = calendar.date(byAdding: .day, value: -daysSinceSunday, to: today)!
        let nextSunday = calendar.date(byAdding: .day, value: 7, to: sunday)!
        return (sunday, nextSunday)
    }

    private func countSessions(in events: [UsageEvent]) -> Int {
        guard !events.isEmpty else { return 0 }
        let sorted = events.sorted { $0.timestamp < $1.timestamp }
        var sessions = 1
        var lastTime = sorted[0].timestamp

        for event in sorted.dropFirst() {
            if event.timestamp.timeIntervalSince(lastTime) > Constants.sessionDuration {
                sessions += 1
            }
            lastTime = event.timestamp
        }
        return sessions
    }
}

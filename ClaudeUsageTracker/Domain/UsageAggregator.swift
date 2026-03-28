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

    // MARK: - Weekly stats

    func weeklyStats() -> WeeklyStats {
        let calendar = Calendar.current
        let now = Date()
        let weekAgo = calendar.date(byAdding: .day, value: -7, to: now)!

        let weekEvents = allEvents.filter { $0.timestamp >= weekAgo }

        // Group by day
        var dayGroups: [Date: [UsageEvent]] = [:]
        for event in weekEvents {
            let day = event.timestamp.startOfDay
            dayGroups[day, default: []].append(event)
        }

        let dailyBreakdown: [DailyStats] = dayGroups.map { day, events in
            DailyStats(
                date: day,
                totalTokens: events.compactMap(\.tokens).reduce(0, +),
                eventCount: events.count,
                sessionCount: countSessions(in: events)
            )
        }.sorted { $0.date < $1.date }

        return WeeklyStats(
            dailyBreakdown: dailyBreakdown,
            totalTokens: weekEvents.compactMap(\.tokens).reduce(0, +),
            totalEvents: weekEvents.count,
            totalSessions: dailyBreakdown.map(\.sessionCount).reduce(0, +)
        )
    }

    // MARK: - Daily stats

    func todayStats() -> DailyStats {
        let todayEvents = allEvents.filter { $0.timestamp >= Date().startOfDay }
        return DailyStats(
            date: Date().startOfDay,
            totalTokens: todayEvents.compactMap(\.tokens).reduce(0, +),
            eventCount: todayEvents.count,
            sessionCount: countSessions(in: todayEvents)
        )
    }

    // MARK: - Private

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

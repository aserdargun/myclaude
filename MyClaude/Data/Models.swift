import Foundation

// MARK: - Usage Event

enum EventType: String, Codable {
    case request
    case response
    case error
    case unknown
}

struct UsageEvent: Codable, Identifiable {
    let id: UUID
    let timestamp: Date
    let tokens: Int?
    let type: EventType
    let model: String?
    let sessionId: String?

    init(
        id: UUID = UUID(),
        timestamp: Date,
        tokens: Int? = nil,
        type: EventType,
        model: String? = nil,
        sessionId: String? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.tokens = tokens
        self.type = type
        self.model = model
        self.sessionId = sessionId
    }
}

// MARK: - Rolling Window Session
//
// Claude uses a rolling 5-hour window: at any moment, your usage =
// sum of all activity in the past 5 hours. "Resets in X" means the
// oldest event in the window will age out in X time.

struct UsageSession: Identifiable {
    let id: UUID
    var events: [UsageEvent]

    /// Events that fall within the current 5-hour rolling window.
    var windowEvents: [UsageEvent] {
        let cutoff = Date().addingTimeInterval(-Constants.sessionDuration)
        return events.filter { $0.timestamp > cutoff }
    }

    /// The oldest event still inside the rolling window.
    var oldestWindowEvent: UsageEvent? {
        windowEvents.min(by: { $0.timestamp < $1.timestamp })
    }

    /// Time until the oldest event in the window ages out (= "resets in").
    var remainingTime: TimeInterval {
        guard let oldest = oldestWindowEvent else { return 0 }
        let expiresAt = oldest.timestamp.addingTimeInterval(Constants.sessionDuration)
        return max(0, expiresAt.timeIntervalSince(Date()))
    }

    /// Whether there are any events in the current rolling window.
    var isActive: Bool {
        !windowEvents.isEmpty
    }

    var totalTokens: Int {
        windowEvents.compactMap(\.tokens).reduce(0, +)
    }

    var eventCount: Int {
        windowEvents.count
    }

    init(id: UUID = UUID(), events: [UsageEvent] = []) {
        self.id = id
        self.events = events
    }
}

// MARK: - Stats

struct DailyStats: Identifiable {
    let id: UUID
    let date: Date
    let totalTokens: Int
    let eventCount: Int
    let sessionCount: Int

    init(
        id: UUID = UUID(),
        date: Date,
        totalTokens: Int,
        eventCount: Int,
        sessionCount: Int
    ) {
        self.id = id
        self.date = date
        self.totalTokens = totalTokens
        self.eventCount = eventCount
        self.sessionCount = sessionCount
    }
}

struct WeeklyStats {
    let dailyBreakdown: [DailyStats]
    let totalTokens: Int
    let totalEvents: Int
    let totalSessions: Int
}

// MARK: - Alert

enum AlertLevel: Comparable {
    case safe
    case warning
    case critical
    case expired
}

struct UsageAlert: Identifiable {
    let id: UUID
    let level: AlertLevel
    let message: String
    let timestamp: Date

    init(id: UUID = UUID(), level: AlertLevel, message: String, timestamp: Date = Date()) {
        self.id = id
        self.level = level
        self.message = message
        self.timestamp = timestamp
    }
}

// MARK: - Log Entry (raw)

struct RawLogEntry {
    let line: String
    let filePath: String
    let lineNumber: Int
}

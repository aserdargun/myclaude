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

// MARK: - Session

struct UsageSession: Identifiable {
    let id: UUID
    let startTime: Date
    var events: [UsageEvent]

    var endTime: Date {
        startTime.addingTimeInterval(Constants.sessionDuration)
    }

    var isExpired: Bool {
        Date() >= endTime
    }

    var remainingTime: TimeInterval {
        max(0, endTime.timeIntervalSince(Date()))
    }

    var totalTokens: Int {
        events.compactMap(\.tokens).reduce(0, +)
    }

    var eventCount: Int {
        events.count
    }

    init(id: UUID = UUID(), startTime: Date, events: [UsageEvent] = []) {
        self.id = id
        self.startTime = startTime
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

import Foundation

// MARK: - Usage Event

enum EventType: String, Codable, Sendable {
    case request
    case response
    case error
    case unknown
}

struct UsageEvent: Codable, Identifiable, Sendable {
    let id: UUID
    let timestamp: Date
    let tokens: Int?
    /// Cost-weighted tokens approximating what Claude's rate limiter counts.
    /// Weights: output=1.0, input=0.25, cache_creation=0.3125, cache_read=0.025
    let weightedTokens: Int?
    let type: EventType
    let model: String?
    let sessionId: String?

    init(
        id: UUID = UUID(),
        timestamp: Date,
        tokens: Int? = nil,
        weightedTokens: Int? = nil,
        type: EventType,
        model: String? = nil,
        sessionId: String? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.tokens = tokens
        self.weightedTokens = weightedTokens
        self.type = type
        self.model = model
        self.sessionId = sessionId
    }
}

// MARK: - Usage Session
//
// Claude uses 5-hour session windows tracked server-side across all products
// (Chat, Cowork, Code). Since we only see Code CLI logs, we detect session
// boundaries by finding gaps (> 1h) in events. The first event after the
// last gap is treated as the session start, giving windowEnd = start + 5h.

struct UsageSession: Identifiable {
    let id: UUID
    let windowStart: Date
    var events: [UsageEvent]

    var windowEnd: Date {
        windowStart.addingTimeInterval(Constants.sessionDuration)
    }

    var isExpired: Bool {
        Date() >= windowEnd
    }

    var remainingTime: TimeInterval {
        max(0, windowEnd.timeIntervalSince(Date()))
    }

    var isActive: Bool {
        !isExpired
    }

    var totalTokens: Int {
        events.compactMap(\.tokens).reduce(0, +)
    }

    var totalWeightedTokens: Int {
        events.compactMap(\.weightedTokens).reduce(0, +)
    }

    var eventCount: Int {
        events.count
    }

    init(id: UUID = UUID(), windowStart: Date, events: [UsageEvent] = []) {
        self.id = id
        self.windowStart = windowStart
        self.events = events
    }
}

// MARK: - Stats

struct DailyStats: Identifiable {
    let id: UUID
    let date: Date
    let totalTokens: Int
    /// Cost-weighted tokens approximating rate-limiter impact.
    let weightedTokens: Int
    let eventCount: Int
    let sessionCount: Int

    init(
        id: UUID = UUID(),
        date: Date,
        totalTokens: Int,
        weightedTokens: Int = 0,
        eventCount: Int,
        sessionCount: Int
    ) {
        self.id = id
        self.date = date
        self.totalTokens = totalTokens
        self.weightedTokens = weightedTokens
        self.eventCount = eventCount
        self.sessionCount = sessionCount
    }
}

struct WeeklyStats {
    let dailyBreakdown: [DailyStats]
    let totalTokens: Int
    let weightedTokens: Int
    let totalEvents: Int
    let totalSessions: Int
}

// MARK: - Alert

enum AlertLevel: Comparable, Sendable {
    case safe
    case warning
    case critical
    case expired
}

struct UsageAlert: Identifiable, Sendable {
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

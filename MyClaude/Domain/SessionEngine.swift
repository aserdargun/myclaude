import Foundation

protocol SessionEngineDelegate: AnyObject {
    func sessionEngine(_ engine: SessionEngine, didUpdateSession session: UsageSession?)
}

final class SessionEngine {
    weak var delegate: SessionEngineDelegate?

    /// The current rolling-window session (events in the last 5 hours).
    private(set) var currentSession: UsageSession?

    /// Historical sessions detected via fixed-window walk (for counting).
    private(set) var allSessions: [UsageSession] = []

    /// All events ever received.
    private var allEvents: [UsageEvent] = []

    /// Deduplication keys.
    private var seenEventIDs: Set<String> = []

    private let sessionDuration: TimeInterval

    init(sessionDuration: TimeInterval = Constants.sessionDuration) {
        self.sessionDuration = sessionDuration
    }

    // MARK: - Public API

    func processEvents(_ events: [UsageEvent]) {
        var addedNew = false
        for event in events {
            let key = "\(event.timestamp.timeIntervalSince1970)-\(event.tokens ?? 0)"
            if seenEventIDs.insert(key).inserted {
                allEvents.append(event)
                addedNew = true
            }
        }

        guard addedNew else {
            delegate?.sessionEngine(self, didUpdateSession: currentSession)
            return
        }

        rebuildHistoricalSessions()
        updateRollingWindow()
        delegate?.sessionEngine(self, didUpdateSession: currentSession)
    }

    /// Called periodically to update the rolling window (events fall off over time).
    func tick() {
        updateRollingWindow()
    }

    // MARK: - Computed properties

    var remainingTime: TimeInterval {
        currentSession?.remainingTime ?? 0
    }

    var sessionProgress: Double {
        guard let session = currentSession else { return 0 }
        let elapsed = Date().timeIntervalSince(session.windowStart)
        return min(1.0, elapsed / sessionDuration)
    }

    var isActive: Bool {
        currentSession?.isActive ?? false
    }

    var hasSession: Bool {
        currentSession != nil
    }

    var currentAlertLevel: AlertLevel {
        guard let session = currentSession, session.isActive else { return .safe }

        let remaining = session.remainingTime
        if remaining <= Constants.thirtyMinWarning {
            return .critical
        } else if remaining <= Constants.oneHourWarning {
            return .warning
        }
        return .safe
    }

    /// Number of detected sessions today (uses historical fixed-window sessions).
    var todaySessionCount: Int {
        let startOfDay = Calendar.current.startOfDay(for: Date())
        return allSessions.filter { $0.windowStart >= startOfDay }.count
    }

    // MARK: - Rolling Window

    /// Updates `currentSession` as a rolling window: all events within the last 5 hours.
    /// windowStart = oldest event's timestamp → windowEnd = windowStart + 5h.
    /// "Resets in" = windowEnd − now = time until the oldest event falls off.
    private func updateRollingWindow() {
        let now = Date()
        let cutoff = now.addingTimeInterval(-sessionDuration)
        let recentEvents = allEvents
            .filter { $0.timestamp >= cutoff && $0.timestamp <= now }
            .sorted { $0.timestamp < $1.timestamp }

        if recentEvents.isEmpty {
            // No events in last 5h — show the most recent historical session (expired)
            currentSession = allSessions.last
        } else {
            let oldest = recentEvents.first!.timestamp
            currentSession = UsageSession(windowStart: oldest, events: recentEvents)
        }
    }

    // MARK: - Historical Sessions (Fixed Windows)

    /// Rebuilds fixed-window sessions for historical counting / stats.
    private func rebuildHistoricalSessions() {
        let sorted = allEvents.sorted { $0.timestamp < $1.timestamp }

        var sessions: [UsageSession] = []
        var current: UsageSession?

        for event in sorted {
            if let sess = current {
                if event.timestamp >= sess.windowEnd {
                    sessions.append(sess)
                    current = UsageSession(windowStart: event.timestamp, events: [event])
                } else if event.timestamp >= sess.windowStart {
                    current?.events.append(event)
                }
            } else {
                current = UsageSession(windowStart: event.timestamp, events: [event])
            }
        }

        if let sess = current {
            sessions.append(sess)
        }

        allSessions = sessions
    }
}

import Foundation

protocol SessionEngineDelegate: AnyObject {
    func sessionEngine(_ engine: SessionEngine, didUpdateSession session: UsageSession?)
}

final class SessionEngine {
    weak var delegate: SessionEngineDelegate?

    /// The current detected session (gap-based detection within rolling window).
    private(set) var currentSession: UsageSession?

    /// Historical sessions detected via fixed-window walk (for counting).
    private(set) var allSessions: [UsageSession] = []

    /// All events ever received.
    private var allEvents: [UsageEvent] = []

    /// Deduplication keys.
    private var seenEventIDs: Set<String> = []

    private let sessionDuration: TimeInterval

    /// Minimum gap between consecutive events to consider a session boundary.
    /// Claude's server tracks ALL product usage (Chat, Cowork, Code) but we only
    /// see Code CLI events. A gap > 1 hour in Code events likely means the user
    /// stopped coding and may have started a new server-side session via another
    /// product. When they resume Code, we treat it as a new session.
    private let sessionGapThreshold: TimeInterval = 60 * 60 // 1 hour

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
        updateCurrentSession()
        delegate?.sessionEngine(self, didUpdateSession: currentSession)
    }

    /// Called periodically — updates current session as events age out.
    func tick() {
        updateCurrentSession()
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

    // MARK: - Current Session Detection

    /// Detects the current session using gap-based analysis within the rolling window.
    ///
    /// Strategy: Look at events in the last 5 hours. Find the last significant gap
    /// (> 1 hour) between consecutive events. Events after that gap form the "current
    /// session." This approximates Claude's server-side session boundaries, which
    /// include Chat/Cowork/Code usage that we can't see in local CLI logs.
    ///
    /// windowStart = first event after the last gap → windowEnd = windowStart + 5h.
    /// "Resets in" = windowEnd − now.
    private func updateCurrentSession() {
        let now = Date()
        let cutoff = now.addingTimeInterval(-sessionDuration)
        let recentEvents = allEvents
            .filter { $0.timestamp >= cutoff && $0.timestamp <= now }
            .sorted { $0.timestamp < $1.timestamp }

        if recentEvents.isEmpty {
            // No events in last 5h — show the most recent historical session (expired)
            currentSession = allSessions.last
            return
        }

        // Walk backwards through events to find the last gap > threshold.
        // Events after that gap belong to the current session.
        var sessionStartIndex = 0
        for i in stride(from: recentEvents.count - 1, through: 1, by: -1) {
            let gap = recentEvents[i].timestamp.timeIntervalSince(recentEvents[i - 1].timestamp)
            if gap >= sessionGapThreshold {
                sessionStartIndex = i
                break
            }
        }

        let sessionEvents = Array(recentEvents[sessionStartIndex...])
        let windowStart = sessionEvents.first!.timestamp
        currentSession = UsageSession(windowStart: windowStart, events: sessionEvents)
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

import Foundation

protocol SessionEngineDelegate: AnyObject {
    func sessionEngine(_ engine: SessionEngine, didUpdateSession session: UsageSession?)
}

final class SessionEngine {
    weak var delegate: SessionEngineDelegate?

    /// The current or most recent session window.
    private(set) var currentSession: UsageSession?

    /// All detected session windows (including current).
    private(set) var allSessions: [UsageSession] = []

    /// All events ever received, used to rebuild windows.
    private var allEvents: [UsageEvent] = []

    /// Deduplication: track event IDs we've already seen.
    private var seenEventIDs: Set<String> = []

    private let sessionDuration: TimeInterval

    init(sessionDuration: TimeInterval = Constants.sessionDuration) {
        self.sessionDuration = sessionDuration
    }

    // MARK: - Public API

    func processEvents(_ events: [UsageEvent]) {
        // Deduplicate and accumulate
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

        rebuildSessions()
        delegate?.sessionEngine(self, didUpdateSession: currentSession)
    }

    /// Called periodically — no-op for now, windows are managed during event processing.
    func tick() {
        // Nothing to do — we keep the most recent window visible even if expired,
        // so the user can see their last session info.
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

    /// Whether the current session window is still active (not expired).
    var isActive: Bool {
        currentSession?.isActive ?? false
    }

    /// Whether there's a session at all (active or recently expired).
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

    /// Number of detected sessions today.
    var todaySessionCount: Int {
        let startOfDay = Calendar.current.startOfDay(for: Date())
        return allSessions.filter { $0.windowStart >= startOfDay }.count
    }

    // MARK: - Rebuild

    /// Rebuilds all session windows from scratch using all accumulated events.
    /// This ensures correct windows regardless of the order files/events arrive.
    private func rebuildSessions() {
        let sorted = allEvents.sorted { $0.timestamp < $1.timestamp }

        var sessions: [UsageSession] = []
        var current: UsageSession?

        for event in sorted {
            if let sess = current {
                if event.timestamp >= sess.windowEnd {
                    // Event falls after current window — finalize and start new
                    sessions.append(sess)
                    current = UsageSession(windowStart: event.timestamp, events: [event])
                } else if event.timestamp >= sess.windowStart {
                    // Event falls within current window
                    current?.events.append(event)
                }
                // Events before windowStart belong to a previous window — already handled
            } else {
                current = UsageSession(windowStart: event.timestamp, events: [event])
            }
        }

        if let sess = current {
            sessions.append(sess)
        }

        allSessions = sessions
        currentSession = sessions.last
    }
}

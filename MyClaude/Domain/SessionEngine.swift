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

    private let sessionDuration: TimeInterval

    init(sessionDuration: TimeInterval = Constants.sessionDuration) {
        self.sessionDuration = sessionDuration
    }

    // MARK: - Public API

    func processEvents(_ events: [UsageEvent]) {
        let sorted = events.sorted { $0.timestamp < $1.timestamp }
        for event in sorted {
            processEvent(event)
        }
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

    // MARK: - Private

    private func processEvent(_ event: UsageEvent) {
        if let session = currentSession {
            if event.timestamp >= session.windowEnd {
                // Event falls after current window — archive and start new
                finishSession()
                startNewWindow(with: event)
            } else if event.timestamp >= session.windowStart {
                // Event falls within current window
                currentSession?.events.append(event)
            }
            // Events before windowStart are from a previous window — ignore
        } else {
            startNewWindow(with: event)
        }
    }

    private func startNewWindow(with event: UsageEvent) {
        let session = UsageSession(
            windowStart: event.timestamp,
            events: [event]
        )
        currentSession = session
        allSessions.append(session)
    }

    private func finishSession() {
        // The session is already in allSessions (added in startNewWindow),
        // but update it with final event list
        if let session = currentSession, let idx = allSessions.lastIndex(where: { $0.id == session.id }) {
            allSessions[idx] = session
        }
        currentSession = nil
    }
}

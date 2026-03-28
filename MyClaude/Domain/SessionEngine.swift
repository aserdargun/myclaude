import Foundation

protocol SessionEngineDelegate: AnyObject {
    func sessionEngine(_ engine: SessionEngine, didUpdateSession session: UsageSession?)
}

final class SessionEngine {
    weak var delegate: SessionEngineDelegate?

    /// The current active session window, if any.
    private(set) var currentSession: UsageSession?

    /// Past expired sessions for history tracking.
    private(set) var sessionHistory: [UsageSession] = []

    private let sessionDuration: TimeInterval

    init(sessionDuration: TimeInterval = Constants.sessionDuration) {
        self.sessionDuration = sessionDuration
    }

    // MARK: - Public API

    func processEvents(_ events: [UsageEvent]) {
        // Sort all events chronologically and assign them to windows
        let sorted = events.sorted { $0.timestamp < $1.timestamp }
        for event in sorted {
            processEvent(event)
        }
        delegate?.sessionEngine(self, didUpdateSession: currentSession)
    }

    /// Called periodically to check if the current window has expired.
    func tick() {
        guard let session = currentSession, session.isExpired else { return }
        sessionHistory.append(session)
        currentSession = nil
        delegate?.sessionEngine(self, didUpdateSession: nil)
    }

    // MARK: - Computed properties

    var remainingTime: TimeInterval {
        currentSession?.remainingTime ?? 0
    }

    /// How much of the 5-hour window has elapsed (0.0 to 1.0).
    var sessionProgress: Double {
        guard let session = currentSession, !session.isExpired else { return 0 }
        let elapsed = Date().timeIntervalSince(session.windowStart)
        return min(1.0, elapsed / sessionDuration)
    }

    var isActive: Bool {
        currentSession?.isActive ?? false
    }

    var currentAlertLevel: AlertLevel {
        guard isActive else { return .safe }

        let remaining = remainingTime
        if remaining <= Constants.thirtyMinWarning {
            return .critical
        } else if remaining <= Constants.oneHourWarning {
            return .warning
        }
        return .safe
    }

    // MARK: - Private

    private func processEvent(_ event: UsageEvent) {
        if let session = currentSession {
            if event.timestamp >= session.windowEnd {
                // This event falls after the current window — archive and start new
                sessionHistory.append(session)
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
        currentSession = UsageSession(
            windowStart: event.timestamp,
            events: [event]
        )
    }
}

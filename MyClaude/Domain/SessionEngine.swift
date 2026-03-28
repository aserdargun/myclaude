import Foundation

protocol SessionEngineDelegate: AnyObject {
    func sessionEngine(_ engine: SessionEngine, didUpdateSession session: UsageSession?)
}

final class SessionEngine {
    weak var delegate: SessionEngineDelegate?

    private(set) var currentSession = UsageSession()

    private let sessionDuration: TimeInterval

    init(sessionDuration: TimeInterval = Constants.sessionDuration) {
        self.sessionDuration = sessionDuration
    }

    // MARK: - Public API

    func processEvents(_ events: [UsageEvent]) {
        currentSession.events.append(contentsOf: events)
        // Sort and deduplicate by id
        currentSession.events.sort { $0.timestamp < $1.timestamp }
        pruneOldEvents()
        delegate?.sessionEngine(self, didUpdateSession: currentSession)
    }

    /// Called periodically to prune events that have fallen out of the window.
    func tick() {
        pruneOldEvents()
    }

    // MARK: - Computed properties

    /// Time until the oldest event in the rolling window ages out.
    var remainingTime: TimeInterval {
        currentSession.remainingTime
    }

    /// Fraction of the 5-hour window that has elapsed since the oldest event.
    /// This represents how "full" the window is time-wise.
    var sessionProgress: Double {
        guard let oldest = currentSession.oldestWindowEvent else { return 0 }
        let windowAge = Date().timeIntervalSince(oldest.timestamp)
        return min(1.0, windowAge / sessionDuration)
    }

    var isActive: Bool {
        currentSession.isActive
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

    /// Remove events older than the rolling window to keep memory bounded.
    private func pruneOldEvents() {
        let cutoff = Date().addingTimeInterval(-sessionDuration)
        currentSession.events.removeAll { $0.timestamp <= cutoff }
    }
}

import Foundation

protocol SessionEngineDelegate: AnyObject {
    func sessionEngine(_ engine: SessionEngine, didUpdateSession session: UsageSession?)
    func sessionEngine(_ engine: SessionEngine, didStartNewSession session: UsageSession)
    func sessionEngine(_ engine: SessionEngine, sessionDidExpire session: UsageSession)
}

final class SessionEngine {
    weak var delegate: SessionEngineDelegate?

    private(set) var currentSession: UsageSession?
    private(set) var sessionHistory: [UsageSession] = []

    private let sessionDuration: TimeInterval
    private let idleThreshold: TimeInterval

    init(
        sessionDuration: TimeInterval = Constants.sessionDuration,
        idleThreshold: TimeInterval = Constants.idleThreshold
    ) {
        self.sessionDuration = sessionDuration
        self.idleThreshold = idleThreshold
    }

    // MARK: - Public API

    func processEvents(_ events: [UsageEvent]) {
        let sorted = events.sorted { $0.timestamp < $1.timestamp }
        for event in sorted {
            processEvent(event)
        }
    }

    func processEvent(_ event: UsageEvent) {
        if let session = currentSession {
            if session.isExpired {
                // Session expired — archive and start new
                archiveSession(session)
                startNewSession(with: event)
            } else if event.timestamp.timeIntervalSince(lastEventTimestamp(in: session)) > idleThreshold {
                // Idle gap detected — could start new session or continue
                // For now, continue existing session if within window
                if event.timestamp < session.endTime {
                    addEvent(event, to: &currentSession!)
                } else {
                    archiveSession(session)
                    startNewSession(with: event)
                }
            } else {
                addEvent(event, to: &currentSession!)
            }
        } else {
            startNewSession(with: event)
        }
    }

    func checkExpiration() {
        guard let session = currentSession, session.isExpired else { return }
        delegate?.sessionEngine(self, sessionDidExpire: session)
        archiveSession(session)
        currentSession = nil
    }

    /// Reconstruct session state from historical events (e.g., after app restart)
    func reconstruct(from events: [UsageEvent]) {
        currentSession = nil
        sessionHistory.removeAll()

        let sorted = events.sorted { $0.timestamp < $1.timestamp }
        for event in sorted {
            processEvent(event)
        }
    }

    // MARK: - Computed properties

    var remainingTime: TimeInterval {
        currentSession?.remainingTime ?? 0
    }

    var sessionProgress: Double {
        guard let session = currentSession else { return 0 }
        let elapsed = Date().timeIntervalSince(session.startTime)
        return min(1.0, elapsed / sessionDuration)
    }

    var isActive: Bool {
        currentSession != nil && !(currentSession?.isExpired ?? true)
    }

    var currentAlertLevel: AlertLevel {
        guard let session = currentSession else { return .safe }
        if session.isExpired { return .expired }

        let remaining = session.remainingTime
        if remaining <= Constants.thirtyMinWarning {
            return .critical
        } else if remaining <= Constants.oneHourWarning {
            return .warning
        }
        return .safe
    }

    // MARK: - Private

    private func startNewSession(with event: UsageEvent) {
        var session = UsageSession(startTime: event.timestamp, events: [event])
        currentSession = session
        delegate?.sessionEngine(self, didStartNewSession: session)
        delegate?.sessionEngine(self, didUpdateSession: session)
    }

    private func addEvent(_ event: UsageEvent, to session: inout UsageSession) {
        session.events.append(event)
        currentSession = session
        delegate?.sessionEngine(self, didUpdateSession: session)
    }

    private func archiveSession(_ session: UsageSession) {
        sessionHistory.append(session)
        delegate?.sessionEngine(self, sessionDidExpire: session)
    }

    private func lastEventTimestamp(in session: UsageSession) -> Date {
        session.events.last?.timestamp ?? session.startTime
    }
}

import Foundation
import Combine
import SwiftUI

@Observable
final class UsageViewModel: LogReaderDelegate, SessionEngineDelegate, AlertEngineDelegate {

    // MARK: - Published state

    var remainingTime: TimeInterval = 0
    var sessionProgress: Double = 0
    var alertLevel: AlertLevel = .safe
    var currentTokens: Int = 0
    var currentEventCount: Int = 0
    var weeklyStats: WeeklyStats = WeeklyStats(
        dailyBreakdown: [], totalTokens: 0, totalEvents: 0, totalSessions: 0
    )
    var todayStats: DailyStats = DailyStats(
        date: Date(), totalTokens: 0, eventCount: 0, sessionCount: 0
    )
    var lastLogRead: Date?
    var totalEventsRead: Int = 0
    var latestAlert: UsageAlert?
    var sessionStartTime: Date?
    var sessionEndTime: Date?
    var isSessionActive: Bool = false

    // MARK: - Status bar display

    var menuBarTitle: String {
        if !isSessionActive {
            return "⏸ No session"
        }
        let icon: String
        switch alertLevel {
        case .safe: icon = "🟢"
        case .warning: icon = "🟡"
        case .critical: icon = "🔴"
        case .expired: icon = "⏹"
        }
        return "\(icon) \(remainingTime.compactRemaining)"
    }

    var statusColor: Color {
        switch alertLevel {
        case .safe: return .green
        case .warning: return .yellow
        case .critical: return .red
        case .expired: return .gray
        }
    }

    // MARK: - Dependencies

    private let logReader: LogReader
    private let sessionEngine: SessionEngine
    private let aggregator: UsageAggregator
    private let alertEngine: AlertEngine
    private let storage: StorageProtocol

    private var updateTimer: Timer?

    // MARK: - Init

    init(
        logReader: LogReader = LogReader(),
        sessionEngine: SessionEngine = SessionEngine(),
        aggregator: UsageAggregator = UsageAggregator(),
        alertEngine: AlertEngine = AlertEngine(),
        storage: StorageProtocol = UserDefaultsStorage()
    ) {
        self.logReader = logReader
        self.sessionEngine = sessionEngine
        self.aggregator = aggregator
        self.alertEngine = alertEngine
        self.storage = storage

        logReader.delegate = self
        sessionEngine.delegate = self
        alertEngine.delegate = self
    }

    // MARK: - Lifecycle

    func start() {
        AlertEngine.requestNotificationPermission()
        logReader.start()
        startUITimer()
    }

    func stop() {
        logReader.stop()
        updateTimer?.invalidate()
        updateTimer = nil
    }

    func forceRefresh() {
        logReader.forceRefresh()
    }

    // MARK: - UI Timer

    private func startUITimer() {
        updateTimer = Timer.scheduledTimer(
            withTimeInterval: Constants.uiUpdateInterval,
            repeats: true
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.tick()
            }
        }
    }

    private func tick() {
        sessionEngine.checkExpiration()
        updateUIState()
        alertEngine.evaluate(session: sessionEngine.currentSession, sessionEngine: sessionEngine)
    }

    private func updateUIState() {
        remainingTime = sessionEngine.remainingTime
        sessionProgress = sessionEngine.sessionProgress
        alertLevel = sessionEngine.currentAlertLevel
        isSessionActive = sessionEngine.isActive
        sessionStartTime = sessionEngine.currentSession?.startTime
        sessionEndTime = sessionEngine.currentSession?.endTime
        currentTokens = aggregator.currentSessionUsage(session: sessionEngine.currentSession)
        currentEventCount = aggregator.currentSessionEventCount(session: sessionEngine.currentSession)
        weeklyStats = aggregator.weeklyStats()
        todayStats = aggregator.todayStats()
        lastLogRead = logReader.lastReadTime
        totalEventsRead = logReader.totalEventsRead
    }

    // MARK: - LogReaderDelegate

    func logReader(_ reader: LogReader, didReadEvents events: [UsageEvent]) {
        sessionEngine.processEvents(events)
        aggregator.addEvents(events)
        updateUIState()
    }

    func logReader(_ reader: LogReader, didEncounterError error: Error) {
        print("Log reader error: \(error)")
    }

    // MARK: - SessionEngineDelegate

    func sessionEngine(_ engine: SessionEngine, didUpdateSession session: UsageSession?) {
        updateUIState()
    }

    func sessionEngine(_ engine: SessionEngine, didStartNewSession session: UsageSession) {
        alertEngine.resetAlerts()
        updateUIState()
    }

    func sessionEngine(_ engine: SessionEngine, sessionDidExpire session: UsageSession) {
        updateUIState()
    }

    // MARK: - AlertEngineDelegate

    func alertEngine(_ engine: AlertEngine, didTriggerAlert alert: UsageAlert) {
        latestAlert = alert
    }
}

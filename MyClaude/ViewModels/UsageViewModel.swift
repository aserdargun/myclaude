import Foundation
import Combine
import SwiftUI

@Observable
final class UsageViewModel: NSObject, LogReaderDelegate, SessionEngineDelegate, AlertEngineDelegate {

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
    var windowStartTime: Date?
    var windowEndTime: Date?
    var isSessionActive: Bool = false
    var hasSession: Bool = false
    var todaySessionCount: Int = 0
    var isRefreshing: Bool = false
    var showSettings: Bool = false

    // MARK: - Calibration state

    var calibrationData: CalibrationData? {
        calibrationManager.currentCalibration
    }

    var estimatedSessionPercent: Double? {
        calibrationManager.estimatedSessionPercent(currentSessionTokens: currentTokens)
    }

    var estimatedTodayPercent: Double? {
        calibrationManager.estimatedTodayPercent(currentTodayTokens: todayStats.totalTokens)
    }

    var estimatedWeeklyPercent: Double? {
        calibrationManager.estimatedWeeklyPercent(currentWeeklyTokens: weeklyStats.totalTokens)
    }

    /// Calibrated session progress (0.0-1.0) based on burn rate, or time-based fallback.
    var calibratedSessionProgress: Double {
        if let pct = estimatedSessionPercent {
            return min(1.0, pct / 100.0)
        }
        return sessionProgress
    }

    /// Display string for session percentage.
    var sessionPercentDisplay: String {
        if let pct = estimatedSessionPercent {
            return "\(Int(min(pct, 100)))%"
        }
        return "\(Int(sessionProgress * 100))%"
    }

    // MARK: - Status bar display

    var menuBarTitle: String {
        if isSessionActive {
            let icon: String
            switch alertLevel {
            case .safe: icon = "🟢"
            case .warning: icon = "🟡"
            case .critical: icon = "🔴"
            case .expired: icon = "⏹"
            }
            return "\(icon) \(remainingTime.compactRemaining)"
        } else if hasSession {
            return "⏹ Expired"
        } else {
            return "⏸ No session"
        }
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
    private let calibrationManager: CalibrationManager

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
        self.calibrationManager = CalibrationManager(storage: storage)
        super.init()

        logReader.delegate = self
        sessionEngine.delegate = self
        alertEngine.delegate = self
    }

    // MARK: - Lifecycle

    func start() {
        alertEngine.requestNotificationPermission()
        restoreCalibration()
        logReader.start()
        startUITimer()
    }

    /// Restore calibrated session override from persisted calibration data.
    private func restoreCalibration() {
        guard let cal = calibrationManager.currentCalibration else { return }
        let now = Date()
        var periodStart = cal.sessionStartTime
        while periodStart.addingTimeInterval(Constants.sessionDuration) <= now {
            periodStart = periodStart.addingTimeInterval(Constants.sessionDuration)
        }
        // Only restore if the current period is still active
        if now < periodStart.addingTimeInterval(Constants.sessionDuration) {
            sessionEngine.overrideSessionStart(periodStart)
        }
    }

    func stop() {
        logReader.stop()
        updateTimer?.invalidate()
        updateTimer = nil
    }

    func forceRefresh() {
        isRefreshing = true
        logReader.forceRefresh()
    }

    /// Query token usage for a specific time range (used by settings period view).
    func usage(from start: Date, to end: Date) -> (tokens: Int, events: Int) {
        aggregator.usage(from: start, to: end)
    }

    // MARK: - Calibration

    func performCalibration(
        sessionStartTime: Date,
        sessionPercentage: Double,
        weeklyPercentage: Double
    ) {
        // Find the current active 5h period by stepping forward from the first session start
        let now = Date()
        var periodStart = sessionStartTime
        while periodStart.addingTimeInterval(Constants.sessionDuration) <= now {
            periodStart = periodStart.addingTimeInterval(Constants.sessionDuration)
        }
        // periodStart is now the start of the current active period

        let periodUsage = aggregator.usage(
            from: periodStart,
            to: periodStart.addingTimeInterval(Constants.sessionDuration)
        )

        let _ = calibrationManager.calibrate(
            sessionStartTime: sessionStartTime,
            sessionPercentage: sessionPercentage,
            weeklyPercentage: weeklyPercentage,
            todayTokens: todayStats.totalTokens,
            weeklyTokens: weeklyStats.totalTokens,
            sessionTokens: periodUsage.tokens
        )

        // Override session engine with the CURRENT period's start, not the first session
        sessionEngine.overrideSessionStart(periodStart)
        updateUIState()
    }

    func resetCalibration() {
        calibrationManager.reset()
        updateUIState()
    }

    // MARK: - UI Timer

    private func startUITimer() {
        updateTimer = Timer.scheduledTimer(
            timeInterval: Constants.uiUpdateInterval,
            target: self,
            selector: #selector(timerFired),
            userInfo: nil,
            repeats: true
        )
    }

    @objc private func timerFired() {
        tick()
    }

    private func tick() {
        sessionEngine.tick()
        updateUIState()
        if let session = sessionEngine.currentSession, session.isActive {
            alertEngine.evaluate(session: session, sessionEngine: sessionEngine)
        }
    }

    private func updateUIState() {
        let session = sessionEngine.currentSession
        remainingTime = sessionEngine.remainingTime
        sessionProgress = sessionEngine.sessionProgress
        alertLevel = sessionEngine.currentAlertLevel
        isSessionActive = sessionEngine.isActive
        hasSession = sessionEngine.hasSession
        windowStartTime = session?.windowStart
        windowEndTime = session?.windowEnd
        currentTokens = session?.totalTokens ?? 0
        currentEventCount = session?.eventCount ?? 0
        todaySessionCount = sessionEngine.todaySessionCount
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

    func logReader(_ reader: LogReader, didFinishScanning totalEvents: Int) {
        isRefreshing = false
        updateUIState()
    }

    func logReader(_ reader: LogReader, didEncounterError error: Error) {
        isRefreshing = false
        print("Log reader error: \(error)")
    }

    // MARK: - SessionEngineDelegate

    func sessionEngine(_ engine: SessionEngine, didUpdateSession session: UsageSession?) {
        updateUIState()
    }

    // MARK: - AlertEngineDelegate

    func alertEngine(_ engine: AlertEngine, didTriggerAlert alert: UsageAlert) {
        latestAlert = alert
    }
}

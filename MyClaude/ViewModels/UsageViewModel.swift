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
    var currentWeightedTokens: Int = 0
    var currentEventCount: Int = 0
    var weeklyStats: WeeklyStats = WeeklyStats(
        dailyBreakdown: [], totalTokens: 0, weightedTokens: 0, totalEvents: 0, totalSessions: 0
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

    // MARK: - Browser scraping state

    var isScraping: Bool = false
    var scrapeError: String?
    var scrapeSuccess: Bool = false

    // MARK: - Calibration state

    /// Tracks which 5h period was active at last calibration, to detect period changes.
    private var lastCalibratedPeriodStart: Date?

    /// Set to true when the 5h period has changed since last calibration.
    var calibrationPeriodChanged: Bool = false

    var calibrationData: CalibrationData? {
        calibrationManager.currentCalibration
    }

    /// How long ago the user last calibrated.
    var calibrationAge: TimeInterval? {
        guard let cal = calibrationManager.currentCalibration else { return nil }
        return Date().timeIntervalSince(cal.calibratedAt)
    }

    /// Whether calibration is stale (>1 hour old).
    var isCalibrationStale: Bool {
        guard let age = calibrationAge else { return false }
        return age > Constants.recalibrationInterval
    }

    /// Whether calibration needs attention (stale or period changed).
    var needsRecalibration: Bool {
        isCalibrationStale || calibrationPeriodChanged
    }

    var estimatedSessionPercent: Double? {
        calibrationManager.estimatedSessionPercent(currentSessionWeightedTokens: currentWeightedTokens)
    }

    var estimatedWeeklyPercent: Double? {
        calibrationManager.estimatedWeeklyPercent(currentWeeklyWeightedTokens: weeklyStats.weightedTokens)
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
    private let browserScraper = BrowserScraper()

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
    func usage(from start: Date, to end: Date) -> (tokens: Int, weightedTokens: Int, events: Int) {
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
            sessionTokens: periodUsage.tokens,
            sessionWeightedTokens: periodUsage.weightedTokens,
            weeklyWeightedTokens: weeklyStats.weightedTokens
        )

        // Override session engine with the CURRENT period's start, not the first session
        sessionEngine.overrideSessionStart(periodStart)
        calibrationPeriodChanged = false
        alertEngine.resetAlerts()
        updateUIState()
    }

    func resetCalibration() {
        calibrationManager.reset()
        calibrationPeriodChanged = false
        updateUIState()
    }

    /// Auto-calibrate by scraping claude.ai/settings from an open browser tab.
    func scrapeAndCalibrate() {
        isScraping = true
        scrapeError = nil
        scrapeSuccess = false

        Task {
            do {
                let data = try await browserScraper.scrape()
                // Compute session start: now + resetsIn - 5 hours
                let sessionStart = Date().addingTimeInterval(
                    data.sessionResetsIn - Constants.sessionDuration
                )
                await MainActor.run {
                    self.performCalibration(
                        sessionStartTime: sessionStart,
                        sessionPercentage: data.sessionPercent,
                        weeklyPercentage: data.weeklyPercent
                    )
                    self.isScraping = false
                    self.scrapeSuccess = true
                    // Auto-dismiss success after 3 seconds
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                        self?.scrapeSuccess = false
                    }
                }
            } catch {
                await MainActor.run {
                    self.scrapeError = error.localizedDescription
                    self.isScraping = false
                }
            }
        }
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
        checkPeriodChange()
        updateUIState()
        if let session = sessionEngine.currentSession, session.isActive {
            alertEngine.evaluate(session: session, sessionEngine: sessionEngine)
        }
    }

    /// Detects when the 5h period has changed since last calibration.
    private func checkPeriodChange() {
        guard let cal = calibrationManager.currentCalibration else {
            calibrationPeriodChanged = false
            return
        }

        // Compute current period start
        let now = Date()
        var periodStart = cal.sessionStartTime
        while periodStart.addingTimeInterval(Constants.sessionDuration) <= now {
            periodStart = periodStart.addingTimeInterval(Constants.sessionDuration)
        }

        // Compute period that was active at calibration time
        var calPeriodStart = cal.sessionStartTime
        while calPeriodStart.addingTimeInterval(Constants.sessionDuration) <= cal.calibratedAt {
            calPeriodStart = calPeriodStart.addingTimeInterval(Constants.sessionDuration)
        }

        // If period changed, flag it
        if periodStart != calPeriodStart && !calibrationPeriodChanged {
            calibrationPeriodChanged = true
            // Send notification
            alertEngine.sendRecalibrationReminder(reason: "New 5h period started")
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

        // For session tokens/events: when calibrated, query the aggregator
        // using the current period range. The session engine's events may be
        // empty if the calibrated grid doesn't align with Code CLI activity,
        // but the aggregator has ALL events and can filter by range.
        if let session, calibrationManager.currentCalibration != nil {
            let periodUsage = aggregator.usage(
                from: session.windowStart,
                to: session.windowEnd
            )
            currentTokens = periodUsage.tokens
            currentWeightedTokens = periodUsage.weightedTokens
            currentEventCount = periodUsage.events
        } else {
            currentTokens = session?.totalTokens ?? 0
            currentWeightedTokens = session?.totalWeightedTokens ?? 0
            currentEventCount = session?.eventCount ?? 0
        }

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

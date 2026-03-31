import Foundation
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

    /// Scraped "Sonnet only" percentage (nil if not available on page)
    var scrapedSonnetPercent: Double?
    /// Scraped All Models reset info
    var scrapedAllModelsReset: WeeklyResetInfo?
    /// Scraped Sonnet reset info
    var scrapedSonnetReset: WeeklyResetInfo?

    /// Browser scrape interval in seconds. Persisted in UserDefaults.
    var scrapeIntervalSeconds: Int {
        didSet {
            UserDefaults.standard.set(scrapeIntervalSeconds, forKey: "scrapeIntervalSeconds")
            restartScrapeTimer()
        }
    }

    /// Claude usage page URL. Persisted in UserDefaults.
    var scrapeSourceURL: String {
        didSet {
            UserDefaults.standard.set(scrapeSourceURL, forKey: "scrapeSourceURL")
        }
    }

    /// Daily target percentages for weekly limits (Sun–Sat). Must sum to 100.
    var dailyTargets: [Int] {
        didSet {
            UserDefaults.standard.set(dailyTargets, forKey: "dailyTargets")
        }
    }

    /// Default daily targets: Sun=15, Mon=10, Tue=15, Wed=15, Thu=10, Fri=15, Sat=20
    static let defaultDailyTargets = [15, 10, 15, 15, 10, 15, 20]

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
    private var scrapeTimer: Timer?

    /// Tracks when the browser page was last reloaded.
    private var lastPageReloadDate: Date = .distantPast

    /// How often to do a full page reload (seconds). Regular scrapes just read the DOM.
    private let pageReloadInterval: TimeInterval = 60

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
        let saved = UserDefaults.standard.integer(forKey: "scrapeIntervalSeconds")
        self.scrapeIntervalSeconds = saved > 0 ? saved : 300
        self.scrapeSourceURL = UserDefaults.standard.string(forKey: "scrapeSourceURL") ?? Constants.claudeUsageURL
        if let saved = UserDefaults.standard.array(forKey: "dailyTargets") as? [Int], saved.count == 7 {
            self.dailyTargets = saved
        } else {
            self.dailyTargets = UsageViewModel.defaultDailyTargets
        }
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
        startScrapeTimer()
    }

    /// Restore calibrated session override from persisted calibration data.
    private func restoreCalibration() {
        guard let cal = calibrationManager.currentCalibration else { return }
        let now = Date()
        let elapsed = now.timeIntervalSince(cal.sessionStartTime)
        let periodsElapsed = max(0, Int(elapsed / Constants.sessionDuration))
        let periodStart = cal.sessionStartTime.addingTimeInterval(Double(periodsElapsed) * Constants.sessionDuration)
        // Only restore if the current period is still active
        if now < periodStart.addingTimeInterval(Constants.sessionDuration) {
            sessionEngine.overrideSessionStart(periodStart)
        }
    }

    func stop() {
        logReader.stop()
        updateTimer?.invalidate()
        updateTimer = nil
        scrapeTimer?.invalidate()
        scrapeTimer = nil
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
        // Find the current active 5h period using arithmetic
        let now = Date()
        let elapsed = now.timeIntervalSince(sessionStartTime)
        let periodsElapsed = max(0, Int(elapsed / Constants.sessionDuration))
        let periodStart = sessionStartTime.addingTimeInterval(Double(periodsElapsed) * Constants.sessionDuration)

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

    /// Auto-calibrate by scraping claude.ai/settings from an open browser tab.
    func scrapeAndCalibrate() {
        guard !isScraping else { return }
        isScraping = true
        scrapeError = nil
        scrapeSuccess = false

        Task {
            do {
                let data = try await browserScraper.scrape(url: self.scrapeSourceURL, reload: true)
                await MainActor.run {
                    self.applyScrapedData(data)
                    self.isScraping = false
                    self.scrapeSuccess = true
                    self.consecutiveScrapeFailures = 0
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

    /// Apply scraped data. Calibrates session only if there's an active session reset time.
    private func applyScrapedData(_ data: ScrapedUsageData) {
        if let resetsIn = data.sessionResetsIn {
            let sessionStart = Date().addingTimeInterval(resetsIn - Constants.sessionDuration)
            performCalibration(
                sessionStartTime: sessionStart,
                sessionPercentage: data.sessionPercent,
                weeklyPercentage: data.weeklyPercent
            )
        }
        // Always update weekly data
        scrapedSonnetPercent = data.sonnetPercent
        scrapedAllModelsReset = data.allModelsReset
        scrapedSonnetReset = data.sonnetReset
        // Update weekly calibration even without active session
        if data.sessionResetsIn == nil {
            calibrationManager.calibrateWeeklyOnly(
                weeklyPercentage: data.weeklyPercent,
                weeklyWeightedTokens: weeklyStats.weightedTokens
            )
            updateUIState()
        }
        // Notify menubar to refresh immediately with new data
        NotificationCenter.default.post(name: .scrapeDataDidUpdate, object: nil)
    }

    // MARK: - Browser Scrape Timer

    private func startScrapeTimer() {
        scrapeTimer?.invalidate()
        guard scrapeIntervalSeconds > 0 else { return }
        // Fire immediately on start
        scrapeQuietly()
    }

    private func restartScrapeTimer() {
        scrapeTimer?.invalidate()
        startScrapeTimer()
    }

    /// Schedule the next scrape after `scrapeIntervalSeconds` from now.
    /// Uses a one-shot timer so the interval is measured from completion of
    /// the previous scrape, not from a fixed repeating clock.
    private func scheduleNextScrape() {
        scrapeTimer?.invalidate()
        guard scrapeIntervalSeconds > 0 else { return }
        let timer = Timer(
            timeInterval: TimeInterval(scrapeIntervalSeconds),
            target: self,
            selector: #selector(scrapeTimerFired),
            userInfo: nil,
            repeats: false
        )
        RunLoop.main.add(timer, forMode: .common)
        scrapeTimer = timer
    }

    @objc private func scrapeTimerFired() {
        scrapeQuietly()
    }

    /// Background scrape failure count for exponential backoff.
    private var consecutiveScrapeFailures: Int = 0

    /// Max consecutive failures before stopping background scrapes.
    private static let maxConsecutiveScrapeFailures = 10

    /// Scrape without showing success/error banners (background refresh).
    ///
    /// Two-tier strategy to support fast intervals (e.g. 5 seconds):
    /// - Most cycles: just read the current DOM (fast, <1s). The SPA keeps
    ///   the "Resets in" countdown live, so #m stays accurate.
    /// - Every `pageReloadInterval` seconds: reload the page first to fetch
    ///   fresh percentage data from the server, then scrape.
    private func scrapeQuietly() {
        guard !isScraping else {
            scheduleNextScrape()
            return
        }
        guard consecutiveScrapeFailures < Self.maxConsecutiveScrapeFailures else {
            // Stop retrying after too many failures
            return
        }
        isScraping = true
        let needsReload = Date().timeIntervalSince(lastPageReloadDate) >= pageReloadInterval
        let sourceURL = self.scrapeSourceURL
        Task {
            do {
                let data = try await browserScraper.scrape(url: sourceURL, reload: needsReload)
                await MainActor.run {
                    if needsReload { self.lastPageReloadDate = Date() }
                    self.applyScrapedData(data)
                    self.isScraping = false
                    self.scrapeError = nil
                    self.consecutiveScrapeFailures = 0
                    self.scheduleNextScrape()
                }
            } catch {
                await MainActor.run {
                    self.isScraping = false
                    self.consecutiveScrapeFailures += 1
                    // Don't show errors for background scrapes, but log them
                    print("Background scrape failed (\(self.consecutiveScrapeFailures)/\(Self.maxConsecutiveScrapeFailures)): \(error.localizedDescription)")
                    self.scheduleNextScrape()
                }
            }
        }
    }

    // MARK: - UI Timer

    private func startUITimer() {
        let timer = Timer(
            timeInterval: Constants.uiUpdateInterval,
            target: self,
            selector: #selector(timerFired),
            userInfo: nil,
            repeats: true
        )
        RunLoop.main.add(timer, forMode: .common)
        updateTimer = timer
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

        let duration = Constants.sessionDuration

        // Compute current period start using arithmetic
        let now = Date()
        let elapsedNow = now.timeIntervalSince(cal.sessionStartTime)
        let currentPeriodIndex = max(0, Int(elapsedNow / duration))
        let periodStart = cal.sessionStartTime.addingTimeInterval(Double(currentPeriodIndex) * duration)

        // Compute period that was active at calibration time
        let elapsedCal = cal.calibratedAt.timeIntervalSince(cal.sessionStartTime)
        let calPeriodIndex = max(0, Int(elapsedCal / duration))
        let calPeriodStart = cal.sessionStartTime.addingTimeInterval(Double(calPeriodIndex) * duration)

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
        // Alert triggered — notification handled by AlertEngine
    }
}

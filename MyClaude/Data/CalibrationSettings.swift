import Foundation

/// Stores calibration data from Claude's usage settings page.
/// The user inputs their current session % and weekly % along with session start time,
/// and myClaude captures token counts at that moment to calculate burn rates.
struct CalibrationData: Codable {
    /// When the user calibrated
    let calibratedAt: Date

    /// Session start time (from Claude's "First" or calculated from "Resets in")
    let sessionStartTime: Date

    /// The session % the user entered from Claude's settings (e.g. 41)
    let sessionPercentage: Double

    /// The weekly "All models" % from Claude's settings (e.g. 55)
    let weeklyPercentage: Double

    /// Token counts captured at calibration moment
    let todayTokensAtCalibration: Int
    let weeklyTokensAtCalibration: Int
    let sessionTokensAtCalibration: Int

    // MARK: - Burn rates (tokens per 1%)

    /// Session burn rate: local session tokens / session %.
    var sessionBurnRate: Double {
        guard sessionPercentage > 0 else { return 0 }
        return Double(sessionTokensAtCalibration) / sessionPercentage
    }

    /// Weekly burn rate: local weekly tokens / weekly %.
    /// This is the most reliable rate (largest token sample).
    var weeklyBurnRate: Double {
        guard weeklyPercentage > 0 else { return 0 }
        return Double(weeklyTokensAtCalibration) / weeklyPercentage
    }

    /// Best available burn rate — session-specific if available, else weekly as fallback.
    /// Weekly burn rate is a good approximation when session has no local tokens
    /// (e.g., all usage was via Claude web before this 5h period).
    var effectiveBurnRate: Double {
        if sessionBurnRate > 0 {
            return sessionBurnRate
        }
        return weeklyBurnRate
    }

    /// Whether this calibration is from the current week (still relevant)
    var isCurrentWeek: Bool {
        let calendar = Calendar.current
        return calendar.isDate(calibratedAt, equalTo: Date(), toGranularity: .weekOfYear)
    }

    /// Session window end based on calibrated start time + 5h
    var sessionEndTime: Date {
        sessionStartTime.addingTimeInterval(Constants.sessionDuration)
    }

    /// Whether the calibrated session is still active
    var isSessionActive: Bool {
        Date() < sessionEndTime
    }
}

/// Manages calibration settings persistence and burn rate calculations.
///
/// Estimation formula: `calibratedPct + deltaTokens / burnRate`
/// - deltaTokens = current local tokens - tokens at calibration
/// - burnRate = tokens per 1% (from session data, or weekly as fallback)
/// - This ensures % starts at the calibrated value and increases as local tokens accumulate
final class CalibrationManager {
    private let storage: StorageProtocol
    private static let storageKey = "calibrationData"

    init(storage: StorageProtocol = UserDefaultsStorage()) {
        self.storage = storage
    }

    /// Current calibration data, if any.
    var currentCalibration: CalibrationData? {
        storage.load(CalibrationData.self, forKey: Self.storageKey)
    }

    /// Save new calibration.
    func calibrate(
        sessionStartTime: Date,
        sessionPercentage: Double,
        weeklyPercentage: Double,
        todayTokens: Int,
        weeklyTokens: Int,
        sessionTokens: Int
    ) -> CalibrationData {
        let data = CalibrationData(
            calibratedAt: Date(),
            sessionStartTime: sessionStartTime,
            sessionPercentage: sessionPercentage,
            weeklyPercentage: weeklyPercentage,
            todayTokensAtCalibration: todayTokens,
            weeklyTokensAtCalibration: weeklyTokens,
            sessionTokensAtCalibration: sessionTokens
        )
        storage.save(data, forKey: Self.storageKey)
        return data
    }

    /// Clear calibration.
    func reset() {
        storage.remove(forKey: Self.storageKey)
    }

    /// Estimate current session % = calibrated% + delta local tokens / burn rate.
    func estimatedSessionPercent(currentSessionTokens: Int) -> Double? {
        guard let cal = currentCalibration else { return nil }
        let burnRate = cal.effectiveBurnRate
        let deltaTokens = max(0, currentSessionTokens - cal.sessionTokensAtCalibration)
        if burnRate > 0 && deltaTokens > 0 {
            return cal.sessionPercentage + Double(deltaTokens) / burnRate
        }
        return cal.sessionPercentage
    }

    /// Estimate current weekly % = calibrated% + delta local tokens / weekly burn rate.
    func estimatedWeeklyPercent(currentWeeklyTokens: Int) -> Double? {
        guard let cal = currentCalibration,
              cal.isCurrentWeek,
              cal.weeklyBurnRate > 0 else { return nil }
        let deltaTokens = max(0, currentWeeklyTokens - cal.weeklyTokensAtCalibration)
        if deltaTokens > 0 {
            return cal.weeklyPercentage + Double(deltaTokens) / cal.weeklyBurnRate
        }
        return cal.weeklyPercentage
    }

    /// Estimate today's contribution as % of session limit using effective burn rate.
    func estimatedTodayPercent(currentTodayTokens: Int) -> Double? {
        guard let cal = currentCalibration else { return nil }
        let burnRate = cal.effectiveBurnRate
        guard burnRate > 0 else { return nil }
        let deltaTokens = max(0, currentTodayTokens - cal.todayTokensAtCalibration)
        if deltaTokens > 0 {
            // Today doesn't have a separate % in Claude's UI, but we can show
            // how many % worth of tokens were consumed today using the session burn rate
            return Double(cal.todayTokensAtCalibration) / burnRate + Double(deltaTokens) / burnRate
        }
        if cal.todayTokensAtCalibration > 0 {
            return Double(cal.todayTokensAtCalibration) / burnRate
        }
        return nil
    }
}

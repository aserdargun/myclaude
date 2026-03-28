import Foundation

/// Stores calibration data from Claude's usage settings page.
/// The user inputs their current session % and weekly % along with session start time,
/// and myClaude captures token counts at that moment to calculate burn rates.
struct CalibrationData: Codable {
    /// When the user calibrated
    let calibratedAt: Date

    /// Session start time (from Claude's "First" or calculated from "Resets in")
    let sessionStartTime: Date

    /// The session % the user entered from Claude's settings (e.g. 23)
    let sessionPercentage: Double

    /// The weekly "All models" % from Claude's settings (e.g. 54)
    let weeklyPercentage: Double

    /// Token counts captured at calibration moment
    let todayTokensAtCalibration: Int
    let weeklyTokensAtCalibration: Int
    let sessionTokensAtCalibration: Int

    /// Calculated burn rates (tokens per 1%)
    var todayBurnRatePerPercent: Double {
        guard sessionPercentage > 0 else { return 0 }
        return Double(todayTokensAtCalibration) / sessionPercentage
    }

    var weeklyBurnRatePerPercent: Double {
        guard weeklyPercentage > 0 else { return 0 }
        return Double(weeklyTokensAtCalibration) / weeklyPercentage
    }

    var sessionBurnRatePerPercent: Double {
        guard sessionPercentage > 0 else { return 0 }
        return Double(sessionTokensAtCalibration) / sessionPercentage
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

    /// Estimate current session % using calibrated base + delta tokens.
    /// Uses calibrated percentage as floor, adds increase from new local tokens.
    func estimatedSessionPercent(currentSessionTokens: Int) -> Double? {
        guard let cal = currentCalibration else { return nil }
        let deltaTokens = max(0, currentSessionTokens - cal.sessionTokensAtCalibration)
        if cal.sessionBurnRatePerPercent > 0 && deltaTokens > 0 {
            return cal.sessionPercentage + Double(deltaTokens) / cal.sessionBurnRatePerPercent
        }
        return cal.sessionPercentage
    }

    /// Estimate current weekly % using calibrated base + delta tokens.
    func estimatedWeeklyPercent(currentWeeklyTokens: Int) -> Double? {
        guard let cal = currentCalibration,
              cal.isCurrentWeek else { return nil }
        let deltaTokens = max(0, currentWeeklyTokens - cal.weeklyTokensAtCalibration)
        if cal.weeklyBurnRatePerPercent > 0 && deltaTokens > 0 {
            return cal.weeklyPercentage + Double(deltaTokens) / cal.weeklyBurnRatePerPercent
        }
        return cal.weeklyPercentage
    }

    /// Estimate today's % using calibrated base + delta tokens.
    func estimatedTodayPercent(currentTodayTokens: Int) -> Double? {
        guard let cal = currentCalibration,
              cal.todayBurnRatePerPercent > 0 else { return nil }
        let deltaTokens = max(0, currentTodayTokens - cal.todayTokensAtCalibration)
        if deltaTokens > 0 {
            return cal.sessionPercentage + Double(deltaTokens) / cal.todayBurnRatePerPercent
        }
        // No today baseline % stored, so return nil if no delta
        return nil
    }
}

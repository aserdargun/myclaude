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

    /// Raw token counts captured at calibration moment
    let todayTokensAtCalibration: Int
    let weeklyTokensAtCalibration: Int
    let sessionTokensAtCalibration: Int

    /// Cost-weighted token counts at calibration (approximating rate-limiter impact)
    let sessionWeightedTokensAtCalibration: Int
    let weeklyWeightedTokensAtCalibration: Int

    // MARK: - Burn rates (weighted tokens per 1%)

    /// Session burn rate using weighted tokens.
    var sessionBurnRate: Double {
        guard sessionPercentage > 0, sessionWeightedTokensAtCalibration > 0 else { return 0 }
        return Double(sessionWeightedTokensAtCalibration) / sessionPercentage
    }

    /// Weekly burn rate using weighted tokens.
    var weeklyBurnRate: Double {
        guard weeklyPercentage > 0, weeklyWeightedTokensAtCalibration > 0 else { return 0 }
        return Double(weeklyWeightedTokensAtCalibration) / weeklyPercentage
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
/// Session and weekly are independent pools with different total capacities.
/// Each pool's burn rate is calculated independently — never cross-applied.
/// Uses cost-weighted tokens (not raw) for burn rate calculations.
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
        sessionTokens: Int,
        sessionWeightedTokens: Int,
        weeklyWeightedTokens: Int
    ) -> CalibrationData {
        let data = CalibrationData(
            calibratedAt: Date(),
            sessionStartTime: sessionStartTime,
            sessionPercentage: sessionPercentage,
            weeklyPercentage: weeklyPercentage,
            todayTokensAtCalibration: todayTokens,
            weeklyTokensAtCalibration: weeklyTokens,
            sessionTokensAtCalibration: sessionTokens,
            sessionWeightedTokensAtCalibration: sessionWeightedTokens,
            weeklyWeightedTokensAtCalibration: weeklyWeightedTokens
        )
        storage.save(data, forKey: Self.storageKey)
        return data
    }

    /// Update only weekly calibration (when no active session exists).
    func calibrateWeeklyOnly(
        weeklyPercentage: Double,
        weeklyWeightedTokens: Int
    ) {
        // Preserve existing calibration if any, just update weekly fields
        let existing = currentCalibration
        let data = CalibrationData(
            calibratedAt: Date(),
            sessionStartTime: existing?.sessionStartTime ?? Date(),
            sessionPercentage: existing?.sessionPercentage ?? 0,
            weeklyPercentage: weeklyPercentage,
            todayTokensAtCalibration: existing?.todayTokensAtCalibration ?? 0,
            weeklyTokensAtCalibration: existing?.weeklyTokensAtCalibration ?? 0,
            sessionTokensAtCalibration: existing?.sessionTokensAtCalibration ?? 0,
            sessionWeightedTokensAtCalibration: existing?.sessionWeightedTokensAtCalibration ?? 0,
            weeklyWeightedTokensAtCalibration: weeklyWeightedTokens
        )
        storage.save(data, forKey: Self.storageKey)
    }

    /// Clear calibration.
    func reset() {
        storage.remove(forKey: Self.storageKey)
    }

    /// Estimate current session % using session-specific burn rate only.
    /// Returns calibrated % as floor. Only increases if session burn rate is available
    /// and new weighted tokens have been added since calibration.
    func estimatedSessionPercent(currentSessionWeightedTokens: Int) -> Double? {
        guard let cal = currentCalibration else { return nil }
        let deltaTokens = max(0, currentSessionWeightedTokens - cal.sessionWeightedTokensAtCalibration)
        if cal.sessionBurnRate > 0 && deltaTokens > 0 {
            return cal.sessionPercentage + Double(deltaTokens) / cal.sessionBurnRate
        }
        return cal.sessionPercentage
    }

    /// Estimate current weekly % using weekly-specific burn rate only.
    func estimatedWeeklyPercent(currentWeeklyWeightedTokens: Int) -> Double? {
        guard let cal = currentCalibration,
              cal.isCurrentWeek else { return nil }
        let deltaTokens = max(0, currentWeeklyWeightedTokens - cal.weeklyWeightedTokensAtCalibration)
        if cal.weeklyBurnRate > 0 && deltaTokens > 0 {
            return cal.weeklyPercentage + Double(deltaTokens) / cal.weeklyBurnRate
        }
        return cal.weeklyPercentage
    }
}

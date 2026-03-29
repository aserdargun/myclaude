import Foundation

enum Constants {
    // Session
    static let sessionDuration: TimeInterval = 5 * 60 * 60 // 5 hours
    static let idleThreshold: TimeInterval = 30 * 60 // 30 minutes

    // Polling
    static let uiUpdateInterval: TimeInterval = 5.0
    static let logPollInterval: TimeInterval = 10.0

    // Alert thresholds (percentage of session time consumed)
    static let warningThreshold: Double = 0.80
    static let criticalThreshold: Double = 0.95

    // Time-based alert thresholds
    static let oneHourWarning: TimeInterval = 60 * 60
    static let thirtyMinWarning: TimeInterval = 30 * 60

    // Calibration
    static let recalibrationInterval: TimeInterval = 60 * 60 // 1 hour
    static let claudeUsageURL = "https://claude.ai/settings/usage"

    // Log paths — focus on projects directory where JSONL conversation logs live
    static var claudeLogPaths: [String] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return [
            "\(home)/.claude/projects"
        ]
    }

    // Storage keys
    static let lastKnownSessionKey = "lastKnownSession"
    static let alertHistoryKey = "alertHistory"
    static let weeklyStatsKey = "weeklyStats"
}

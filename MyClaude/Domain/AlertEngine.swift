import Foundation
#if canImport(UserNotifications)
import UserNotifications
#endif

protocol AlertEngineDelegate: AnyObject {
    func alertEngine(_ engine: AlertEngine, didTriggerAlert alert: UsageAlert)
}

final class AlertEngine {
    weak var delegate: AlertEngineDelegate?

    private var triggeredAlerts: Set<String> = []
    private var lastAlertLevel: AlertLevel = .safe

    // MARK: - Evaluate

    func evaluate(session: UsageSession?, sessionEngine: SessionEngine) {
        guard let session else {
            resetAlerts()
            return
        }

        let remaining = session.remainingTime
        let progress = sessionEngine.sessionProgress

        // Time-based alerts
        if remaining <= Constants.thirtyMinWarning && remaining > 0 {
            triggerAlertIfNeeded(
                key: "30min_\(session.id)",
                level: .critical,
                message: "Only \(Int(remaining / 60)) minutes remaining in session!"
            )
        } else if remaining <= Constants.oneHourWarning && remaining > Constants.thirtyMinWarning {
            triggerAlertIfNeeded(
                key: "1hr_\(session.id)",
                level: .warning,
                message: "1 hour remaining in session"
            )
        }

        // Usage-based alerts
        if progress >= Constants.criticalThreshold {
            triggerAlertIfNeeded(
                key: "95pct_\(session.id)",
                level: .critical,
                message: "95% of session time consumed!"
            )
        } else if progress >= Constants.warningThreshold {
            triggerAlertIfNeeded(
                key: "80pct_\(session.id)",
                level: .warning,
                message: "80% of session time consumed"
            )
        }

        // Session expired
        if session.isExpired {
            triggerAlertIfNeeded(
                key: "expired_\(session.id)",
                level: .expired,
                message: "Session has expired. New activity will start a new session."
            )
        }
    }

    func resetAlerts() {
        triggeredAlerts.removeAll()
        lastAlertLevel = .safe
    }

    // MARK: - Private

    private func triggerAlertIfNeeded(key: String, level: AlertLevel, message: String) {
        guard !triggeredAlerts.contains(key) else { return }
        triggeredAlerts.insert(key)

        let alert = UsageAlert(level: level, message: message)
        lastAlertLevel = level
        delegate?.alertEngine(self, didTriggerAlert: alert)
        sendNotification(alert)
    }

    private func sendNotification(_ alert: UsageAlert) {
        #if canImport(UserNotifications)
        let content = UNMutableNotificationContent()
        content.title = "myClaude"
        content.body = alert.message
        content.sound = alert.level >= .critical ? .defaultCritical : .default

        let request = UNNotificationRequest(
            identifier: alert.id.uuidString,
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request)
        #endif
    }

    // MARK: - Setup

    static func requestNotificationPermission() {
        #if canImport(UserNotifications)
        UNUserNotificationCenter.current().requestAuthorization(
            options: [.alert, .sound, .badge]
        ) { granted, error in
            if let error {
                print("Notification permission error: \(error)")
            }
        }
        #endif
    }
}

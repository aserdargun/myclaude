import Foundation
import os.log
#if canImport(UserNotifications)
import UserNotifications
#endif

private let logger = Logger(subsystem: "com.myclaude", category: "AlertEngine")

protocol AlertEngineDelegate: AnyObject {
    func alertEngine(_ engine: AlertEngine, didTriggerAlert alert: UsageAlert)
}

final class AlertEngine {
    weak var delegate: AlertEngineDelegate?

    private var triggeredAlerts: Set<String> = []
    private var lastAlertLevel: AlertLevel = .safe
    private var notificationsAvailable = false

    // MARK: - Evaluate

    func evaluate(session: UsageSession, sessionEngine: SessionEngine) {
        guard session.isActive else {
            resetAlerts()
            return
        }

        let remaining = session.remainingTime
        let progress = sessionEngine.sessionProgress

        // Time-based alerts
        if remaining <= Constants.thirtyMinWarning && remaining > 0 {
            triggerAlertIfNeeded(
                key: "30min",
                level: .critical,
                message: "Only \(Int(remaining / 60)) minutes until session resets!"
            )
        } else if remaining <= Constants.oneHourWarning && remaining > Constants.thirtyMinWarning {
            triggerAlertIfNeeded(
                key: "1hr",
                level: .warning,
                message: "1 hour until session resets"
            )
        }

        // Usage-based alerts (progress = how much of the 5h window is "filled")
        if progress >= Constants.criticalThreshold {
            triggerAlertIfNeeded(
                key: "95pct",
                level: .critical,
                message: "95% of session time consumed!"
            )
        } else if progress >= Constants.warningThreshold {
            triggerAlertIfNeeded(
                key: "80pct",
                level: .warning,
                message: "80% of session time consumed"
            )
        }
    }

    func resetAlerts() {
        triggeredAlerts.removeAll()
        lastAlertLevel = .safe
    }

    /// Sends a macOS notification reminding the user to re-calibrate.
    func sendRecalibrationReminder(reason: String) {
        guard !triggeredAlerts.contains("recalibrate") else { return }
        triggeredAlerts.insert("recalibrate")

        let alert = UsageAlert(
            level: .warning,
            message: "Re-calibrate myClaude: \(reason). Open Claude settings and update your usage %."
        )
        delegate?.alertEngine(self, didTriggerAlert: alert)
        sendNotification(alert)
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
        guard notificationsAvailable else { return }
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

    /// Whether the app has a valid bundle identifier required by UNUserNotificationCenter.
    /// Calling UNUserNotificationCenter.current() without one crashes with an NSException
    /// that cannot be caught in Swift (Xcode debug builds without .app wrapper).
    private static var hasBundleIdentifier: Bool {
        Bundle.main.bundleIdentifier != nil
    }

    // MARK: - Setup

    func requestNotificationPermission() {
        guard Self.hasBundleIdentifier else {
            logger.info("Notifications unavailable: no bundle identifier (build as .app bundle)")
            return
        }
        #if canImport(UserNotifications)
        UNUserNotificationCenter.current().requestAuthorization(
            options: [.alert, .sound, .badge]
        ) { [weak self] granted, error in
            DispatchQueue.main.async { [weak self] in
                if let error {
                    logger.error("Notification permission error: \(error.localizedDescription)")
                    self?.notificationsAvailable = false
                } else if granted {
                    self?.notificationsAvailable = true
                } else {
                    logger.info("Notifications not granted by user")
                    self?.notificationsAvailable = false
                }
            }
        }
        #endif
    }
}

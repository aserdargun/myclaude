import SwiftUI
import AppKit

@main
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let viewModel = UsageViewModel()
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var updateTimer: Timer?

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)

        // Create status item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            button.target = self
            button.action = #selector(togglePopover)
            updateMenuBarTitle()
        }

        // Create popover with SwiftUI content
        popover = NSPopover()
        popover.contentSize = NSSize(width: 340, height: 500)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(
            rootView: MenuBarView(viewModel: viewModel)
        )

        // Start view model
        viewModel.start()

        // Timer to update attributed title
        updateTimer = Timer.scheduledTimer(
            timeInterval: Constants.uiUpdateInterval,
            target: self,
            selector: #selector(updateMenuBarTitle),
            userInfo: nil,
            repeats: true
        )
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }

        if popover.isShown {
            popover.performClose(nil)
        } else {
            // Update content before showing
            popover.contentViewController = NSHostingController(
                rootView: MenuBarView(viewModel: viewModel)
            )
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)

            // Close when clicking outside
            if let window = popover.contentViewController?.view.window {
                window.makeKey()
            }
        }
    }

    @objc private func updateMenuBarTitle() {
        guard let button = statusItem.button else { return }

        let fontSize: CGFloat = 9
        let font = NSFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .medium)

        if viewModel.isSessionActive {
            let mins = Int(viewModel.remainingTime / 60)
            let sessionPct = viewModel.estimatedSessionPercent
            let weeklyPct = viewModel.estimatedWeeklyPercent

            let result = NSMutableAttributedString()

            // Time segment — colored by time remaining
            let timeColor = nsColor(from: viewModel.statusColor)
            let timeStr = NSAttributedString(
                string: "\(mins)m",
                attributes: [.font: font, .foregroundColor: timeColor]
            )
            result.append(timeStr)

            // Separator
            let sep = NSAttributedString(
                string: "-",
                attributes: [.font: font, .foregroundColor: NSColor.secondaryLabelColor]
            )
            result.append(sep)

            // Session % — colored by usage
            let sessionStr: String
            let sessionColor: NSColor
            if let pct = sessionPct {
                let val = Int(min(pct, 100))
                sessionStr = "\(val)%"
                sessionColor = usageNSColor(val)
            } else {
                sessionStr = "-"
                sessionColor = NSColor.secondaryLabelColor
            }
            result.append(NSAttributedString(
                string: sessionStr,
                attributes: [.font: font, .foregroundColor: sessionColor]
            ))

            result.append(sep)

            // Weekly % — colored by usage
            let weeklyStr: String
            let weeklyColor: NSColor
            if let pct = weeklyPct {
                let val = Int(min(pct, 100))
                weeklyStr = "\(val)%"
                weeklyColor = usageNSColor(val)
            } else {
                weeklyStr = "-"
                weeklyColor = NSColor.secondaryLabelColor
            }
            result.append(NSAttributedString(
                string: weeklyStr,
                attributes: [.font: font, .foregroundColor: weeklyColor]
            ))

            button.attributedTitle = result
        } else if viewModel.hasSession {
            button.attributedTitle = NSAttributedString(
                string: "Expired",
                attributes: [.font: font, .foregroundColor: NSColor.secondaryLabelColor]
            )
        } else {
            button.attributedTitle = NSAttributedString(
                string: "No session",
                attributes: [.font: font, .foregroundColor: NSColor.secondaryLabelColor]
            )
        }
    }

    /// Convert usage percentage to NSColor: green < 60%, yellow 60-80%, red > 80%.
    private func usageNSColor(_ percent: Int) -> NSColor {
        if percent >= 80 { return NSColor.systemRed }
        if percent >= 60 { return NSColor.systemYellow }
        return NSColor.systemGreen
    }

    /// Convert SwiftUI Color to NSColor for time-based status.
    private func nsColor(from color: Color) -> NSColor {
        switch viewModel.alertLevel {
        case .safe: return NSColor.systemGreen
        case .warning: return NSColor.systemYellow
        case .critical: return NSColor.systemRed
        case .expired: return NSColor.systemGray
        }
    }
}

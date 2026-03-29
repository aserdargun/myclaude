import SwiftUI
import AppKit

/// Floating panel that behaves like MenuBarExtra's .window style:
/// - Closes when clicking outside or when the app deactivates
/// - Non-activating (doesn't steal focus from other apps)
/// - Proper rounded appearance
private class MenuBarPanel: NSPanel {
    override var canBecomeKey: Bool { true }

    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .statusBar
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isMovableByWindowBackground = false
        isReleasedWhenClosed = false
        hidesOnDeactivate = true
        backgroundColor = .clear
    }
}

@main
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let viewModel = UsageViewModel()
    private var statusItem: NSStatusItem!
    private var panel: MenuBarPanel?
    private var hostingView: NSHostingView<MenuBarView>?
    private var updateTimer: Timer?
    private var eventMonitor: Any?

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
            button.action = #selector(togglePanel)
            updateMenuBarTitle()
        }

        // Create panel with SwiftUI content
        panel = MenuBarPanel(contentRect: NSRect(x: 0, y: 0, width: 340, height: 500))
        hostingView = NSHostingView(rootView: MenuBarView(viewModel: viewModel))
        panel?.contentView = hostingView

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

    @objc private func togglePanel() {
        guard let panel else { return }
        if panel.isVisible {
            closePanel()
        } else {
            showPanel()
        }
    }

    private func showPanel() {
        guard let panel, let hostingView,
              let button = statusItem.button,
              let buttonWindow = button.window else { return }

        // Position panel below the status item
        let buttonRect = button.convert(button.bounds, to: nil)
        let screenRect = buttonWindow.convertToScreen(buttonRect)

        let panelWidth: CGFloat = 340
        let x = screenRect.midX - panelWidth / 2
        let y = screenRect.minY

        // Size the panel to fit content
        let fittingSize = hostingView.fittingSize
        let panelHeight = min(fittingSize.height, 700)

        panel.setFrame(
            NSRect(x: x, y: y - panelHeight, width: panelWidth, height: panelHeight),
            display: true
        )

        panel.makeKeyAndOrderFront(nil)

        // Start monitoring for outside clicks to close
        startEventMonitor()
    }

    private func closePanel() {
        panel?.orderOut(nil)
        stopEventMonitor()
    }

    private func startEventMonitor() {
        stopEventMonitor()
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self, let panel = self.panel, panel.isVisible else { return }
            // Only close if the click is outside the panel
            let clickLocation = event.locationInWindow
            if event.window != panel {
                self.closePanel()
            }
        }
    }

    private func stopEventMonitor() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
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
            let timeColor = nsColorForTime()
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

    /// Usage percentage to NSColor: green < 60%, yellow 60-80%, red > 80%.
    private func usageNSColor(_ percent: Int) -> NSColor {
        if percent >= 80 { return NSColor.systemRed }
        if percent >= 60 { return NSColor.systemYellow }
        return NSColor.systemGreen
    }

    /// Time-based status color.
    private func nsColorForTime() -> NSColor {
        switch viewModel.alertLevel {
        case .safe: return NSColor.systemGreen
        case .warning: return NSColor.systemYellow
        case .critical: return NSColor.systemRed
        case .expired: return NSColor.systemGray
        }
    }
}

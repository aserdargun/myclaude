import SwiftUI
import AppKit

/// Custom NSView for drawing two lines of text in the menubar.
/// Uses manual frame-based drawing — no Auto Layout to avoid
/// layout recursion inside NSStatusBarButton.
private class MenuBarStatusView: NSView {
    var labelLine: NSAttributedString?
    var valueLine: NSAttributedString?

    override func draw(_ dirtyRect: NSRect) {
        guard let labelLine, let valueLine else { return }

        let labelSize = labelLine.size()
        let valueSize = valueLine.size()
        let totalHeight = labelSize.height + valueSize.height
        let topPad = (bounds.height - totalHeight) / 2

        // Label (top), centered horizontally
        let labelX = (bounds.width - labelSize.width) / 2
        labelLine.draw(at: NSPoint(x: labelX, y: bounds.height - topPad - labelSize.height))

        // Values (below label), centered horizontally
        let valueX = (bounds.width - valueSize.width) / 2
        valueLine.draw(at: NSPoint(x: valueX, y: bounds.height - topPad - labelSize.height - valueSize.height))
    }

    override func mouseDown(with event: NSEvent) {
        superview?.mouseDown(with: event)
    }
}

/// Floating panel that behaves like MenuBarExtra's .window style:
/// - Closes when clicking outside or when the app deactivates
/// - Non-activating (doesn't steal focus from other apps)
/// - Proper rounded appearance
private class MenuBarPanel: NSPanel {
    override var canBecomeKey: Bool { true }

    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.nonactivatingPanel, .fullSizeContentView, .borderless],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .statusBar
        isMovableByWindowBackground = false
        isReleasedWhenClosed = false
        hasShadow = true
        isOpaque = false
        backgroundColor = NSColor.windowBackgroundColor
    }
}

@main
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let viewModel = UsageViewModel()
    private var statusItem: NSStatusItem!
    private var panel: MenuBarPanel?
    private var hostingView: NSHostingView<MenuBarView>?
    private var updateTimer: Timer?
    private var activity: NSObjectProtocol?

    /// Two-line menubar custom view
    private var menuBarView: MenuBarStatusView?

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)

        // Prevent App Nap from suspending timers when no windows are visible
        activity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiatedAllowingIdleSystemSleep, .idleSystemSleepDisabled],
            reason: "Menubar needs continuous timer updates"
        )

        // Create status item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            button.target = self
            button.action = #selector(togglePanel)
            updateMenuBarTitle()
        }

        // Create panel with SwiftUI content
        panel = MenuBarPanel(contentRect: NSRect(x: 0, y: 0, width: 340, height: 500))
        panel?.delegate = self
        hostingView = NSHostingView(rootView: MenuBarView(viewModel: viewModel))
        panel?.contentView = hostingView

        // Listen for content size changes to resize panel
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(resizePanel),
            name: .panelContentDidChange,
            object: nil
        )

        // Refresh menubar title immediately when scrape data arrives
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(updateMenuBarTitle),
            name: .scrapeDataDidUpdate,
            object: nil
        )

        // Start view model
        viewModel.start()

        // Timer to update attributed title — use .common mode so it fires
        // even during menu tracking and other UI interactions
        let timer = Timer(
            timeInterval: Constants.uiUpdateInterval,
            target: self,
            selector: #selector(updateMenuBarTitle),
            userInfo: nil,
            repeats: true
        )
        RunLoop.main.add(timer, forMode: .common)
        updateTimer = timer

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
        guard let panel,
              let hostingView,
              let button = statusItem.button,
              let buttonWindow = button.window else { return }

        // Position panel below the status item
        let buttonRect = button.convert(button.bounds, to: nil)
        let screenRect = buttonWindow.convertToScreen(buttonRect)

        let panelWidth: CGFloat = 340
        // Compute intrinsic height from SwiftUI content
        let fittingSize = hostingView.fittingSize
        let panelHeight = min(max(fittingSize.height, 300), 800)
        let x = screenRect.midX - panelWidth / 2
        let y = screenRect.minY - panelHeight

        panel.setFrame(
            NSRect(x: x, y: y, width: panelWidth, height: panelHeight),
            display: true
        )

        panel.makeKeyAndOrderFront(nil)
    }

    private func closePanel() {
        panel?.orderOut(nil)
    }

    @objc private func resizePanel() {
        guard let panel, let hostingView, panel.isVisible else { return }

        let panelWidth: CGFloat = 340
        let fittingSize = hostingView.fittingSize
        let newHeight = min(max(fittingSize.height, 300), 800)

        // Keep the top edge fixed: top = frame.maxY
        let topEdge = panel.frame.maxY
        let newY = topEdge - newHeight
        let newFrame = NSRect(x: panel.frame.origin.x, y: newY, width: panelWidth, height: newHeight)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().setFrame(newFrame, display: true)
        }
    }

    // MARK: - NSWindowDelegate

    func windowDidResignKey(_ notification: Notification) {
        closePanel()
    }

    @objc private func updateMenuBarTitle() {
        guard let button = statusItem.button else { return }

        let valueFontSize: CGFloat = 9
        let labelFontSize: CGFloat = 7
        let valueFont = NSFont.monospacedDigitSystemFont(ofSize: valueFontSize, weight: .medium)
        let labelFont = NSFont.systemFont(ofSize: labelFontSize, weight: .regular)
        let labelColor = NSColor.secondaryLabelColor

        if viewModel.isSessionActive {
            let mins = Int(viewModel.remainingTime / 60)
            let sessionPct = viewModel.estimatedSessionPercent
            let weeklyPct = viewModel.estimatedWeeklyPercent

            // -- Label row --
            let labelLine = NSAttributedString(
                string: "Resets in - Session - Weekly",
                attributes: [.font: labelFont, .foregroundColor: labelColor]
            )

            // -- Value row (colored) --
            let valueLine = NSMutableAttributedString()
            let timeColor = nsColorForTime()
            valueLine.append(NSAttributedString(
                string: "\(mins)m",
                attributes: [.font: valueFont, .foregroundColor: timeColor]
            ))
            let sep = NSAttributedString(
                string: "-",
                attributes: [.font: valueFont, .foregroundColor: NSColor.secondaryLabelColor]
            )
            valueLine.append(sep)

            if let pct = sessionPct {
                let val = Int(min(pct, 100))
                valueLine.append(NSAttributedString(
                    string: "\(val)%",
                    attributes: [.font: valueFont, .foregroundColor: usageNSColor(val)]
                ))
            } else {
                valueLine.append(NSAttributedString(
                    string: "-",
                    attributes: [.font: valueFont, .foregroundColor: NSColor.secondaryLabelColor]
                ))
            }
            valueLine.append(sep)

            if let pct = weeklyPct {
                let val = Int(min(pct, 100))
                valueLine.append(NSAttributedString(
                    string: "\(val)%",
                    attributes: [.font: valueFont, .foregroundColor: usageNSColor(val)]
                ))
            } else {
                valueLine.append(NSAttributedString(
                    string: "-",
                    attributes: [.font: valueFont, .foregroundColor: NSColor.secondaryLabelColor]
                ))
            }

            applyTwoLineDisplay(button: button, labelLine: labelLine, valueLine: valueLine)

        } else if viewModel.hasSession {
            let text = NSAttributedString(
                string: "Expired",
                attributes: [.font: valueFont, .foregroundColor: NSColor.secondaryLabelColor]
            )
            applySingleLineDisplay(button: button, text: text)
        } else {
            let text = NSAttributedString(
                string: "No session",
                attributes: [.font: valueFont, .foregroundColor: NSColor.secondaryLabelColor]
            )
            applySingleLineDisplay(button: button, text: text)
        }
    }

    private func applyTwoLineDisplay(button: NSStatusBarButton, labelLine: NSAttributedString, valueLine: NSAttributedString) {
        let labelSize = labelLine.size()
        let valueSize = valueLine.size()
        let width = ceil(max(labelSize.width, valueSize.width)) + 8
        let barHeight = NSStatusBar.system.thickness

        statusItem.length = width

        if menuBarView == nil {
            let view = MenuBarStatusView(frame: NSRect(x: 0, y: 0, width: width, height: barHeight))
            button.addSubview(view)
            menuBarView = view
        }

        menuBarView?.frame = NSRect(x: 0, y: 0, width: width, height: barHeight)
        menuBarView?.labelLine = labelLine
        menuBarView?.valueLine = valueLine
        menuBarView?.isHidden = false
        menuBarView?.needsDisplay = true
        button.attributedTitle = NSAttributedString()
    }

    private func applySingleLineDisplay(button: NSStatusBarButton, text: NSAttributedString) {
        menuBarView?.isHidden = true
        statusItem.length = NSStatusItem.variableLength
        button.attributedTitle = text
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

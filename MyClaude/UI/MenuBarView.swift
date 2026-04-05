import SwiftUI

extension Notification.Name {
    static let panelContentDidChange = Notification.Name("panelContentDidChange")
    static let scrapeDataDidUpdate = Notification.Name("scrapeDataDidUpdate")
}

struct MenuBarView: View {
    let viewModel: UsageViewModel
    @State private var isLocalExpanded = false

    var body: some View {
        if viewModel.showSettings {
            SettingsView(viewModel: viewModel)
        } else {
            mainView
        }
    }

    private var mainView: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                MyClaudeIcon(size: 18)
                Text("myClaude")
                    .font(.headline)
                    .fontWeight(.bold)

                Spacer()

                // Scrape status in title bar
                if viewModel.isScraping || viewModel.isRefreshing {
                    HStack(spacing: 4) {
                        ProgressView()
                            .controlSize(.mini)
                        Text("Updating...")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                } else if let error = viewModel.scrapeError {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption2)
                            .foregroundStyle(.red)
                        Text(error)
                            .font(.caption2)
                            .foregroundStyle(.red)
                            .lineLimit(1)
                        Button {
                            viewModel.scrapeError = nil
                        } label: {
                            Image(systemName: "xmark")
                                .font(.caption2)
                        }
                        .buttonStyle(.borderless)
                    }
                } else if viewModel.scrapeSuccess {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption2)
                            .foregroundStyle(.green)
                        Text("Updated")
                            .font(.caption2)
                            .foregroundStyle(.green)
                    }
                }

                Button {
                    viewModel.forceRefresh()
                    viewModel.scrapeAndCalibrate()
                } label: {
                    Image(systemName: "globe")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .help("Auto-refresh and scrape")
                .disabled(viewModel.isScraping || viewModel.isRefreshing)

                Button {
                    viewModel.showSettings = true
                } label: {
                    Image(systemName: "gearshape")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .help("Settings & Calibration")

                Circle()
                    .fill(sessionPercentColor)
                    .frame(width: 10, height: 10)
            }
            .padding(.bottom, 4)

            // Claude header (centered)
            HStack {
                Spacer()
                Image(systemName: "sparkle")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text("Claude")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .textCase(.uppercase)
                    .foregroundStyle(.secondary)
                Spacer()
            }

            // Section 1: Current Session
            sessionSection

            // Section 2: Weekly Limits
            weeklyLimitsSection

            // Section 3: Extra Usage (if available)
            if viewModel.extraUsageEnabled != nil {
                extraUsageSection
            }

            Divider()

            // Section 4: Local (session usage, today, this week, daily breakdown)
            localSection

            Divider()

            // Actions
            actionsSection
        }
        .padding(12)
        .frame(width: 340)
        .onAppear {
            // Initial resize
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                NotificationCenter.default.post(name: .panelContentDidChange, object: nil)
            }
        }
        .onChange(of: viewModel.extraUsageEnabled) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                NotificationCenter.default.post(name: .panelContentDidChange, object: nil)
            }
        }
    }

    // MARK: - Session Section

    private var sessionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Current Session", icon: "clock")

            if viewModel.isSessionActive {
                // Active session
                HStack {
                    Text("Resets in \(viewModel.displayRemainingTime.compactRemaining)")
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundStyle(viewModel.statusColor)
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(viewModel.sessionPercentDisplay)
                            .font(.title2)
                            .fontWeight(.semibold)
                            .foregroundStyle(sessionPercentColor)
                        if let cal = viewModel.calibrationData {
                            Text("Updated \(cal.calibratedAt.shortTimeString)")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }

                ProgressBarView(
                    progress: viewModel.calibratedSessionProgress,
                    color: sessionPercentColor
                )

                if let start = viewModel.windowStartTime,
                   let end = viewModel.windowEndTime {
                    HStack {
                        Text("First: \(start.shortTimeString)")
                        Spacer()
                        Text("Resets: \(end.shortTimeString)")
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }
            } else if viewModel.hasSession {
                // Session expired (no events in last 5h)
                HStack {
                    Text("Session expired")
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                    Spacer()
                }

                ProgressBarView(progress: 1.0, color: .gray)

                if let start = viewModel.windowStartTime,
                   let end = viewModel.windowEndTime {
                    HStack {
                        Text("Last active: \(start.shortTimeString) – \(end.shortTimeString)")
                        Spacer()
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }
            } else {
                Text("No session detected")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Text("Start using Claude to begin tracking")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: - Recalibration Banner

    // MARK: - Weekly Limits Section

    private var weeklyLimitsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header with All Models % right-aligned
            HStack(alignment: .top) {
                SectionHeader(title: "Weekly Limits", icon: "chart.bar")
                Spacer()
                if let weeklyPct = viewModel.estimatedWeeklyPercent {
                    Text("\(Int(min(weeklyPct, 100)))%")
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundStyle(usageColor(weeklyPct))
                }
            }

            // All Models progress bar with targets
            if let weeklyPct = viewModel.estimatedWeeklyPercent {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("All Models")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        if let reset = viewModel.scrapedAllModelsReset {
                            Text(resetDisplayText(reset))
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    VStack(spacing: 0) {
                        ProgressBarView(
                            progress: min(weeklyPct / 100.0, 1.0),
                            color: usageColor(weeklyPct),
                            dailyTargets: viewModel.dailyTargets,
                            currentDayIndex: currentWindowSegmentIndex
                        )
                        .frame(height: 8)

                        targetLabelsRow
                    }
                }
            }

            // Sonnet only with % right-aligned above reset text
            if let sonnetPct = viewModel.scrapedSonnetPercent {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .top) {
                        Text("Sonnet only")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("\(Int(min(sonnetPct, 100)))%")
                                .font(.callout)
                                .fontWeight(.semibold)
                                .foregroundStyle(usageColor(sonnetPct))
                            if let reset = viewModel.scrapedSonnetReset {
                                Text(resetDisplayText(reset))
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                    ProgressBarView(
                        progress: min(sonnetPct / 100.0, 1.0),
                        color: usageColor(sonnetPct)
                    )
                    .frame(height: 4)
                }
            }

            if viewModel.estimatedWeeklyPercent == nil && viewModel.scrapedSonnetPercent == nil {
                Text("Waiting for browser scrape data...")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: - Extra Usage Section

    private var extraUsageSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                SectionHeader(title: "Extra Usage", icon: "dollarsign.circle")
                Spacer()
                if let enabled = viewModel.extraUsageEnabled {
                    Text(enabled ? "On" : "Off")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(enabled ? .green : .secondary)
                }
            }

            if viewModel.extraUsageEnabled == true {
                // Spent and limit
                if let spent = viewModel.extraUsageSpent {
                    HStack {
                        Text(String(format: "$%.2f Spent", spent))
                            .font(.caption)
                            .foregroundStyle(.primary)
                        Spacer()
                        if let resets = viewModel.extraUsageResets {
                            Text("Resets \(resets)")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }

                    // Progress bar
                    if let limit = viewModel.extraUsageLimit, limit > 0 {
                        let pct = min(spent / limit * 100, 100)
                        ProgressBarView(
                            progress: pct / 100.0,
                            color: usageColor(pct)
                        )
                        .frame(height: 4)

                        HStack {
                            Text("\(Int(pct))% used")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(String(format: "$%.0f limit", limit))
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            }
        }
    }

    private static let shortDayNames = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

    /// Day labels for 8-segment targets in window order.
    /// The reset day appears as first and last element.
    private var windowDayLabels: [String] {
        let resetDay = resetDayCalendarIndex
        var labels: [String] = []
        for i in 0..<7 {
            let idx = (resetDay + i) % 7
            labels.append(Self.shortDayNames[idx])
        }
        labels.append(Self.shortDayNames[resetDay])
        return labels
    }

    /// Calendar day index (0=Sun) of the weekly reset day
    private var resetDayCalendarIndex: Int {
        if let reset = viewModel.scrapedAllModelsReset {
            switch reset {
            case .resetsAt(let day, _):
                let map = ["sun": 0, "mon": 1, "tue": 2, "wed": 3, "thu": 4, "fri": 5, "sat": 6]
                return map[day.lowercased().prefix(3).description] ?? 0
            case .resetsIn(let interval):
                let resetDate = Date().addingTimeInterval(interval)
                let weekday = Calendar.current.component(.weekday, from: resetDate)
                return weekday - 1
            }
        }
        return 0
    }

    /// Which of the 8 target segments is "today"?
    /// Segments: [resetDay1, day2, day3, ..., day7, resetDay2]
    private var currentWindowSegmentIndex: Int {
        let weekday = Calendar.current.component(.weekday, from: viewModel.todayStats.date)
        let todayCalIndex = weekday - 1  // 0=Sun
        let resetDay = resetDayCalendarIndex
        let offset = (todayCalIndex - resetDay + 7) % 7
        // offset 0 = reset day. Could be segment 0 (first half) or 7 (second half).
        // Use current time vs reset time to decide.
        if offset == 0 {
            return isBeforeResetTime ? 7 : 0
        }
        return offset
    }

    /// Whether current time is before the reset time on the reset day
    private var isBeforeResetTime: Bool {
        if let reset = viewModel.scrapedAllModelsReset {
            switch reset {
            case .resetsAt(_, let time):
                let formatter = DateFormatter()
                formatter.dateFormat = "h:mm a"
                if let resetDate = formatter.date(from: time) {
                    let cal = Calendar.current
                    let resetHour = cal.component(.hour, from: resetDate)
                    let resetMin = cal.component(.minute, from: resetDate)
                    let nowHour = cal.component(.hour, from: Date())
                    let nowMin = cal.component(.minute, from: Date())
                    return (nowHour * 60 + nowMin) < (resetHour * 60 + resetMin)
                }
            case .resetsIn:
                return false
            }
        }
        return false
    }

    /// Day name and target % labels centered within each segment between vertical markers
    private var targetLabelsRow: some View {
        GeometryReader { geometry in
            let targets = viewModel.dailyTargets
            let labels = windowDayLabels
            let segIndex = currentWindowSegmentIndex
            ForEach(0..<targets.count, id: \.self) { i in
                let segStart = i == 0 ? 0 : targets.prefix(i).reduce(0, +)
                let segEnd = targets.prefix(i + 1).reduce(0, +)
                let xStart = geometry.size.width * Double(segStart) / 100.0
                let xEnd = geometry.size.width * Double(segEnd) / 100.0
                let isCurrentDay = (i == segIndex)
                VStack(spacing: 0) {
                    Text(i < labels.count ? labels[i] : "")
                        .font(.system(size: 7))
                        .foregroundStyle(isCurrentDay ? .red : .secondary)
                    Text("\(targets.prefix(i + 1).reduce(0, +))%")
                        .font(.system(size: 8))
                        .foregroundColor(isCurrentDay ? .red.opacity(0.7) : .secondary.opacity(0.6))
                }
                .position(x: (xStart + xEnd) / 2, y: geometry.size.height / 2)
            }
        }
        .frame(height: 20)
    }

    private func resetDisplayText(_ reset: WeeklyResetInfo) -> String {
        switch reset {
        case .resetsIn(let interval):
            return "Resets in \(interval.compactRemaining)"
        case .resetsAt(let day, let time):
            return "Resets \(day) \(time)"
        }
    }

    /// Session percentage color using the unified usage color scale.
    private var sessionPercentColor: Color {
        if let pct = viewModel.estimatedSessionPercent {
            return usageColor(pct)
        }
        return usageColor(viewModel.sessionProgress * 100)
    }

    /// Unified color for any usage percentage: green < 60%, yellow 60–80%, red > 80%.
    private func usageColor(_ percent: Double) -> Color {
        if percent >= 80 { return .red }
        if percent >= 60 { return .yellow }
        return .green
    }

    // MARK: - Local Section

    private var localSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                isLocalExpanded.toggle()
                // Resize panel immediately — no delay to avoid top-section jitter
                NotificationCenter.default.post(name: .panelContentDidChange, object: nil)
            } label: {
                HStack {
                    Spacer()
                    Image(systemName: isLocalExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    SectionHeader(title: "Local", icon: "desktopcomputer")
                    Spacer()
                }
            }
            .buttonStyle(.borderless)

            if isLocalExpanded {
                StatsView(
                    viewModel: viewModel,
                    hasCalibration: viewModel.calibrationData != nil
                )
            }
        }
    }

    // MARK: - Actions

    private var actionsSection: some View {
        VStack(spacing: 4) {
            Button("Quit myClaude") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.borderless)
            .font(.caption)
            .foregroundStyle(.red)
        }
        .frame(maxWidth: .infinity)
    }

}

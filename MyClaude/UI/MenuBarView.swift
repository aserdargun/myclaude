import SwiftUI

struct MenuBarView: View {
    let viewModel: UsageViewModel

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

            // Re-calibration reminder
            if viewModel.needsRecalibration {
                recalibrationBanner
            }

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

            Divider()

            // Section 3: Local (session usage, today, this week, daily breakdown)
            localSection

            Divider()

            // Actions
            actionsSection
        }
        .padding(12)
        .frame(width: 340)
    }

    // MARK: - Session Section

    private var sessionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Current Session", icon: "clock")

            if viewModel.isSessionActive {
                // Active session
                HStack {
                    Text("Resets in \(viewModel.remainingTime.compactRemaining)")
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundStyle(viewModel.statusColor)
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(viewModel.sessionPercentDisplay)
                            .font(.title3)
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

    private var recalibrationBanner: some View {
        Button {
            viewModel.showSettings = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: viewModel.calibrationPeriodChanged
                      ? "exclamationmark.triangle.fill"
                      : "clock.arrow.circlepath")
                    .font(.caption)
                    .foregroundStyle(viewModel.calibrationPeriodChanged ? .orange : .yellow)

                VStack(alignment: .leading, spacing: 1) {
                    Text(viewModel.calibrationPeriodChanged
                         ? "New period — re-calibrate"
                         : "Calibration is \(calibrationAgeText) old")
                        .font(.caption2)
                        .fontWeight(.medium)
                    Text("Update % from Claude settings")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(viewModel.calibrationPeriodChanged
                          ? Color.orange.opacity(0.1)
                          : Color.yellow.opacity(0.1))
            )
        }
        .buttonStyle(.borderless)
    }

    private var calibrationAgeText: String {
        guard let age = viewModel.calibrationAge else { return "?" }
        let hours = Int(age) / 3600
        let minutes = (Int(age) % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }

    // MARK: - Weekly Limits Section

    private var weeklyLimitsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header with All Models % right-aligned (bigger) and reset below
            HStack(alignment: .top) {
                SectionHeader(title: "Weekly Limits", icon: "chart.bar")
                Spacer()
                if let weeklyPct = viewModel.estimatedWeeklyPercent {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(Int(min(weeklyPct, 100)))%")
                            .font(.title3)
                            .fontWeight(.semibold)
                            .foregroundStyle(usageColor(weeklyPct))
                        if let reset = viewModel.scrapedAllModelsReset {
                            Text(resetDisplayText(reset))
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
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
                    }
                    VStack(spacing: 0) {
                        ProgressBarView(
                            progress: min(weeklyPct / 100.0, 1.0),
                            color: usageColor(weeklyPct),
                            dailyTargets: viewModel.dailyTargets,
                            currentDayIndex: currentSundayBasedDayIndex
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
                                .font(.caption)
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

    /// Labels showing cumulative target % below each vertical marker
    private var targetLabelsRow: some View {
        GeometryReader { geometry in
            let targets = viewModel.dailyTargets
            let dayIndex = currentSundayBasedDayIndex
            ForEach(0..<targets.count - 1, id: \.self) { i in
                let cumulative = targets.prefix(i + 1).reduce(0, +)
                let xPos = geometry.size.width * Double(cumulative) / 100.0
                let isCurrentDay = (i == dayIndex)
                Text("\(cumulative)")
                    .font(.system(size: 7))
                    .foregroundStyle(isCurrentDay ? .red : .secondary)
                    .position(x: xPos, y: geometry.size.height / 2)
            }
        }
        .frame(height: 12)
    }

    /// Current day index where Sunday=0, Saturday=6
    private var currentSundayBasedDayIndex: Int {
        let weekday = Calendar.current.component(.weekday, from: Date())
        return weekday - 1  // Calendar weekday: 1=Sun, 2=Mon, ..., 7=Sat → 0-6
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
            HStack {
                Spacer()
                SectionHeader(title: "Local", icon: "desktopcomputer")
                Spacer()
            }

            StatsView(
                weeklyStats: viewModel.weeklyStats,
                todayStats: viewModel.todayStats,
                todaySessionCount: viewModel.todaySessionCount,
                currentTokens: viewModel.currentTokens,
                currentEventCount: viewModel.currentEventCount,
                hasCalibration: viewModel.calibrationData != nil
            )
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

    private func formatTokens(_ count: Int) -> String {
        if count >= 1_000_000 {
            return String(format: "%.1fM", Double(count) / 1_000_000)
        } else if count >= 1_000 {
            return String(format: "%.1fK", Double(count) / 1_000)
        }
        return "\(count)"
    }
}

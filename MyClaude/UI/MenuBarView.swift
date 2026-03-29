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
                Text("myClaude")
                    .font(.headline)
                    .fontWeight(.bold)
                Spacer()

                Button {
                    viewModel.forceRefresh()
                    viewModel.scrapeAndCalibrate()
                } label: {
                    if viewModel.isScraping || viewModel.isRefreshing {
                        ProgressView()
                            .controlSize(.mini)
                    } else {
                        Image(systemName: "globe")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
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
                    .fill(viewModel.statusColor)
                    .frame(width: 10, height: 10)
            }
            .padding(.bottom, 4)

            // Browser scrape feedback
            if let error = viewModel.scrapeError {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption2)
                        .foregroundStyle(.red)
                    Text(error)
                        .font(.caption2)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Button {
                        viewModel.scrapeError = nil
                    } label: {
                        Image(systemName: "xmark")
                            .font(.caption2)
                    }
                    .buttonStyle(.borderless)
                }
                .padding(6)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.red.opacity(0.1)))
            }

            if viewModel.scrapeSuccess {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption2)
                        .foregroundStyle(.green)
                    Text("Scraped from browser")
                        .font(.caption2)
                        .foregroundStyle(.green)
                }
                .padding(6)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.green.opacity(0.1)))
            }

            // Re-calibration reminder
            if viewModel.needsRecalibration {
                recalibrationBanner
                Divider()
            }

            // Section 1: Current Session (All)
            sessionSection

            Divider()

            // Section 2: Weekly Limits
            weeklyLimitsSection

            Divider()

            // Section 3: Local (session usage, today, this week, daily breakdown)
            localSection

            Divider()

            // Section 4: Debug
            debugSection

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
            SectionHeader(title: "Current Session on Claude", icon: "clock")

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
                            .foregroundStyle(viewModel.statusColor)
                        if let cal = viewModel.calibrationData {
                            Text("Scraped \(cal.calibratedAt.shortTimeString)")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }

                ProgressBarView(
                    progress: viewModel.calibratedSessionProgress,
                    color: viewModel.statusColor
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
            SectionHeader(title: "Weekly Limits on Claude", icon: "chart.bar")

            // All Models
            if let weeklyPct = viewModel.estimatedWeeklyPercent {
                weeklyLimitRow(
                    label: "All Models",
                    percent: weeklyPct,
                    reset: viewModel.scrapedAllModelsReset,
                    color: weeklyLimitColor(weeklyPct)
                )
            }

            // Sonnet only
            if let sonnetPct = viewModel.scrapedSonnetPercent {
                weeklyLimitRow(
                    label: "Sonnet only",
                    percent: sonnetPct,
                    reset: viewModel.scrapedSonnetReset,
                    color: weeklyLimitColor(sonnetPct)
                )
            }

            if viewModel.estimatedWeeklyPercent == nil && viewModel.scrapedSonnetPercent == nil {
                Text("Waiting for browser scrape data...")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func weeklyLimitRow(label: String, percent: Double, reset: WeeklyResetInfo?, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(Int(min(percent, 100)))%")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(color)
                if let reset = reset {
                    Text(resetDisplayText(reset))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            ProgressBarView(
                progress: min(percent / 100.0, 1.0),
                color: color
            )
            .frame(height: 4)
        }
    }

    private func resetDisplayText(_ reset: WeeklyResetInfo) -> String {
        switch reset {
        case .resetsIn(let interval):
            return "Resets in \(interval.compactRemaining)"
        case .resetsAt(let day, let time):
            return "Resets \(day) \(time)"
        }
    }

    private func weeklyLimitColor(_ percent: Double) -> Color {
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

    // MARK: - Debug Section

    private var debugSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionHeader(title: "Debug", icon: "ant")

            if let lastRead = viewModel.lastLogRead {
                StatRow(label: "Last log read", value: lastRead.shortTimeString)
            } else {
                StatRow(label: "Last log read", value: "Never")
            }
            StatRow(label: "Events parsed", value: "\(viewModel.totalEventsRead)")
            StatRow(label: "Sessions detected", value: "\(viewModel.todaySessionCount)")

            if viewModel.calibrationData != nil {
                StatRow(label: "Updated", value: calibrationAgeText + " ago")
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

    private func formatTokens(_ count: Int) -> String {
        if count >= 1_000_000 {
            return String(format: "%.1fM", Double(count) / 1_000_000)
        } else if count >= 1_000 {
            return String(format: "%.1fK", Double(count) / 1_000)
        }
        return "\(count)"
    }
}

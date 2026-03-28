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

            // Re-calibration reminder
            if viewModel.needsRecalibration {
                recalibrationBanner
                Divider()
            }

            // Section 1: Session
            sessionSection

            Divider()

            // Section 2: Usage (last/current session)
            usageSection

            Divider()

            // Section 3: Today + Weekly
            StatsView(
                weeklyStats: viewModel.weeklyStats,
                todayStats: viewModel.todayStats,
                todaySessionCount: viewModel.todaySessionCount,
                estimatedWeeklyPercent: viewModel.estimatedWeeklyPercent
            )

            Divider()

            // Section 4: Debug
            debugSection

            Divider()

            // Actions
            actionsSection
        }
        .padding(12)
        .frame(width: 280)
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
                    Text(viewModel.sessionPercentDisplay)
                        .font(.caption)
                        .foregroundStyle(.secondary)
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

    // MARK: - Usage Section

    private var usageSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(
                title: viewModel.isSessionActive ? "Session Usage" : "Last Session Usage",
                icon: "chart.pie"
            )

            // Show estimated % from calibration prominently
            if let pct = viewModel.estimatedSessionPercent {
                HStack {
                    Text("Estimated")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(Int(min(pct, 100)))% of limit")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.blue)
                }
            }

            HStack {
                StatRow(
                    label: viewModel.calibrationData != nil ? "Local Tokens" : "Tokens",
                    value: formatTokens(viewModel.currentTokens)
                )
            }
            StatRow(
                label: viewModel.calibrationData != nil ? "Local Events" : "Events",
                value: "\(viewModel.currentEventCount)"
            )

            if viewModel.calibrationData != nil && viewModel.currentTokens == 0 {
                Text("No local events in this period yet.\nRe-calibrate to update % from Claude.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
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
                StatRow(label: "Calibration", value: calibrationAgeText + " ago")
            }
        }
    }

    // MARK: - Actions

    private var actionsSection: some View {
        VStack(spacing: 4) {
            Button {
                viewModel.forceRefresh()
            } label: {
                if viewModel.isRefreshing {
                    HStack(spacing: 4) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Scanning...")
                    }
                } else {
                    Text("Refresh Now")
                }
            }
            .buttonStyle(.borderless)
            .font(.caption)
            .disabled(viewModel.isRefreshing)

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

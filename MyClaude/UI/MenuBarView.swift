import SwiftUI

struct MenuBarView: View {
    let viewModel: UsageViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Text("myClaude")
                    .font(.headline)
                    .fontWeight(.bold)
                Spacer()
                Circle()
                    .fill(viewModel.statusColor)
                    .frame(width: 10, height: 10)
            }
            .padding(.bottom, 4)

            Divider()

            // Section 1: Session
            sessionSection

            Divider()

            // Section 2: Usage
            usageSection

            Divider()

            // Section 3: Weekly
            StatsView(
                weeklyStats: viewModel.weeklyStats,
                todayStats: viewModel.todayStats
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
                HStack {
                    Text("Resets in \(viewModel.remainingTime.compactRemaining)")
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundStyle(viewModel.statusColor)
                    Spacer()
                    Text("\(Int(viewModel.sessionProgress * 100))%")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                ProgressBarView(
                    progress: viewModel.sessionProgress,
                    color: viewModel.statusColor
                )

                if let start = viewModel.windowStartTime,
                   let end = viewModel.windowEndTime {
                    HStack {
                        Text("Started: \(start.shortTimeString)")
                        Spacer()
                        Text("Ends: \(end.shortTimeString)")
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }
            } else {
                Text("No active session")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Text("Start using Claude to begin tracking")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: - Usage Section

    private var usageSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Current Usage", icon: "chart.pie")

            StatRow(
                label: "Tokens",
                value: formatTokens(viewModel.currentTokens)
            )
            StatRow(
                label: "Events",
                value: "\(viewModel.currentEventCount)"
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

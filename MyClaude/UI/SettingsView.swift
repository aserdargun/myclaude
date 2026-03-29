import SwiftUI

/// A single 5-hour period in the chain from the input start to now.
private struct SessionPeriod: Identifiable {
    let id: Int // period index (0-based)
    let start: Date
    let end: Date
    let tokens: Int
    let weightedTokens: Int
    let events: Int
    let isCurrent: Bool // contains "now"

    var isExpired: Bool { Date() >= end }

    var remaining: TimeInterval { max(0, end.timeIntervalSince(Date())) }

    var elapsed: Double {
        let e = Date().timeIntervalSince(start)
        return min(1.0, max(0, e / Constants.sessionDuration))
    }
}

struct SettingsView: View {
    let viewModel: UsageViewModel

    @State private var showResetConfirmation: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Button {
                    viewModel.showSettings = false
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.caption)
                }
                .buttonStyle(.borderless)

                Text("Settings")
                    .font(.headline)
                    .fontWeight(.bold)
                Spacer()
            }

            Divider()

            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 12) {
                    // Scrape settings
                    scrapeSettingsSection

                    Divider()

                    // 5h period chain
                    periodChainSection

                    Divider()

                    // Burn rates (if calibrated)
                    if let cal = viewModel.calibrationData {
                        burnRatesSection(cal)
                        Divider()
                    }

                    // Calibrated estimates
                    if viewModel.calibrationData != nil {
                        estimatesSection
                    }
                }
                .padding(.bottom, 8)
            }
        }
        .padding(12)
        .frame(width: 340, height: 600)
    }

    // MARK: - Period chain from calibration data

    /// Build the current 5h period from calibration data.
    private var periods: [SessionPeriod] {
        guard let cal = viewModel.calibrationData else { return [] }
        let now = Date()
        let firstStart = cal.sessionStartTime
        guard firstStart <= now else { return [] }

        var result: [SessionPeriod] = []
        var periodStart = firstStart
        var index = 0

        while periodStart < now {
            let periodEnd = periodStart.addingTimeInterval(Constants.sessionDuration)
            let isCurrent = now >= periodStart && now < periodEnd
            let usage = viewModel.usage(from: periodStart, to: periodEnd)

            result.append(SessionPeriod(
                id: index,
                start: periodStart,
                end: periodEnd,
                tokens: usage.tokens,
                weightedTokens: usage.weightedTokens,
                events: usage.events,
                isCurrent: isCurrent
            ))

            periodStart = periodEnd
            index += 1
        }
        return result
    }

    /// Estimated % for a period using session burn rate.
    private func estimatedPercent(weightedTokens: Int) -> Double? {
        guard let cal = viewModel.calibrationData,
              cal.sessionBurnRate > 0 else { return nil }
        return Double(weightedTokens) / cal.sessionBurnRate
    }

    // MARK: - Scrape Settings

    private var scrapeSettingsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Browser Scrape", icon: "globe")

            VStack(alignment: .leading, spacing: 4) {
                Text("Source URL")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("https://claude.ai/settings/usage", text: Binding(
                    get: { viewModel.scrapeSourceURL },
                    set: { viewModel.scrapeSourceURL = $0 }
                ))
                    .textFieldStyle(.roundedBorder)
                    .font(.caption)
            }

            HStack(spacing: 4) {
                Text("Auto-refresh:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("sec", value: Binding(
                    get: { viewModel.scrapeIntervalSeconds },
                    set: { viewModel.scrapeIntervalSeconds = max(1, $0) }
                ), format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 44)
                    .font(.caption)
                Text("sec")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            // Reset calibration
            if viewModel.calibrationData != nil {
                HStack {
                    Button("Reset Calibration") {
                        showResetConfirmation = true
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .foregroundStyle(.red)
                }

                if showResetConfirmation {
                    HStack {
                        Text("Reset calibration?")
                            .font(.caption)
                            .foregroundStyle(.red)
                        Button("Yes") {
                            viewModel.resetCalibration()
                            showResetConfirmation = false
                        }
                        .font(.caption)
                        Button("No") {
                            showResetConfirmation = false
                        }
                        .font(.caption)
                    }
                }
            }
        }
    }

    // MARK: - 5h Period Chain

    private var periodChainSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Current Session Period", icon: "timer")

            let allPeriods = periods
            if allPeriods.isEmpty {
                Text("Waiting for browser scrape data...")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            } else {
                // Show period count summary
                Text("\(allPeriods.count) period\(allPeriods.count == 1 ? "" : "s") since \(allPeriods.first!.start.shortDateTimeString)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)

                // Only show the last (current/most recent) period
                if let lastPeriod = allPeriods.last {
                    periodRow(lastPeriod)
                }
            }
        }
    }

    private func periodRow(_ period: SessionPeriod) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            // Header: period number + time range
            HStack {
                Text("#\(period.id + 1)")
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundStyle(period.isCurrent ? .primary : .secondary)
                    .frame(width: 22, alignment: .leading)

                Text("\(period.start.shortTimeString) – \(period.end.shortTimeString)")
                    .font(.caption2)
                    .foregroundStyle(period.isCurrent ? .primary : .secondary)

                Spacer()

                if period.isCurrent {
                    Text(period.remaining.compactRemaining)
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundStyle(periodColor(period))
                } else {
                    Text("Expired")
                        .font(.caption2)
                        .foregroundStyle(.gray)
                }
            }

            // Progress bar
            ProgressBarView(
                progress: period.isCurrent ? period.elapsed : 1.0,
                color: period.isCurrent ? periodColor(period) : .gray.opacity(0.5)
            )
            .frame(height: 6)

            // Tokens + estimated %
            HStack {
                Text(formatTokens(period.weightedTokens))
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                if let pct = estimatedPercent(weightedTokens: period.weightedTokens) {
                    Text("(\(Int(min(pct, 999)))%)")
                        .font(.caption2)
                        .foregroundStyle(period.isCurrent ? .blue : .secondary)
                }

                Spacer()

                Text("\(period.events) events")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 4)
        .background(
            period.isCurrent
                ? RoundedRectangle(cornerRadius: 4).fill(Color.blue.opacity(0.08))
                : RoundedRectangle(cornerRadius: 4).fill(Color.clear)
        )
    }

    private func periodColor(_ period: SessionPeriod) -> Color {
        if period.remaining <= Constants.thirtyMinWarning {
            return .red
        } else if period.remaining <= Constants.oneHourWarning {
            return .yellow
        }
        return .green
    }

    // MARK: - Burn Rates Display

    private func burnRatesSection(_ cal: CalibrationData) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionHeader(title: "Burn Rates (weighted tokens per 1%)", icon: "flame")

            StatRow(
                label: "Session",
                value: cal.sessionBurnRate > 0
                    ? "\(formatTokens(Int(cal.sessionBurnRate))) / %"
                    : "n/a (no local tokens in period)"
            )
            StatRow(
                label: "Weekly",
                value: cal.weeklyBurnRate > 0
                    ? "\(formatTokens(Int(cal.weeklyBurnRate))) / %"
                    : "n/a"
            )

            Text("Weighted: out×1.0 + in×0.25 + cache_create×0.31 + cache_read×0.025")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Text("Calibrated: \(cal.calibratedAt.shortDateTimeString)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: - Estimates Display

    private var estimatesSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionHeader(title: "Estimated Usage", icon: "gauge.with.dots.needle.33percent")

            if let sessionPct = viewModel.estimatedSessionPercent {
                StatRow(
                    label: "Current Session",
                    value: "\(Int(min(sessionPct, 100)))% used"
                )
            }
            if let weeklyPct = viewModel.estimatedWeeklyPercent {
                StatRow(
                    label: "Weekly (All models)",
                    value: "\(Int(min(weeklyPct, 100)))% used"
                )
            }
        }
    }

    // MARK: - Helpers

    private func formatTokens(_ count: Int) -> String {
        if count >= 1_000_000 {
            return String(format: "%.1fM", Double(count) / 1_000_000)
        } else if count >= 1_000 {
            return String(format: "%.1fK", Double(count) / 1_000)
        }
        return "\(count)"
    }
}

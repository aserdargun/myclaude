import SwiftUI

/// A single 5-hour period in the chain from the input start to now.
private struct SessionPeriod: Identifiable {
    let id: Int // period index (0-based)
    let start: Date
    let end: Date
    let tokens: Int
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

    // Input fields
    @State private var sessionStartDate: Date = Date()
    @State private var sessionStartHour: Int = 0
    @State private var sessionStartMinute: Int = 0
    @State private var sessionPercentText: String = ""
    @State private var weeklyPercentText: String = ""
    @State private var showConfirmation: Bool = false
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
                    // Calibration inputs
                    calibrationInputSection

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
        .onAppear {
            prefillFromCurrentState()
        }
    }

    // MARK: - Computed: session start from inputs

    private var inputSessionStart: Date? {
        let calendar = Calendar.current
        let dayComponents = calendar.dateComponents([.year, .month, .day], from: sessionStartDate)
        var components = dayComponents
        components.hour = sessionStartHour
        components.minute = sessionStartMinute
        components.second = 0
        return calendar.date(from: components)
    }

    /// Build all 5h periods from the input start forward until now.
    private var periods: [SessionPeriod] {
        guard let firstStart = inputSessionStart else { return [] }
        let now = Date()
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
                events: usage.events,
                isCurrent: isCurrent
            ))

            periodStart = periodEnd
            index += 1
        }
        return result
    }

    /// Estimated % for a period using the effective burn rate.
    private func estimatedPercent(tokens: Int) -> Double? {
        guard let cal = viewModel.calibrationData,
              cal.effectiveBurnRate > 0 else { return nil }
        return Double(tokens) / cal.effectiveBurnRate
    }

    // MARK: - Calibration Input

    private var calibrationInputSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Calibrate from Claude", icon: "slider.horizontal.3")

            Text("Enter values from Claude's usage settings page.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)

            // Session start date + time on same row
            VStack(alignment: .leading, spacing: 4) {
                Text("First Session Start")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    DatePicker(
                        "",
                        selection: $sessionStartDate,
                        displayedComponents: [.date]
                    )
                    .datePickerStyle(.field)
                    .labelsHidden()
                    .font(.caption)

                    TextField("HH", value: $sessionStartHour, format: .number.precision(.integerLength(2)))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 32)
                        .font(.caption)
                    Text(":")
                        .font(.caption)
                    TextField("MM", value: $sessionStartMinute, format: .number.precision(.integerLength(2)))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 32)
                        .font(.caption)
                }
            }

            // Percentages on same row
            VStack(alignment: .leading, spacing: 4) {
                Text("Usage Percentages")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 12) {
                    HStack(spacing: 4) {
                        Text("Session")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        TextField("41", text: $sessionPercentText)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 44)
                            .font(.caption)
                        Text("%")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    HStack(spacing: 4) {
                        Text("Weekly")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        TextField("55", text: $weeklyPercentText)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 44)
                            .font(.caption)
                        Text("%")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            // Buttons
            HStack {
                Button("Calibrate Now") {
                    performCalibration()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(!isInputValid)

                if viewModel.calibrationData != nil {
                    Button("Reset") {
                        showResetConfirmation = true
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .foregroundStyle(.red)
                }
            }
            .padding(.top, 4)

            if showConfirmation {
                Text("Calibration saved!")
                    .font(.caption)
                    .foregroundStyle(.green)
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

    // MARK: - 5h Period Chain

    private var periodChainSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Current Session Period", icon: "timer")

            let allPeriods = periods
            if allPeriods.isEmpty {
                Text("Enter a valid date and time above to see session periods.")
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
                Text(formatTokens(period.tokens))
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                if let pct = estimatedPercent(tokens: period.tokens) {
                    Text("(\(Int(min(pct, 999)))% used)")
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
            SectionHeader(title: "Burn Rates (tokens per 1%)", icon: "flame")

            StatRow(
                label: "Session",
                value: cal.sessionBurnRate > 0
                    ? "\(formatTokens(Int(cal.sessionBurnRate))) / %"
                    : "n/a (0 local tokens)"
            )
            StatRow(
                label: "Weekly",
                value: cal.weeklyBurnRate > 0
                    ? "\(formatTokens(Int(cal.weeklyBurnRate))) / %"
                    : "n/a"
            )
            StatRow(
                label: "Effective",
                value: "\(formatTokens(Int(cal.effectiveBurnRate))) / %"
            )

            if cal.sessionBurnRate == 0 && cal.weeklyBurnRate > 0 {
                Text("Using weekly rate as fallback (no session local tokens)")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }

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

    // MARK: - Logic

    private var isInputValid: Bool {
        let sessionPct = Double(sessionPercentText) ?? 0
        let weeklyPct = Double(weeklyPercentText) ?? 0
        return sessionStartHour >= 0 && sessionStartHour < 24
            && sessionStartMinute >= 0 && sessionStartMinute < 60
            && sessionPct > 0 && sessionPct <= 100
            && weeklyPct > 0 && weeklyPct <= 100
    }

    private func performCalibration() {
        guard let sessionStart = inputSessionStart,
              let sessionPct = Double(sessionPercentText),
              let weeklyPct = Double(weeklyPercentText) else { return }

        viewModel.performCalibration(
            sessionStartTime: sessionStart,
            sessionPercentage: sessionPct,
            weeklyPercentage: weeklyPct
        )

        showConfirmation = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            showConfirmation = false
        }
    }

    private func prefillFromCurrentState() {
        if let cal = viewModel.calibrationData {
            sessionPercentText = "\(Int(cal.sessionPercentage))"
            weeklyPercentText = "\(Int(cal.weeklyPercentage))"
            sessionStartDate = cal.sessionStartTime
            let calendar = Calendar.current
            sessionStartHour = calendar.component(.hour, from: cal.sessionStartTime)
            sessionStartMinute = calendar.component(.minute, from: cal.sessionStartTime)
        } else if let start = viewModel.windowStartTime {
            sessionStartDate = start
            let calendar = Calendar.current
            sessionStartHour = calendar.component(.hour, from: start)
            sessionStartMinute = calendar.component(.minute, from: start)
        }
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

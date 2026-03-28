import SwiftUI

struct SettingsView: View {
    let viewModel: UsageViewModel

    // Input fields
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

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 12) {
                    // Calibration Section
                    calibrationInputSection

                    Divider()

                    // Current burn rates (if calibrated)
                    if let cal = viewModel.calibrationData {
                        burnRatesSection(cal)
                        Divider()
                    }

                    // Calibrated estimates
                    if viewModel.calibrationData != nil {
                        estimatesSection
                    }
                }
            }
        }
        .padding(12)
        .frame(width: 300)
        .onAppear {
            prefillFromCurrentState()
        }
    }

    // MARK: - Calibration Input

    private var calibrationInputSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Calibrate from Claude", icon: "slider.horizontal.3")

            Text("Enter values from Claude's usage settings page to calibrate burn rates.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)

            // Session start time
            VStack(alignment: .leading, spacing: 4) {
                Text("Session Start Time")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 4) {
                    TextField("HH", value: $sessionStartHour, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 40)
                        .font(.caption)
                    Text(":")
                        .font(.caption)
                    TextField("MM", value: $sessionStartMinute, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 40)
                        .font(.caption)
                    Text("(24h format)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            // Current session %
            VStack(alignment: .leading, spacing: 4) {
                Text("Current Session Used %")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 4) {
                    TextField("e.g. 23", text: $sessionPercentText)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 60)
                        .font(.caption)
                    Text("%")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("(from \"Current session\")")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            // Weekly all models %
            VStack(alignment: .leading, spacing: 4) {
                Text("All Models Weekly Used %")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 4) {
                    TextField("e.g. 54", text: $weeklyPercentText)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 60)
                        .font(.caption)
                    Text("%")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("(from \"All models\")")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
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

    // MARK: - Burn Rates Display

    private func burnRatesSection(_ cal: CalibrationData) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionHeader(title: "Burn Rates", icon: "flame")

            StatRow(
                label: "Session",
                value: "\(formatTokens(Int(cal.sessionBurnRatePerPercent))) / %"
            )
            StatRow(
                label: "Today",
                value: "\(formatTokens(Int(cal.todayBurnRatePerPercent))) / %"
            )
            StatRow(
                label: "Weekly",
                value: "\(formatTokens(Int(cal.weeklyBurnRatePerPercent))) / %"
            )

            HStack {
                Text("Calibrated: \(cal.calibratedAt.shortTimeString)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Spacer()
                Text("Session: \(cal.sessionStartTime.shortTimeString) – \(cal.sessionEndTime.shortTimeString)")
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
            if let todayPct = viewModel.estimatedTodayPercent {
                StatRow(
                    label: "Today",
                    value: "\(Int(min(todayPct, 100)))% used"
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
        guard let sessionPct = Double(sessionPercentText),
              let weeklyPct = Double(weeklyPercentText) else { return }

        // Build session start Date from hour/minute for today
        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month, .day], from: Date())
        components.hour = sessionStartHour
        components.minute = sessionStartMinute
        components.second = 0

        guard let sessionStart = calendar.date(from: components) else { return }

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
        // Pre-fill from existing calibration first
        if let cal = viewModel.calibrationData {
            sessionPercentText = "\(Int(cal.sessionPercentage))"
            weeklyPercentText = "\(Int(cal.weeklyPercentage))"
            let calendar = Calendar.current
            sessionStartHour = calendar.component(.hour, from: cal.sessionStartTime)
            sessionStartMinute = calendar.component(.minute, from: cal.sessionStartTime)
        } else if let start = viewModel.windowStartTime {
            // Pre-fill session start from current detected session
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

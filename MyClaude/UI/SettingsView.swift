import SwiftUI

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

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 12) {
                    // Calibration Section
                    calibrationInputSection

                    Divider()

                    // 5h session progression preview
                    sessionProgressionPreview

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

    private var inputSessionEnd: Date? {
        inputSessionStart?.addingTimeInterval(Constants.sessionDuration)
    }

    /// How far into the 5h window we are right now (0.0 – 1.0).
    private var sessionElapsedProgress: Double {
        guard let start = inputSessionStart else { return 0 }
        let elapsed = Date().timeIntervalSince(start)
        return min(1.0, max(0, elapsed / Constants.sessionDuration))
    }

    /// Time remaining in the 5h window.
    private var sessionTimeRemaining: TimeInterval {
        guard let end = inputSessionEnd else { return 0 }
        return max(0, end.timeIntervalSince(Date()))
    }

    private var isSessionExpired: Bool {
        sessionTimeRemaining <= 0
    }

    // MARK: - Calibration Input

    private var calibrationInputSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Calibrate from Claude", icon: "slider.horizontal.3")

            Text("Enter values from Claude's usage settings page to calibrate burn rates.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)

            // Session start date
            VStack(alignment: .leading, spacing: 4) {
                Text("Session Start Date")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                DatePicker(
                    "",
                    selection: $sessionStartDate,
                    displayedComponents: [.date]
                )
                .datePickerStyle(.field)
                .labelsHidden()
                .font(.caption)
            }

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

    // MARK: - 5h Session Progression Preview

    private var sessionProgressionPreview: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionHeader(title: "5h Session Window", icon: "timer")

            if let start = inputSessionStart, let end = inputSessionEnd {
                // Progress bar
                ProgressBarView(
                    progress: sessionElapsedProgress,
                    color: isSessionExpired ? .gray : progressColor
                )

                // Time labels
                HStack {
                    Text(start.shortTimeString)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if isSessionExpired {
                        Text("Expired")
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .foregroundStyle(.gray)
                    } else {
                        Text("\(sessionTimeRemaining.compactRemaining) left")
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .foregroundStyle(progressColor)
                    }
                    Spacer()
                    Text(end.shortTimeString)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                // Percentage
                HStack {
                    Text("Time elapsed: \(Int(sessionElapsedProgress * 100))%")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Spacer()
                    Text(start.shortDateString)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            } else {
                Text("Enter a valid date and time above")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var progressColor: Color {
        if sessionTimeRemaining <= Constants.thirtyMinWarning {
            return .red
        } else if sessionTimeRemaining <= Constants.oneHourWarning {
            return .yellow
        }
        return .green
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
        // Pre-fill from existing calibration first
        if let cal = viewModel.calibrationData {
            sessionPercentText = "\(Int(cal.sessionPercentage))"
            weeklyPercentText = "\(Int(cal.weeklyPercentage))"
            sessionStartDate = cal.sessionStartTime
            let calendar = Calendar.current
            sessionStartHour = calendar.component(.hour, from: cal.sessionStartTime)
            sessionStartMinute = calendar.component(.minute, from: cal.sessionStartTime)
        } else if let start = viewModel.windowStartTime {
            // Pre-fill session start from current detected session
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

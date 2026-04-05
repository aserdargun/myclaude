import SwiftUI

struct SettingsView: View {
    let viewModel: UsageViewModel

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

            // Browser Scrape settings
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
            }

            Divider()

            // Daily Targets aligned to weekly reset window
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    SectionHeader(title: "Weekly Daily Targets", icon: "chart.bar")
                    Spacer()
                    let total = viewModel.dailyTargets.reduce(0, +)
                    Text("Total: \(total)%")
                        .font(.caption2)
                        .foregroundStyle(total == 100 ? .green : .red)
                }

                // Show reset window info
                if let resetInfo = viewModel.scrapedAllModelsReset {
                    HStack(spacing: 2) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        Text("Window: \(resetDisplayText(resetInfo))")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }

                dailyTargetsGrid

                if viewModel.dailyTargets.reduce(0, +) > 100 {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                        Text("Daily targets exceed 100%. Please adjust values.")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                }
            }
        }
        .padding(12)
        .frame(width: 340)
    }

    /// Day labels aligned to the weekly reset window.
    /// If reset is "Sun 3:00 PM", the window runs:
    /// Sun PM → Mon → Tue → Wed → Thu → Fri → Sat → Sun PM
    private var windowDayLabels: [String] {
        let resetDay = resetDayIndex
        var labels: [String] = []
        let dayNames = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        for i in 0..<7 {
            let idx = (resetDay + i) % 7
            labels.append(dayNames[idx])
        }
        return labels
    }

    /// The calendar day index (0=Sun) where the weekly window starts.
    private var resetDayIndex: Int {
        if let reset = viewModel.scrapedAllModelsReset {
            switch reset {
            case .resetsAt(let day, _):
                return dayNameToIndex(day)
            case .resetsIn(let interval):
                let resetDate = Date().addingTimeInterval(interval)
                let weekday = Calendar.current.component(.weekday, from: resetDate)
                return weekday - 1 // 1=Sun → 0
            }
        }
        return 0 // Default: Sunday
    }

    /// The reset time string (e.g. "3:00 PM")
    private var resetTimeString: String {
        if let reset = viewModel.scrapedAllModelsReset {
            switch reset {
            case .resetsAt(_, let time):
                return time
            case .resetsIn(let interval):
                let resetDate = Date().addingTimeInterval(interval)
                let formatter = DateFormatter()
                formatter.dateFormat = "h:mm a"
                return formatter.string(from: resetDate)
            }
        }
        return ""
    }

    private var dailyTargetsGrid: some View {
        VStack(spacing: 4) {
            // Reset time label at the top
            if !resetTimeString.isEmpty {
                HStack {
                    Text(resetTimeString)
                        .font(.system(size: 8))
                        .foregroundStyle(.tertiary)
                    Spacer()
                    Text(resetTimeString)
                        .font(.system(size: 8))
                        .foregroundStyle(.tertiary)
                }
            }

            // Day fields: 7 days from reset day to reset day
            HStack(spacing: 3) {
                let labels = windowDayLabels
                ForEach(0..<7, id: \.self) { i in
                    windowDayTargetField(index: i, label: labels[i])
                }
            }
        }
    }

    private func windowDayTargetField(index: Int, label: String) -> some View {
        // Map window-order index back to storage index (Sun=0-based)
        let storageIndex = (resetDayIndex + index) % 7
        return VStack(spacing: 2) {
            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
            TextField("", value: Binding(
                get: { viewModel.dailyTargets[storageIndex] },
                set: { newVal in
                    var targets = viewModel.dailyTargets
                    targets[storageIndex] = max(0, min(100, newVal))
                    viewModel.dailyTargets = targets
                }
            ), format: .number)
                .textFieldStyle(.roundedBorder)
                .frame(width: 36)
                .font(.caption)
                .multilineTextAlignment(.center)
        }
    }

    private func dayNameToIndex(_ name: String) -> Int {
        let map = ["sun": 0, "mon": 1, "tue": 2, "wed": 3, "thu": 4, "fri": 5, "sat": 6]
        return map[name.lowercased().prefix(3).description] ?? 0
    }

    private func resetDisplayText(_ reset: WeeklyResetInfo) -> String {
        switch reset {
        case .resetsIn(let interval):
            return "Resets in \(interval.compactRemaining)"
        case .resetsAt(let day, let time):
            return "\(day) \(time) → \(day) \(time)"
        }
    }
}

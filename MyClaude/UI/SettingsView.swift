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

            // Daily Targets
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    SectionHeader(title: "Weekly Daily Targets", icon: "chart.bar")
                    Spacer()
                    let total = viewModel.dailyTargets.reduce(0, +)
                    Text("Total: \(total)%")
                        .font(.caption2)
                        .foregroundStyle(total == 100 ? .green : .red)
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

    private static let dayNames = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

    private var dailyTargetsGrid: some View {
        HStack(spacing: 4) {
            ForEach(0..<7, id: \.self) { i in
                dayTargetField(index: i)
            }
        }
    }

    private func dayTargetField(index: Int) -> some View {
        VStack(spacing: 2) {
            Text(Self.dayNames[index])
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
            TextField("", value: Binding(
                get: { viewModel.dailyTargets[index] },
                set: { newVal in
                    var targets = viewModel.dailyTargets
                    targets[index] = max(0, min(100, newVal))
                    viewModel.dailyTargets = targets
                }
            ), format: .number)
                .textFieldStyle(.roundedBorder)
                .frame(width: 36)
                .font(.caption)
                .multilineTextAlignment(.center)
        }
    }
}

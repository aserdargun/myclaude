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
            }
        }
        .padding(12)
        .frame(width: 340)
    }

    private static let dayNames = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

    private var dailyTargetsGrid: some View {
        VStack(spacing: 6) {
            // Row 1: Sun–Wed
            HStack(spacing: 8) {
                ForEach(0..<4, id: \.self) { i in
                    dayTargetField(index: i)
                }
            }
            // Row 2: Thu–Sat
            HStack(spacing: 8) {
                ForEach(4..<7, id: \.self) { i in
                    dayTargetField(index: i)
                }
                Spacer()
            }
        }
    }

    private func dayTargetField(index: Int) -> some View {
        VStack(spacing: 2) {
            Text(Self.dayNames[index])
                .font(.caption2)
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
                .frame(width: 40)
                .font(.caption)
                .multilineTextAlignment(.center)
            Text("%")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }
}

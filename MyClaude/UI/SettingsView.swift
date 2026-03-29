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
        }
        .padding(12)
        .frame(width: 340)
    }
}

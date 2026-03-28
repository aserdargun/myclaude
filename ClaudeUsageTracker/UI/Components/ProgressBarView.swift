import SwiftUI

struct ProgressBarView: View {
    let progress: Double
    let color: Color

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.secondary.opacity(0.2))

                RoundedRectangle(cornerRadius: 4)
                    .fill(color)
                    .frame(width: geometry.size.width * min(1.0, max(0, progress)))
                    .animation(.easeInOut(duration: 0.3), value: progress)
            }
        }
        .frame(height: 8)
    }
}

struct StatRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
                .font(.caption)
            Spacer()
            Text(value)
                .font(.caption)
                .fontWeight(.medium)
        }
    }
}

struct SectionHeader: View {
    let title: String
    let icon: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2)
            Text(title)
                .font(.caption)
                .fontWeight(.semibold)
                .textCase(.uppercase)
        }
        .foregroundStyle(.secondary)
    }
}

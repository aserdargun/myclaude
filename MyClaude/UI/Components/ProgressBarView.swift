import SwiftUI

struct ProgressBarView: View {
    let progress: Double
    let color: Color
    var dailyTargets: [Int]? = nil
    var currentDayIndex: Int? = nil

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.secondary.opacity(0.2))

                RoundedRectangle(cornerRadius: 4)
                    .fill(color)
                    .frame(width: geometry.size.width * min(1.0, max(0, progress)))
                    .animation(.easeInOut(duration: 0.3), value: progress)

                // Daily target vertical markers
                if let targets = dailyTargets {
                    ForEach(0..<targets.count - 1, id: \.self) { i in
                        let cumulative = targets.prefix(i + 1).reduce(0, +)
                        let xPos = geometry.size.width * Double(cumulative) / 100.0
                        let isCurrentDay = (i == currentDayIndex)
                        Rectangle()
                            .fill(isCurrentDay ? Color.red : Color.white.opacity(0.6))
                            .frame(width: isCurrentDay ? 2 : 1, height: geometry.size.height + 4)
                            .position(x: xPos, y: geometry.size.height / 2)
                    }
                }
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

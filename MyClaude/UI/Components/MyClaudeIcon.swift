import SwiftUI

/// A small rendered version of the myClaude app icon.
/// Terracotta/peach gradient background with white 6-pointed starburst.
struct MyClaudeIcon: View {
    let size: CGFloat

    var body: some View {
        ZStack {
            // Background
            RoundedRectangle(cornerRadius: size * 0.22)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 235/255, green: 160/255, blue: 120/255),
                            Color(red: 200/255, green: 110/255, blue: 80/255)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

            // Starburst
            StarburstShape(points: 6, innerRatio: 0.35)
                .fill(.white.opacity(0.9))
                .frame(width: size * 0.6, height: size * 0.6)

            // Center glow
            Circle()
                .fill(.white)
                .frame(width: size * 0.18, height: size * 0.18)
        }
        .frame(width: size, height: size)
    }
}

/// A star/starburst shape with configurable points.
struct StarburstShape: Shape {
    let points: Int
    let innerRatio: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let outerRadius = min(rect.width, rect.height) / 2
        let innerRadius = outerRadius * innerRatio

        for i in 0..<(points * 2) {
            let angle = (Double(i) * .pi / Double(points)) - .pi / 2
            let radius = i.isMultiple(of: 2) ? outerRadius : innerRadius
            let point = CGPoint(
                x: center.x + CGFloat(cos(angle)) * radius,
                y: center.y + CGFloat(sin(angle)) * radius
            )
            if i == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        path.closeSubpath()
        return path
    }
}

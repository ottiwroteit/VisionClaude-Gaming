import SwiftUI

enum ArcheryVenues {
    static let all: [Venue] = [
        Venue(id: "training-range", gameID: "archery", name: "Training Range",
              tagline: "Dawn. Still air. Begin.", unlockAt: 0) {
            TrainingRangeBG()
        },
        Venue(id: "bamboo-forest", gameID: "archery", name: "Bamboo Forest",
              tagline: "Green silence. Focus the breath.", unlockAt: 70) {
            BambooForestBG()
        },
        Venue(id: "floating-isle", gameID: "archery", name: "Floating Isle",
              tagline: "Wind above the clouds.", unlockAt: 250) {
            FloatingIsleBG()
        }
    ]
}

private struct TrainingRangeBG: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.8, green: 0.82, blue: 0.9),
                         Color(red: 0.6, green: 0.55, blue: 0.5)],
                startPoint: .top, endPoint: .bottom
            )
            // Distant mountains
            VStack {
                Spacer()
                ZStack {
                    MountainLayer(color: Color(red: 0.55, green: 0.55, blue: 0.6))
                        .frame(height: 140)
                        .offset(y: -60)
                    MountainLayer(color: Color(red: 0.4, green: 0.4, blue: 0.45))
                        .frame(height: 120)
                        .offset(y: -20)
                }
            }
            // Ground
            VStack {
                Spacer()
                Rectangle()
                    .fill(Color(red: 0.5, green: 0.4, blue: 0.25))
                    .frame(height: 80)
            }
        }
    }
}

private struct MountainLayer: View {
    let color: Color
    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width, h = proxy.size.height
            Path { p in
                p.move(to: CGPoint(x: 0, y: h))
                p.addLine(to: CGPoint(x: 0, y: h * 0.6))
                p.addLine(to: CGPoint(x: w * 0.2, y: h * 0.2))
                p.addLine(to: CGPoint(x: w * 0.35, y: h * 0.5))
                p.addLine(to: CGPoint(x: w * 0.55, y: h * 0.1))
                p.addLine(to: CGPoint(x: w * 0.75, y: h * 0.55))
                p.addLine(to: CGPoint(x: w * 0.9, y: h * 0.3))
                p.addLine(to: CGPoint(x: w, y: h * 0.6))
                p.addLine(to: CGPoint(x: w, y: h))
                p.closeSubpath()
            }
            .fill(color)
        }
    }
}

private struct BambooForestBG: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.25, green: 0.45, blue: 0.35),
                         Color(red: 0.1, green: 0.25, blue: 0.2)],
                startPoint: .top, endPoint: .bottom
            )
            // Bamboo stalks
            HStack(spacing: 18) {
                ForEach(0..<10, id: \.self) { i in
                    VStack(spacing: 1) {
                        ForEach(0..<14, id: \.self) { _ in
                            Rectangle()
                                .fill(Color(red: 0.15, green: 0.35, blue: 0.2))
                                .frame(width: 8, height: 30)
                                .overlay(
                                    Rectangle()
                                        .fill(Color(red: 0.08, green: 0.2, blue: 0.12))
                                        .frame(height: 2)
                                )
                        }
                    }
                    .offset(y: CGFloat((i * 31) % 40))
                    .opacity(i.isMultiple(of: 3) ? 0.6 : 1.0)
                }
            }
            // Light rays
            RadialGradient(
                colors: [Color(red: 1.0, green: 0.95, blue: 0.7).opacity(0.25), .clear],
                center: UnitPoint(x: 0.2, y: 0.1), startRadius: 0, endRadius: 260
            )
        }
    }
}

private struct FloatingIsleBG: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.6, green: 0.85, blue: 1.0),
                         Color(red: 0.95, green: 0.8, blue: 0.9)],
                startPoint: .top, endPoint: .bottom
            )
            // Clouds
            ForEach(0..<6, id: \.self) { i in
                Capsule()
                    .fill(Color.white.opacity(0.85))
                    .frame(width: 120, height: 30)
                    .offset(
                        x: CGFloat((i * 97) % 360) - 180,
                        y: CGFloat((i * 61) % 400) - 200
                    )
            }
            // Floating island
            VStack {
                Spacer()
                ZStack(alignment: .top) {
                    // Rock bottom (pointed)
                    Path { p in
                        p.move(to: CGPoint(x: 0, y: 0))
                        p.addLine(to: CGPoint(x: 260, y: 0))
                        p.addLine(to: CGPoint(x: 160, y: 80))
                        p.closeSubpath()
                    }
                    .fill(Color(red: 0.35, green: 0.25, blue: 0.2))
                    .frame(width: 260, height: 80)
                    // Grass top
                    Rectangle()
                        .fill(Color(red: 0.4, green: 0.7, blue: 0.35))
                        .frame(width: 260, height: 14)
                }
                .padding(.bottom, 80)
            }
        }
    }
}

import SwiftUI

enum BoxingVenues {
    static let all: [Venue] = [
        Venue(id: "back-alley", gameID: "boxing", name: "Back Alley",
              tagline: "Cold brick. Hot breath.", unlockAt: 0) {
            BackAlleyBG()
        },
        Venue(id: "underground", gameID: "boxing", name: "Underground Ring",
              tagline: "Smoke. Spotlight. Blood in the air.", unlockAt: 200) {
            UndergroundBG()
        },
        Venue(id: "title-fight", gameID: "boxing", name: "Title Fight",
              tagline: "Packed house. Worldwide broadcast.", unlockAt: 800) {
            TitleFightBG()
        }
    ]
}

private struct BackAlleyBG: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.08, green: 0.08, blue: 0.1),
                         Color(red: 0.18, green: 0.14, blue: 0.14)],
                startPoint: .top, endPoint: .bottom
            )
            // Brick pattern
            VStack(spacing: 0) {
                ForEach(0..<14, id: \.self) { row in
                    HStack(spacing: 3) {
                        ForEach(0..<8, id: \.self) { col in
                            Rectangle()
                                .fill(Color(red: 0.22, green: 0.12, blue: 0.1))
                                .frame(height: 22)
                                .offset(x: row.isMultiple(of: 2) ? 0 : 18)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
            .opacity(0.6)
            // Flickering streetlight cone
            RadialGradient(
                colors: [Color(red: 1.0, green: 0.85, blue: 0.5).opacity(0.35), .clear],
                center: UnitPoint(x: 0.3, y: 0.1), startRadius: 10, endRadius: 240
            )
        }
    }
}

private struct UndergroundBG: View {
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            // Smoke haze
            RadialGradient(
                colors: [Color(red: 0.35, green: 0.1, blue: 0.1).opacity(0.7), .clear],
                center: .center, startRadius: 20, endRadius: 300
            )
            // Spot beam from above
            GeometryReader { proxy in
                let w = proxy.size.width
                Path { p in
                    p.move(to: CGPoint(x: w / 2 - 30, y: 0))
                    p.addLine(to: CGPoint(x: w / 2 + 30, y: 0))
                    p.addLine(to: CGPoint(x: w / 2 + 200, y: proxy.size.height))
                    p.addLine(to: CGPoint(x: w / 2 - 200, y: proxy.size.height))
                    p.closeSubpath()
                }
                .fill(Color.white.opacity(0.08))
            }
            // Ring ropes silhouette at bottom
            VStack(spacing: 14) {
                Spacer()
                ForEach(0..<3, id: \.self) { _ in
                    Rectangle()
                        .fill(Color(red: 0.8, green: 0.2, blue: 0.2))
                        .frame(height: 4)
                        .shadow(color: Color(red: 0.8, green: 0.2, blue: 0.2), radius: 4)
                }
                Spacer().frame(height: 40)
            }
        }
    }
}

private struct TitleFightBG: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.9, green: 0.75, blue: 0.2),
                         Color(red: 0.6, green: 0.1, blue: 0.15)],
                startPoint: .top, endPoint: .bottom
            )
            // Confetti
            ForEach(0..<24, id: \.self) { i in
                Rectangle()
                    .fill([Color.white, Color.yellow, Color(red: 1, green: 0.3, blue: 0.3)].randomElement()!)
                    .frame(width: 6, height: 12)
                    .rotationEffect(.degrees(Double((i * 37) % 360)))
                    .offset(
                        x: CGFloat((i * 71) % 400) - 200,
                        y: CGFloat((i * 53) % 500) - 250
                    )
            }
            // Crowd with raised signs
            VStack {
                Spacer()
                HStack(spacing: -2) {
                    ForEach(0..<30, id: \.self) { i in
                        Circle()
                            .fill(Color.black)
                            .frame(width: 14, height: 14)
                            .offset(y: CGFloat((i * 17) % 10))
                    }
                }
                Rectangle()
                    .fill(Color.black.opacity(0.85))
                    .frame(height: 80)
            }
        }
    }
}

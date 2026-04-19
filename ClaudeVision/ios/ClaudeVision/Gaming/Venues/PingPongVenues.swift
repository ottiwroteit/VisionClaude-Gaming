import SwiftUI

enum PingPongVenues {
    static let all: [Venue] = [
        Venue(id: "basement", gameID: "pingpong", name: "Basement",
              tagline: "One bulb. One table. No mercy.", unlockAt: 0) {
            BasementBG()
        },
        Venue(id: "tokyo-alley", gameID: "pingpong", name: "Tokyo Alley",
              tagline: "Lanterns, neon kanji, rain.", unlockAt: 15,
              modifier: VenueModifier(
                difficultyMultiplier: 1.25,
                flavorLine: "Rain-slick ball. CPU returns faster.",
                effect: .rainTempo
              )) {
            TokyoAlleyBG()
        },
        Venue(id: "cyber-arena", gameID: "pingpong", name: "Cyber Arena",
              tagline: "Grid floor. Holographic crowd.", unlockAt: 60,
              modifier: VenueModifier(
                scoreMultiplier: 1.5,
                difficultyMultiplier: 1.4,
                flavorLine: "Hyperspeed table. Points worth more, reactions tighter.",
                effect: .rainTempo
              )) {
            CyberArenaBG()
        }
    ]
}

private struct BasementBG: View {
    var body: some View {
        ZStack {
            Color(red: 0.12, green: 0.1, blue: 0.12).ignoresSafeArea()
            // Light bulb cone
            RadialGradient(
                colors: [Color(red: 1.0, green: 0.95, blue: 0.7).opacity(0.5), .clear],
                center: .top, startRadius: 10, endRadius: 260
            )
            // Bulb
            VStack {
                Circle()
                    .fill(Color(red: 1.0, green: 0.95, blue: 0.7))
                    .frame(width: 18, height: 18)
                    .overlay(Rectangle().fill(Color.black).frame(width: 2, height: 30).offset(y: -20))
                    .padding(.top, 20)
                Spacer()
            }
            // Concrete floor
            VStack {
                Spacer()
                Rectangle()
                    .fill(Color(red: 0.2, green: 0.18, blue: 0.18))
                    .frame(height: 120)
            }
        }
    }
}

private struct TokyoAlleyBG: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.08, green: 0.04, blue: 0.14),
                         Color(red: 0.2, green: 0.06, blue: 0.2)],
                startPoint: .top, endPoint: .bottom
            )
            // Neon signs (vertical)
            HStack {
                Rectangle()
                    .fill(Color(red: 1.0, green: 0.2, blue: 0.4))
                    .frame(width: 22, height: 200)
                    .shadow(color: Color(red: 1.0, green: 0.2, blue: 0.4), radius: 10)
                Spacer()
                Rectangle()
                    .fill(Color(red: 0.3, green: 0.9, blue: 1.0))
                    .frame(width: 22, height: 160)
                    .shadow(color: Color(red: 0.3, green: 0.9, blue: 1.0), radius: 10)
            }
            .padding(.horizontal, 20)
            .padding(.top, 40)
            .frame(maxHeight: .infinity, alignment: .top)
            // Lantern
            Circle()
                .fill(Color(red: 1.0, green: 0.4, blue: 0.2))
                .frame(width: 44, height: 56)
                .overlay(Rectangle().stroke(Color.black, lineWidth: 2).frame(width: 38, height: 50))
                .shadow(color: Color(red: 1.0, green: 0.5, blue: 0.2), radius: 14)
                .offset(x: 80, y: -120)
            // Rain streaks
            ForEach(0..<30, id: \.self) { i in
                Rectangle()
                    .fill(Color.white.opacity(0.12))
                    .frame(width: 1, height: 20)
                    .offset(x: CGFloat((i * 37) % 400) - 200,
                            y: CGFloat((i * 71) % 600) - 300)
                    .rotationEffect(.degrees(15))
            }
        }
    }
}

private struct CyberArenaBG: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.02, green: 0.05, blue: 0.15),
                         Color(red: 0.05, green: 0.15, blue: 0.3)],
                startPoint: .top, endPoint: .bottom
            )
            // Grid perspective floor
            GeometryReader { proxy in
                let w = proxy.size.width, h = proxy.size.height
                Path { p in
                    // Horizontal lines
                    for i in 0..<8 {
                        let y = h * 0.55 + CGFloat(i) * (h * 0.065)
                        p.move(to: CGPoint(x: 0, y: y))
                        p.addLine(to: CGPoint(x: w, y: y))
                    }
                    // Vertical converging lines
                    for i in 0...10 {
                        let x = CGFloat(i) * (w / 10)
                        p.move(to: CGPoint(x: x, y: h))
                        p.addLine(to: CGPoint(x: w / 2, y: h * 0.55))
                    }
                }
                .stroke(Color(red: 0.3, green: 0.9, blue: 1.0).opacity(0.6), lineWidth: 1)
            }
            // Glow horizon
            VStack {
                Spacer()
                Rectangle()
                    .fill(Color(red: 0.3, green: 0.9, blue: 1.0))
                    .frame(height: 2)
                    .shadow(color: Color(red: 0.3, green: 0.9, blue: 1.0), radius: 16)
                    .padding(.bottom, 170)
            }
        }
    }
}

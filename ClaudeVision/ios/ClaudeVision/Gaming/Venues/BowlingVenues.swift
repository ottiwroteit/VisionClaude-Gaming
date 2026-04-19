import SwiftUI

enum BowlingVenues {
    static let all: [Venue] = [
        Venue(id: "neon-lanes", gameID: "bowling", name: "Neon Lanes",
              tagline: "The starter alley. Purple haze.", unlockAt: 0) {
            NeonLanesBG()
        },
        Venue(id: "sunset-strip", gameID: "bowling", name: "Sunset Strip",
              tagline: "Palm trees and magenta skies.", unlockAt: 150,
              modifier: VenueModifier(
                flavorLine: "Warm lane oil — weak rolls still knock pins.",
                effect: .stickyLane
              )) {
            SunsetStripBG()
        },
        Venue(id: "dragon-shrine", gameID: "bowling", name: "Dragon Shrine",
              tagline: "Holy ground. Roll with reverence.", unlockAt: 500,
              modifier: VenueModifier(
                scoreMultiplier: 2.0,
                difficultyMultiplier: 1.3,
                flavorLine: "Sacred lane. Double points, unforgiving pins."
              )) {
            DragonShrineBG()
        }
    ]
}

private struct NeonLanesBG: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.1, green: 0.04, blue: 0.2),
                         Color(red: 0.25, green: 0.06, blue: 0.45)],
                startPoint: .top, endPoint: .bottom
            )
            // Lane perspective lines
            GeometryReader { proxy in
                Path { p in
                    let w = proxy.size.width, h = proxy.size.height
                    p.move(to: CGPoint(x: w * 0.35, y: h))
                    p.addLine(to: CGPoint(x: w * 0.5, y: h * 0.4))
                    p.addLine(to: CGPoint(x: w * 0.5, y: h * 0.4))
                    p.addLine(to: CGPoint(x: w * 0.65, y: h))
                }
                .stroke(Color(red: 1.0, green: 0.3, blue: 0.85), lineWidth: 2)
            }
            // Horizon neon band
            VStack {
                Spacer()
                Rectangle()
                    .fill(LinearGradient(colors: [.clear, Color(red: 0.9, green: 0.2, blue: 0.8).opacity(0.6)],
                                         startPoint: .top, endPoint: .bottom))
                    .frame(height: 80)
            }
        }
    }
}

private struct SunsetStripBG: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 1.0, green: 0.35, blue: 0.55),
                         Color(red: 1.0, green: 0.6, blue: 0.3),
                         Color(red: 0.35, green: 0.1, blue: 0.4)],
                startPoint: .top, endPoint: .bottom
            )
            // Sun
            Circle()
                .fill(Color(red: 1.0, green: 0.85, blue: 0.4))
                .frame(width: 140, height: 140)
                .offset(y: -80)
            // Palm silhouettes
            HStack(alignment: .bottom) {
                PalmSilhouette().frame(width: 60, height: 180)
                Spacer()
                PalmSilhouette().frame(width: 50, height: 140)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
            .frame(maxHeight: .infinity, alignment: .bottom)
        }
    }
}

private struct PalmSilhouette: View {
    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width, h = proxy.size.height
            ZStack(alignment: .bottom) {
                Rectangle()
                    .fill(Color.black)
                    .frame(width: w * 0.08)
                ForEach(0..<5, id: \.self) { i in
                    Capsule()
                        .fill(Color.black)
                        .frame(width: w * 0.55, height: 6)
                        .rotationEffect(.degrees(Double(i) * 36 - 72))
                        .offset(y: -h * 0.85)
                }
            }
            .frame(width: w, height: h, alignment: .bottom)
        }
    }
}

private struct DragonShrineBG: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.35, green: 0.05, blue: 0.1),
                         Color(red: 0.7, green: 0.15, blue: 0.1)],
                startPoint: .top, endPoint: .bottom
            )
            // Moon
            Circle()
                .fill(Color(red: 1.0, green: 0.85, blue: 0.5))
                .frame(width: 90, height: 90)
                .offset(x: -80, y: -160)
            // Pagoda silhouette
            VStack(spacing: -2) {
                ForEach(0..<4, id: \.self) { i in
                    let width = 80 + CGFloat(i) * 30
                    ZStack {
                        Rectangle().fill(Color.black).frame(width: width - 20, height: 28)
                        // Upturned roof
                        Path { p in
                            p.move(to: CGPoint(x: 0, y: 10))
                            p.addQuadCurve(to: CGPoint(x: width, y: 10),
                                           control: CGPoint(x: width / 2, y: -4))
                            p.addLine(to: CGPoint(x: width - 12, y: 14))
                            p.addLine(to: CGPoint(x: 12, y: 14))
                            p.closeSubpath()
                        }
                        .fill(Color.black)
                        .frame(width: width, height: 14)
                        .offset(y: -14)
                    }
                }
            }
            .frame(maxHeight: .infinity, alignment: .bottom)
            .padding(.bottom, 30)
        }
    }
}

import SwiftUI

enum FruitSlashVenues {
    static let all: [Venue] = [
        Venue(id: "kitchen", gameID: "fruitslash", name: "Kitchen Counter",
              tagline: "Humble beginnings. Fresh produce.", unlockAt: 0) {
            KitchenBG()
        },
        Venue(id: "orchard", gameID: "fruitslash", name: "Orchard Sunrise",
              tagline: "Dew on leaves. First light.", unlockAt: 30,
              modifier: VenueModifier(
                scoreMultiplier: 1.3,
                flavorLine: "Ripe season. +30% per slice."
              )) {
            OrchardBG()
        },
        Venue(id: "heavens-garden", gameID: "fruitslash", name: "Heaven's Garden",
              tagline: "Pink clouds. Golden fruit. Divine.", unlockAt: 150,
              modifier: VenueModifier(
                scoreMultiplier: 2.0,
                flavorLine: "Double points. Miss a fruit and time slows.",
                effect: .slowMo
              )) {
            HeavensGardenBG()
        }
    ]
}

private struct KitchenBG: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.95, green: 0.88, blue: 0.75),
                         Color(red: 0.75, green: 0.6, blue: 0.45)],
                startPoint: .top, endPoint: .bottom
            )
            // Wood counter
            VStack {
                Spacer()
                Rectangle()
                    .fill(Color(red: 0.55, green: 0.35, blue: 0.2))
                    .frame(height: 120)
                    .overlay(
                        VStack(spacing: 8) {
                            ForEach(0..<6, id: \.self) { _ in
                                Rectangle()
                                    .fill(Color.black.opacity(0.15))
                                    .frame(height: 1)
                            }
                        }
                    )
            }
            // Window light
            RadialGradient(
                colors: [Color.white.opacity(0.4), .clear],
                center: UnitPoint(x: 0.8, y: 0.15),
                startRadius: 0, endRadius: 200
            )
        }
    }
}

private struct OrchardBG: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 1.0, green: 0.75, blue: 0.55),
                         Color(red: 0.6, green: 0.8, blue: 0.5)],
                startPoint: .top, endPoint: .bottom
            )
            // Rising sun
            Circle()
                .fill(Color(red: 1.0, green: 0.9, blue: 0.5))
                .frame(width: 120, height: 120)
                .offset(y: -50)
                .shadow(color: Color(red: 1.0, green: 0.9, blue: 0.5), radius: 40)
            // Tree row
            HStack(alignment: .bottom, spacing: 20) {
                ForEach(0..<5, id: \.self) { i in
                    AppleTree()
                        .frame(width: 60, height: CGFloat(140 + (i * 23) % 40))
                        .opacity(0.85)
                }
            }
            .frame(maxHeight: .infinity, alignment: .bottom)
            .padding(.bottom, 60)
        }
    }
}

private struct AppleTree: View {
    var body: some View {
        VStack(spacing: -10) {
            ZStack {
                Circle()
                    .fill(Color(red: 0.3, green: 0.55, blue: 0.25))
                    .frame(width: 70, height: 70)
                Circle()
                    .fill(Color(red: 0.9, green: 0.2, blue: 0.2))
                    .frame(width: 8, height: 8)
                    .offset(x: -15, y: 5)
                Circle()
                    .fill(Color(red: 0.9, green: 0.2, blue: 0.2))
                    .frame(width: 8, height: 8)
                    .offset(x: 18, y: -5)
            }
            Rectangle()
                .fill(Color(red: 0.35, green: 0.2, blue: 0.12))
                .frame(width: 14, height: 70)
        }
    }
}

private struct HeavensGardenBG: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 1.0, green: 0.85, blue: 0.95),
                         Color(red: 1.0, green: 0.7, blue: 0.8),
                         Color(red: 0.95, green: 0.85, blue: 1.0)],
                startPoint: .top, endPoint: .bottom
            )
            // Glowing clouds
            ForEach(0..<8, id: \.self) { i in
                Capsule()
                    .fill(Color.white.opacity(0.85))
                    .frame(width: CGFloat(100 + (i * 31) % 80),
                           height: 26)
                    .offset(
                        x: CGFloat((i * 83) % 340) - 170,
                        y: CGFloat((i * 61) % 400) - 200
                    )
                    .shadow(color: Color(red: 1.0, green: 0.9, blue: 1.0), radius: 20)
            }
            // Golden halo
            Circle()
                .stroke(Color(red: 1.0, green: 0.9, blue: 0.5), lineWidth: 6)
                .frame(width: 220, height: 220)
                .blur(radius: 2)
                .opacity(0.7)
            // Floating golden fruit
            ForEach(0..<5, id: \.self) { i in
                Circle()
                    .fill(Color(red: 1.0, green: 0.85, blue: 0.3))
                    .frame(width: 18, height: 18)
                    .shadow(color: Color(red: 1.0, green: 0.85, blue: 0.3), radius: 14)
                    .offset(
                        x: CGFloat((i * 71) % 300) - 150,
                        y: CGFloat((i * 47) % 400) - 200
                    )
            }
        }
    }
}

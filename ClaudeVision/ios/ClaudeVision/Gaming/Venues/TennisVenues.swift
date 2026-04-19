import SwiftUI

enum TennisVenues {
    static let all: [Venue] = [
        Venue(id: "rooftop", gameID: "tennis", name: "Rooftop Court",
              tagline: "City skyline, evening heat.", unlockAt: 0) {
            RooftopBG()
        },
        Venue(id: "cherry-park", gameID: "tennis", name: "Cherry Blossom Park",
              tagline: "Petals drift across the baseline.", unlockAt: 80) {
            CherryParkBG()
        },
        Venue(id: "grand-arena", gameID: "tennis", name: "Grand Arena",
              tagline: "Stadium lights. Sold out.", unlockAt: 300) {
            GrandArenaBG()
        }
    ]
}

private struct RooftopBG: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.9, green: 0.5, blue: 0.3),
                         Color(red: 0.35, green: 0.2, blue: 0.45)],
                startPoint: .top, endPoint: .bottom
            )
            // Skyline
            HStack(alignment: .bottom, spacing: 4) {
                ForEach(0..<12, id: \.self) { i in
                    Rectangle()
                        .fill(Color.black.opacity(0.7))
                        .frame(width: 24, height: CGFloat(60 + (i * 37) % 140))
                }
            }
            .frame(maxHeight: .infinity, alignment: .bottom)
            .padding(.bottom, 180)
            // Court floor tint
            VStack {
                Spacer()
                Rectangle()
                    .fill(Color(red: 0.3, green: 0.55, blue: 0.4).opacity(0.5))
                    .frame(height: 160)
            }
        }
    }
}

private struct CherryParkBG: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 1.0, green: 0.85, blue: 0.9),
                         Color(red: 0.95, green: 0.6, blue: 0.75)],
                startPoint: .top, endPoint: .bottom
            )
            // Drifting petals
            ForEach(0..<18, id: \.self) { i in
                Circle()
                    .fill(Color(red: 1.0, green: 0.55, blue: 0.75).opacity(0.8))
                    .frame(width: 8, height: 8)
                    .offset(
                        x: CGFloat((i * 47) % 360) - 180,
                        y: CGFloat((i * 83) % 500) - 250
                    )
            }
            // Tree silhouette
            HStack {
                Spacer()
                VStack(spacing: -10) {
                    Circle().fill(Color(red: 0.9, green: 0.4, blue: 0.6)).frame(width: 160, height: 140)
                    Rectangle().fill(Color(red: 0.3, green: 0.15, blue: 0.1)).frame(width: 24, height: 100)
                }
                .offset(x: 40, y: 100)
            }
        }
    }
}

private struct GrandArenaBG: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.05, green: 0.08, blue: 0.18),
                         Color(red: 0.12, green: 0.18, blue: 0.3)],
                startPoint: .top, endPoint: .bottom
            )
            // Stadium lights
            HStack(spacing: 30) {
                ForEach(0..<4, id: \.self) { _ in
                    VStack {
                        Circle().fill(Color(red: 1.0, green: 0.98, blue: 0.85))
                            .frame(width: 40, height: 40)
                            .shadow(color: .white, radius: 30)
                        Rectangle().fill(Color.black).frame(width: 3, height: 60)
                    }
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
            .padding(.top, 40)
            // Crowd silhouettes
            VStack {
                Spacer()
                Rectangle()
                    .fill(Color.black.opacity(0.85))
                    .frame(height: 100)
                    .overlay(
                        HStack(spacing: 2) {
                            ForEach(0..<40, id: \.self) { i in
                                Circle()
                                    .fill(Color.black)
                                    .frame(width: 10, height: 10)
                                    .offset(y: CGFloat((i * 13) % 8))
                            }
                        }
                        .offset(y: -40)
                    )
            }
        }
    }
}

import SwiftUI

/// Venues for Jamario: Streets. Backgrounds painted behind the
/// SpriteKit playfield (SKView is transparent).
enum JamarioStreetsVenues {
  static let all: [Venue] = [
    Venue(
      id: "downtown", gameID: "jamariostreets", name: "Downtown",
      tagline: "Wave-based street fight.", unlockAt: 0
    ) {
      DowntownBG()
    },
    Venue(
      id: "neon-block", gameID: "jamariostreets", name: "Neon Block",
      tagline: "Goombas + neon = trouble.", unlockAt: 200,
      modifier: VenueModifier(
        scoreMultiplier: 1.5,
        flavorLine: "Crowd's hyped — every takedown scores 1.5×."
      )
    ) {
      NeonBlockBG()
    },
  ]
}

private struct DowntownBG: View {
  var body: some View {
    LinearGradient(
      colors: [
        Color(red: 0.30, green: 0.10, blue: 0.30),
        Color(red: 0.55, green: 0.20, blue: 0.40),
        Color(red: 0.20, green: 0.10, blue: 0.20),
      ],
      startPoint: .top, endPoint: .bottom)
  }
}

private struct NeonBlockBG: View {
  var body: some View {
    LinearGradient(
      colors: [
        Color(red: 0.05, green: 0.05, blue: 0.20),
        Color(red: 0.65, green: 0.15, blue: 0.50),
        Color(red: 0.10, green: 0.05, blue: 0.20),
      ],
      startPoint: .top, endPoint: .bottom)
  }
}

import SwiftUI

/// Venues for Meta Firefox. Backgrounds painted behind the SceneKit
/// playfield (SCNView is transparent).
enum FirefoxVenues {
  static let all: [Venue] = [
    Venue(
      id: "arctic-run", gameID: "firefox", name: "Arctic Run",
      tagline: "Cold sky, fast jets.", unlockAt: 0
    ) {
      ArcticBG()
    },
    Venue(
      id: "midnight-strike", gameID: "firefox", name: "Midnight Strike",
      tagline: "Night ops over the strait.", unlockAt: 300,
      modifier: VenueModifier(
        scoreMultiplier: 1.5,
        flavorLine: "Night vision — score 1.5×."
      )
    ) {
      MidnightBG()
    },
    Venue(
      id: "desert-dogfight", gameID: "firefox", name: "Desert Dogfight",
      tagline: "Sun on the canopy. Bandits on the six.", unlockAt: 800,
      modifier: VenueModifier(
        scoreMultiplier: 2.0,
        difficultyMultiplier: 1.3,
        flavorLine: "Heat haze. 2× score, faster bandits."
      )
    ) {
      DesertBG()
    },
  ]
}

private struct ArcticBG: View {
  var body: some View {
    LinearGradient(
      colors: [
        Color(red: 0.55, green: 0.78, blue: 0.95),
        Color(red: 0.85, green: 0.92, blue: 0.98),
      ],
      startPoint: .top, endPoint: .bottom)
  }
}

private struct MidnightBG: View {
  var body: some View {
    LinearGradient(
      colors: [
        Color(red: 0.05, green: 0.05, blue: 0.18),
        Color(red: 0.10, green: 0.10, blue: 0.30),
      ],
      startPoint: .top, endPoint: .bottom)
  }
}

private struct DesertBG: View {
  var body: some View {
    LinearGradient(
      colors: [
        Color(red: 0.95, green: 0.65, blue: 0.30),
        Color(red: 1.00, green: 0.85, blue: 0.55),
      ],
      startPoint: .top, endPoint: .bottom)
  }
}

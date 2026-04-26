import SwiftUI

/// Venues for Jamario. Each one is a SwiftUI background painted
/// behind the SpriteKit playfield (the SKView is transparent), so
/// the player gets a different sky and horizon per venue. The
/// SpriteKit scene's per-venue palette comes from
/// `JamarioSceneTheme.theme(forVenueID:)`.
enum JamarioVenues {
  static let all: [Venue] = [
    Venue(
      id: "jamario-kingdom", gameID: "jamario", name: "Jamario's Kingdom",
      tagline: "Where it all begins.", unlockAt: 0
    ) {
      JamarioKingdomBG()
    },
    Venue(
      id: "shifting-sands", gameID: "jamario", name: "Shifting Sands",
      tagline: "Hot dunes, hotter goombas.", unlockAt: 250,
      modifier: VenueModifier(
        scoreMultiplier: 1.25,
        flavorLine: "Desert run — coins are worth 25% more."
      )
    ) {
      ShiftingSandsBG()
    },
    Venue(
      id: "cloud-tops", gameID: "jamario", name: "Cloud Tops",
      tagline: "Up in the violet sky.", unlockAt: 600,
      modifier: VenueModifier(
        scoreMultiplier: 1.5,
        difficultyMultiplier: 1.2,
        flavorLine: "Thin air — score 1.5×, but pits hurt more."
      )
    ) {
      CloudTopsBG()
    },
  ]
}

// MARK: - Backgrounds

private struct JamarioKingdomBG: View {
  var body: some View {
    LinearGradient(
      colors: [
        Color(red: 0.40, green: 0.70, blue: 1.00),
        Color(red: 0.75, green: 0.92, blue: 1.00),
      ],
      startPoint: .top, endPoint: .bottom)
  }
}

private struct ShiftingSandsBG: View {
  var body: some View {
    LinearGradient(
      colors: [
        Color(red: 0.95, green: 0.65, blue: 0.30),
        Color(red: 1.00, green: 0.85, blue: 0.55),
      ],
      startPoint: .top, endPoint: .bottom)
  }
}

private struct CloudTopsBG: View {
  var body: some View {
    LinearGradient(
      colors: [
        Color(red: 0.45, green: 0.30, blue: 0.65),
        Color(red: 0.85, green: 0.65, blue: 0.95),
      ],
      startPoint: .top, endPoint: .bottom)
  }
}

import SwiftUI

/// A playable environment for one game. Venues are pure SwiftUI — no assets —
/// so they can be authored quickly and later swapped for real key art without
/// changing the data model. Each venue belongs to one gameID and unlocks when
/// the player's cumulative score for that game crosses `unlockAt`.
///
/// Optional `modifier` tweaks the game's rules while playing in this venue —
/// bonus multipliers, difficulty curves, flavor effects.
struct Venue: Identifiable {
  let id: String
  let gameID: String
  let name: String
  let tagline: String
  let unlockAt: Int
  let background: AnyView
  let modifier: VenueModifier

  init<V: View>(
    id: String,
    gameID: String,
    name: String,
    tagline: String,
    unlockAt: Int,
    modifier: VenueModifier = .default,
    @ViewBuilder background: () -> V
  ) {
    self.id = id
    self.gameID = gameID
    self.name = name
    self.tagline = tagline
    self.unlockAt = unlockAt
    self.background = AnyView(background())
    self.modifier = modifier
  }
}

/// Per-venue gameplay modifiers. Games read these before resolving a gesture
/// to adjust scoring, difficulty, and flavor. All fields default to neutral
/// values so a venue without a modifier behaves exactly as before.
struct VenueModifier {
  /// Multiplies every score increment coming out of the game.
  var scoreMultiplier: Double = 1.0
  /// Multiplies the CPU / target difficulty knob. 1.0 = default, 1.2 = harder.
  var difficultyMultiplier: Double = 1.0
  /// Human-readable one-liner shown on the coaching panel so the player
  /// knows the rules changed.
  var flavorLine: String? = nil
  /// Named special effect the game can switch on. Opt-in per game.
  var effect: Effect = .none

  enum Effect: String {
    case none
    case windDrift  // archery — draw gets a random magnitude offset
    case slowMo  // fruit slash — near-misses trigger brief slow-mo
    case crowdPressure  // boxing — hooks do bonus damage
    case stickyLane  // bowling — low-power rolls still knock a few pins
    case rainTempo  // ping pong — CPU returns faster
    case highAltitude  // archery — larger sweet spot for bullseye
  }

  static let `default` = VenueModifier()
}

/// Central registry of every venue, grouped by game. Each game's list is
/// ordered by unlock threshold, so index 0 is always the starter venue.
enum VenueLibrary {
  static func venues(for gameID: String) -> [Venue] {
    switch gameID {
    case "bowling": return BowlingVenues.all
    case "tennis": return TennisVenues.all
    case "pingpong": return PingPongVenues.all
    case "boxing": return BoxingVenues.all
    case "archery": return ArcheryVenues.all
    case "fruitslash": return FruitSlashVenues.all
    case "jamario": return JamarioVenues.all
    case "jamariostreets": return JamarioStreetsVenues.all
    case "firefox": return FirefoxVenues.all
    default: return []
    }
  }

  static func starter(for gameID: String) -> Venue? {
    venues(for: gameID).first
  }

  static func venue(id: String, gameID: String) -> Venue? {
    venues(for: gameID).first(where: { $0.id == id })
  }
}

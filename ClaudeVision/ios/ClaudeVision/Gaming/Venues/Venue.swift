import SwiftUI

/// A playable environment for one game. Venues are pure SwiftUI — no assets —
/// so they can be authored quickly and later swapped for real key art without
/// changing the data model. Each venue belongs to one gameID and unlocks when
/// the player's cumulative score for that game crosses `unlockAt`.
struct Venue: Identifiable {
    let id: String
    let gameID: String
    let name: String
    let tagline: String
    let unlockAt: Int
    let background: (AnyView)

    init<V: View>(
        id: String,
        gameID: String,
        name: String,
        tagline: String,
        unlockAt: Int,
        @ViewBuilder background: () -> V
    ) {
        self.id = id
        self.gameID = gameID
        self.name = name
        self.tagline = tagline
        self.unlockAt = unlockAt
        self.background = AnyView(background())
    }
}

/// Central registry of every venue, grouped by game. Each game's list is
/// ordered by unlock threshold, so index 0 is always the starter venue.
enum VenueLibrary {
    static func venues(for gameID: String) -> [Venue] {
        switch gameID {
        case "bowling":    return BowlingVenues.all
        case "tennis":     return TennisVenues.all
        case "pingpong":   return PingPongVenues.all
        case "boxing":     return BoxingVenues.all
        case "archery":    return ArcheryVenues.all
        case "fruitslash": return FruitSlashVenues.all
        default:           return []
        }
    }

    static func starter(for gameID: String) -> Venue? {
        venues(for: gameID).first
    }

    static func venue(id: String, gameID: String) -> Venue? {
        venues(for: gameID).first(where: { $0.id == id })
    }
}

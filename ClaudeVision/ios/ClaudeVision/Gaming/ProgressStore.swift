import Foundation
import Combine
import SwiftUI

/// Persists the player's cumulative score per game and currently-selected
/// venue per game. Backs the unlock system for venues.
///
/// Cumulative (not best-session) is used so every game counts toward unlocks —
/// a player can grind or go for one big score and both pay off.
@MainActor
final class ProgressStore: ObservableObject {
    static let shared = ProgressStore()

    @Published private(set) var totals: [String: Int] = [:]
    @Published private(set) var selectedVenue: [String: String] = [:]
    /// Venues that have ever been unlocked. We check this to suppress repeated
    /// celebration overlays when a user re-crosses a threshold.
    @Published private(set) var celebratedVenues: Set<String> = []

    /// Set from GameSessionView when a new venue crosses the unlock line so
    /// HomeView can pop a celebration.
    @Published var pendingCelebration: Venue?

    private let totalsKey = "venue.totals.v1"
    private let selectedKey = "venue.selected.v1"
    private let celebratedKey = "venue.celebrated.v1"

    init() {
        load()
    }

    // MARK: - Score reporting

    /// Adds to the cumulative total for `gameID` and returns the list of
    /// venues (if any) that crossed their unlockAt threshold on this call.
    @discardableResult
    func reportScore(_ score: Int, for gameID: String) -> [Venue] {
        guard score > 0 else { return [] }
        let previous = totals[gameID, default: 0]
        let next = previous + score
        totals[gameID] = next
        save()

        let newlyUnlocked = VenueLibrary.venues(for: gameID).filter {
            $0.unlockAt > previous && $0.unlockAt <= next && !celebratedVenues.contains($0.id)
        }
        if let first = newlyUnlocked.first {
            pendingCelebration = first
        }
        return newlyUnlocked
    }

    func acknowledgeCelebration(_ venue: Venue) {
        celebratedVenues.insert(venue.id)
        if pendingCelebration?.id == venue.id { pendingCelebration = nil }
        save()
    }

    // MARK: - Venue selection

    func currentVenue(for gameID: String) -> Venue {
        if let id = selectedVenue[gameID],
           let v = VenueLibrary.venue(id: id, gameID: gameID),
           isUnlocked(v) {
            return v
        }
        return VenueLibrary.starter(for: gameID)!
    }

    func selectVenue(_ venue: Venue) {
        guard isUnlocked(venue) else { return }
        selectedVenue[venue.gameID] = venue.id
        save()
    }

    func isUnlocked(_ venue: Venue) -> Bool {
        totals[venue.gameID, default: 0] >= venue.unlockAt
    }

    func total(for gameID: String) -> Int {
        totals[gameID, default: 0]
    }

    func progressToNextUnlock(for gameID: String) -> (current: Int, next: Int)? {
        let current = total(for: gameID)
        let upcoming = VenueLibrary.venues(for: gameID)
            .first(where: { $0.unlockAt > current })
        guard let next = upcoming else { return nil }
        return (current, next.unlockAt)
    }

    // MARK: - Persistence

    private func load() {
        let defaults = UserDefaults.standard
        if let data = defaults.data(forKey: totalsKey),
           let decoded = try? JSONDecoder().decode([String: Int].self, from: data) {
            totals = decoded
        }
        if let data = defaults.data(forKey: selectedKey),
           let decoded = try? JSONDecoder().decode([String: String].self, from: data) {
            selectedVenue = decoded
        }
        if let data = defaults.data(forKey: celebratedKey),
           let decoded = try? JSONDecoder().decode([String].self, from: data) {
            celebratedVenues = Set(decoded)
        }
    }

    private func save() {
        let defaults = UserDefaults.standard
        if let data = try? JSONEncoder().encode(totals) {
            defaults.set(data, forKey: totalsKey)
        }
        if let data = try? JSONEncoder().encode(selectedVenue) {
            defaults.set(data, forKey: selectedKey)
        }
        if let data = try? JSONEncoder().encode(Array(celebratedVenues)) {
            defaults.set(data, forKey: celebratedKey)
        }
    }

    #if DEBUG
    func resetForTesting() {
        totals.removeAll()
        selectedVenue.removeAll()
        celebratedVenues.removeAll()
        pendingCelebration = nil
        save()
    }
    #endif
}

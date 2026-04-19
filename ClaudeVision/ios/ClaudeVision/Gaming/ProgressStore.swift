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
    /// Best single-session score per (gameID, venueID). Keyed as "gameID|venueID".
    @Published private(set) var highScores: [String: Int] = [:]
    /// Venues that have ever been unlocked. We check this to suppress repeated
    /// celebration overlays when a user re-crosses a threshold.
    @Published private(set) var celebratedVenues: Set<String> = []
    /// Daily challenge progress, keyed by the challenge's date stamp.
    @Published private(set) var challengeProgress: [String: ChallengeRecord] = [:]

    /// Set from GameSessionView when a new venue crosses the unlock line so
    /// HomeView can pop a celebration.
    @Published var pendingCelebration: Venue?
    /// Set when the player finishes a session that set a new high score
    /// (or completed a challenge). Consumed by the session's game-over screen.
    @Published var pendingHighScore: HighScoreFlash?

    private let totalsKey = "venue.totals.v1"
    private let selectedKey = "venue.selected.v1"
    private let celebratedKey = "venue.celebrated.v1"
    private let highScoresKey = "venue.highscores.v1"
    private let challengeKey = "challenge.progress.v1"

    struct ChallengeRecord: Codable {
        var progress: Int
        var completed: Bool
    }

    struct HighScoreFlash {
        let gameID: String
        let venueID: String
        let score: Int
        let previous: Int
    }

    init() {
        load()
    }

    // MARK: - Score reporting

    /// Adds to the cumulative total for `gameID` and returns the list of
    /// venues (if any) that crossed their unlockAt threshold on this call.
    /// Also updates the per-venue high score and reports challenge progress.
    @discardableResult
    func reportScore(_ score: Int, for gameID: String) -> [Venue] {
        guard score > 0 else { return [] }
        let previous = totals[gameID, default: 0]
        let next = previous + score
        totals[gameID] = next

        // Per-venue high score.
        let venue = currentVenue(for: gameID)
        let scoreKey = highScoreKey(gameID: gameID, venueID: venue.id)
        let previousHigh = highScores[scoreKey, default: 0]
        if score > previousHigh {
            highScores[scoreKey] = score
            pendingHighScore = HighScoreFlash(
                gameID: gameID,
                venueID: venue.id,
                score: score,
                previous: previousHigh
            )
        }

        // Daily challenge.
        recordChallengeProgress(gameID: gameID, sessionScore: score)

        save()

        let newlyUnlocked = VenueLibrary.venues(for: gameID).filter {
            $0.unlockAt > previous && $0.unlockAt <= next && !celebratedVenues.contains($0.id)
        }
        if let first = newlyUnlocked.first {
            pendingCelebration = first
        }
        return newlyUnlocked
    }

    // MARK: - High scores

    func highScore(gameID: String, venueID: String) -> Int {
        highScores[highScoreKey(gameID: gameID, venueID: venueID), default: 0]
    }

    func clearPendingHighScore() {
        pendingHighScore = nil
    }

    private func highScoreKey(gameID: String, venueID: String) -> String {
        "\(gameID)|\(venueID)"
    }

    // MARK: - Daily challenge

    /// Returns today's challenge. Deterministic per date so the same device
    /// sees the same challenge all day, but it varies day to day.
    var todaysChallenge: DailyChallenge {
        DailyChallenge.forToday()
    }

    func challengeRecord(for challenge: DailyChallenge) -> ChallengeRecord {
        challengeProgress[challenge.dateKey, default: ChallengeRecord(progress: 0, completed: false)]
    }

    private func recordChallengeProgress(gameID: String, sessionScore: Int) {
        let challenge = todaysChallenge
        guard challenge.gameID == gameID else { return }
        var record = challengeRecord(for: challenge)
        guard !record.completed else { return }
        record.progress = min(challenge.target, record.progress + challenge.contribution(sessionScore: sessionScore))
        if record.progress >= challenge.target {
            record.completed = true
            // Reward: bonus points toward unlocks.
            totals[gameID, default: 0] += challenge.rewardBonus
        }
        challengeProgress[challenge.dateKey] = record
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
        if let data = defaults.data(forKey: highScoresKey),
           let decoded = try? JSONDecoder().decode([String: Int].self, from: data) {
            highScores = decoded
        }
        if let data = defaults.data(forKey: challengeKey),
           let decoded = try? JSONDecoder().decode([String: ChallengeRecord].self, from: data) {
            challengeProgress = decoded
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
        if let data = try? JSONEncoder().encode(highScores) {
            defaults.set(data, forKey: highScoresKey)
        }
        if let data = try? JSONEncoder().encode(challengeProgress) {
            defaults.set(data, forKey: challengeKey)
        }
    }

    #if DEBUG
    func resetForTesting() {
        totals.removeAll()
        selectedVenue.removeAll()
        celebratedVenues.removeAll()
        highScores.removeAll()
        challengeProgress.removeAll()
        pendingCelebration = nil
        pendingHighScore = nil
        save()
    }
    #endif
}

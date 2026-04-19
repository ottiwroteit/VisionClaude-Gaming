import Foundation

/// A small, deterministic daily challenge. Same calendar day yields the same
/// challenge across app restarts — no server, no clock juggling. The seed is
/// the day number since the reference date, so the rotation cycles through
/// all (game, goal) combinations over time.
struct DailyChallenge {
    let dateKey: String          // YYYY-MM-DD, used as the storage key
    let gameID: String
    let headline: String         // "STRIKE WEEK", "ARCHER'S EYE", etc.
    let goal: String             // "Score 120 in bowling"
    let target: Int              // numeric target
    let rewardBonus: Int         // bonus added to cumulative total on completion

    /// How much a single session contributes to progress. Most challenges are
    /// "score N" (contribution = session score), but a few are "win N rounds"
    /// which would count as 1 per completed session. We keep it simple here —
    /// every challenge is score-based.
    func contribution(sessionScore: Int) -> Int { sessionScore }

    // MARK: - Factory

    static func forToday(date: Date = Date(), calendar: Calendar = .current) -> DailyChallenge {
        let key = dateFormatter.string(from: date)
        let day = calendar.ordinality(of: .day, in: .era, for: date) ?? 0
        let template = templates[day % templates.count]
        return DailyChallenge(
            dateKey: key,
            gameID: template.gameID,
            headline: template.headline,
            goal: template.goal,
            target: template.target,
            rewardBonus: template.rewardBonus
        )
    }

    private struct Template {
        let gameID: String
        let headline: String
        let goal: String
        let target: Int
        let rewardBonus: Int
    }

    private static let templates: [Template] = [
        Template(gameID: "bowling",    headline: "STRIKE WEEK",    goal: "Score 120 in one bowling game",   target: 120, rewardBonus: 40),
        Template(gameID: "tennis",     headline: "CLAY COURT",     goal: "Win 6 tennis points in a set",     target: 6,   rewardBonus: 30),
        Template(gameID: "pingpong",   headline: "WHIPLASH",       goal: "Reach 8 points in ping pong",      target: 8,   rewardBonus: 25),
        Template(gameID: "boxing",     headline: "IRON CHIN",      goal: "Deal 80 damage in one boxing round", target: 80, rewardBonus: 50),
        Template(gameID: "archery",    headline: "ARCHER'S EYE",   goal: "Score 35 in archery",              target: 35,  rewardBonus: 30),
        Template(gameID: "fruitslash", headline: "SHARP BLADE",    goal: "Slice 20 fruit in a single run",   target: 20,  rewardBonus: 25),
    ]

    static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = .init(identifier: .gregorian)
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
}

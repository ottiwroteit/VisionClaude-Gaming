import Foundation

/// Canned gesture scripts we can replay against games to validate mechanics
/// without wearing the glasses. Each scenario is tuned to drive a game's
/// state machine through an interesting path — not a perfect-score run,
/// just enough variety to exercise win/lose/edge-case behavior.
enum TestScenarios {

    static let library: [GestureRecorder.Script] = [
        perfectBowlingGame,
        mixedBowlingGame,
        tennisQuickWin,
        pingPongRally,
        boxingComboLand,
        archeryFullQuiver,
        fruitSlashSpree
    ]

    static func scenarios(for gameID: String) -> [GestureRecorder.Script] {
        library.filter { $0.gameID == gameID }
    }

    // MARK: - Bowling

    private static let perfectBowlingGame = GestureRecorder.Script(
        id: "bowling-perfect",
        label: "Perfect game (10 strike flicks)",
        gameID: "bowling",
        steps: Array(repeating: flick(.up, 1.0, gap: 1.2), count: 10)
    )

    private static let mixedBowlingGame = GestureRecorder.Script(
        id: "bowling-mixed",
        label: "Mixed frames (strikes, spares, opens)",
        gameID: "bowling",
        steps: [
            flick(.up, 1.0, gap: 0.8),   // strike
            flick(.up, 0.55, gap: 1.2), flick(.up, 0.95, gap: 0.9),   // spare-ish
            flick(.up, 0.4, gap: 1.2),  flick(.up, 0.6, gap: 0.9),    // open
            flick(.up, 1.0, gap: 1.2),  // strike
            flick(.up, 0.5, gap: 1.2),  flick(.up, 0.5, gap: 0.9),    // 5 + 4
            flick(.up, 1.0, gap: 1.2),  // strike
            flick(.up, 0.8, gap: 1.2),  flick(.up, 1.0, gap: 0.9),    // spare
            flick(.up, 0.7, gap: 1.2),  flick(.up, 0.3, gap: 0.9),    // open
            flick(.up, 1.0, gap: 1.2),  // strike
            flick(.up, 1.0, gap: 1.2),  // strike
            flick(.up, 1.0, gap: 1.2)   // strike
        ]
    )

    // MARK: - Tennis

    private static let tennisQuickWin = GestureRecorder.Script(
        id: "tennis-rally",
        label: "Serve + 4-shot rally win",
        gameID: "tennis",
        steps: [
            flick(.up, 0.9, gap: 0.6),     // serve
            swing(.right, 0.8, gap: 0.8),  // forehand
            swing(.left, 0.7, gap: 0.8),   // backhand
            swing(.right, 0.9, gap: 0.8),  // forehand
            swing(.left, 1.0, gap: 0.8)    // winner
        ]
    )

    // MARK: - Ping pong

    private static let pingPongRally = GestureRecorder.Script(
        id: "pingpong-rally",
        label: "6-return rally to a point",
        gameID: "pingpong",
        steps: [
            flick(.right, 0.8, gap: 0.6),
            flick(.left, 0.7, gap: 0.6),
            flick(.up, 0.9, gap: 0.5),
            flick(.right, 0.8, gap: 0.5),
            flick(.left, 0.9, gap: 0.5),
            flick(.right, 1.0, gap: 0.4)
        ]
    )

    // MARK: - Boxing

    private static let boxingComboLand = GestureRecorder.Script(
        id: "boxing-combo",
        label: "Dodge → jab → hook combo",
        gameID: "boxing",
        steps: [
            flick(.right, 0.7, gap: 1.3),   // slip a left hook
            flick(.down, 0.9, gap: 0.7),    // jab
            swing(.right, 1.0, gap: 0.6),   // hook right
            flick(.down, 0.7, gap: 1.4),    // duck uppercut
            flick(.down, 0.95, gap: 0.6),   // jab
            swing(.left, 1.0, gap: 0.6)     // hook left
        ]
    )

    // MARK: - Archery
    // Archery's drawStrength climbs while hold events keep firing, so each
    // arrow is a burst of `ticks` hold steps followed by an up-flick. More
    // ticks = bigger draw = more power.

    private static let archeryFullQuiver = GestureRecorder.Script(
        id: "archery-full",
        label: "Full quiver, varied draw strengths",
        gameID: "archery",
        steps: drawAndFire(ticks: 9) + drawAndFire(ticks: 6) + drawAndFire(ticks: 12)
            + drawAndFire(ticks: 4) + drawAndFire(ticks: 10)
    )

    private static func drawAndFire(ticks: Int) -> [GestureRecorder.Script.Step] {
        var out: [GestureRecorder.Script.Step] = []
        for _ in 0..<ticks { out.append(hold(0.2)) }
        out.append(flick(.up, 1.0, gap: 0.1))
        // Pause between arrows so the next drawStart can reset cleanly.
        out.append(hold(0.6))
        return out
    }

    // MARK: - Fruit slash

    private static let fruitSlashSpree = GestureRecorder.Script(
        id: "fruitslash-spree",
        label: "10 consecutive slices in all 4 directions",
        gameID: "fruitslash",
        steps: [
            flick(.up, 0.8, gap: 0.9),
            flick(.right, 0.9, gap: 0.9),
            flick(.down, 0.7, gap: 0.9),
            flick(.left, 0.8, gap: 0.9),
            flick(.up, 1.0, gap: 0.9),
            flick(.right, 0.9, gap: 0.9),
            flick(.down, 0.8, gap: 0.9),
            flick(.left, 1.0, gap: 0.9),
            flick(.up, 0.85, gap: 0.9),
            flick(.right, 1.0, gap: 0.9)
        ]
    )

    // MARK: - Helpers

    private static func flick(_ direction: GestureDirection, _ magnitude: Float, gap: TimeInterval) -> GestureRecorder.Script.Step {
        .init(delay: gap, kind: "flick", direction: direction.rawValue, magnitude: magnitude, duration: 0.18)
    }

    private static func swing(_ direction: GestureDirection, _ magnitude: Float, gap: TimeInterval) -> GestureRecorder.Script.Step {
        .init(delay: gap, kind: "swing", direction: direction.rawValue, magnitude: magnitude, duration: 0.45)
    }

    private static func hold(_ duration: TimeInterval) -> GestureRecorder.Script.Step {
        .init(delay: duration, kind: "hold", direction: "none", magnitude: 0, duration: duration)
    }
}

import SwiftUI

/// Home-screen banner for today's daily challenge. Tapping it jumps straight
/// into the target game's venue picker.
struct DailyChallengeCard: View {
    let challenge: DailyChallenge
    let record: ProgressStore.ChallengeRecord
    var onJump: () -> Void

    private var tint: Color {
        Theme.color(for: tintForGame(challenge.gameID))
    }

    private var progressFraction: CGFloat {
        guard challenge.target > 0 else { return 0 }
        return min(1, CGFloat(record.progress) / CGFloat(challenge.target))
    }

    var body: some View {
        Button(action: onJump) {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Image(systemName: "calendar")
                            .font(.caption.weight(.heavy))
                        Text("TODAY'S CHALLENGE").tracking(3)
                    }
                    .font(.hype(11))
                    .foregroundColor(tint)

                    Text(challenge.headline.uppercased())
                        .font(.hype(22))
                        .foregroundColor(Theme.textPrimary)
                        .shadow(color: tint, radius: 0, x: 2, y: 2)

                    Text(challenge.goal)
                        .font(.caption.weight(.semibold))
                        .foregroundColor(Theme.textSecondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    // Progress chunks — same energy-bar motif as motion meter.
                    HStack(spacing: 2) {
                        let segments = 12
                        let filled = Int(progressFraction * CGFloat(segments))
                        ForEach(0..<segments, id: \.self) { i in
                            Rectangle()
                                .fill(i < filled ? tint : Theme.surface)
                                .frame(height: 8)
                        }
                    }
                    .overlay(Rectangle().stroke(Color.black, lineWidth: 1.5))
                    .padding(.top, 2)

                    HStack {
                        Text("\(record.progress) / \(challenge.target)")
                            .font(.hype(12)).foregroundColor(tint)
                        Spacer()
                        Text("+\(challenge.rewardBonus) BONUS")
                            .font(.hype(11)).tracking(2)
                            .foregroundColor(Theme.textSecondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if record.completed {
                    VStack {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 36, weight: .black))
                            .foregroundColor(Theme.success)
                        Text("DONE").tracking(2)
                            .font(.hype(11)).foregroundColor(Theme.success)
                    }
                }
            }
            .padding(14)
            .celBorder(tint: record.completed ? Theme.success : tint)
        }
        .buttonStyle(.plain)
    }

    private func tintForGame(_ id: String) -> GameTint {
        switch id {
        case "bowling":    return .accent
        case "tennis":     return .court
        case "pingpong":   return .table
        case "boxing":     return .ring
        case "archery":    return .gold
        case "fruitslash": return .berry
        default:           return .accent
        }
    }
}

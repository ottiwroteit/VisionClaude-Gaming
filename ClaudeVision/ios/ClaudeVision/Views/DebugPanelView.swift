import SwiftUI

/// Dev-only sheet for running canned scenarios without the glasses. Lets us
/// iterate on game mechanics + UI while the Ray-Bans are unavailable.
///
/// Reached via a long-press on the Home screen's "GAMING" title (hidden so
/// real users don't stumble in).
struct DebugPanelView: View {
    @ObservedObject var progress: ProgressStore
    var onRunScenario: (GestureRecorder.Script) -> Void
    var onDismiss: () -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                Halftone().ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        header

                        section("Canned scenarios", color: Theme.accent) {
                            VStack(spacing: 10) {
                                ForEach(TestScenarios.library, id: \.id) { script in
                                    scenarioRow(script: script)
                                }
                            }
                        }

                        section("Progress", color: Theme.success) {
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(gameIDs, id: \.self) { gameID in
                                    HStack {
                                        Text(gameID.uppercased())
                                            .font(.hype(12)).tracking(2)
                                            .foregroundColor(Theme.textSecondary)
                                        Spacer()
                                        Text("\(progress.total(for: gameID)) pts")
                                            .font(.hype(12))
                                            .foregroundColor(Theme.textPrimary)
                                    }
                                    .padding(.vertical, 2)
                                }
                                Button {
                                    progress.resetForTesting()
                                } label: {
                                    Text("RESET ALL PROGRESS").tracking(3)
                                        .font(.hype(13))
                                        .foregroundColor(.black)
                                        .padding(.horizontal, 14).padding(.vertical, 8)
                                        .background(Theme.danger)
                                        .overlay(Rectangle().stroke(Color.black, lineWidth: 2))
                                }
                                .buttonStyle(.plain)
                                .padding(.top, 8)
                            }
                            .padding(14)
                            .celBorder(tint: Theme.success, strokeWidth: 2)
                        }

                        section("Today's challenge", color: Theme.accent) {
                            let challenge = progress.todaysChallenge
                            let record = progress.challengeRecord(for: challenge)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(challenge.headline.uppercased())
                                    .font(.hype(18)).foregroundColor(Theme.textPrimary)
                                Text(challenge.goal)
                                    .font(.caption.weight(.semibold))
                                    .foregroundColor(Theme.textSecondary)
                                Text("\(record.progress) / \(challenge.target) · \(record.completed ? "COMPLETED" : "IN PROGRESS")")
                                    .font(.hype(11)).tracking(2)
                                    .foregroundColor(record.completed ? Theme.success : Theme.accent)
                            }
                            .padding(14)
                            .celBorder(tint: Theme.accent, strokeWidth: 2)
                        }
                    }
                    .padding(20)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("CLOSE") { onDismiss() }
                        .foregroundColor(Theme.accent)
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("DEV CONSOLE")
                .font(.hype(28))
                .foregroundColor(Theme.textPrimary)
                .shadow(color: Theme.accent, radius: 0, x: 3, y: 3)
            Text("Drive games without the glasses.")
                .font(.caption).foregroundColor(Theme.textSecondary)
        }
    }

    private func section<Content: View>(_ title: String, color: Color, @ViewBuilder body: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.hype(13)).tracking(3)
                .foregroundColor(color)
            body()
        }
    }

    private func scenarioRow(script: GestureRecorder.Script) -> some View {
        Button {
            onRunScenario(script)
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(script.gameID.uppercased())
                        .font(.hype(11)).tracking(3)
                        .foregroundColor(Theme.accent)
                    Text(script.label)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(Theme.textPrimary)
                    Text("\(script.steps.count) steps")
                        .font(.caption2).foregroundColor(Theme.textSecondary)
                }
                Spacer()
                Image(systemName: "play.fill")
                    .foregroundColor(.black)
                    .padding(8)
                    .background(Theme.accent)
                    .overlay(Rectangle().stroke(Color.black, lineWidth: 2))
            }
            .padding(12)
            .celBorder(tint: Theme.accent, strokeWidth: 2)
        }
        .buttonStyle(.plain)
    }

    private var gameIDs: [String] {
        ["bowling", "tennis", "pingpong", "boxing", "archery", "fruitslash"]
    }
}

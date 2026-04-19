import SwiftUI

/// Full-screen modal that fires when a venue crosses its unlock threshold.
/// Shows the unlocked venue's background as a peek, with a big anime banner.
/// Caller must invoke `onAcknowledge` (tapping the button) so the
/// ProgressStore records it as seen and stops re-announcing.
struct UnlockCelebration: View {
    let venue: Venue
    var onAcknowledge: () -> Void

    @State private var appeared = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.75).ignoresSafeArea()
            SpeedLines(tint: Theme.accent, intensity: 0.8)
                .ignoresSafeArea()

            VStack(spacing: 18) {
                Text("NEW VENUE")
                    .font(.hype(14)).tracking(6)
                    .foregroundColor(Theme.accent)
                Text("UNLOCKED")
                    .font(.hype(44))
                    .foregroundColor(Theme.textPrimary)
                    .shadow(color: Theme.accent, radius: 0, x: 4, y: 4)

                // Peek of the newly-unlocked venue.
                ZStack {
                    venue.background
                    Color.black.opacity(0.25)
                    VStack(spacing: 4) {
                        Text(venue.name.uppercased())
                            .font(.hype(26)).foregroundColor(.white)
                            .shadow(color: .black, radius: 0, x: 2, y: 2)
                        Text(venue.tagline)
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.white.opacity(0.9))
                    }
                }
                .frame(height: 180)
                .overlay(Rectangle().stroke(Theme.accent, lineWidth: 4))
                .shadow(color: .black, radius: 0, x: 5, y: 6)
                .padding(.horizontal, 24)

                Button(action: {
                    withAnimation(.easeIn(duration: 0.2)) {
                        appeared = false
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        onAcknowledge()
                    }
                }) {
                    Text("LET'S GO").tracking(4)
                        .font(.hype(20))
                        .foregroundColor(.black)
                        .padding(.horizontal, 28).padding(.vertical, 12)
                        .background(Theme.accent)
                        .overlay(Rectangle().stroke(Color.black, lineWidth: 3))
                }
                .buttonStyle(.plain)
                .rotationEffect(.degrees(-2))
                .shadow(color: .black, radius: 0, x: 4, y: 5)
            }
            .scaleEffect(appeared ? 1.0 : 0.7)
            .opacity(appeared ? 1.0 : 0.0)
            .onAppear {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.65)) {
                    appeared = true
                }
            }
        }
    }
}

import SwiftUI

/// Shown when the Meta Ray-Ban glasses aren't registered or aren't streaming.
/// Walks the user through pairing in the Meta AI app and starting the feed.
struct GlassesSetupView: View {
    @ObservedObject var rayBan: RayBanManager

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            Halftone().ignoresSafeArea()
            SpeedLines(tint: Theme.accent, intensity: 0.35)
                .ignoresSafeArea()
                .opacity(0.6)

            VStack(spacing: 24) {
                Spacer()

                ZStack {
                    Burst(points: 10, innerRatio: 0.7)
                        .fill(Theme.accent)
                        .frame(width: 200, height: 200)
                    Burst(points: 10, innerRatio: 0.7)
                        .stroke(Color.black, lineWidth: 3)
                        .frame(width: 200, height: 200)
                    Image(systemName: "eyeglasses")
                        .font(.system(size: 80, weight: .black))
                        .foregroundColor(.black)
                }
                .rotationEffect(.degrees(-6))
                .shadow(color: .black, radius: 0, x: 5, y: 6)

                VStack(spacing: 4) {
                    Text("VISIONCLAUDE")
                        .font(.hype(16)).tracking(6)
                        .foregroundColor(Theme.accent)
                    Text("GAMING")
                        .font(.hype(52))
                        .foregroundColor(Theme.textPrimary)
                        .shadow(color: Theme.accent, radius: 0, x: 4, y: 4)
                }

                Text("Link your Meta Ray-Bans to fight.")
                    .font(.hype(16)).tracking(2)
                    .foregroundColor(Theme.textSecondary)
                    .multilineTextAlignment(.center)

                VStack(alignment: .leading, spacing: 12) {
                    step(number: 1, text: "POWER ON YOUR GLASSES")
                    step(number: 2, text: "PAIR IN THE META AI APP")
                    step(number: 3, text: "TAP CONNECT TO AUTHORIZE")
                }
                .padding(16)
                .celBorder(tint: Theme.accent)
                .padding(.horizontal, 24)

                statusPill

                Spacer()

                Button(action: primaryAction) {
                    Text(primaryActionLabel.uppercased())
                        .font(.hype(22)).tracking(4)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Theme.accent)
                        .foregroundColor(.black)
                        .overlay(Rectangle().stroke(Color.black, lineWidth: 3))
                }
                .buttonStyle(.plain)
                .rotationEffect(.degrees(-1))
                .shadow(color: .black, radius: 0, x: 4, y: 5)
                .padding(.horizontal, 24)
            }
            .padding(.vertical, 40)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear {
            rayBan.startMonitoringRegistration()
        }
    }

    @ViewBuilder
    private func step(number: Int, text: String) -> some View {
        HStack(alignment: .center, spacing: 14) {
            Text("\(number)")
                .font(.hype(18))
                .frame(width: 32, height: 32)
                .background(Theme.accent)
                .overlay(Rectangle().stroke(Color.black, lineWidth: 2))
                .foregroundColor(.black)
                .rotationEffect(.degrees(-4))
            Text(text)
                .font(.hype(14)).tracking(1)
                .foregroundColor(Theme.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var statusPill: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(statusColor)
                .frame(width: 10, height: 10)
                .overlay(Circle().stroke(Color.black, lineWidth: 1))
            Text(statusText.uppercased())
                .font(.hype(12)).tracking(3)
                .foregroundColor(Theme.textPrimary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Theme.surfaceStrong)
        .overlay(Rectangle().stroke(statusColor, lineWidth: 2))
    }

    private var statusText: String {
        if rayBan.isRunning { return "Streaming" }
        if rayBan.isRegistered { return "Registered — tap Start to stream" }
        return rayBan.registrationState.capitalized
    }

    private var statusColor: Color {
        if rayBan.isRunning { return Theme.success }
        if rayBan.isRegistered { return Theme.accent }
        return Theme.textSecondary
    }

    private var primaryActionLabel: String {
        if !rayBan.isRegistered { return "Connect glasses" }
        if !rayBan.isRunning { return "Start feed" }
        return "Streaming"
    }

    private func primaryAction() {
        if !rayBan.isRegistered {
            Task { await rayBan.register() }
        } else if !rayBan.isRunning {
            try? rayBan.start()
        }
    }
}

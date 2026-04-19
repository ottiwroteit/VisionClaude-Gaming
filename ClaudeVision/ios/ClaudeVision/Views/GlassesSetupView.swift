import SwiftUI

/// Shown when the Meta Ray-Ban glasses aren't registered or aren't streaming.
/// Walks the user through pairing in the Meta AI app and starting the feed.
struct GlassesSetupView: View {
    @ObservedObject var rayBan: RayBanManager

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "eyeglasses")
                .font(.system(size: 96, weight: .light))
                .foregroundColor(Theme.accent)

            VStack(spacing: 8) {
                Text("Connect your glasses")
                    .font(.largeTitle.bold())
                    .foregroundColor(Theme.textPrimary)
                Text("VisionClaude Gaming needs your Meta Ray-Ban feed to read head motion.")
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundColor(Theme.textSecondary)
                    .padding(.horizontal)
            }

            VStack(alignment: .leading, spacing: 14) {
                step(number: 1, text: "Power on your glasses and open the hinges")
                step(number: 2, text: "Pair them in the Meta AI app if you haven't already")
                step(number: 3, text: "Tap Connect — you'll be bounced to Meta AI to approve")
            }
            .padding(.horizontal, 24)

            statusPill

            Spacer()

            Button(action: primaryAction) {
                Text(primaryActionLabel)
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Theme.accent)
                    .foregroundColor(.black)
                    .cornerRadius(Theme.Radius.medium)
            }
            .padding(.horizontal, 24)
        }
        .padding(.vertical, 40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background.ignoresSafeArea())
        .onAppear {
            rayBan.startMonitoringRegistration()
        }
    }

    @ViewBuilder
    private func step(number: Int, text: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Text("\(number)")
                .font(.subheadline.bold())
                .frame(width: 28, height: 28)
                .background(Circle().fill(Theme.surfaceStrong))
                .foregroundColor(Theme.accent)
            Text(text)
                .font(.subheadline)
                .foregroundColor(Theme.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var statusPill: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
            Text(statusText)
                .font(.footnote)
                .foregroundColor(Theme.textSecondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Capsule().fill(Theme.surface))
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

import SwiftUI

/// Plays for ~1.8s on cold launch. Uses the anime primitives (burst, speed
/// lines) to set the tone before ContentView takes over. Auto-dismisses via
/// `onFinished` callback — no gestures required.
struct LaunchSplashView: View {
    var onFinished: () -> Void

    @State private var scale: CGFloat = 0.2
    @State private var rotation: Double = -40
    @State private var bannerOffset: CGFloat = 400
    @State private var intensity: CGFloat = 0

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            Halftone().ignoresSafeArea()
            SpeedLines(tint: Theme.accent, intensity: intensity)
                .ignoresSafeArea()

            VStack(spacing: 28) {
                ZStack {
                    Burst(points: 14, innerRatio: 0.65)
                        .fill(Theme.accent)
                        .frame(width: 260, height: 260)
                    Burst(points: 14, innerRatio: 0.65)
                        .stroke(Color.black, lineWidth: 4)
                        .frame(width: 260, height: 260)
                    Image(systemName: "eyeglasses")
                        .font(.system(size: 110, weight: .black))
                        .foregroundColor(.black)
                }
                .rotationEffect(.degrees(rotation))
                .scaleEffect(scale)
                .shadow(color: .black, radius: 0, x: 6, y: 8)

                VStack(spacing: -4) {
                    Text("VISIONCLAUDE")
                        .font(.hype(18)).tracking(8)
                        .foregroundColor(Theme.accent)
                    Text("GAMING")
                        .font(.hype(64))
                        .foregroundColor(Theme.textPrimary)
                        .shadow(color: Theme.accent, radius: 0, x: 5, y: 5)
                }
                .offset(y: bannerOffset)
            }
        }
        .onAppear(perform: animate)
    }

    private func animate() {
        withAnimation(.spring(response: 0.6, dampingFraction: 0.55)) {
            scale = 1.0
            rotation = -8
        }
        withAnimation(.spring(response: 0.7, dampingFraction: 0.7).delay(0.25)) {
            bannerOffset = 0
        }
        withAnimation(.easeInOut(duration: 0.9).delay(0.3)) {
            intensity = 0.9
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
            withAnimation(.easeIn(duration: 0.25)) {
                intensity = 0
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                onFinished()
            }
        }
    }
}

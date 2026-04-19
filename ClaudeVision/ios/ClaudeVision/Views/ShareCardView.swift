import SwiftUI

/// Branded bragging image for a finished session. Composed entirely from
/// SwiftUI so we can render it with ImageRenderer and share the PNG via
/// UIActivityViewController.
struct ShareCardView: View {
    let gameTitle: String
    let venueName: String
    let venueTagline: String
    let venueBackground: AnyView
    let tint: Color
    let score: Int
    let isNewRecord: Bool

    // Portrait 3:4 — Instagram story-ish ratio without being exactly 9:16.
    static let size = CGSize(width: 900, height: 1200)

    var body: some View {
        ZStack {
            venueBackground
                .ignoresSafeArea()
            LinearGradient(
                colors: [Color.black.opacity(0.2), Color.black.opacity(0.85)],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()
            SpeedLines(tint: tint, intensity: 0.4)
                .ignoresSafeArea()

            VStack(spacing: 24) {
                HStack {
                    VStack(alignment: .leading, spacing: -6) {
                        Text("VISIONCLAUDE")
                            .font(.hype(22)).tracking(6)
                            .foregroundColor(tint)
                        Text("GAMING")
                            .font(.hype(48))
                            .foregroundColor(.white)
                            .shadow(color: tint, radius: 0, x: 4, y: 4)
                    }
                    Spacer()
                }

                Spacer()

                VStack(spacing: 12) {
                    if isNewRecord {
                        Text("NEW RECORD!").tracking(6)
                            .font(.hype(26))
                            .foregroundColor(.black)
                            .padding(.horizontal, 24).padding(.vertical, 10)
                            .background(tint)
                            .overlay(Rectangle().stroke(Color.black, lineWidth: 3))
                            .rotationEffect(.degrees(-3))
                            .shadow(color: .black, radius: 0, x: 6, y: 7)
                    }
                    BurstBadge(text: "\(score)", tint: tint, size: 320)
                    Text("FINAL SCORE").tracking(6)
                        .font(.hype(22))
                        .foregroundColor(.white.opacity(0.8))
                }

                Spacer()

                VStack(spacing: 8) {
                    Text(gameTitle.uppercased())
                        .font(.hype(38))
                        .foregroundColor(.white)
                        .shadow(color: tint, radius: 0, x: 3, y: 3)
                        .multilineTextAlignment(.center)
                    Text("AT \(venueName.uppercased())")
                        .font(.hype(22)).tracking(3)
                        .foregroundColor(tint)
                    Text(venueTagline)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.white.opacity(0.8))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }

                Text("PLAY IT — visionclaude.gaming")
                    .font(.hype(16)).tracking(3)
                    .foregroundColor(.white.opacity(0.6))
                    .padding(.top, 8)
            }
            .padding(40)
        }
        .frame(width: Self.size.width, height: Self.size.height)
    }
}

/// Renders a ShareCardView to a UIImage using SwiftUI's ImageRenderer.
enum ShareCardRenderer {
    @MainActor
    static func render(_ card: ShareCardView) -> UIImage? {
        let renderer = ImageRenderer(content: card)
        renderer.scale = 2.0
        renderer.proposedSize = .init(ShareCardView.size)
        return renderer.uiImage
    }
}

/// UIKit share-sheet wrapper. Hands the image to UIActivityViewController.
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

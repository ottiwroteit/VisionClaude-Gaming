import SwiftUI

/// Horizontal venue picker shown between the home grid and the game session.
/// Each venue renders its own background as a preview card. Locked venues
/// show the score needed to unlock them.
struct VenueSelectView: View {
    @ObservedObject var progress: ProgressStore
    let game: any Game
    var onStart: (Venue) -> Void
    var onCancel: () -> Void

    @State private var focused: Int = 0

    private var tint: Color { Theme.color(for: game.tint) }
    private var venues: [Venue] { VenueLibrary.venues(for: game.id) }

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            Halftone().ignoresSafeArea()

            VStack(spacing: 16) {
                header
                carousel
                footer
            }
            .padding(20)
        }
        .onAppear(perform: seedFocus)
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Button(action: onCancel) {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                    Text("BACK").tracking(2)
                }
                .font(.hype(14))
                .foregroundColor(.black)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(Theme.textPrimary)
                .overlay(Rectangle().stroke(Color.black, lineWidth: 2))
                .rotationEffect(.degrees(-3))
            }
            Spacer()
            VStack(alignment: .trailing, spacing: -2) {
                Text(game.title.uppercased())
                    .font(.hype(22)).foregroundColor(Theme.textPrimary)
                    .shadow(color: tint, radius: 0, x: 2, y: 2)
                if let (current, next) = progress.progressToNextUnlock(for: game.id) {
                    Text("\(current) / \(next) TO NEXT VENUE")
                        .font(.hype(10)).tracking(2)
                        .foregroundColor(Theme.textSecondary)
                } else {
                    Text("ALL VENUES UNLOCKED")
                        .font(.hype(10)).tracking(2)
                        .foregroundColor(Theme.success)
                }
            }
        }
    }

    // MARK: - Carousel

    private var carousel: some View {
        GeometryReader { proxy in
            let cardHeight = proxy.size.height
            ScrollViewReader { scrollProxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 16) {
                        ForEach(Array(venues.enumerated()), id: \.element.id) { idx, venue in
                            VenueCard(
                                venue: venue,
                                tint: tint,
                                unlocked: progress.isUnlocked(venue),
                                isSelected: progress.currentVenue(for: game.id).id == venue.id,
                                highScore: progress.highScore(gameID: game.id, venueID: venue.id)
                            )
                            .frame(width: proxy.size.width - 80, height: cardHeight)
                            .id(venue.id)
                            .onTapGesture { handleTap(venue) }
                        }
                    }
                    .padding(.horizontal, 40)
                }
                .onAppear {
                    scrollProxy.scrollTo(
                        progress.currentVenue(for: game.id).id,
                        anchor: .center
                    )
                }
            }
        }
    }

    // MARK: - Footer

    private var footer: some View {
        let selected = progress.currentVenue(for: game.id)
        return Button {
            onStart(selected)
        } label: {
            HStack {
                Text("PLAY AT")
                    .font(.hype(14)).tracking(3)
                    .foregroundColor(.black.opacity(0.7))
                Text(selected.name.uppercased())
                    .font(.hype(22)).tracking(2)
                    .foregroundColor(.black)
                Spacer()
                Image(systemName: "play.fill")
                    .font(.system(size: 20, weight: .black))
                    .foregroundColor(.black)
            }
            .padding(.horizontal, 18).padding(.vertical, 16)
            .frame(maxWidth: .infinity)
            .background(tint)
            .overlay(Rectangle().stroke(Color.black, lineWidth: 3))
        }
        .buttonStyle(.plain)
        .rotationEffect(.degrees(-1))
        .shadow(color: .black, radius: 0, x: 4, y: 5)
    }

    // MARK: - Helpers

    private func seedFocus() {
        let current = progress.currentVenue(for: game.id).id
        focused = venues.firstIndex(where: { $0.id == current }) ?? 0
    }

    private func handleTap(_ venue: Venue) {
        if progress.isUnlocked(venue) {
            progress.selectVenue(venue)
        }
    }
}

// MARK: - VenueCard

private struct VenueCard: View {
    let venue: Venue
    let tint: Color
    let unlocked: Bool
    let isSelected: Bool
    let highScore: Int

    var body: some View {
        ZStack {
            // Live background preview — the actual venue backdrop.
            venue.background
                .clipShape(Rectangle())

            // Dim when locked so copy stays readable.
            if !unlocked {
                Color.black.opacity(0.65)
            }

            VStack {
                HStack {
                    if isSelected {
                        Text("SELECTED")
                            .font(.hype(11)).tracking(3)
                            .foregroundColor(.black)
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(tint)
                            .overlay(Rectangle().stroke(Color.black, lineWidth: 1.5))
                    }
                    Spacer()
                    if !unlocked {
                        HStack(spacing: 4) {
                            Image(systemName: "lock.fill")
                            Text("\(venue.unlockAt) PTS").tracking(2)
                        }
                        .font(.hype(11))
                        .foregroundColor(.black)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Theme.textPrimary)
                        .overlay(Rectangle().stroke(Color.black, lineWidth: 1.5))
                    }
                }
                .padding(12)

                Spacer()

                VStack(alignment: .leading, spacing: 6) {
                    if highScore > 0 {
                        HStack(spacing: 6) {
                            Image(systemName: "crown.fill")
                                .foregroundColor(tint)
                            Text("BEST \(highScore)")
                                .font(.hype(12)).tracking(2)
                                .foregroundColor(.white)
                        }
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Color.black.opacity(0.55))
                        .overlay(Rectangle().stroke(tint, lineWidth: 1.5))
                    }
                    Text(venue.name.uppercased())
                        .font(.hype(28))
                        .foregroundColor(.white)
                        .shadow(color: .black, radius: 0, x: 2, y: 2)
                    Text(venue.tagline)
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.white.opacity(0.85))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(Color.black.opacity(0.45))
            }
        }
        .overlay(Rectangle().stroke(isSelected ? tint : Color.black, lineWidth: isSelected ? 4 : 2))
        .shadow(color: .black, radius: 0, x: 4, y: 5)
    }
}

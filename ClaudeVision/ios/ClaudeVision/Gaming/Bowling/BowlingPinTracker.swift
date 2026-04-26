import SwiftUI

/// Top-left HUD showing which of the 10 pins are still standing this
/// roll. Lays the pins out in the standard bowling triangle (1 head pin
/// at the front, 2-3 / 4-6 / 7-10 rows behind), greys out pins that
/// have been knocked down. Bowling Crew uses a similar overlay; this is
/// the SwiftUI version that sits on top of the SceneKit view.
struct BowlingPinTracker: View {
  @ObservedObject var game: BowlingGame
  let tint: Color

  var body: some View {
    let standing = standingPinIndices()
    return VStack(alignment: .leading, spacing: 6) {
      Text("PINS")
        .font(.hype(10)).tracking(2)
        .foregroundColor(.white.opacity(0.85))
      VStack(spacing: 2) {
        row(indices: [6, 7, 8, 9], standing: standing)
        row(indices: [3, 4, 5], standing: standing)
        row(indices: [1, 2], standing: standing)
        row(indices: [0], standing: standing)
      }
      Text("\(standing.count)/10")
        .font(.hype(11)).tracking(1)
        .foregroundColor(tint)
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 8)
    .background(.ultraThinMaterial.opacity(0.9))
    .clipShape(RoundedRectangle(cornerRadius: 8))
    .overlay(
      RoundedRectangle(cornerRadius: 8)
        .stroke(tint.opacity(0.6), lineWidth: 1)
    )
  }

  private func row(indices: [Int], standing: Set<Int>) -> some View {
    HStack(spacing: 3) {
      ForEach(indices, id: \.self) { idx in
        Circle()
          .fill(standing.contains(idx) ? tint : Color.white.opacity(0.18))
          .frame(width: 8, height: 8)
          .overlay(
            Circle().stroke(Color.white.opacity(0.6), lineWidth: standing.contains(idx) ? 0 : 0.5)
          )
      }
    }
  }

  /// Pin-tracking is approximate — we don't know WHICH specific pins
  /// fell, only the count from the game model. Map the count to the
  /// front-of-the-rack pins (so pin 1 falls first, then 2/3, etc.).
  /// Visually this matches the "diamond" tracker convention even if it
  /// isn't physics-accurate per pin.
  private func standingPinIndices() -> Set<Int> {
    let standing = max(0, min(10, game.pinsRemaining))
    return Set((10 - standing)..<10)
  }
}

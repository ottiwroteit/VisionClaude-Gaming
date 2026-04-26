import Foundation
import simd

enum GestureKind: String {
  case flick
  case swing
  case hold
}

enum GestureDirection: String {
  case up, down, left, right
  case rollLeft, rollRight
  case forward, backward
  case none
}

struct GestureEvent {
  let kind: GestureKind
  let direction: GestureDirection
  let magnitude: Float
  let peakVelocity: Float
  let duration: TimeInterval
  let vector: SIMD2<Float>
  let timestamp: Date
  /// How much the gesture path curved laterally over its duration.
  /// Range roughly -1..+1; positive = path bent to the right during the
  /// flick, negative = bent to the left. Computed by comparing the
  /// dominant lateral component of the second half of the gesture
  /// against the first half. Bowling consumes this as the ball "hook".
  let lateralCurvature: Float

  static let zero = GestureEvent(
    kind: .hold,
    direction: .none,
    magnitude: 0,
    peakVelocity: 0,
    duration: 0,
    vector: .zero,
    timestamp: Date(),
    lateralCurvature: 0
  )
}

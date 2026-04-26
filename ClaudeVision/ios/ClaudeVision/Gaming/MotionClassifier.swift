import Foundation
import simd

/// Converts a rolling buffer of inter-frame flow vectors into GestureEvents.
/// The classifier is intentionally single-channel (translation): direction picks the
/// shot, magnitude picks the power, duration picks flick-vs-swing-vs-hold. Games
/// map this small vocabulary to their own action set.
final class MotionClassifier {

  struct Sample {
    let vector: SIMD2<Float>  // frame-to-frame translation in normalized image units
    let timestamp: Date
  }

  struct Thresholds {
    /// Below this per-frame magnitude the wearer is considered still.
    var stillThreshold: Float = 0.004
    /// Above this the motion qualifies as an intentional gesture.
    var activeThreshold: Float = 0.012
    /// Flicks finish in under this many seconds; longer = swing.
    var flickMaxDuration: TimeInterval = 0.28
    /// Hold must be still for at least this long to emit a hold event.
    var minHoldDuration: TimeInterval = 0.4
    /// Ignore motion axes smaller than this fraction of the dominant axis.
    var axisDominance: Float = 1.6
    /// Hard ceiling on a single gesture's active duration. Once a
    /// gesture has been open this long, the classifier force-closes it
    /// on the next sample regardless of whether motion has dropped
    /// below `activeThreshold`. Prevents post-flick head-settling
    /// micromotion from holding the gesture open and delaying the
    /// emitted event by 1–2 seconds. Games with low active thresholds
    /// (bowling) should override this to a tighter value.
    var maxGestureDuration: TimeInterval = 1.5
  }

  private(set) var thresholds = Thresholds()
  private var samples: [Sample] = []
  private var activeStart: Date?
  private var peakVelocity: Float = 0
  private var accumulated: SIMD2<Float> = .zero
  private var lastHoldEmit: Date = .distantPast
  /// Per-sample vectors captured WHILE a gesture is in progress. Cleared
  /// when the gesture starts and consumed when it closes to compute the
  /// lateralCurvature field on the emitted event. Bounded so long swings
  /// don't grow without limit.
  private var gestureSamples: [SIMD2<Float>] = []

  func configure(_ thresholds: Thresholds) {
    self.thresholds = thresholds
  }

  /// Feed one flow sample. Returns an event when a gesture completes.
  func ingest(_ sample: Sample) -> GestureEvent? {
    samples.append(sample)
    if samples.count > 60 { samples.removeFirst(samples.count - 60) }

    let speed = simd_length(sample.vector)

    if speed >= thresholds.activeThreshold {
      if activeStart == nil {
        activeStart = sample.timestamp
        accumulated = .zero
        peakVelocity = 0
        gestureSamples.removeAll(keepingCapacity: true)
      }
      accumulated += sample.vector
      peakVelocity = max(peakVelocity, speed)
      if gestureSamples.count < 240 {
        gestureSamples.append(sample.vector)
      }
      // Force-close once the gesture has been open longer than its
      // ceiling — the user's intentional motion is captured in
      // `accumulated` / `peakVelocity` already, so we can emit now
      // even though motion hasn't yet dipped below the active floor.
      if let start = activeStart,
        sample.timestamp.timeIntervalSince(start) >= thresholds.maxGestureDuration,
        simd_length(accumulated) >= thresholds.activeThreshold
      {
        let duration = sample.timestamp.timeIntervalSince(start)
        activeStart = nil
        let event = makeEvent(duration: duration, at: sample.timestamp)
        gestureSamples.removeAll(keepingCapacity: true)
        return event
      }
      return nil
    }

    // Motion has dipped below active. If we were in a gesture, close it out.
    if let start = activeStart {
      let duration = sample.timestamp.timeIntervalSince(start)
      activeStart = nil
      guard simd_length(accumulated) >= thresholds.activeThreshold else {
        gestureSamples.removeAll(keepingCapacity: true)
        return nil
      }
      let event = makeEvent(duration: duration, at: sample.timestamp)
      gestureSamples.removeAll(keepingCapacity: true)
      return event
    }

    // Not in a gesture — emit a hold pulse periodically when truly still.
    if speed < thresholds.stillThreshold {
      let elapsed = sample.timestamp.timeIntervalSince(lastHoldEmit)
      if elapsed >= thresholds.minHoldDuration {
        lastHoldEmit = sample.timestamp
        return GestureEvent(
          kind: .hold,
          direction: .none,
          magnitude: 0,
          peakVelocity: 0,
          duration: elapsed,
          vector: .zero,
          timestamp: sample.timestamp,
          lateralCurvature: 0
        )
      }
    }
    return nil
  }

  private func makeEvent(duration: TimeInterval, at time: Date) -> GestureEvent {
    // Scene motion is the inverse of head motion: a chin-up flick makes the
    // world pan down, so invert the vector before classifying direction.
    let headMotion = -accumulated
    let direction = classifyDirection(headMotion)
    let kind: GestureKind = duration <= thresholds.flickMaxDuration ? .flick : .swing
    let magnitude = min(1.0, simd_length(headMotion) * 20.0)
    let curvature = computeLateralCurvature()
    return GestureEvent(
      kind: kind,
      direction: direction,
      magnitude: magnitude,
      peakVelocity: peakVelocity,
      duration: duration,
      vector: headMotion,
      timestamp: time,
      lateralCurvature: curvature
    )
  }

  /// Curvature = how much the lateral component of head motion shifted
  /// between the first and second halves of the gesture. Used by bowling
  /// for the ball "hook": a perfectly straight chin-flick hooks 0; a
  /// chin-flick that drifts right halfway through hooks right.
  private func computeLateralCurvature() -> Float {
    guard gestureSamples.count >= 4 else { return 0 }
    let mid = gestureSamples.count / 2
    let first = gestureSamples[..<mid]
    let second = gestureSamples[mid...]
    let firstSum = first.reduce(SIMD2<Float>.zero, +)
    let secondSum = second.reduce(SIMD2<Float>.zero, +)
    let firstMag = simd_length(firstSum)
    let secondMag = simd_length(secondSum)
    guard firstMag > 1e-5, secondMag > 1e-5 else { return 0 }
    // Normalized lateral fraction per half. Negate to flip into
    // head-motion space (matches the rest of the public API).
    let firstLat = -firstSum.x / firstMag
    let secondLat = -secondSum.x / secondMag
    let raw = secondLat - firstLat
    return max(-1, min(1, raw))
  }

  private func classifyDirection(_ v: SIMD2<Float>) -> GestureDirection {
    let ax = abs(v.x)
    let ay = abs(v.y)
    if ax > ay * thresholds.axisDominance {
      return v.x >= 0 ? .right : .left
    }
    if ay > ax * thresholds.axisDominance {
      return v.y >= 0 ? .up : .down
    }
    // Diagonal — pick the larger axis.
    if ax >= ay { return v.x >= 0 ? .right : .left }
    return v.y >= 0 ? .up : .down
  }

  func reset() {
    samples.removeAll()
    activeStart = nil
    peakVelocity = 0
    accumulated = .zero
    gestureSamples.removeAll(keepingCapacity: true)
  }
}

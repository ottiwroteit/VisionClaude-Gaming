import Foundation
import simd

/// Converts a rolling buffer of inter-frame flow vectors into GestureEvents.
/// The classifier is intentionally single-channel (translation): direction picks the
/// shot, magnitude picks the power, duration picks flick-vs-swing-vs-hold. Games
/// map this small vocabulary to their own action set.
final class MotionClassifier {

    struct Sample {
        let vector: SIMD2<Float>   // frame-to-frame translation in normalized image units
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
    }

    private(set) var thresholds = Thresholds()
    private var samples: [Sample] = []
    private var activeStart: Date?
    private var peakVelocity: Float = 0
    private var accumulated: SIMD2<Float> = .zero
    private var lastHoldEmit: Date = .distantPast

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
            }
            accumulated += sample.vector
            peakVelocity = max(peakVelocity, speed)
            return nil
        }

        // Motion has dipped below active. If we were in a gesture, close it out.
        if let start = activeStart {
            let duration = sample.timestamp.timeIntervalSince(start)
            activeStart = nil
            guard simd_length(accumulated) >= thresholds.activeThreshold else { return nil }
            return makeEvent(duration: duration, at: sample.timestamp)
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
                    timestamp: sample.timestamp
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
        return GestureEvent(
            kind: kind,
            direction: direction,
            magnitude: magnitude,
            peakVelocity: peakVelocity,
            duration: duration,
            vector: headMotion,
            timestamp: time
        )
    }

    private func classifyDirection(_ v: SIMD2<Float>) -> GestureDirection {
        let ax = abs(v.x), ay = abs(v.y)
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
    }
}

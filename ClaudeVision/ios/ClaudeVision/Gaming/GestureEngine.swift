import Combine
import Foundation
import UIKit
import Vision
import simd

/// Runs optical-flow-based gesture detection on a stream of frames from the
/// Ray-Ban glasses (or any FrameSource). Emits GestureEvents on `events`.
///
/// Pipeline per frame:
///   previous CGImage + current CGImage
///     → VNTranslationalImageRegistrationRequest
///     → normalized translation vector
///     → MotionClassifier
///     → GestureEvent
///
/// This engine is game-agnostic: every game subscribes to the same event stream
/// and maps the small gesture vocabulary (flick/swing/hold × 4 cardinal
/// directions) to its own action set.
@MainActor
final class GestureEngine: ObservableObject {

  let events = PassthroughSubject<GestureEvent, Never>()

  @Published private(set) var isRunning: Bool = false
  @Published private(set) var lastEvent: GestureEvent = .zero
  @Published private(set) var liveMagnitude: Float = 0

  private let classifier = MotionClassifier()
  private var previousCGImage: CGImage?
  private var previousTimestamp: Date?
  private let flowQueue = DispatchQueue(label: "gesture.flow", qos: .userInitiated)

  func start() {
    isRunning = true
    classifier.reset()
    previousCGImage = nil
    previousTimestamp = nil
  }

  func stop() {
    isRunning = false
    classifier.reset()
    previousCGImage = nil
    previousTimestamp = nil
    liveMagnitude = 0
  }

  func configure(_ thresholds: MotionClassifier.Thresholds) {
    classifier.configure(thresholds)
  }

  /// Feed a raw frame. Downscaling happens inside.
  func ingest(image: UIImage, at timestamp: Date = Date()) {
    guard isRunning, let cg = image.cgImage else { return }
    let current = downscale(cg, maxSide: 240)
    let previous = previousCGImage
    previousCGImage = current
    let prevTime = previousTimestamp
    previousTimestamp = timestamp
    guard let previous, let prevTime else { return }

    let dt = max(1.0 / 60.0, timestamp.timeIntervalSince(prevTime))

    flowQueue.async { [weak self] in
      guard let self else { return }
      let vector = Self.computeFlow(from: previous, to: current)
      let perSecond = vector / Float(dt)

      Task { @MainActor [weak self] in
        guard let self else { return }
        self.liveMagnitude = simd_length(perSecond)
        let sample = MotionClassifier.Sample(vector: perSecond, timestamp: timestamp)
        if let event = self.classifier.ingest(sample) {
          self.lastEvent = event
          self.events.send(event)
        }
      }
    }
  }

  // MARK: - Optical Flow

  nonisolated private static func computeFlow(from previous: CGImage, to current: CGImage) -> SIMD2<
    Float
  > {
    let request = VNTranslationalImageRegistrationRequest(targetedCGImage: current)
    let handler = VNImageRequestHandler(cgImage: previous, options: [:])
    do {
      try handler.perform([request])
    } catch {
      return .zero
    }
    guard let observation = request.results?.first as? VNImageTranslationAlignmentObservation else {
      return .zero
    }
    let tx = Float(observation.alignmentTransform.tx) / Float(current.width)
    let ty = Float(observation.alignmentTransform.ty) / Float(current.height)
    return SIMD2<Float>(tx, ty)
  }

  private func downscale(_ image: CGImage, maxSide: Int) -> CGImage {
    let w = image.width
    let h = image.height
    let longest = max(w, h)
    guard longest > maxSide else { return image }
    let scale = CGFloat(maxSide) / CGFloat(longest)
    let newW = Int(CGFloat(w) * scale)
    let newH = Int(CGFloat(h) * scale)
    guard let colorspace = image.colorSpace,
      let ctx = CGContext(
        data: nil,
        width: newW,
        height: newH,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorspace,
        bitmapInfo: image.bitmapInfo.rawValue
      )
    else { return image }
    ctx.interpolationQuality = .low
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: newW, height: newH))
    return ctx.makeImage() ?? image
  }
}

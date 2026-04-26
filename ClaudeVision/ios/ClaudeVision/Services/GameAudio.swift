import AVFoundation
import Foundation

/// Single voice for in-game audio. Holds a speech synthesizer for score
/// callouts plus an AVAudioEngine pipeline that plays three programmatically
/// synthesized bowling SFX (thump, rolling rumble, pin crash). No audio
/// assets bundled — every sound is generated into a PCM buffer at startup.
@MainActor
final class GameAudio {
  static let shared = GameAudio()

  private let synthesizer = AVSpeechSynthesizer()
  private let engine = AVAudioEngine()
  private let thumpPlayer = AVAudioPlayerNode()
  private let rollingPlayer = AVAudioPlayerNode()
  private let crashPlayer = AVAudioPlayerNode()
  private var thumpBuffer: AVAudioPCMBuffer?
  private var rollingBuffer: AVAudioPCMBuffer?
  private var crashBuffer: AVAudioPCMBuffer?

  private init() {
    configureAudioSession()
    setupEngine()
  }

  // MARK: - Speech

  /// Speak a short phrase. Cancels anything currently being spoken so
  /// rapid scoring callouts don't queue up behind a finishing utterance.
  func speak(_ text: String, rate: Float = 0.55, pitch: Float = 1.05) {
    if synthesizer.isSpeaking {
      synthesizer.stopSpeaking(at: .immediate)
    }
    let utterance = AVSpeechUtterance(string: text)
    utterance.rate = rate
    utterance.pitchMultiplier = pitch
    utterance.volume = 1.0
    synthesizer.speak(utterance)
  }

  func stop() {
    synthesizer.stopSpeaking(at: .immediate)
    thumpPlayer.stop()
    rollingPlayer.stop()
    crashPlayer.stop()
  }

  // MARK: - Bowling sequence

  /// Plays the audio arc for a roll. Synthesized SFX are temporarily
  /// disabled — they crashed AVAudioEngine with "player did not see an
  /// IO cycle" and sounded bad anyway. Speech-only until real audio
  /// samples are bundled in the next pass.
  func playBowlSequence(scoreCallout: String) {
    scheduleAfter(0.4) { [weak self] in self?.speak(scoreCallout) }
  }

  // Synth playback paths kept around for the next iteration when real
  // file-backed playback replaces them. Currently unreachable.
  @MainActor private func playThump() {
    guard let buf = thumpBuffer, engine.isRunning else { return }
    thumpPlayer.stop()
    thumpPlayer.scheduleBuffer(buf, at: nil, options: .interrupts, completionHandler: nil)
    if !thumpPlayer.isPlaying { thumpPlayer.play() }
  }

  @MainActor private func playRolling() {
    guard let buf = rollingBuffer, engine.isRunning else { return }
    rollingPlayer.stop()
    rollingPlayer.scheduleBuffer(buf, at: nil, options: .interrupts, completionHandler: nil)
    if !rollingPlayer.isPlaying { rollingPlayer.play() }
  }

  @MainActor private func playCrash() {
    guard let buf = crashBuffer, engine.isRunning else { return }
    crashPlayer.stop()
    crashPlayer.scheduleBuffer(buf, at: nil, options: .interrupts, completionHandler: nil)
    if !crashPlayer.isPlaying { crashPlayer.play() }
  }

  private func scheduleAfter(_ seconds: TimeInterval, _ work: @escaping @MainActor () -> Void) {
    Task { @MainActor in
      try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
      work()
    }
  }

  // MARK: - Engine setup

  private func setupEngine() {
    guard let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1) else {
      print("[GameAudio] Could not build audio format")
      return
    }

    engine.attach(thumpPlayer)
    engine.attach(rollingPlayer)
    engine.attach(crashPlayer)
    engine.connect(thumpPlayer, to: engine.mainMixerNode, format: format)
    engine.connect(rollingPlayer, to: engine.mainMixerNode, format: format)
    engine.connect(crashPlayer, to: engine.mainMixerNode, format: format)

    thumpBuffer = makeThump(format: format)
    rollingBuffer = makeRolling(format: format)
    crashBuffer = makeCrash(format: format)

    do {
      try engine.start()
    } catch {
      print("[GameAudio] Engine start failed: \(error)")
    }
  }

  // MARK: - SFX synthesis

  /// Ball lands on lane. 60 Hz sine with fast exponential decay — short
  /// percussive low thump, ~150ms.
  private func makeThump(format: AVAudioFormat) -> AVAudioPCMBuffer? {
    let duration: TimeInterval = 0.15
    return makeBuffer(format: format, duration: duration) { t in
      let env = expf(-t * 22)
      let body = sinf(2 * .pi * 60 * t)
      let click = sinf(2 * .pi * 200 * t) * expf(-t * 60) * 0.4
      return (body + click) * env * 0.75
    }
  }

  /// Ball rolling. Integrated noise (brown-noise-ish) with a slow
  /// tremolo so it feels like motion, ~1.5s with fade in/out.
  private func makeRolling(format: AVAudioFormat) -> AVAudioPCMBuffer? {
    let duration: TimeInterval = 1.5
    var brown: Float = 0
    return makeBuffer(format: format, duration: duration) { t in
      let white = Float.random(in: -1...1)
      brown = (brown + 0.02 * white) * 0.997
      let tremolo = 1.0 + 0.25 * sinf(2 * .pi * 7 * t)
      let env: Float
      if t < 0.12 {
        env = t / 0.12
      } else if t > Float(duration) - 0.25 {
        env = (Float(duration) - t) / 0.25
      } else {
        env = 1.0
      }
      return brown * tremolo * env * 5.0
    }
  }

  /// Pin crash. Wide-band noise burst plus three high "clack" sine
  /// transients (400/800/1600 Hz) that decay fast, ~500ms.
  private func makeCrash(format: AVAudioFormat) -> AVAudioPCMBuffer? {
    let duration: TimeInterval = 0.5
    return makeBuffer(format: format, duration: duration) { t in
      let env = expf(-t * 5.5)
      let noise = Float.random(in: -1...1)
      let clack1 = sinf(2 * .pi * 400 * t) * expf(-t * 28)
      let clack2 = sinf(2 * .pi * 800 * t) * expf(-t * 22)
      let clack3 = sinf(2 * .pi * 1600 * t) * expf(-t * 18)
      let mixed = noise * 0.55 + (clack1 + clack2 * 0.6 + clack3 * 0.35) * 0.4
      return mixed * env * 0.85
    }
  }

  /// Helper that walks t from 0..duration and asks the closure for one
  /// sample. Keeps the synthesis functions short and focused on shape.
  private func makeBuffer(
    format: AVAudioFormat,
    duration: TimeInterval,
    _ sample: (Float) -> Float
  ) -> AVAudioPCMBuffer? {
    let frameCount = AVAudioFrameCount(format.sampleRate * duration)
    guard let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
      return nil
    }
    buf.frameLength = frameCount
    guard let samples = buf.floatChannelData?[0] else { return nil }
    let sr = Float(format.sampleRate)
    for i in 0..<Int(frameCount) {
      let t = Float(i) / sr
      samples[i] = max(-1.0, min(1.0, sample(t)))
    }
    return buf
  }

  // MARK: - Audio session

  /// Use .ambient so we don't kill the user's music, but duck whatever
  /// else is playing while a callout speaks.
  private func configureAudioSession() {
    do {
      try AVAudioSession.sharedInstance().setCategory(
        .ambient,
        mode: .default,
        options: [.mixWithOthers, .duckOthers]
      )
      try AVAudioSession.sharedInstance().setActive(true)
    } catch {
      print("[GameAudio] Failed to configure audio session: \(error)")
    }
  }
}

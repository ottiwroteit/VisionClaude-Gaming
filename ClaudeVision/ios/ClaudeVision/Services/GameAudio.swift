import AVFoundation
import Foundation

/// Single voice for in-game audio. Phase 1 ships score-callout speech only
/// (`speak(_:)`); phase 2 will add programmatic SFX (rolling rumble, pin
/// crash) on top of the same instance.
@MainActor
final class GameAudio {
  static let shared = GameAudio()

  private let synthesizer = AVSpeechSynthesizer()

  private init() {
    configureAudioSession()
  }

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
  }

  /// Use the .ambient category so we don't kill the user's music, but
  /// duck whatever else is playing while we're talking.
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

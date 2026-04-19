# Architecture

VisionClaude Gaming is a single-screen iOS app that turns the Meta Ray-Ban camera feed into a motion controller for a catalog of mini-games. This doc explains the pipeline end-to-end.

## Layers

```
┌──────────────────────────────────────────────────────────────┐
│  Meta Ray-Ban Smart Glasses                                   │
│  • 30fps camera stream via Meta DAT SDK                       │
│  • No IMU/motion API available to third-party apps            │
└──────────────────────────────────────────────────────────────┘
                        │  BLE + Bonjour (handled by DAT SDK)
                        ▼
┌──────────────────────────────────────────────────────────────┐
│  RayBanManager (Swift, @MainActor)                            │
│  • Handles Meta AI registration + permission handoff          │
│  • Subscribes to DAT SDK videoFramePublisher                  │
│  • Publishes latestImage: UIImage @30fps                      │
└──────────────────────────────────────────────────────────────┘
                        │  @Published UIImage?
                        ▼
┌──────────────────────────────────────────────────────────────┐
│  GestureEngine                                                │
│  • Keeps the previous frame                                   │
│  • Per pair, runs VNTranslationalImageRegistrationRequest     │
│  • Emits SIMD2<Float> flow vectors (translation per second)   │
└──────────────────────────────────────────────────────────────┘
                        │  MotionClassifier.Sample
                        ▼
┌──────────────────────────────────────────────────────────────┐
│  MotionClassifier                                             │
│  • State machine: idle → active → resolved                    │
│  • Accumulates vectors while magnitude > activeThreshold      │
│  • On dip below threshold, closes out into a GestureEvent:    │
│      - kind: flick | swing | hold                             │
│      - direction: up/down/left/right (head-motion frame)      │
│      - magnitude: normalized 0..1                             │
│      - duration, peakVelocity                                 │
└──────────────────────────────────────────────────────────────┘
                        │  GestureEvent
                        ▼
┌──────────────────────────────────────────────────────────────┐
│  GameCoordinator                                              │
│  • Owns GestureEngine                                         │
│  • Registers all Games by id                                  │
│  • Activates one game at a time; routes events to it          │
│  • Forwards the active game's objectWillChange                │
└──────────────────────────────────────────────────────────────┘
                        │  ObservableObject updates
                        ▼
┌──────────────────────────────────────────────────────────────┐
│  SwiftUI Views                                                │
│  • ContentView  — three-state router                          │
│  • GlassesSetupView — pairing + "Start feed"                  │
│  • HomeView — game picker + motion meter                      │
│  • GameSessionView — shared chrome + per-game hero art        │
└──────────────────────────────────────────────────────────────┘
```

## Why optical flow?

Meta Ray-Bans expose video and audio to third-party apps via the DAT SDK, but not the IMU. A "chin flick up" can't be read as a rotation — but when the wearer flicks their chin up, the scene pans *down* in the video feed, and that pan is trivial to detect.

`VNTranslationalImageRegistrationRequest` from Apple's Vision framework is a perfect match: it's a single-call API that estimates the translation between two images. On a downscaled 240px frame it runs in well under 10ms on modern iPhones, so the pipeline keeps up with the 30fps stream easily.

We invert the resulting flow vector to get the wearer's head motion (camera moves, world moves opposite), and feed that into the classifier.

## The gesture vocabulary

The classifier intentionally exposes a tiny vocabulary. Three kinds × four directions × a magnitude scalar = enough primitives to cover every sport-style game in the catalog.

```swift
enum GestureKind { case flick, swing, hold }
enum GestureDirection { case up, down, left, right, rollLeft, rollRight, forward, backward, none }

struct GestureEvent {
    let kind: GestureKind
    let direction: GestureDirection
    let magnitude: Float
    let peakVelocity: Float
    let duration: TimeInterval
    let vector: SIMD2<Float>
    let timestamp: Date
}
```

`rollLeft`/`rollRight` are reserved for a future upgrade using `VNHomographicImageRegistrationRequest` to pull rotation out of the flow — not wired in the MVP but the games already have slots for it.

## The `Game` protocol

```swift
@MainActor
protocol Game: AnyObject, ObservableObject {
    var id: String { get }
    var title: String { get }
    var howToPlay: String { get }
    var statusLine: String { get }
    var score: Int { get }
    var isFinished: Bool { get }

    func start()
    func reset()
    func handle(_ event: GestureEvent)
}
```

Every game is a state machine that:
1. Observes gesture events
2. Mutates `@Published` properties
3. Lets SwiftUI re-render automatically via `objectWillChange`

Adding a game is ~80–120 lines:
- Declare state properties with `@Published`
- Implement `handle(_:)` — a switch over direction + kind
- Drop a hero-art view into `GameSessionView`'s dispatcher

## Threading model

- **Frame ingestion**: on the main actor (DAT SDK publisher hops to main).
- **Optical flow**: dispatched to a background queue (`gesture.flow`) so the 30fps stream never blocks the UI.
- **Gesture classification + game state**: back on the main actor for SwiftUI.

## Tuning knobs

`MotionClassifier.Thresholds` exposes the full calibration surface:

```swift
stillThreshold:   0.004  // below this, user is still
activeThreshold:  0.012  // above this, a gesture has started
flickMaxDuration: 0.28   // longer = swing, shorter = flick
minHoldDuration:  0.4    // how long to stay still before emitting a hold
axisDominance:    1.6    // how much one axis must beat the other
```

These can be tweaked per-game by calling `coordinator.engine.configure(...)` before activation.

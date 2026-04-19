# VisionClaude Gaming

Motion-controlled games on your phone, driven entirely by the camera feed from your **Meta Ray-Ban smart glasses**. Flick your chin up to bowl. Turn your head to swing a tennis racket. Duck to dodge a jab.

The glasses are the controller. The phone is the game.

## The idea

Meta Ray-Bans don't expose an IMU or motion API to third-party apps — but they *do* expose a live camera feed. VisionClaude Gaming runs optical flow on that feed in real time: when your head moves, the scene pans, and the app converts that motion into a small gesture vocabulary that every game shares.

| Gesture | How it looks to the optical-flow engine |
| --- | --- |
| **Flick** | Short, sharp motion under ~280ms — "chin flick up", "head snap left" |
| **Swing** | Longer sustained motion in one direction — "forehand turn", "hook" |
| **Hold** | Steady, low-motion window — used for aiming and charging |

Each gesture carries a **direction** (up/down/left/right), a **magnitude** (0–1, maps to power), and a **duration**. Games map that vocabulary to their own action set.

## Games

Six built-in games, all sharing one engine:

- **Meta Bowling** — flick your chin up to roll; harder flick = more power
- **Meta Tennis** — turn right/left for forehand/backhand, chin-up to serve
- **Meta Ping Pong** — twitch-reflex flicks; timing matters more than power
- **Meta Boxing** — bob and slip to dodge telegraphed punches, chin-down to jab, side-swing to hook
- **Meta Archery** — hold still to draw, chin-flick up to release; draw duration = power
- **Meta Fruit Slash** — flick your head toward each incoming fruit; don't slice the bombs

Adding a seventh game is ~80 lines of Swift — conform to the `Game` protocol, map gestures to actions, and publish state.

## Architecture

```
Meta Ray-Ban glasses
        │  30fps camera stream (DAT SDK)
        ▼
    RayBanManager (iOS)
        │  UIImage frames
        ▼
    GestureEngine ──► VNTranslationalImageRegistrationRequest
        │  SIMD2<Float> flow vectors
        ▼
    MotionClassifier
        │  GestureEvent { kind, direction, magnitude, duration }
        ▼
    GameCoordinator ──► active Game ──► @Published state
                                          │
                                          ▼
                              HomeView / GameSessionView (SwiftUI)
```

See [ARCHITECTURE.md](./ARCHITECTURE.md) for the deeper dive.

## Running it

Requirements:
- Xcode 26 / iOS 17+
- Meta Ray-Ban Smart Glasses paired with the Meta AI app
- A Mac with [xcodegen](https://github.com/yonaskolb/XcodeGen) installed

```sh
cd ClaudeVision/ios
xcodegen                       # regenerate the Xcode project from project.yml
open ClaudeVision.xcodeproj    # build + run on a physical device
```

On first launch:
1. The app opens to the **Connect glasses** screen
2. Tap **Connect glasses** — you'll be handed off to the Meta AI app to approve the camera permission
3. Back in VisionClaude Gaming, tap **Start feed** and then pick a game

## First to market

No third-party app has shipped real-time motion gaming on Meta Ray-Bans yet, because most teams assume they need the IMU. Optical flow on the video stream is the wedge — it works today, on shipping hardware, with no Meta partnership required.

## Project layout

```
ClaudeVision/ios/
├── project.yml                        # xcodegen spec
└── ClaudeVision/
    ├── ClaudeVisionApp.swift          # @main + DAT SDK bootstrap
    ├── Info.plist                     # glasses/BLE permissions only
    ├── Services/
    │   ├── RayBanManager.swift        # DAT SDK wrapper
    │   └── FrameSource.swift          # abstract frame-source protocol
    ├── Gaming/
    │   ├── GestureEvent.swift         # gesture vocabulary
    │   ├── MotionClassifier.swift     # flow vectors → GestureEvents
    │   ├── GestureEngine.swift        # Vision-framework optical flow
    │   ├── Game.swift                 # game protocol
    │   ├── GameCoordinator.swift      # wiring glue
    │   └── Games/                     # six concrete games
    └── Views/
        ├── Theme.swift                # design tokens
        ├── ContentView.swift          # root router
        ├── GlassesSetupView.swift     # pairing onboarding
        ├── HomeView.swift             # game picker + motion meter
        └── GameSessionView.swift      # gameplay + per-game art
```

## License

MIT — see [LICENSE](./LICENSE).

# Handoff — VisionClaude Gaming · Bowling deep-dive session

**Last session ended:** 2026-04-26.
**Branch:** `claude/meta-glasses-bowling-game-DcTR3` — never push to `main`.
**Working tree:** `/Users/otti/Documents/GitHub/VisionClaude-Gaming` on the user's Mac.

---

## TL;DR · Read this first

The user is bowling-only right now. The bowling game has gone through ~25 commits this session (full-bleed lane, 3D tilt, scoreboard, pinspotter, themed venues, real-bowling scoring, aim-then-release with continuous head motion, 10-second aim window, ball picker, turkey-fire bonus, etc.). **The user does not see any of these updates because the build on their phone is stale.** Every session opens with this exact problem: source on disk is correct, Xcode is running a cached binary.

**First action when a new session starts:**

1. Take an Xcode screenshot. If the build status says "Build Failed" or is older than the most recent commit, the user is on a stale build.
2. Tell the user: **Cmd + Shift + K (Clean Build Folder), then Cmd + R**. Do not proceed with feature work until they confirm a fresh build is running.
3. The `xcodebuild` CLI is the source of truth for "does this compile" — run it before assuming an Xcode build status is accurate:
   ```
   xcodebuild -project ClaudeVision.xcodeproj -scheme ClaudeVision -destination 'generic/platform=iOS' -quiet build
   ```
   (run from `ClaudeVision/ios/`)

---

## What the user is asking for

Reference apps (sent as YouTube Shorts in the session — I could not watch the videos, only extract titles):

- **Bowling Crew** — glossy 3D mobile bowling, themed venues (skyline / Mars / etc), big animated STRIKE pop-ups, ball with light trail.
- **Skyline Bowling** — full-bleed lane, camera follows ball, themed living-room and bridge backdrops, depth-perceived red aim laser pointing at pins.
- **Bowling Fury / Hells Balls** — neon explosion vibe, ball goes on fire on streaks, big themed venues (Mars, Hell, Build N Roll construction site).
- **3D Bowling / Bowling Master** — ball selection screen with themed balls (skull, 8-ball, basketball, sport patterns).

The user has been screenshotting these reference images and asking us to match. We **cannot match Unity-grade 3D in SwiftUI** — be honest about this. We can fake a lot with `rotation3DEffect`, gradients, and SF Symbols, but pin physics / camera-on-rails / real lighting are not coming.

---

## User's pet peeves and strong preferences

These are non-negotiable. Re-reading these before responding will save at least one cycle of frustration.

1. **"Just try it. Use computer-use. Stop asking me."** The user has Xcode at click-tier on display "LS32CG51x". They've granted access. They want me to take screenshots, click Run, read the console myself. Caveat: clicking inside the editor pane has at least once typed garbage into a file (likely macOS press-and-hold accent menu triggered by my click landing somewhere unexpected). **Click only the Run button (▶, just right of Stop ⏹) at the very top of the toolbar. Verify with `zoom` first if uncertain about coordinates.**
2. **"One terminal command per code block."** The Bash hook actively blocks chained `git add && commit && push`. Always split.
3. **Real bowling rules.** "Do your research." The current implementation has 10 frames, strike/spare bonus scoring, proper 10th-frame fill-ball logic. Don't simplify.
4. **Strict roll lockout.** "I shouldn't be able to roll again until pins are reset." The state machine enforces this; the model is correct. If the user says it's broken, the running build is stale (see TL;DR).
5. **No phallic pin shape.** The current `BowlingPinShape` uses USBC-spec proportions (small head, narrow neck, wide belly, gentle waist, small base) — do NOT regress to a simpler shape.
6. **Glasses-only motion input.** No phone-IMU fallback. The whole app point is Ray-Ban Meta head tracking.
7. **Smaller chrome, lane is the star.** All UI overlays should be compact and translucent. Lane fills the screen.
8. **Themed venues, not solid colors.** Each venue is its own scene (palms, dunes, pyramids, vines, neon, blood moon). Six built for bowling.

---

## SDK gotchas (MWDAT 0.6) — keep these in memory

The MWDAT iOS SDK (`from: 0.5.0` resolves to 0.6.0 currently) has several non-obvious requirements. **Reading [`memory/mwdat_streaming_order.md`](file:///Users/otti/.claude/projects/-Users-otti-Documents-GitHub-VisionClaude-Gaming/memory/mwdat_streaming_order.md) at session start is mandatory** — it has the canonical streaming order.

Quick reminders:

- `addStream` returns `nil` silently if camera permission isn't granted OR the device session isn't `.started`. Order of operations: permission → createSession → deviceSession.start() → wait for state == `.started` → addStream → install listeners → stream.start(). All of this is implemented in `RayBanManager.beginStreamSession`.
- `createSession` throws `sessionAlreadyExists` when a previous session is held cross-process by the Meta AI bridge after an Xcode kill or crash. Auto-recovery via `forceReset()` (unregister → reregister) is wired in. There's also a manual "Reset connection" button on the Glasses Setup screen.
- The audio engine path is **disabled** in `GameAudio` because programmatic synth crashed AVAudioEngine with "player did not see an IO cycle" AND sounded bad. Speech callouts via AVSpeechSynthesizer still work. The synth code is preserved (gated behind `engine.isRunning`) for the next pass that swaps in real audio samples (planned: archive.org bowling SFX, but never wired up — see Open work below).

---

## Architecture cheat-sheet

```
ClaudeVision/ios/ClaudeVision/
├── ClaudeVisionApp.swift            App entry; configures DAT SDK
├── Info.plist                       MetaAppID, ClientToken, Bluetooth permissions, MWDAT keys
├── Gaming/
│   ├── Game.swift                   Protocol — handle(event), handleMotion(vector)
│   ├── GameCoordinator.swift        Wires engine → active game; forwards events AND liveVector
│   ├── GestureEngine.swift          Optical-flow → MotionClassifier; publishes events + liveVector
│   ├── MotionClassifier.swift       Discrete flick/swing/hold + direction
│   ├── ProgressStore.swift          Persistent per-game cumulative score → unlocks
│   ├── DailyChallenge.swift         Date-stamped challenge generator
│   ├── GestureRecorder.swift        Replay system for dev scenarios
│   ├── TestScenarios.swift          Recorded scripts
│   ├── Games/
│   │   ├── BowlingGame.swift        ⭐ Main focus this session
│   │   ├── TennisGame.swift         Untouched
│   │   ├── PingPongGame.swift       Untouched
│   │   ├── BoxingGame.swift         Untouched
│   │   ├── ArcheryGame.swift        Untouched
│   │   └── FruitSlashGame.swift     Untouched
│   └── Venues/
│       ├── Venue.swift              Data model + library
│       ├── BowlingVenues.swift      ⭐ 6 themed scenes (this session)
│       └── (others)                 Unchanged
├── Services/
│   ├── RayBanManager.swift          ⭐ MWDAT lifecycle + auto-recovery
│   ├── GameAudio.swift              Speech only (synth disabled)
│   ├── AppIconManager.swift         Alt icon switcher
│   └── FrameSource.swift            Protocol
└── Views/
    ├── ContentView.swift            Root router; scenePhase cleanup hook
    ├── GameSessionView.swift        ⭐ Per-game session screen; bowling has full-bleed branch
    ├── HomeView.swift               Dashboard (vertical scroll + horizontal game carousel)
    ├── GlassesSetupView.swift       Connect/Start + Reset Connection button
    ├── VenueSelectView.swift        Venue picker
    ├── DailyChallengeCard.swift
    ├── DebugPanelView.swift
    ├── LaunchSplashView.swift
    ├── ShareCardView.swift
    ├── UnlockCelebration.swift
    ├── AnimeStyle.swift             Halftone, BurstBadge, SpeedLines, etc.
    └── Theme.swift                  Color palette + Radius constants
```

The **bowling-specific code is all in three files**: `BowlingGame.swift` (model + state machine), `BowlingVenues.swift` (six venue scenes), and the bowling section of `GameSessionView.swift` (which contains: `BowlingArt`, `BowlingScoreboard`, `BowlingPinSpotter`, `BowlingCountdown`, `BowlingAimGuide`, `BowlingBallView`, `BowlingBallPicker`, `BowlingCelebration`, plus shape primitives `BowlingLaneShape`, `BowlingLaneStripe`, `BowlingGutterShape`, `BowlingLaneGrain`, `BowlingPinShape`, `Triangle`, `Pentagon`).

---

## What was built this session — chronological commits on `claude/meta-glasses-bowling-game-DcTR3`

| Commit | Subject |
| --- | --- |
| `7b40cc0` | fix: GameCoordinator default-arg main-actor bug (the original Issue #2) |
| `36fa1cc` | fix: route StreamSession through DeviceSession (MWDAT 0.6 API migration) |
| `e82017a` | chore: nonisolated computeFlow to silence Swift 6 warning |
| `0d43266` | fix: defer createSession until AutoDeviceSelector finds a device |
| `c335e1e` | fix: actionable sessionAlreadyExists error |
| `cecbf70` | fix: scenePhase cleanup so app-background releases the SDK session |
| `cf79359` | chore: log start() entry conditions |
| `0760dbd` | fix: addStream order — added before deviceSession.start() (later reverted to start-first) |
| `c59ace5` | fix: poll deviceSession.state == .started before addStream |
| `b68e838` | feat(bowling): gentle chin-flick threshold + spoken score callouts |
| `1fe8223` | feat(bowling): synthesized SFX (later disabled — crashed engine) |
| `014ff1a` | fix: Theme.text → Theme.textPrimary; disable crashing SFX |
| `d0d520d` | feat(bowling): real lane visual (perspective, 10 pins, animated ball) |
| `2462508` | feat(home): scrollable dashboard + horizontal game carousel |
| `4493ff3` | feat(bowling): QubicaAMF pinspotter mechanism |
| `1cead45` | feat(bowling): gutter direction + ball with finger holes + scoreboard apparatus + dismissable coaching |
| `f2e7c8c` | feat(bowling): real-bowling state machine + correct pin shape (USBC proportions) |
| `3578d74` | feat(bowling): arcade 3-2-1 countdown before each turn |
| `5b97923` | feat(bowling): aim-then-release (discrete-tilt step model — later replaced) |
| `80d115e` | feat: auto-recover from sessionAlreadyExists + manual Reset Connection button |
| `2731c8a` | feat(bowling): glossy lane + arcade celebrations (option C — STRIKE pop-up + particles + shake) |
| `428561a` | feat(bowling): six themed venue backgrounds (island, desert, jungle, sunset strip, neon lanes, dragon shrine) |
| `f36016d` | feat(bowling): real-time aim from live head motion + 10s aim window + scoreboard clamp + drop frame counter |
| `bb9fe1e` | feat(bowling): tilt the lane plane in 3D (rotation3DEffect, anchor .bottom, perspective 0.85) |
| `9db574a` | feat(bowling): full-bleed lane + camera follow + ball spin + light trail + red aim beam |
| `3e93633` | feat(bowling): themed ball picker + 3-strike turkey fire bonus |

---

## Bowling state machine (current model)

```
Phase: countingDown → idle → rolling → knocking → resetting → idle (next ball)
                          ↘                                ↘
                           rolling → knocking → finalScoring (game over)
```

- **countingDown** (1.8s): 3-2-1 overlay; aim resets to 0; input ignored.
- **idle**: 10s aim window; live head motion (vector.x) integrated into `aimPosition` ∈ [-1, +1]; only chin UP/DOWN releases. Auto-release at 0s with mid power.
- **rolling** (1.5s): ball animates from player end to pins, curves into gutter if `|aim| > 0.7`, otherwise straight along aim vector.
- **knocking** (0.8s): pinsRemaining decrements; pins fade + rotate (this is what the user calls "disappearing"). Pinspotter rack descends, sweep traverses.
- **resetting** (0.6s): rack lifts back up; for frame-end, fresh 10 pins.

`handleMotion(vector)` only writes aim when `aimTimeRemaining != nil && phase == .idle`. Outside that window, motion is ignored (so head movement during ball travel doesn't leak into next aim).

`consecutiveStrikes` counter drives `isOnFire` (≥3). `activeSkin = isOnFire ? .fire : selectedSkin`. Bonus: +5 per pin while on fire.

---

## What does NOT match the reference apps yet — be honest with the user

1. **Pins fade rather than fall.** Currently a fallen pin is rendered with `.opacity(0.25)`, `.rotationEffect(±55°, anchor: .bottom)`, and `.scaleEffect(y: 0.55, anchor: .bottom)`. With the correct spring animation it reads as a tip-over; without it, it reads as a shrink-fade. The user perceives it as fade. **Fix path:** make the rotation more violent (90° instead of 55°), add a 3D-axis component (axis: (1,1,0) so the pin tips both forward and sideways), and consider a brief `offset` spring to simulate the pin sliding off the deck. Or use TimelineView for keyframed multi-stage animation.
2. **Camera doesn't actually travel; it zooms.** `scaleEffect(1 + (1 - ballRollProgress) * 0.18, anchor: .top)` is a fake. Real camera-follow needs translating the lane upward AND scaling AND maybe rotating the perspective tilt. Closest fake: also animate `rotation3DEffect`'s degrees (more tilt at start, less at end, so the lane "lifts up" as we approach the pins). **The user explicitly called this out as missing.**
3. **No sprite-based ball trail.** Just a stroked line. Reference apps use particle sprites with motion blur. We can fake more with multiple offset blurred copies but it's diminishing returns.
4. **Pin shadows are static.** They don't shift with light direction or animate when pins fall.
5. **Audio is speech-only.** No real bowling SFX. The user repeatedly said "the SFX sound like crap." Plan was to fetch CC0 samples from `archive.org/details/78_2-bowling-and-making-a-strike_gbia0187400` (URLs collected, never bundled). Pixabay/Mixkit are blocked behind Cloudflare/JS and don't yield direct URLs to WebFetch.
6. **No real 3D pins.** SwiftUI primitives only. Real pin geometry would require SceneKit / RealityKit / Metal.

If the user keeps asking for "more 3D", the real answer is to integrate a Metal/SceneKit view for the lane. That's a 1-day refactor minimum and adds a hard dependency on 3D content. **Discuss this trade-off with the user before going down that path.**

---

## Open / unfinished work in priority order

1. **The user's running app may not match the source.** First action: make sure they're on a clean rebuild before touching anything else.
2. **Pins falling, not fading.** Highest-impact visual fix; isolated to `pin(displayIndex:)` in `GameSessionView.swift`. Aim for a 2-3 stage keyframed animation: snap rotation forward 30° → settle to 75° tipped + slight slide off deck.
3. **Real ball-following camera.** Animate `rotation3DEffect` degrees and add a `.offset(y:)` proportional to `ballRollProgress` so the lane "scrolls" toward the player.
4. **Real bowling SFX bundle.** Use the archive.org URLs (already collected, see CHANGELOG section in `memory/mwdat_streaming_order.md` — no, they're in this session's chat, repeat below):
   - `https://archive.org/download/78_2-bowling-and-making-a-strike_gbia0187400/02%20-%202.%20Bowling%20and%20Making%20A%20Strike.mp3` (one we already curl'd to `/tmp/bowling-sfx/strike1.mp3`, ~700KB)
   - Tracks 1-6 are alternates / ambient mixes
   Bundle into `Resources/Audio/`, update `project.yml` to include resources, swap `GameAudio.playBowlSequence` to play AVAudioPlayer files. Re-run `xcodegen` after.
5. **Smaller chrome.** User said "let the bowling game be the star." Current chrome already uses `.ultraThinMaterial`; the scoreboard could be 60% of its current height. Coaching panel auto-collapse to a single line when not the player's first turn. Motion bar can be removed entirely or hidden behind a long-press.
6. **Tennis / Boxing / etc.** Untouched all session. They still work but their visuals are sparse. Future work.
7. **Score display includes turkey bonus inconsistency.** `score = computeScore() + turkeyBonus` — the turkey bonus is added on top of the canonical bowling score, which means the scoreboard's per-frame cumulative totals don't include the bonus, but the displayed total does. Probably not what the user wants long-term. Either bake bonus into the frame display or surface it as a separate "Bonus: +N" badge.

---

## Memory files (read these in a fresh session)

`/Users/otti/.claude/projects/-Users-otti-Documents-GitHub-VisionClaude-Gaming/memory/`

- **MEMORY.md** — index
- **workflow_rules.md** — one bash command per block; never push to main; bowling branch only
- **computer_use_granted.md** — Xcode at click tier on LS32CG51x display
- **mwdat_streaming_order.md** — canonical SDK streaming order (read first when touching RayBanManager)
- **bowling_threshold.md** — `activeThreshold = 0.005` validated by user as "much better"
- **project_state.md** — connection works; tuning + UX phase

---

## Reference images URL list

The user sent these YouTube Shorts as visual references this session:

- `https://www.youtube.com/shorts/OsOLWc2Kj3I` — Bowling Fury (arcade explosion vibe)
- `https://www.youtube.com/shorts/Sy5ujtFgz0Y` — Skyline Bowling (glossy, full-bleed, depth-aware aim laser)
- `https://www.youtube.com/shorts/6DCkljTow3A` — Bowling Crew Golden Sands

Plus screenshots:
- "Hells Balls" — Mars/skull theme, full-bleed lane, themed venue surrounds
- "Build N Roll" construction-site lane
- "Strike From Mars" celebration sequence — green spark trail behind ball, big STRIKE animation
- QubicaAMF scoreboard (reference)
- Bowling Crew aim selector — circular arc around the ball with rotating arrows + red aim laser pointing at pins

---

## Workflow rules (the user's hard boundaries)

1. **Branch:** `claude/meta-glasses-bowling-game-DcTR3`. Never main.
2. **Bash:** one command per block. The hook will deny `git add && git commit && git push`.
3. **xcodegen:** the user runs it — only when `project.yml` changed (new files in source tree are auto-discovered, but Xcode's project.pbxproj does need regenerating to pick them up).
4. **swift-format hook (`~/.claude/hooks/swift-format-on-edit.sh`)** runs on every Edit — expect indentation churn (4-space → 2-space) on every commit. The diff will be 50–150 lines on a 3-line logical change. Mention this in commit messages so the user knows.
5. **Don't pre-tune motion thresholds.** Wait for real numbers. Bowling's threshold `0.005 / 0.5` is the validated baseline.

---

## Diagnostic procedure when "feature X isn't appearing"

1. `git log --oneline -10` — confirm the commit is on the local branch.
2. `xcodebuild -project ClaudeVision.xcodeproj -scheme ClaudeVision -destination 'generic/platform=iOS' -quiet build` from `ClaudeVision/ios/` — confirm source compiles.
3. Computer-use screenshot of Xcode. Read top-right status — if "Build Failed" or stale timestamp, the user is on the prior binary.
4. **Tell the user: Cmd+Shift+K, then Cmd+R.** Don't theorize about the feature being broken until they confirm a fresh build.
5. If a fresh build still doesn't show it, then dig into the code.

This was the failure mode this entire session. Most user complaints "I don't see X" resolved themselves after a clean rebuild.

---

## Audio session warning

`GameAudio.swift` line 1 (the `import AVFoundation`) was corrupted twice in this session by accidental clicks landing in the editor + macOS dictation/long-press menu inserting text. If you see "Build Failed" with `Cannot find 'AVFoundation' in scope`, read the first line of `GameAudio.swift` first — fix is just to make sure it reads `import AVFoundation`. Do not click in the Xcode editor pane to "verify" — read via Bash/Read tool.

---

## What to do FIRST in the next session

1. Run `git log --oneline -5` to confirm `3e93633` (or later) is the head of the bowling branch.
2. Read `memory/mwdat_streaming_order.md`.
3. Run `xcodebuild ... build` from `ClaudeVision/ios/` to confirm the source compiles. Should succeed with only the icon warning.
4. Take an Xcode screenshot. Verify build status, ask user to do **Cmd+Shift+K + Cmd+R** if it's stale.
5. **Don't add features until the user confirms they see the existing committed work** — full-bleed lane, ball picker, turkey fire, themed venues. If they still don't, dig into Xcode build logs (the build is failing on their side somehow that the CLI doesn't reproduce).
6. Once parity is confirmed, the highest-priority unfinished item is **pins falling instead of fading** — see Open work #2.

---

## Final sanity-check note for the next session

The user is patient and forgiving when I tell the truth, and very impatient when I keep shipping commits that don't materialize on their phone. Honesty about what SwiftUI can and can't do beats over-promising. If they ask for "real 3D" again, suggest the SceneKit/Metal route as a deliberate choice, not a polish iteration.

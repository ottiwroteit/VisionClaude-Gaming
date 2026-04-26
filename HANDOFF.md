# Handoff — VisionClaude Gaming · 9-game multi-engine session

**Last session ended:** 2026-04-26.
**Branch:** `claude/meta-glasses-bowling-game-DcTR3` — never push to `main`.
**Working tree:** `/Users/otti/Documents/GitHub/VisionClaude-Gaming` on the user's Mac.
**Player's first name:** Jamario (note spelling — Ja-mario, not Mario). The platformer game and its player character are both named after him.

---

## TL;DR · Read this first

App now ships **9 games** total. All gameplay rendering uses native Apple frameworks: SceneKit for 3D games (bowling, tennis, ping pong, boxing, archery, firefox), SpriteKit for 2D games (Jamario auto-runner, Jamario Streets brawler, AI Slasher). No SwiftUI primitives in any game scene anymore — those are all dead code in `GameSessionView.swift` waiting on a cleanup commit.

The recurring "stale build" problem still applies on every fresh session — Xcode keeps a cached binary across SDK refreshes:

1. Xcode screenshot. If "Build Failed" or stale timestamp → tell the user **Cmd+Shift+K** then **Cmd+R**. Do not proceed with feature work until they confirm a fresh build is running.
2. CLI source-of-truth for "does this compile" before trusting Xcode:
   ```
   xcodebuild -project ClaudeVision.xcodeproj -scheme ClaudeVision -destination 'generic/platform=iOS' -quiet build
   ```
   (from `ClaudeVision/ios/`)
3. After adding new files, **xcodegen** must regenerate `.pbxproj`. If the user has Xcode open they'll get a project-changed prompt — accept the reload.

---

## Game lineup (alphabetical-by-title in the home carousel)

| Game | id | Engine | Mechanic |
|---|---|---|---|
| AI Slasher | `fruitslash` | SpriteKit | Head-tracked samurai sword + falling AI/LLM company logos. Real slice-in-half. Bombs ("AGI") penalize. |
| Jamario: Streets | `jamariostreets` | SpriteKit | Side-scrolling beat-em-up. Tilt = walk, chin UP = punch, chin DOWN = kick. Wave-based. |
| Meta Archery | `archery` | SceneKit | 3D target + nocking arrow + flight + camera follow. |
| Meta Bowling | `bowling` | SceneKit | 3D pin physics + ball impulses + camera follow + turkey VFX. |
| Meta Boxing | `boxing` | SceneKit | First-person POV vs. humanoid opponent. 400 HP each (recently bumped). |
| Meta Firefox | `firefox` | SceneKit | First-person flight combat. Bank/pitch via tilt, chin UP = fire missile. |
| Meta Jamario | `jamario` | SpriteKit | Auto-runner platformer. Chin UP = jump. 8-frame run cycle from the user's MP4. |
| Meta Fruit Slash → AI Slasher | (renamed) | — | (see AI Slasher above) |
| Meta Tennis | `tennis` | SceneKit | 3D court, net, ball arcs, opponent humanoid. |
| Meta Ping Pong | `pingpong` | SceneKit | 3D table + paddles + arcing ball. |

---

## File layout

```
ClaudeVision/ios/ClaudeVision/
├── Gaming/
│   ├── Game.swift                  Protocol — handle, handleMotion, etc.
│   ├── GameCoordinator.swift       Wires engine → active game
│   ├── GestureEngine.swift         Optical-flow → MotionClassifier
│   ├── GestureEvent.swift          (now includes lateralCurvature)
│   ├── MotionClassifier.swift      Now has maxGestureDuration cutoff (cuts post-flick latency)
│   ├── ProgressStore.swift         Per-game cumulative score → unlocks
│   ├── DailyChallenge.swift / GestureRecorder.swift / TestScenarios.swift  Untouched
│   ├── Games/                      Pure model files, one per game
│   ├── Venues/                     Per-game venue lists + SwiftUI backgrounds
│   ├── Bowling/                    SceneKit module
│   ├── Tennis/                     SceneKit module
│   ├── PingPong/                   SceneKit module
│   ├── Boxing/                     SceneKit module
│   ├── Archery/                    SceneKit module (with camera follow tracker)
│   ├── Firefox/                    SceneKit module (with render-tick bridge)
│   ├── FruitSlash/                 SpriteKit module (was SceneKit, redesigned)
│   ├── Jamario/                    SpriteKit module + sprite scene
│   └── JamarioStreets/             SpriteKit module
├── Services/                       RayBanManager, GameAudio (synth disabled), AppIconManager, FrameSource
└── Views/
    ├── ContentView.swift           Registers all games with the coordinator
    ├── GameSessionView.swift       Hero-art DISPATCHER + ~1500 lines of dead SwiftUI primitives
    ├── HomeView.swift              Horizontal game carousel (240×240 cards)
    ├── GlassesSetupView.swift / VenueSelectView.swift / etc.
    └── (dashboards, share cards, splash, theme)
```

---

## Sprite assets

- 13 imagesets at top level of `Assets.xcassets/` (jamario_idle, jamario_run_1..8, jamario_jump, jamario_punch, jamario_kick, jamario_enemy_idle, jamario_enemy_walk_1/2, jamario_coin).
- Loaded via `SKTexture(image: UIImage(named: "jamario_idle")!)`. **Don't use `Jamario.spriteatlas/` with `provides-namespace: true`** — that broke silently in the first attempt.
- 60 unused source PNGs sit in `JAMARIO GAME/2D SPRITES/` outside the iOS target — available for future polish (climbing rope, throwing chain, payphone scenes, vault scenes, helicopter set pieces).
- Source MP4 of Jamario running at `Apps/SUPER-JAMARIO/hf_20260426_094306_*.mp4`.
- Helper: `/tmp/strip_checker.py` chroma-keys the AI-generated checkerboard background out of any sprite PNG (transparent grays with avg ≥ 120, neutrality within ±10). The AI-generated PNGs LOOK transparent in previewers but the checkerboard is baked-in pixels — must be stripped before bundling.

---

## Connection-blocked recovery (recurring issue)

When the user says "I'm stuck on START FEED" with `sessionAlreadyExists`-style symptoms:

1. **Glasses Setup screen → "Reset connection" button.** Triggers `forceReset()` which unregisters + re-registers via Meta AI bridge. Works ~80% of the time.
2. **iPhone Settings → Bluetooth → forget "Ray-Ban Meta", re-pair via Meta AI app.** Works ~95% of the time when Reset doesn't.
3. **Phone reboot** is the absolute last resort and only if Bluetooth is wedged at the iOS level.

Source-of-truth for the SDK lifecycle is [`memory/mwdat_streaming_order.md`](file:///Users/otti/.claude/projects/-Users-otti-Documents-GitHub-VisionClaude-Gaming/memory/mwdat_streaming_order.md). Read first when touching `RayBanManager`.

---

## User's pet peeves (re-read these to save a frustration cycle)

1. **"Just try it. Use computer-use. Stop asking me."** Xcode is at click-tier on display "LS32CG51x". Take screenshots, click Run, read the console yourself. CAVEAT: clicking inside the editor pane has caused garbage characters to appear in source files. **Click only the Run button at the very top of the toolbar.**
2. **"One terminal command per code block."** Bash hook actively blocks chained `git add && commit && push`. Always split.
3. **"Don't ask me questions when in auto-mode."** The user is hands-off. Make reasonable assumptions and proceed; user gives course corrections as needed.
4. **Honest about limits.** SwiftUI primitives can't match polished commercial games — that was the lesson from the bowling deep-dive. Always reach for the right tool (SceneKit for 3D, SpriteKit for 2D).
5. **Real bowling rules.** 10 frames, strike/spare bonus scoring, proper 10th-frame fill-ball logic. Don't simplify.
6. **No phallic pin shape.** USBC-spec proportions in `BowlingPinShape` (now superseded by SceneKit cylinder pin physics anyway).
7. **Glasses-only motion input.** No phone-IMU fallback.
8. **Themed venues, not solid colors.** Each venue has its own scene treatment.

---

## SDK gotchas (MWDAT 0.6) — keep in memory

The MWDAT iOS SDK has several non-obvious requirements documented in [`memory/mwdat_streaming_order.md`](file:///Users/otti/.claude/projects/-Users-otti-Documents-GitHub-VisionClaude-Gaming/memory/mwdat_streaming_order.md). Read first when touching streaming code.

Key reminders:
- `addStream` returns `nil` silently if camera permission isn't granted OR the device session isn't `.started`. Order: permission → createSession → deviceSession.start() → wait for `.started` → addStream → install listeners → stream.start(). Implemented in `RayBanManager.beginStreamSession`.
- `createSession` throws `sessionAlreadyExists` when a previous session is held cross-process by the Meta AI bridge after an Xcode kill or crash. Auto-recovery via `forceReset()` (unregister → reregister) is wired in. There's also a manual "Reset connection" button on the Glasses Setup screen.
- Audio engine path is **disabled** in `GameAudio` because programmatic synth crashed AVAudioEngine with "player did not see an IO cycle" AND sounded bad. Speech callouts via AVSpeechSynthesizer still work. The synth code is preserved (gated behind `engine.isRunning`) for the next pass that swaps in real audio samples.

---

## Workflow rules (the user's hard boundaries)

1. **Branch:** `claude/meta-glasses-bowling-game-DcTR3`. Never main.
2. **Bash:** one command per block. The hook will deny `git add && git commit && git push`.
3. **xcodegen:** runs whenever a new file is added (folder discovery is automatic but `.pbxproj` needs regenerating). The user has it installed at `/opt/homebrew/bin/xcodegen`.
4. **swift-format hook (`~/.claude/hooks/swift-format-on-edit.sh`)** runs on every Edit — expect indentation churn (4-space → 2-space) on every commit. The diff will be 50-150 lines on a 3-line logical change. Mention this in commit messages so the user knows.
5. **Don't pre-tune motion thresholds.** Wait for real numbers. Bowling's threshold `0.005 / 0.5 / maxGestureDuration 0.6` is the validated baseline.

---

## Recent commits (most recent first)

```
45836c7  feat(fruitslash): redesigned as AI Slasher — head-tracked samurai sword + AI/LLM logos + real slice
e87a152  fix(bowling, boxing): camera follows ball to the pins; boxing fights last 30-60s (HP 100→400)
7f33cb5  feat(firefox): new SceneKit flight combat — first-person dogfight inspired by 1984 Atari Firefox
78a4dca  feat(jamario-streets): new SpriteKit beat-em-up — Streets-of-Rage style brawler
0855539  feat(jamario): 8-frame run cycle extracted from user-provided MP4
132cc23  fix(jamario): sprites actually visible — drop sprite-atlas + chroma-key checkerboard
90715d7  feat(jamario): wire 2D character sprites — texture atlas + run cycle + jump + enemy walk
6eb16c3  feat(jamario): new SpriteKit auto-runner platformer named after the player
6492d6a  fix(home): force horizontal carousel on game cards
20c07e9  feat(boxing): opponent gets a real face + body details
0c7c0d7  feat(archery): camera follows in-flight arrow
c0fc3c1  feat(archery): SceneKit port — 3D target, arrow nock + flight animation
0aaa527  feat(tennis): SceneKit port
2c2986b  feat(pingpong): SceneKit port
b597d19  feat(fruitslash): SceneKit port (later replaced by SpriteKit AI Slasher)
7685b5f  feat(boxing): replace heavy bag with first-person 3D humanoid boxer
e5c7546  feat(boxing): SceneKit port v1 (heavy bag — replaced)
d50fe0e  feat(bowling): turkey fireworks + slow-mo on contact
ac7b6a5  fix(bowling): force-close gestures past max duration to cut chin-flick latency
```

Use `git log --oneline -30 claude/meta-glasses-bowling-game-DcTR3` for the full picture.

---

## Known deferred items

- **Bowling audio (Phase C)** — never wired. Previous AVAudioEngine synth attempt crashed with "player did not see an IO cycle." Needs sourced .caf samples (archive.org URLs were collected in an earlier session — see `memory/mwdat_streaming_order.md` history). Skipped to avoid shipping a fragile audio path.
- **Dead SwiftUI primitives in `GameSessionView.swift`** — ~1500 lines of `BowlingArt` / `TennisArt` / `BoxingArt` / `ArcheryArt` / `PingPongArt` / `GenericArt` plus a dozen helper Shape structs no longer referenced from the dispatcher. Build is clean, runtime unaffected, just visual noise. (`FruitSlashArt` was already removed during the AI Slasher rewrite.)
- **Per-game polish** — many games shipped at "v1, looks right, plays right" bar. Camera dynamics, particle effects, geometry tuning are all candidates for follow-ups.

---

## Memory files (read these in a fresh session)

`/Users/otti/.claude/projects/-Users-otti-Documents-GitHub-VisionClaude-Gaming/memory/`

- **MEMORY.md** — index
- **user_name.md** — Jamario, his first name (note spelling)
- **workflow_rules.md** — one bash command per block; never push to main; bowling branch only
- **computer_use_granted.md** — Xcode at click tier on LS32CG51x display
- **mwdat_streaming_order.md** — canonical SDK streaming order (read first when touching RayBanManager)
- **bowling_threshold.md** — `activeThreshold = 0.005` validated by user as "much better"
- **project_state.md** — most recent project snapshot

---

## What to do FIRST in the next session

1. Read this file (you're doing it) and `git log --oneline -10` to confirm the branch head.
2. Read `memory/project_state.md` and `memory/user_name.md`.
3. Take an Xcode screenshot. Verify build status. If stale → ask user to do **Cmd+Shift+K + Cmd+R**.
4. Wait for the user to describe what they want; don't dive in cold.

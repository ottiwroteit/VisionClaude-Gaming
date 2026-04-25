# Handoff — VisionClaude Gaming first-build session

## TL;DR

Branch `claude/meta-glasses-bowling-game-DcTR3` is fully committed (gaming rebuild + personal Meta credentials). User regenerated Xcode project on Mac via `xcodegen` and hit **3 compile/asset issues on first build attempt**. This doc captures everything you need to pick up cold.

## What's already done (do not redo)

- Gaming rebuild complete: 7 games (Bowling, Tennis, PingPong, Boxing, Archery, FruitSlash, plus venue progression). All committed.
- `VenueModifier` system + `ShareCardView` + `LaunchSplashView` + alternate icon scaffolding shipped.
- `project.yml` has `DEVELOPMENT_TEAM: "4ZCZ9LLR98"` (user's Apple team).
- `Info.plist` has user's Meta credentials:
  - `MetaAppID: 815101094206954`
  - `ClientToken: AR|815101094206954|3eec2204c9e5de89217b80abe1894b50`
  - `AppLinkURLScheme: claudevision://` (matches `CFBundleURLSchemes`).
- User's working tree: `/Users/otti/Documents/GitHub/VisionClaude-Gaming` on Mac.
- `xcodegen` ran successfully → `ClaudeVision.xcodeproj` regenerated.

The user wants commands one-per-block in the terminal — no batched chains.

## Current blocker — 3 issues from first Xcode build

### 1. RayBanManager — `'StreamSession' cannot be constructed because it has no accessible initializers`

**File:** `ClaudeVision/ios/ClaudeVision/Services/RayBanManager.swift:134`

**Code:**
```swift
let session = StreamSession(streamSessionConfig: config, deviceSelector: selector)
```

**Diagnosis:** The MWDAT SDK is pinned to `from: "0.5.0"` in `project.yml`. The `StreamSession` initializer is no longer public in the resolved version — it's almost certainly created via a factory on `Wearables` or `MWDATCamera`. Need to inspect the resolved package to find the correct entry point.

**Investigation steps:**
1. In Xcode: Project Navigator → expand `Package Dependencies` → `meta-wearables-dat-ios` → `MWDATCamera` → look at `StreamSession.swift` to see what initializer (if any) is `public`.
2. Or: `find ~/Library/Developer/Xcode/DerivedData -name "StreamSession.swift" 2>/dev/null` and grep for `public init` / `public static func`.
3. Likely fix: replace the `StreamSession(...)` call with something like `Wearables.shared.makeStreamSession(config:deviceSelector:)` or a builder. The exact name needs verification — do not guess.

**Don't:** Bump the SDK version without checking the changelog at `https://github.com/facebook/meta-wearables-dat-ios/blob/main/CHANGELOG.md` first — the API may have changed again.

### 2. GameCoordinator — `Main actor-isolated static property 'shared' can not be referenced from a nonisolated context`

**File:** `ClaudeVision/ios/ClaudeVision/Gaming/GameCoordinator.swift:22`

**Code:**
```swift
init(progress: ProgressStore = .shared) { ... }
```

**Diagnosis:** Swift 6 strict concurrency. `ProgressStore.shared` is `@MainActor`-isolated (`ProgressStore.swift:10-12`). Default-argument expressions are evaluated in the caller's context, not the init's, so the main-actor isolation of `GameCoordinator` doesn't cover them.

**Fix:** Drop the default and resolve `.shared` inside the init body:

```swift
init() {
    self.progress = ProgressStore.shared  // OK — init body runs on @MainActor
    ...
}
```

`ContentView.swift:11` already does `@StateObject private var coordinator = GameCoordinator()` with no argument, so removing the default is non-breaking. No other call sites pass a custom progress store.

### 3. Asset warning — `AppIcon set has 9 unassigned children`

**Diagnosis:** Alternate-icon scaffolding committed without per-icon image assets. Non-blocking warning. Expected at this stage. Either:
- Ignore for now (build will still succeed once errors 1 and 2 are fixed).
- Or strip the alternate icon entries from `Info.plist` (the `CFBundleAlternateIcons` dict) until art assets are made.

User has not asked for art assets. Leave as a warning.

## After build succeeds — first-test workflow

The original first-test plan is at `/root/.claude/plans/i-have-all-of-spicy-quasar.md` — read it before this section. Short version:

1. User builds in Xcode → installs to iPhone via USB → trusts dev profile in Settings → General → VPN & Device Management.
2. App launches → splash plays ~1.8s → routes to `GlassesSetupView`.
3. Tap **CONNECT GLASSES** → bounces to Meta AI app for camera permission → returns via `claudevision://` URL scheme.
4. Tap **START FEED**. Status pill should turn green; `[RayBan]` log lines start appearing in Xcode console.
5. On Home: motion bar should fill when user turns their head.
6. Pick **Meta Bowling**. Have user do a deliberate chin-flick up. Watch the debug label: `flick / direction / m=X.XX`.

**Ask user to report:**
- Did motion bar move? Roughly what magnitude?
- What did the debug label say after a flick?
- Did the pins react?

## Tuning loop after first test

Likely follow-ups (don't pre-tune — wait for numbers):

- Bar moves but no flick fires → lower `MotionClassifier.Thresholds.activeThreshold` in `GestureEngine.start()` or per-game in `Game.preferredThresholds`.
- Every twitch fires a flick → raise `activeThreshold`, widen `stillThreshold`.
- Direction is inverted → flip sign of `headMotion = -accumulated` in `MotionClassifier.makeEvent`.
- Hold events never fire → shorten `minHoldDuration`.
- No frames at all → check `[RayBan]` console output for failed registration or permission steps.

User's loop expectation: they flick, they paste numbers, you push a one-line tuning change, they `xcodegen` (only if `project.yml` changed — usually not) and rebuild.

## Workflow rules user has set

1. **One terminal command per code block.** Never batch with `&&` or newlines. They copy-paste one at a time.
2. **Confirm uncommitted changes before significant edits.** Stop hook complains otherwise.
3. **Never push to `main`.** All work goes to `claude/meta-glasses-bowling-game-DcTR3`.
4. They cannot remote-control their Mac through this session — they run `xcodegen`, Xcode, build, install. You edit code + commit + push.

## Current repo state (server-side)

- HEAD: `dc17ffd` "Configure MWDAT credentials for personal Meta app" on `claude/meta-glasses-bowling-game-DcTR3`.
- User-side may have a regenerated `project.pbxproj` uncommitted from `xcodegen` — that's fine, it's deterministic from `project.yml`.

## Next action when new session starts

Check this branch is current. Then propose the GameCoordinator fix (issue 2) — it's the safe, mechanical one. Get user to commit + rebuild and confirm whether issue 1 still blocks. Then dig into the StreamSession API change with the user's resolved-package inspection output.

Do not start by running `xcodegen` or guessing at the StreamSession API. Inspect first.

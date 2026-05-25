# VisionClaude — Meta Display Web Apps

Web app ports of the VisionClaude gaming suite, built for Meta Ray-Ban Display glasses
([SDK docs](https://wearables.developer.meta.com/docs/develop/webapps)).

## What this is

Each subdirectory is an independently deployable web app — one URL per game, matching Meta's
one-app-one-URL distribution model. The web app loads on the glasses through the Meta AI app
on the paired phone, rendering at a fixed 600×600 viewport on an additive transparent display.

## Platform constraints (read before editing)

| Constraint | Value | What it means |
|---|---|---|
| Viewport | 600×600 px | Fixed. Don't design for resize. |
| Display | Additive transparent | Pure black = invisible. Use dark backgrounds with bright foregrounds. |
| Input | Arrow keys + Enter | Neural Band emits keyboard events. No proprietary API. |
| Hosting | Public HTTPS | Vercel works; any HTTPS URL works. No localhost. |
| Frame rate | Modest | Snake sample ticks at 120ms (~8 fps). Don't assume 60fps. |

## Games

| Game | Status | URL |
|---|---|---|
| Bowling | In development | TBD |

## Adding a game to your glasses

1. Open the Meta AI app on the phone paired to your glasses
2. Devices → Display Glasses settings → App connections → Web apps → Add a web app
3. Paste the game's HTTPS URL

Or scan a QR code generated from the deployed URL — deep-links into the Meta AI flow above.

## Local development

Each game is plain HTML/CSS/JS — no build step required.

```
# Run any game locally
cd webapp/bowling
python3 -m http.server 8000
# Open http://localhost:8000 in Chrome
# Open DevTools (F12) → device toolbar (Ctrl+Shift+M) → set custom 600×600 viewport
# Play with arrow keys + Enter
```

## Deploying a game

Each game directory is its own Vercel project:

```
cd webapp/bowling
vercel deploy --prod
```

Save the HTTPS URL, then follow the "Adding a game to your glasses" steps above.

## File layout

```
webapp/
├── shared/           # Cross-game utilities (design tokens, focus mgmt, canvas helpers)
├── bowling/          # Meta Bowling
└── …                 # Future games
```

Source of truth for game LOGIC remains the iOS implementation at
`ClaudeVision/ios/ClaudeVision/Gaming/Games/*Game.swift`. The web port reproduces the rules
verbatim; only rendering and input change.

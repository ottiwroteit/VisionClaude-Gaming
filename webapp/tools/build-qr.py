#!/usr/bin/env python3
"""
Generate per-game QR code PNGs from manifest.js.

Each QR encodes the https URL of the add page for that game's code, e.g.
  https://visionclaude-bowling.vercel.app/add/?code=100001

Run from the webapp/ directory:
  python3 tools/build-qr.py

Outputs PNGs to webapp/add/qr-<code>.png — one per game in manifest.js.

Reuses Meta's pure-Python QR generator from the meta-wearables-webapp
plugin (cloned to /tmp/meta-wearables-webapp). No external deps.
"""

import re
import subprocess
import sys
from pathlib import Path

WEBAPP_DIR = Path(__file__).resolve().parent.parent
MANIFEST = WEBAPP_DIR / 'manifest.js'
ADD_DIR = WEBAPP_DIR / 'add'
QR_GEN = Path('/tmp/meta-wearables-webapp/plugins/meta-wearables-webapp/skills/qr-code/scripts/qr_generator.py')


def parse_manifest():
    """Return (host, [{id, shareCode, ...}]) parsed out of the JS file.

    We don't actually run JS — just regex-parse the small literal section.
    The manifest is small and stable enough that this is reliable.
    """
    text = MANIFEST.read_text()
    host_match = re.search(r"export const HOST = '([^']+)'", text)
    if not host_match:
        sys.exit('manifest.js: HOST constant not found')
    host = host_match.group(1)

    games = []
    # Each game is a `{ ... }` block inside the GAMES array.
    block_re = re.compile(r'\{\s*(?:id|name|shareCode|path|blurb|emoji)\s*:.*?\}', re.S)
    for block in block_re.findall(text):
        def field(name):
            m = re.search(rf"{name}\s*:\s*'([^']+)'", block)
            return m.group(1) if m else None
        game = {
            'id': field('id'),
            'name': field('name'),
            'shareCode': field('shareCode'),
            'path': field('path'),
        }
        if all(game.values()):
            games.append(game)
    if not games:
        sys.exit('manifest.js: no games found')
    return host, games


def build_qr(url, out_path):
    if not QR_GEN.exists():
        sys.exit(f'QR generator not found at {QR_GEN}. Clone meta-wearables-webapp first.')
    subprocess.run(
        ['python3', str(QR_GEN), '--png', str(out_path), '--scale', '12', url],
        check=True,
    )


def main():
    host, games = parse_manifest()
    ADD_DIR.mkdir(exist_ok=True)
    for game in games:
        share_url = f"{host}/add/?code={game['shareCode']}"
        out = ADD_DIR / f"qr-{game['shareCode']}.png"
        build_qr(share_url, out)
        print(f"  {game['name']:24} {game['shareCode']}  -> {out.relative_to(WEBAPP_DIR)}")


if __name__ == '__main__':
    main()

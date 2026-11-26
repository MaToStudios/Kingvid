#!/bin/sh
# Runs the behavioural tests for the injected page scripts in headless Chromium (Playwright).
# Extracts the JavaScript straight from the Swift sources, so the tests always check what ships.
set -e
DIR=$(cd "$(dirname "$0")" && pwd)
ROOT="$DIR/../.."
python3 - "$ROOT" "$DIR" <<'PY'
import re, sys, textwrap
root, out = sys.argv[1], sys.argv[2]
def extract(path):
    src = open(path).read()
    return textwrap.dedent(re.search(r'#"""\n(.*?)\n\s*"""#', src, re.S).group(1))
bridge = extract(root + '/KingVid/Media/MediaScripts.swift')
yt = extract(root + '/KingVid/Media/YouTubeScripts.swift')
open(out + '/bridge.js', 'w').write("window.__KV_OPTS = {spoof: true, resume: true};\n" + bridge)
open(out + '/yt_browse.js', 'w').write("window.__KV_YT = {role: 'browse', hideChrome: true};\n" + yt)
open(out + '/yt_player.js', 'w').write("window.__KV_YT = {role: 'player', hideChrome: true};\n" + yt)
open(out + '/page.html', 'w').write('<!doctype html><title>Test Video</title><body><video id=v src="test.webm" playsinline controls width=320></video></body>')
PY
[ -f "$DIR/test.webm" ] || ffmpeg -loglevel error -y -f lavfi -i testsrc=duration=60:size=320x180:rate=15 \
  -f lavfi -i sine=frequency=440:duration=60 -c:v libvpx -b:v 200k -c:a libvorbis -shortest "$DIR/test.webm"
for t in bridge_test yt_test fix_test layout_test; do
  echo "== $t"; node "$DIR/$t.js"
done

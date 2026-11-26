#!/bin/sh
# Builds and runs the YouTube parser test against a freshly downloaded m.youtube.com results page.
set -e
DIR=$(cd "$(dirname "$0")" && pwd)
ROOT="$DIR/../.."
OUT=${TMPDIR:-/tmp}/kingvid-parser-test
mkdir -p "$OUT"
curl -sSL --max-time 30 -A 'Mozilla/5.0 (iPhone; CPU iPhone OS 18_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.5 Mobile/15E148 Safari/604.1' \
  -H 'Accept-Language: en-US,en' -b 'SOCS=CAI; CONSENT=YES+cb' -o "$OUT/results.html" "https://m.youtube.com/results?search_query=${1:-lofi}"
swiftc -O -o "$OUT/parser-test" "$ROOT/KingVid/YouTube/YouTubeData.swift" "$DIR/main.swift"
"$OUT/parser-test" "$OUT/results.html"

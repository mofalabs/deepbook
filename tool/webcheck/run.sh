#!/usr/bin/env bash
# Proves the SDK's network layer works in a real browser: builds a minimal
# Flutter Web app against this package, serves it, loads it in headless
# Chrome and asserts the live gRPC-web reads succeeded.
#
# Usage: tool/webcheck/run.sh [chrome-binary]
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
PKG="$(cd "$HERE/../.." && pwd)"
CHROME=${1:-"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"}
APP=$(mktemp -d)/webcheck
PORT=8899

flutter create --platforms=web --project-name deepbook_webcheck "$APP" > /dev/null
cp "$HERE/main.dart" "$APP/lib/main.dart"
python3 - "$APP/pubspec.yaml" "$PKG" <<'EOF'
import sys
pubspec, pkg = sys.argv[1], sys.argv[2]
s = open(pubspec).read()
s = s.replace("""dependencies:
  flutter:
    sdk: flutter""", f"""dependencies:
  flutter:
    sdk: flutter
  deepbook:
    path: {pkg}""")
# sui/bcs come from the monorepo, so pin them through overrides.
s += f"""
dependency_overrides:
  sui:
    path: {pkg}/../sui
  bcs:
    path: {pkg}/../bcs
"""
open(pubspec, 'w').write(s)
EOF

(cd "$APP" && flutter pub get > /dev/null && flutter build web --release > /dev/null)
echo "built $APP/build/web"

(cd "$APP/build/web" && python3 -m http.server $PORT > /dev/null 2>&1) &
SERVER=$!
trap 'kill $SERVER 2>/dev/null || true' EXIT
sleep 3

PROFILE=$(mktemp -d)
"$CHROME" --headless=new --disable-gpu --no-sandbox --user-data-dir="$PROFILE" \
  --enable-logging=stderr --virtual-time-budget=40000 \
  --dump-dom "http://127.0.0.1:$PORT/" > /dev/null 2> "$PROFILE/err.txt"

if grep -q "PROBE_RESULT" "$PROFILE/err.txt"; then
  grep -o "PROBE_RESULT.*" "$PROFILE/err.txt" | head -1
  echo "WEB OK — live gRPC-web reads succeeded in the browser"
else
  grep -o "PROBE_ERROR.*" "$PROFILE/err.txt" | head -1 || echo "no probe output"
  echo "WEB FAILED"
  exit 1
fi

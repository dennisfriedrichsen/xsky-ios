#!/bin/sh
# Regenerates the golden fixture file from the legacy C implementation.
#
# Usage: tools/golden/generate.sh [path-to-legacy-xsky-checkout]
#
# Compiles the unmodified legacy position.c (MEEUS branch) plus the Herget
# precession functions extracted verbatim from boundary.c, runs the driver,
# and writes Packages/XSkyCore/Tests/XSkyCoreTests/Fixtures/golden.json.
# The legacy tree is read-only; extraction happens in a build directory.

set -eu

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/../.." && pwd)
LEGACY=${1:-"$REPO_ROOT/../xsky"}
BUILD_DIR="$SCRIPT_DIR/build"
OUT="$REPO_ROOT/Packages/XSkyCore/Tests/XSkyCoreTests/Fixtures/golden.json"

if [ ! -f "$LEGACY/position.c" ]; then
  echo "error: legacy xsky checkout not found at $LEGACY" >&2
  exit 1
fi

mkdir -p "$BUILD_DIR"

# Extract the two static Herget precession functions (K&R definitions)
# verbatim from boundary.c. They span from the herget_precession comment
# block through the end of the file.
sed -n '753,842p' "$LEGACY/boundary.c" > "$BUILD_DIR/herget_body.c"
grep -q "init_herget_precession" "$BUILD_DIR/herget_body.c" || {
  echo "error: Herget extraction from boundary.c failed" >&2
  exit 1
}

cc -O2 -DMEEUS -Wno-deprecated-non-prototype -Wno-return-type \
   -I"$LEGACY" -I"$BUILD_DIR" \
   -o "$BUILD_DIR/goldengen" \
   "$SCRIPT_DIR/goldengen.c" "$SCRIPT_DIR/herget_wrapper.c" \
   "$LEGACY/position.c" -lm

mkdir -p "$(dirname "$OUT")"
"$BUILD_DIR/goldengen" > "$OUT"

# sanity check that the output is valid JSON
python3 -c "import json,sys; json.load(open('$OUT'))"
echo "wrote $OUT"

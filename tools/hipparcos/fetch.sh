#!/bin/sh
# Retrieves the candidate Hipparcos distributions evaluated in
# design/adr/0001-hipparcos-star-catalog.md.
#
# Usage: tools/hipparcos/fetch.sh [destination-directory]
#
# Default destination is tools/hipparcos/build, which is not committed.
# Nothing here writes into Resources/LegacyCatalogs: the evaluation never
# bundles these files with the app.
#
# Both distributions come from the CDS/VizieR FTP mirror at Strasbourg.
# The 1997 ESA release is served pre-gzipped only under version_cd/cats;
# the top-level hip_main.dat is the same bytes, uncompressed.

set -eu

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
DEST=${1:-"$SCRIPT_DIR/build"}
BASE=https://cdsarc.cds.unistra.fr/ftp

mkdir -p "$DEST"

fetch() {
  echo "fetching $2"
  curl -fsS --retry 3 -o "$DEST/$2" "$BASE/$1"
}

fetch I/239/ReadMe                          ReadMe.I239
fetch I/239/version_cd/cats/hip_main.dat.gz hip_main.dat.gz
fetch I/311/ReadMe                          ReadMe.I311
fetch I/311/hip2.dat.gz                     hip2.dat.gz

gunzip -kf "$DEST/hip_main.dat.gz" "$DEST/hip2.dat.gz"

echo
echo "SHA-256 of the retrieved files:"
shasum -a 256 "$DEST/hip_main.dat" "$DEST/hip2.dat" \
              "$DEST/ReadMe.I239" "$DEST/ReadMe.I311"

cat <<'EOF'

Expected (retrieved 2026-08-10):
  e98e9076f9caf3e15c75b4cadd9a6576df9ab4d6a321fc02a26ad3f08aa8a8a9  hip_main.dat
  c45d6325bd59dd691764af173a9702e543804a2b6c1d9fea59210e8332e50a4a  hip2.dat

hip_main.dat is 53,434,536 bytes / 118,218 records of 451 bytes plus newline.
hip2.dat is 32,673,535 bytes / 117,955 records of 276 bytes plus newline.
EOF

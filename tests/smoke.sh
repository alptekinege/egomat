#!/usr/bin/env bash
# egomat — end-to-end smoke test.
#
# Generates test images with ImageMagick and runs the commands the menu uses
# against them, inside a throw-away directory.
#
#   ./tests/smoke.sh
#
# Exits non-zero on the first failed check.

set -o pipefail

ROOT=$(cd -P "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
EGOMAT="$ROOT/bin/egomat"
export EGOMAT_UI=none

# Work whether or not the checked-out files carry the executable bit.
chmod +x "$EGOMAT" "$ROOT/install.sh" "$ROOT/uninstall.sh" 2>/dev/null || true

fails=0
checks=0

pass() { checks=$((checks + 1)); printf '  ok   %s\n' "$1"; }
fail() { checks=$((checks + 1)); fails=$((fails + 1)); printf '  FAIL %s\n' "$1"; }

check() {  # description, command...
  local what=$1
  shift
  if "$@" >/dev/null 2>&1; then pass "$what"; else fail "$what"; fi
}

if ! command -v magick >/dev/null 2>&1 && ! command -v convert >/dev/null 2>&1; then
  echo "smoke: ImageMagick is required to generate the test images" >&2
  exit 77
fi

TMP=$(mktemp -d "${TMPDIR:-/tmp}/egomat-smoke.XXXXXX") || exit 1
trap 'rm -rf -- "$TMP"' EXIT

echo "egomat smoke test in $TMP"

# --- fixtures --------------------------------------------------------------
if command -v magick >/dev/null 2>&1; then IM=magick; else IM=convert; fi
"$IM" -size 640x480 gradient:'#3366ff-#ff9933' "$TMP/photo.png" 2>/dev/null
"$IM" "$TMP/photo.png" -quality 92 "$TMP/photo.jpg" 2>/dev/null
"$IM" -size 300x300 gradient:'#00aa88-#004466' "$TMP/anim.png" 2>/dev/null
"$IM" "$TMP/anim.png" -set delay 10 "$TMP/anim.gif" 2>/dev/null
rm -f -- "$TMP/anim.png"
printf '%s\n' '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">
  <rect width="100" height="100" fill="#7a4dff"/>
  <circle cx="50" cy="50" r="30" fill="#ffffff"/>
</svg>' >"$TMP/logo.svg"

check "test fixtures created" test -s "$TMP/photo.png"
check "version runs" "$EGOMAT" version
check "help runs" "$EGOMAT" help
check "formats runs" "$EGOMAT" formats

# --- conversion ------------------------------------------------------------
check "png -> webp" "$EGOMAT" convert -f webp "$TMP/photo.png"
check "webp exists" test -s "$TMP/photo.webp"

check "png -> jpg" "$EGOMAT" convert -f jpg "$TMP/photo.png"
check "jpg exists" test -s "$TMP/photo.jpg"

check "jpg -> png (no clobber)" "$EGOMAT" convert -f png "$TMP/photo.jpg"
check "jpg -> png wrote photo-1.png" test -s "$TMP/photo-1.png"

check "convert with resize" "$EGOMAT" convert -f webp -r 320 "$TMP/photo.png" -o "$TMP/out"
check "resized file exists" test -s "$TMP/out/photo.webp"

check "svg -> png" "$EGOMAT" convert -f png "$TMP/logo.svg"
check "svg raster exists" test -s "$TMP/logo.png"

check "same format does not overwrite" "$EGOMAT" convert -f png "$TMP/photo.png"
check "same format wrote -egomat" test -s "$TMP/photo-egomat.png"

check "batch conversion" "$EGOMAT" convert -f webp "$TMP/photo.png" "$TMP/photo.jpg"

check "unknown format is refused" bash -c "! '$EGOMAT' convert -f nonsense '$TMP/photo.png'"
check "bad geometry is refused" bash -c "! '$EGOMAT' convert -f png -r 'abc!' '$TMP/photo.png'"

# --- optimisation ----------------------------------------------------------
if "$EGOMAT" formats 2>/dev/null | grep -q 'oxipng\s*yes\|optipng\s*yes\|pngquant\s*yes'; then
  cp -- "$TMP/photo.png" "$TMP/before.png"
  check "optimize png" "$EGOMAT" optimize -l balanced "$TMP/photo.png"
  check "png still readable after optimize" test -s "$TMP/photo.png"
  check "png did not grow" bash -c \
    "[ \$(stat -c %s '$TMP/photo.png') -le \$(stat -c %s '$TMP/before.png') ]"
else
  echo "  skip png optimisation (no PNG optimiser installed)"
fi

if command -v jpegoptim >/dev/null 2>&1 || command -v jpegtran >/dev/null 2>&1; then
  cp -- "$TMP/photo.jpg" "$TMP/before.jpg"
  check "optimize jpg" "$EGOMAT" optimize -l light "$TMP/photo.jpg"
  check "jpg did not grow" bash -c \
    "[ \$(stat -c %s '$TMP/photo.jpg') -le \$(stat -c %s '$TMP/before.jpg') ]"
else
  echo "  skip jpg optimisation (no JPEG optimiser installed)"
fi

check "optimize to outdir" "$EGOMAT" optimize -l light -o "$TMP/opt" "$TMP/photo.png"
check "optimized copy exists" test -s "$TMP/opt/photo.png"

# --- resize ----------------------------------------------------------------
check "resize command" "$EGOMAT" resize 200 "$TMP/photo.png"
check "resized file exists" test -s "$TMP/photo-resized.png"

# --- info ------------------------------------------------------------------
check "info runs" "$EGOMAT" info "$TMP/photo.png"

# --- menu entry points -----------------------------------------------------
check "menu convert" "$EGOMAT" menu convert webp "$TMP/photo.png"
check "menu optimize" "$EGOMAT" menu optimize light "$TMP/photo.png"
check "menu info" "$EGOMAT" menu info "$TMP/photo.png"

# --- installer -------------------------------------------------------------
FAKE="$TMP/prefix"
check "install into a prefix" "$ROOT/install.sh" --prefix "$FAKE" --no-kde --no-freedesktop
check "installed launcher runs" "$FAKE/bin/egomat" version
check "installed launcher converts" "$FAKE/bin/egomat" convert -f webp "$TMP/photo.png" -o "$TMP/inst"
check "installer rendered the app entry" test -s "$FAKE/share/applications/egomat.desktop"
check "uninstall" "$ROOT/uninstall.sh" --prefix "$FAKE"
check "uninstall removed the launcher" test ! -e "$FAKE/bin/egomat"

echo
if [ "$fails" -eq 0 ]; then
  echo "all $checks checks passed"
  exit 0
fi
echo "$fails of $checks checks failed"
exit 1

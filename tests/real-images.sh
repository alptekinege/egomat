#!/usr/bin/env bash
# Exercise conversions and optimization on the real JPEGs in sample-images.
#
#   bash ./tests/real-images.sh [SAMPLE_DIR]
#
# Generated files live in a temporary directory. Exit 77 when the samples or
# ImageMagick are unavailable; report optional backends as skipped.

set -o pipefail

ROOT=$(cd -P "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
EGOMAT="$ROOT/bin/egomat"
SAMPLE_DIR=${1:-$ROOT/sample-images}
export EGOMAT_UI=none

if [ ! -d "$SAMPLE_DIR" ]; then
  printf 'real-images: sample directory not found: %s\n' "$SAMPLE_DIR" >&2
  exit 77
fi
SAMPLE_DIR=$(cd -P "$SAMPLE_DIR" && pwd) || exit 1

if ! command -v magick >/dev/null 2>&1 &&
   ! command -v identify >/dev/null 2>&1 &&
   ! command -v convert >/dev/null 2>&1; then
  echo "real-images: ImageMagick is required for this test" >&2
  exit 77
fi

images=()
while IFS= read -r -d '' path; do images+=("$path"); done < <(
  find "$SAMPLE_DIR" -maxdepth 1 -type f \
    \( -iname '*.jpg' -o -iname '*.jpeg' \) -print0 | sort -z
)
if [ ${#images[@]} -eq 0 ]; then
  printf 'real-images: no JPEG samples found in %s\n' "$SAMPLE_DIR" >&2
  exit 77
fi

TMP=$(mktemp -d "${TMPDIR:-/tmp}/egomat-real-images.XXXXXXXX") || exit 1
trap 'rm -rf -- "$TMP"' EXIT
mkdir -p -- "$TMP/input" "$TMP/originals" "$TMP/converted/png"

fails=0
checks=0
pass() { checks=$((checks + 1)); printf '  ok   %s\n' "$1"; }
fail() { checks=$((checks + 1)); fails=$((fails + 1)); printf '  FAIL %s\n' "$1"; }

check() {
  local what=$1
  shift
  if "$@" >"$TMP/command.log" 2>&1; then
    pass "$what"
  else
    fail "$what"
    cat "$TMP/command.log" >&2
  fi
}

egomat() { bash "$EGOMAT" "$@"; }

image_info() {
  if command -v magick >/dev/null 2>&1; then
    magick identify -format '%m %w %h\n' "$1" 2>/dev/null
  elif command -v identify >/dev/null 2>&1; then
    identify -format '%m %w %h\n' "$1" 2>/dev/null
  else
    convert "$1" -format '%m %w %h\n' info: 2>/dev/null
  fi
}

valid_resized_png() {
  local info format width height
  info=$(image_info "$1") || return 1
  read -r format width height <<<"$info"
  [ "$format" = PNG ] &&
    [[ $width =~ ^[0-9]+$ && $height =~ ^[0-9]+$ ]] &&
    [ "$width" -le 800 ] && [ "$height" -le 800 ]
}

same_dimensions() {
  local before after before_format before_width before_height after_format after_width after_height
  before=$(image_info "$1") || return 1
  after=$(image_info "$2") || return 1
  read -r before_format before_width before_height <<<"$before"
  read -r after_format after_width after_height <<<"$after"
  [ "$after_format" = AVIF ] || return 1
  [[ $before_width =~ ^[0-9]+$ && $before_height =~ ^[0-9]+$ &&
     $after_width =~ ^[0-9]+$ && $after_height =~ ^[0-9]+$ ]] || return 1
  [ "$before_width" -eq "$after_width" ] && [ "$before_height" -eq "$after_height" ]
}

same_format_dimensions() {
  local before after before_format before_width before_height after_format after_width after_height
  before=$(image_info "$1") || return 1
  after=$(image_info "$2") || return 1
  read -r before_format before_width before_height <<<"$before"
  read -r after_format after_width after_height <<<"$after"
  [ "$after_format" = JPEG ] || return 1
  [[ $before_width =~ ^[0-9]+$ && $before_height =~ ^[0-9]+$ &&
     $after_width =~ ^[0-9]+$ && $after_height =~ ^[0-9]+$ ]] || return 1
  [ "$before_width" -eq "$after_width" ] && [ "$before_height" -eq "$after_height" ]
}

output_for() {
  local source=$1 outdir=$2 ext=$3 name
  name=${source##*/}
  name=${name%.*}
  printf '%s/%s.%s\n' "$outdir" "$name" "$ext"
}

printf 'Real-image test using %d JPEG sample(s) from %s\n' "${#images[@]}" "$SAMPLE_DIR"

work_images=()
snapshots=()
i=0
for image in "${images[@]}"; do
  i=$((i + 1))
  case $i in
    1) name='photo with spaces.jpg' ;;
    2) name='-leading dash.jpg' ;;
    *) name=${image##*/} ;;
  esac
  staged="$TMP/input/$name"
  snapshot="$TMP/originals/$i.jpg"
  if ! cp -p -- "$image" "$staged" || ! cp -- "$staged" "$snapshot"; then
    printf 'real-images: could not stage sample: %s\n' "$image" >&2
    exit 1
  fi
  work_images+=("$staged")
  snapshots+=("$snapshot")
  check "sample $i is readable" image_info "$staged"
done

# Convert every real photo to a resized PNG. Names deliberately include spaces
# and a leading dash; the source samples themselves are never modified.
for i in "${!work_images[@]}"; do
  source=${work_images[$i]}
  dest=$(output_for "$source" "$TMP/converted/png" png)
  check "convert sample $((i + 1)) to resized PNG" \
    egomat convert -f png -r '800x800>' -o "$TMP/converted/png" -- "$source"
  check "PNG sample $((i + 1)) is readable and within 800px" valid_resized_png "$dest"
  check "conversion left sample $((i + 1)) unchanged" cmp -s "$source" "${snapshots[$i]}"
done

# AVIF is optional: run the real conversion when this ImageMagick build can
# both read and write AVIF, then verify the encoded image and source.
avif_rw=0
if command -v magick >/dev/null 2>&1; then
  magick -list format 2>/dev/null | awk '$1 == "AVIF" && $3 ~ /r/ && $3 ~ /w/ { found=1 } END { exit !found }' && avif_rw=1
elif command -v identify >/dev/null 2>&1; then
  identify -list format 2>/dev/null | awk '$1 == "AVIF" && $3 ~ /r/ && $3 ~ /w/ { found=1 } END { exit !found }' && avif_rw=1
fi
if [ "$avif_rw" -eq 1 ]; then
  mkdir -p -- "$TMP/converted/avif"
  source=${work_images[0]}
  dest=$(output_for "$source" "$TMP/converted/avif" avif)
  check "convert a real JPEG to AVIF" \
    egomat convert -f avif -o "$TMP/converted/avif" -- "$source"
  check "AVIF output is readable with matching dimensions" same_dimensions "$source" "$dest"
  check "AVIF conversion left its source unchanged" cmp -s "$source" "${snapshots[0]}"
else
  echo "  skip AVIF conversion (ImageMagick AVIF read/write support unavailable)"
fi

# Optimize every real photo through all three levels. --force makes the test
# exercise and validate a real output even when a lossless pass saves no bytes.
if command -v jpegoptim >/dev/null 2>&1 || command -v jpegtran >/dev/null 2>&1; then
  for level in light balanced aggressive; do
    outdir="$TMP/optimized/$level"
    mkdir -p -- "$outdir"
    for i in "${!work_images[@]}"; do
      source=${work_images[$i]}
      dest=$(output_for "$source" "$outdir" jpg)
      check "optimize sample $((i + 1)) at $level" \
        egomat optimize -l "$level" --force -o "$outdir" -- "$source"
      check "optimized sample $((i + 1)) at $level is readable with matching dimensions" \
        same_format_dimensions "$source" "$dest"
      check "optimization left sample $((i + 1)) unchanged" \
        cmp -s "$source" "${snapshots[$i]}"
    done
  done

  # Verify that the non-force size guard agrees with the actual light candidate.
  source=${work_images[0]}
  base=$(output_for "$source" "$TMP/optimized/light" jpg)
  before_size=$(stat -c '%s' -- "$source")
  candidate_size=$(stat -c '%s' -- "$base")
  guarded_dir="$TMP/optimized/no-force"
  mkdir -p -- "$guarded_dir"
  dest=$(output_for "$source" "$guarded_dir" jpg)
  check "run real-image optimization without --force" \
    egomat optimize -l light -o "$guarded_dir" -- "$source"
  if [ "$candidate_size" -lt "$before_size" ]; then
    check "smaller real-image candidate is written without --force" test -s "$dest"
    check "non-forced output is smaller than its source" \
      test "$(stat -c '%s' -- "$dest" 2>/dev/null || printf 0)" -lt "$before_size"
  else
    check "non-smaller real-image candidate is discarded" test ! -e "$dest"
  fi
else
  echo "  skip JPEG optimization (jpegoptim and jpegtran are unavailable)"
fi

# Recursive directory input over the staged real photos: the whole input
# directory is converted without naming files individually.
mkdir -p -- "$TMP/converted/recursive"
check "convert the real-sample directory with --recursive" \
  egomat convert -f webp --recursive -o "$TMP/converted/recursive" -- "$TMP/input"
recursive_count=0
for f in "$TMP/converted/recursive"/*.webp; do
  [ -f "$f" ] && recursive_count=$((recursive_count + 1))
done
check "recursive conversion produced one WebP per real photo" \
  test "$recursive_count" -eq "${#work_images[@]}"
check "recursive WebP output is readable" \
  image_info "$(output_for "${work_images[0]}" "$TMP/converted/recursive" webp)"
check "recursive conversion left the real photos unchanged" \
  cmp -s "${work_images[0]}" "${snapshots[0]}"

for i in "${!images[@]}"; do
  check "original sample $((i + 1)) remains unchanged" \
    cmp -s "${images[$i]}" "${snapshots[$i]}"
done

echo
if [ "$fails" -eq 0 ]; then
  printf 'all %d real-image checks passed\n' "$checks"
  exit 0
fi
printf '%d of %d real-image checks failed\n' "$fails" "$checks"
exit 1

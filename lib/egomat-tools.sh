# shellcheck shell=bash
# egomat — backend discovery and thin wrappers around the imaging tools.

# ---------------------------------------------------------------------------
# ImageMagick / GraphicsMagick
# ---------------------------------------------------------------------------
_EGOMAT_MAGICK=""
_EGOMAT_MAGICK_PROBED=0

# Print the ImageMagick entry point ("magick" for IM7, "convert" for IM6).
# Returns non-zero when ImageMagick is not installed.
detect_magick() {
  if [ "$_EGOMAT_MAGICK_PROBED" -eq 0 ]; then
    _EGOMAT_MAGICK_PROBED=1
    if have magick; then
      _EGOMAT_MAGICK=magick
    elif have convert; then
      _EGOMAT_MAGICK=convert
    else
      _EGOMAT_MAGICK=""
    fi
  fi
  [ -n "$_EGOMAT_MAGICK" ] || return 1
  printf '%s\n' "$_EGOMAT_MAGICK"
}

# Run ImageMagick with the given arguments.
im() {
  local m
  m=$(detect_magick) || return 127
  if [ "$m" = magick ]; then
    magick "$@"
  else
    "$m" "$@"
  fi
}

# Print "WIDTH HEIGHT" for an image, or nothing when it cannot be read.
img_dims() {
  local f=$1 m out=""
  if m=$(detect_magick); then
    if [ "$m" = magick ]; then
      out=$(magick identify -format '%w %h' "$f" 2>/dev/null)
    else
      out=$(identify -format '%w %h' "$f" 2>/dev/null)
    fi
  fi
  if [ -z "$out" ] && have ffprobe; then
    out=$(ffprobe -v error -select_streams v:0 \
      -show_entries stream=width,height -of csv=p=0 "$f" 2>/dev/null)
    out=${out%%$'\n'*}
    out=${out//,/ }
  fi
  printf '%s\n' "$out"
}

# ---------------------------------------------------------------------------
# ffmpeg geometry helper
# ---------------------------------------------------------------------------

# Translate an ImageMagick-style geometry into an ffmpeg scale filter.
# Prints an empty line when the geometry cannot be expressed (callers then
# skip resizing rather than guessing).
ffmpeg_scale() {
  local g=${1-} w="" h="" force=0
  if [ -z "$g" ]; then
    printf '\n'
    return 0
  fi
  case $g in
    *'!'*) force=1; g=${g%'!'} ;;
  esac
  case $g in
    *[xX]*)
      w=${g%%[xX]*}
      h=${g#*[xX]}
      ;;
    *) w=$g; h="" ;;
  esac
  w=${w%%[!0-9]*}
  h=${h%%[!0-9]*}
  if [ -n "$w" ] && [ -n "$h" ]; then
    if [ "$force" -eq 1 ]; then
      printf 'scale=%s:%s\n' "$w" "$h"
    else
      printf 'scale=%s:%s:force_original_aspect_ratio=decrease\n' "$w" "$h"
    fi
  elif [ -n "$w" ]; then
    printf 'scale=%s:-2\n' "$w"
  elif [ -n "$h" ]; then
    printf 'scale=-2:%s\n' "$h"
  else
    printf '\n'
  fi
}

# ---------------------------------------------------------------------------
# Tool inventory
# ---------------------------------------------------------------------------

# True when at least one image optimizer is available.
optimizer_available() {
  have oxipng && return 0
  have optipng && return 0
  have zopflipng && return 0
  have pngquant && return 0
  have jpegoptim && return 0
  have jpegtran && return 0
  have gifsicle && return 0
  have svgo && return 0
  have cwebp && return 0
  have webpmux && return 0
  detect_magick >/dev/null 2>&1 && return 0
  return 1
}

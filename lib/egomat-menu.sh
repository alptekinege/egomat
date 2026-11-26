# shellcheck shell=bash
# egomat — context-menu entry points and the interactive assistant.
# The .desktop actions in share/ all end up calling `egomat menu ...`.

usage() {
  cat <<EOF
$EGOMAT_NAME $EGOMAT_VERSION — convert and optimise images from the command
line or from your file manager's right-click menu.

Usage:
  $EGOMAT_NAME convert [options] FILE...
  $EGOMAT_NAME optimize [options] FILE...
  $EGOMAT_NAME resize GEOMETRY [options] FILE...
  $EGOMAT_NAME info FILE...
  $EGOMAT_NAME formats
  $EGOMAT_NAME assistant [FILE...]
  $EGOMAT_NAME menu ACTION [PARAM] FILE...
  $EGOMAT_NAME install [options]
  $EGOMAT_NAME uninstall [options]
  $EGOMAT_NAME version | help

Convert options:
  -f, --format FMT     target format: $EGOMAT_TARGETS
  -q, --quality N      quality 1-100 for lossy formats
                       (defaults: jpg 88, webp 82, avif 60)
  -r, --resize GEOM    resize; e.g. 1920, 1920x1080, 800x800!
                       (full ImageMagick geometry syntax)
  -o, --outdir DIR     write results into DIR (default: next to the source)
  -s, --suffix SUFFIX  add SUFFIX to the new file name
      --overwrite      replace an existing output file
      --keep-metadata  do not strip EXIF/ICC data
      --delete-source  remove the source after a successful conversion

Optimize options:
  -l, --level LEVEL    light | balanced | aggressive  (default: balanced)
  -o, --outdir DIR     write optimised copies into DIR instead of in place
  -s, --suffix SUFFIX  write to a new name instead of in place
      --backup         keep a copy of the original as FILE.egomat-orig
      --force          replace the file even when nothing got smaller

Resize options:
  -o, --outdir DIR     write into DIR
  -s, --suffix SUFFIX  file-name suffix (default: -resized)
      --overwrite      replace an existing output file

Menu actions (used by the desktop entries):
  convert FORMAT | optimize LEVEL | resize GEOMETRY | info
  The words "custom" (FORMAT), "ask" (LEVEL) and "ask" (GEOMETRY) open a
  prompt instead.

Global options (before the command, or after it):
  --quiet   --verbose   --ui=none|auto|dialog

Conversion needs ImageMagick, ffmpeg, cwebp/avifenc or img2pdf.
Optimization needs any of oxipng, optipng, pngquant, jpegoptim, gifsicle,
svgo, cwebp/webpmux or ImageMagick. Run "$EGOMAT_NAME formats" to see what
this machine has.
EOF
}

# ---------------------------------------------------------------------------
# menu — what the .desktop actions run
# ---------------------------------------------------------------------------
_menu_convert_custom() {
  local fmt
  fmt=$(ui_prompt "$EGOMAT_NAME" "Target format ($EGOMAT_TARGETS):" "webp") || exit 0
  [ -n "$fmt" ] || exit 0
  fmt=$(norm_format "$fmt")
  if ! format_supported "$fmt"; then
    ui_error "$EGOMAT_NAME" "Unsupported format: $fmt"
    exit 1
  fi
  cmd_convert -f "$fmt" -- "$@"
}

_menu_resize_ask() {
  local geo
  geo=$(ui_prompt "$EGOMAT_NAME" "New size (e.g. 1920, 1920x1080, 800x800!):" "") || exit 0
  [ -n "$geo" ] || exit 0
  if ! check_geometry "$geo"; then
    ui_error "$EGOMAT_NAME" "Invalid size: $geo"
    exit 1
  fi
  cmd_resize "$geo" -- "$@"
}

cmd_menu() {
  local verb=${1-}
  [ $# -gt 0 ] && shift
  [ -n "$verb" ] || die "menu: no action given (try '$EGOMAT_NAME help')"

  local param=""
  case $verb in
    convert|optimize|resize)
      param=${1-}
      [ $# -gt 0 ] && shift
      ;;
  esac

  if [ $# -eq 0 ]; then
    ui_error "$EGOMAT_NAME" "No files selected."
    exit 1
  fi

  case $verb in
    convert)
      case $param in
        '')
          ui_error "$EGOMAT_NAME" "No target format given."
          exit 1
          ;;
        custom)
          _menu_convert_custom "$@"
          ;;
        *)
          param=$(norm_format "$param")
          if ! format_supported "$param"; then
            ui_error "$EGOMAT_NAME" "Unsupported format: $param"
            exit 1
          fi
          cmd_convert -f "$param" -- "$@"
          ;;
      esac
      ;;
    optimize)
      local level
      if [ "$param" = ask ] || [ -z "$param" ]; then
        level=balanced
        level=$(ui_choose "$EGOMAT_NAME" "How hard should I squeeze?" \
          light "Light — lossless, no quality change" \
          balanced "Balanced — small, invisible quality loss" \
          aggressive "Aggressive — largest savings") || exit 0
      else
        level=$(norm_level "$param")
      fi
      if [ -z "$level" ]; then
        ui_error "$EGOMAT_NAME" "Unknown optimization level: $param"
        exit 1
      fi
      cmd_optimize -l "$level" -- "$@"
      ;;
    resize)
      if [ -z "$param" ] || [ "$param" = ask ]; then
        _menu_resize_ask "$@"
      else
        if ! check_geometry "$param"; then
          ui_error "$EGOMAT_NAME" "Invalid size: $param"
          exit 1
        fi
        cmd_resize "$param" -- "$@"
      fi
      ;;
    info)
      cmd_info -- "$@"
      ;;
    *)
      die "menu: unknown action: $verb"
      ;;
  esac
}

# ---------------------------------------------------------------------------
# assistant — the file-manager wizard
# ---------------------------------------------------------------------------
cmd_assistant() {
  if ! have kdialog && ! have zenity; then
    die "assistant: needs kdialog or zenity. Use '$EGOMAT_NAME help' for the command line."
  fi
  [ "${1-}" = "--" ] && shift

  local -a files=()
  local line listing action fmt geo

  if [ $# -gt 0 ]; then
    files=("$@")
  else
    listing=$(ui_pick_files) || exit 0
    [ -n "$listing" ] || exit 0
    while IFS= read -r line; do
      [ -n "$line" ] && files+=("$line")
    done <<<"$listing"
    [ ${#files[@]} -gt 0 ] || exit 0
  fi

  action=$(ui_choose "$EGOMAT_NAME" "What should I do with ${#files[@]} file(s)?" \
    convert-webp "Convert to WebP" \
    convert-avif "Convert to AVIF" \
    convert-jpeg "Convert to JPEG" \
    convert-png "Convert to PNG" \
    convert-gif "Convert to GIF" \
    convert-pdf "Convert to PDF" \
    convert-custom "Convert to…" \
    resize "Resize…" \
    optimize-light "Optimize: light (lossless)" \
    optimize-balanced "Optimize: balanced" \
    optimize-aggressive "Optimize: aggressive" \
    info "Show image details") || exit 0
  [ -n "$action" ] || exit 0

  case $action in
    convert-webp)   cmd_convert -f webp -- "${files[@]}" ;;
    convert-avif)   cmd_convert -f avif -- "${files[@]}" ;;
    convert-jpeg)   cmd_convert -f jpg  -- "${files[@]}" ;;
    convert-png)    cmd_convert -f png  -- "${files[@]}" ;;
    convert-gif)    cmd_convert -f gif  -- "${files[@]}" ;;
    convert-pdf)    cmd_convert -f pdf  -- "${files[@]}" ;;
    convert-custom) _menu_convert_custom "${files[@]}" ;;
    resize)         _menu_resize_ask "${files[@]}" ;;
    optimize-light) cmd_optimize -l light -- "${files[@]}" ;;
    optimize-balanced) cmd_optimize -l balanced -- "${files[@]}" ;;
    optimize-aggressive) cmd_optimize -l aggressive -- "${files[@]}" ;;
    info)           cmd_info -- "${files[@]}" ;;
    *)              die "assistant: unknown action: $action" ;;
  esac
}

# ---------------------------------------------------------------------------
# formats — what this machine can actually do
# ---------------------------------------------------------------------------
cmd_formats() {
  printf 'Target formats: %s\n\n' "$EGOMAT_TARGETS"

  printf 'Conversion backends:\n'
  _fmt_row magick          'ImageMagick 7 (recommended)'
  _fmt_row convert         'ImageMagick 6'
  _fmt_row ffmpeg          'ffmpeg'
  _fmt_row cwebp           'WebP encoder'
  _fmt_row avifenc         'AVIF encoder'
  _fmt_row img2pdf         'PDF from JPEG/PNG'
  _fmt_row rsvg-convert    'SVG renderer (librsvg)'
  _fmt_row inkscape        'SVG renderer (Inkscape)'
  _fmt_row resvg           'SVG renderer (resvg)'

  printf '\nOptimisation backends:\n'
  _fmt_row oxipng          'PNG, lossless'
  _fmt_row optipng         'PNG, lossless'
  _fmt_row zopflipng       'PNG, lossless'
  _fmt_row pngquant        'PNG, lossy quantiser'
  _fmt_row jpegoptim       'JPEG'
  _fmt_row jpegtran        'JPEG, lossless'
  _fmt_row gifsicle        'GIF'
  _fmt_row svgo            'SVG'
  _fmt_row webpmux         'WebP metadata'
  _fmt_row dwebp           'WebP decoder'

  printf '\nDialogs:\n'
  _fmt_row kdialog         'KDE dialogs'
  _fmt_row zenity          'GTK dialogs'
  _fmt_row notify-send     'Desktop notifications'
}

_fmt_row() {
  local tool=$1 note=$2 mark=no
  if have "$tool"; then mark=yes; fi
  printf '  %-14s %-3s %s\n' "$tool" "$mark" "$note"
}

cmd_install() {
  if [ ! -f "$EGOMAT_ROOT/install.sh" ]; then
    die "install: $EGOMAT_ROOT/install.sh is missing"
  fi
  exec "$EGOMAT_ROOT/install.sh" "$@"
}

cmd_uninstall() {
  if [ ! -f "$EGOMAT_ROOT/uninstall.sh" ]; then
    die "uninstall: $EGOMAT_ROOT/uninstall.sh is missing"
  fi
  exec "$EGOMAT_ROOT/uninstall.sh" "$@"
}

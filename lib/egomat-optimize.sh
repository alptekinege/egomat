# shellcheck shell=bash
# egomat — image optimisation engine.
#
# Three levels, applied per format:
#
#   light       never touches pixel data; strips metadata and re-packs the
#               bitstream losslessly (JPEG Huffman tables, PNG deflate, ...)
#   balanced    small, visually invisible quality loss
#   aggressive  larger savings, still reviewable by eye
#
# Every file is optimised into a temporary copy first and only replaces the
# original when the result is actually smaller.

norm_level() {
  case $(printf '%s' "${1-}" | tr 'A-Z' 'a-z') in
    light|lossless|fast)         printf 'light\n' ;;
    balanced|normal|default|mid) printf 'balanced\n' ;;
    aggressive|max|maximum|strong|heavy) printf 'aggressive\n' ;;
    *)                           printf '' ;;
  esac
}

# ---------------------------------------------------------------------------
# Per-format passes. Every one of them works on the temporary copy in place
# and returns 0 even when the tool is missing (the file simply stays as it is).
# ---------------------------------------------------------------------------

EGOMAT_TEMP_FILES=()
EGOMAT_TEMP_PATH=""

egomat_temp_file() {
  local dir=$1 tag=$2 suffix=${3-} template
  case $dir in -*) dir=./$dir ;; esac
  template="$dir/.egomat-${tag}.XXXXXXXX"
  if [ -n "$suffix" ]; then
    EGOMAT_TEMP_PATH=$(mktemp --suffix=".$suffix" "$template") || return 1
  else
    EGOMAT_TEMP_PATH=$(mktemp "$template") || return 1
  fi
  EGOMAT_TEMP_FILES+=("$EGOMAT_TEMP_PATH")
}

egomat_cleanup_temps() {
  local path
  for path in "${EGOMAT_TEMP_FILES[@]}"; do
    rm -f -- "$path"
  done
}

egomat_forget_temp() {
  local remove=$1 path
  local -a keep=()
  for path in "${EGOMAT_TEMP_FILES[@]}"; do
    [ "$path" = "$remove" ] || keep+=("$path")
  done
  EGOMAT_TEMP_FILES=("${keep[@]}")
}

egomat_remove_temp() {
  local path=$1
  if rm -f -- "$path"; then
    egomat_forget_temp "$path"
  else
    return 1
  fi
}

egomat_install_temp_traps() {
  trap 'egomat_cleanup_temps' EXIT
  trap 'egomat_cleanup_temps; exit 129' HUP
  trap 'egomat_cleanup_temps; exit 130' INT
  trap 'egomat_cleanup_temps; exit 143' TERM
}

image_format() {
  case $1 in
    jpg|jpeg) printf 'JPEG\n' ;;
    tif|tiff) printf 'TIFF\n' ;;
    *) printf '%s\n' "$1" | tr 'a-z' 'A-Z' ;;
  esac
}

image_readable() {
  local f=$1 ext=${2-} m dims input
  input=$f
  [ -z "$ext" ] || input="$(image_format "$ext"):$f"
  if m=$(detect_magick); then
    if [ "$m" = magick ]; then
      if dims=$(magick identify -quiet -format '%w %h' "$input" 2>/dev/null); then
        [[ $dims =~ ^[0-9]+[[:space:]]+[0-9]+ ]] && return 0
      fi
    elif have identify; then
      if dims=$(identify -quiet -format '%w %h' "$input" 2>/dev/null); then
        [[ $dims =~ ^[0-9]+[[:space:]]+[0-9]+ ]] && return 0
      fi
    else
      if dims=$(im "$input" -format '%w %h' info: 2>/dev/null); then
        [[ $dims =~ ^[0-9]+[[:space:]]+[0-9]+ ]] && return 0
      fi
    fi
  fi

  if have ffprobe; then
    dims=$(ffprobe -v error -select_streams v:0 \
      -show_entries stream=width,height -of csv=p=0 "$f" 2>/dev/null)
    dims=${dims%%$'\n'*}
    dims=${dims//,/ }
    [[ $dims =~ ^[0-9]+[[:space:]]+[0-9]+$ ]] && return 0
  fi

  if [ "$(file_ext "$f")" = svg ] && have svgo; then
    svgo -i "$f" -o /dev/null --multipass >/dev/null 2>&1
    return $?
  fi
  return 1
}

_pngquant() {
  local f=$1 range=$2 o
  have pngquant || return 0
  egomat_temp_file "$(dirname_of "$f")" pq png || return 0
  o=$EGOMAT_TEMP_PATH
  if pngquant --force --skip-if-larger --strip --speed 1 \
      --quality="$range" --output "$o" "$f" >/dev/null 2>&1; then
    if [ -s "$o" ]; then mv -f -- "$o" "$f"; fi
  fi
  egomat_remove_temp "$o"
  return 0
}

_png_recompress() {
  local f=$1 level=$2 o
  if have oxipng; then
    case $level in
      aggressive) oxipng -q -o max --strip all  "$f" >/dev/null 2>&1 ;;
      balanced)   oxipng -q -o 4   --strip safe "$f" >/dev/null 2>&1 ;;
      *)          oxipng -q -o 2   --strip safe "$f" >/dev/null 2>&1 ;;
    esac
    return 0
  fi
  if have optipng; then
    optipng -quiet -o2 -strip all "$f" >/dev/null 2>&1
    return 0
  fi
  if have zopflipng; then
    egomat_temp_file "$(dirname_of "$f")" zp png || return 0
    o=$EGOMAT_TEMP_PATH
    if zopflipng -y -q "$f" "$o" >/dev/null 2>&1 && [ -s "$o" ]; then
      mv -f -- "$o" "$f"
    fi
    egomat_remove_temp "$o"
    return 0
  fi
  return 0
}

_opt_png() {
  local f=$1 level=$2
  case $level in
    aggressive) _pngquant "$f" 50-80 ;;
    balanced)   _pngquant "$f" 70-95 ;;
  esac
  _png_recompress "$f" "$level"
}

_opt_jpeg() {
  local f=$1 level=$2 q="" o ext
  ext=$(file_ext "$f")
  case $level in
    aggressive) q=72 ;;
    balanced)   q=85 ;;
  esac
  if have jpegoptim; then
    if [ -n "$q" ]; then
      jpegoptim --strip-all --all-progressive --preserve --quiet \
        --max="$q" "$f" >/dev/null 2>&1
    else
      jpegoptim --strip-all --all-progressive --preserve --quiet \
        "$f" >/dev/null 2>&1
    fi
    return 0
  fi
  if have jpegtran; then
    egomat_temp_file "$(dirname_of "$f")" jt "$ext" || return 0
    o=$EGOMAT_TEMP_PATH
    if jpegtran -optimize -progressive -copy none -outfile "$o" "$f" >/dev/null 2>&1 &&
       [ -s "$o" ]; then
      mv -f -- "$o" "$f"
    fi
    egomat_remove_temp "$o"
    return 0
  fi
  return 0
}

_opt_webp() {
  local f=$1 level=$2 q="" o png
  case $level in
    aggressive) q=68 ;;
    balanced)   q=82 ;;
  esac

  if [ -z "$q" ]; then
    # Light: strip metadata only, pixels untouched.
    if have webpmux; then
      egomat_temp_file "$(dirname_of "$f")" wm webp || return 0
      o=$EGOMAT_TEMP_PATH
      if webpmux -strip all "$f" -o "$o" >/dev/null 2>&1 && [ -s "$o" ]; then
        mv -f -- "$o" "$f"
      fi
      egomat_remove_temp "$o"
    fi
    return 0
  fi

  have cwebp && have dwebp || return 0
  egomat_temp_file "$(dirname_of "$f")" wp-png png || return 0
  png=$EGOMAT_TEMP_PATH
  if ! egomat_temp_file "$(dirname_of "$f")" wp-webp webp; then
    egomat_remove_temp "$png"
    return 0
  fi
  o=$EGOMAT_TEMP_PATH
  if dwebp -quiet "$f" -o "$png" >/dev/null 2>&1; then
    if cwebp -quiet -mt -q "$q" "$png" -o "$o" >/dev/null 2>&1 && [ -s "$o" ]; then
      mv -f -- "$o" "$f"
    fi
  fi
  egomat_remove_temp "$png"
  egomat_remove_temp "$o"
  return 0
}

_opt_gif() {
  local f=$1 level=$2 o
  have gifsicle || return 0
  egomat_temp_file "$(dirname_of "$f")" gi gif || return 0
  o=$EGOMAT_TEMP_PATH
  case $level in
    aggressive) gifsicle -O3 --careful --lossy=80 "$f" -o "$o" >/dev/null 2>&1 ;;
    *)          gifsicle -O3 --careful "$f" -o "$o" >/dev/null 2>&1 ;;
  esac
  if [ -s "$o" ]; then mv -f -- "$o" "$f"; fi
  egomat_remove_temp "$o"
  return 0
}

_opt_svg() {
  local f=$1 o
  have svgo || return 0
  egomat_temp_file "$(dirname_of "$f")" sv svg || return 0
  o=$EGOMAT_TEMP_PATH
  if svgo -i "$f" -o "$o" --multipass >/dev/null 2>&1 && [ -s "$o" ]; then
    mv -f -- "$o" "$f"
  fi
  egomat_remove_temp "$o"
  return 0
}

_opt_generic() {
  local f=$1 level=$2 ext=$3 q format o
  case $level in
    aggressive) q=70 ;;
    balanced)   q=85 ;;
    *)          q=95 ;;
  esac
  detect_magick >/dev/null 2>&1 || return 0
  if [ -n "$ext" ]; then
    format=$(image_format "$ext")
  else
    format=$(im "$f" -format '%m' info: 2>/dev/null) || return 0
  fi
  [ -n "$format" ] || return 0
  egomat_temp_file "$(dirname_of "$f")" gen "$ext" || return 0
  o=$EGOMAT_TEMP_PATH
  if [ "$format" = TIFF ]; then
    im "$format:$f" -strip -compress lzw "$format:$o" >/dev/null 2>&1
  else
    im "$format:$f" -strip -quality "$q" "$format:$o" >/dev/null 2>&1
  fi
  if [ -s "$o" ]; then mv -f -- "$o" "$f"; fi
  egomat_remove_temp "$o"
  return 0
}

optimize_apply() {
  local f=$1 ext=$2 level=$3
  case $ext in
    png)      _opt_png "$f" "$level" ;;
    jpg|jpeg) _opt_jpeg "$f" "$level" ;;
    webp)     _opt_webp "$f" "$level" ;;
    gif)      _opt_gif "$f" "$level" ;;
    svg)      _opt_svg "$f" "$level" ;;
    *)        _opt_generic "$f" "$level" "$ext" ;;
  esac
  return 0
}

# ---------------------------------------------------------------------------
# One file
# ---------------------------------------------------------------------------
backup_of() {
  local src=$1 b stage
  if ! egomat_temp_file "$(dirname_of "$src")" backup; then
    log_error "cannot create backup for: $src"
    return 1
  fi
  stage=$EGOMAT_TEMP_PATH
  if ! cp -p -- "$src" "$stage"; then
    egomat_remove_temp "$stage"
    log_error "cannot create backup for: $src"
    return 1
  fi
  while :; do
    b=$(unique_path "$src.egomat-orig") || return 1
    if ln -- "$stage" "$b" 2>/dev/null; then
      break
    fi
    if [ ! -e "$b" ] && [ ! -L "$b" ]; then
      egomat_remove_temp "$stage"
      log_error "cannot create backup: $b"
      return 1
    fi
  done
  egomat_remove_temp "$stage"
  log_verbose "backup: $b"
}

optimize_one() {
  local src=$1
  local level=$OPT_LEVEL
  local ext dir base stem sfx target work before after

  if [ ! -f "$src" ]; then
    log_error "not a file: $src"
    EGOMAT_FAILED=$((EGOMAT_FAILED + 1))
    return 1
  fi

  ext=$(file_ext "$src")
  dir=$(dirname_of "$src")
  base=${src##*/}
  stem=$base
  case $stem in *.*) stem=${stem%.*} ;; esac
  sfx=${base#"$stem"}

  if [ -z "$OPT_OUTDIR" ] && [ -z "$OPT_SUFFIX" ]; then
    target=$src
  else
    local od=${OPT_OUTDIR:-$dir}
    target=$(unique_path "$od/$stem$OPT_SUFFIX$sfx")
    if ! mkdir -p -- "$od" 2>/dev/null; then
      log_error "cannot create directory: $od"
      EGOMAT_FAILED=$((EGOMAT_FAILED + 1))
      return 1
    fi
  fi

  if ! egomat_temp_file "$dir" opt "$ext"; then
    log_error "cannot create temporary file for: $src"
    EGOMAT_FAILED=$((EGOMAT_FAILED + 1))
    return 1
  fi
  work=$EGOMAT_TEMP_PATH
  if ! cp -p -- "$src" "$work"; then
    log_error "cannot read: $src"
    EGOMAT_FAILED=$((EGOMAT_FAILED + 1))
    return 1
  fi

  before=$(fsize "$src")
  optimize_apply "$work" "$ext" "$level"

  after=$(fsize "$work")
  if [ "$after" -eq 0 ]; then
    egomat_remove_temp "$work"
    log_error "optimization produced an empty file: $src"
    EGOMAT_FAILED=$((EGOMAT_FAILED + 1))
    return 1
  fi

  if [ "$after" -ge "$before" ] && [ "$OPT_FORCE" -ne 1 ]; then
    egomat_remove_temp "$work"
    if [ "$target" = "$src" ]; then
      log_info "$(basename -- "$src") is already optimal ($(human "$before"))"
    else
      log_info "$(basename -- "$src") was not written (result is not smaller)"
    fi
    EGOMAT_OPTIMIZED=$((EGOMAT_OPTIMIZED + 1))
    return 0
  fi

  if ! image_readable "$work" "$ext"; then
    egomat_remove_temp "$work"
    log_error "cannot verify optimized image is readable: $src"
    EGOMAT_FAILED=$((EGOMAT_FAILED + 1))
    return 1
  fi

  if [ "$target" = "$src" ]; then
    if [ "$OPT_BACKUP" -eq 1 ] && ! backup_of "$src"; then
      egomat_remove_temp "$work"
      EGOMAT_FAILED=$((EGOMAT_FAILED + 1))
      return 1
    fi
    if ! mv -f -- "$work" "$target"; then
      egomat_remove_temp "$work"
      log_error "cannot write: $target"
      EGOMAT_FAILED=$((EGOMAT_FAILED + 1))
      return 1
    fi
    egomat_forget_temp "$work"
    track_sizes "$before" "$after"
    EGOMAT_OPTIMIZED=$((EGOMAT_OPTIMIZED + 1))
    log_info "$(basename -- "$src") $before -> $after bytes ($(human "$before") -> $(human "$after"))"
  else
    if [ "$OPT_BACKUP" -eq 1 ] && ! backup_of "$src"; then
      egomat_remove_temp "$work"
      EGOMAT_FAILED=$((EGOMAT_FAILED + 1))
      return 1
    fi
    if ! mv -f -- "$work" "$target"; then
      egomat_remove_temp "$work"
      log_error "cannot write: $target"
      EGOMAT_FAILED=$((EGOMAT_FAILED + 1))
      return 1
    fi
    egomat_forget_temp "$work"
    track_sizes "$before" "$after"
    EGOMAT_OPTIMIZED=$((EGOMAT_OPTIMIZED + 1))
    log_info "$(basename -- "$src") -> $target ($(human "$before") -> $(human "$after"))"
  fi
  return 0
}

# ---------------------------------------------------------------------------
# Command
# ---------------------------------------------------------------------------
cmd_optimize() {
  OPT_LEVEL=balanced
  OPT_OUTDIR=""
  OPT_SUFFIX=""
  OPT_BACKUP=0
  OPT_FORCE=0
  local -a files=()

  while [ $# -gt 0 ]; do
    case $1 in
      -l|--level)
        [ $# -ge 2 ] || die "option $1 needs a value"
        OPT_LEVEL=$(norm_level "$2"); shift 2 ;;
      --level=*)
        OPT_LEVEL=$(norm_level "${1#*=}"); shift ;;
      -o|--outdir|--output-dir)
        [ $# -ge 2 ] || die "option $1 needs a value"
        OPT_OUTDIR=$2; shift 2 ;;
      --outdir=*|--output-dir=*)
        OPT_OUTDIR=${1#*=}; shift ;;
      -s|--suffix)
        [ $# -ge 2 ] || die "option $1 needs a value"
        OPT_SUFFIX=$2; shift 2 ;;
      --suffix=*)
        OPT_SUFFIX=${1#*=}; shift ;;
      --quiet)  EGOMAT_LOG_LEVEL=quiet; shift ;;
      --verbose) EGOMAT_LOG_LEVEL=verbose; shift ;;
      --backup) OPT_BACKUP=1; shift ;;
      --force)  OPT_FORCE=1; shift ;;
      --)
        shift
        while [ $# -gt 0 ]; do files+=("$1"); shift; done
        ;;
      -*) die "optimize: unknown option: $1" ;;
      *)  files+=("$1"); shift ;;
    esac
  done

  [ -n "$OPT_LEVEL" ] ||
    die "optimize: --level must be one of: light, balanced, aggressive"
  [ ${#files[@]} -gt 0 ] || die "optimize: no input files"

  optimizer_available ||
    die "optimize: no image optimizer found. Install one of oxipng, optipng, pngquant, jpegoptim, gifsicle, svgo, cwebp/webpmux or ImageMagick."

  local f rc=0
  egomat_install_temp_traps
  for f in "${files[@]}"; do
    optimize_one "$f" || rc=1
  done
  finish "$rc"
}

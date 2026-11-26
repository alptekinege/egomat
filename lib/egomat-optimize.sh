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

_pngquant() {
  local f=$1 range=$2 o
  have pngquant || return 0
  o="$(dirname_of "$f")/.egomat-pq-$$-$(basename -- "$f")"
  if pngquant --force --skip-if-larger --strip --speed 1 \
      --quality="$range" --output "$o" "$f" >/dev/null 2>&1; then
    if [ -s "$o" ]; then mv -f -- "$o" "$f"; fi
  fi
  rm -f -- "$o"
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
    o="$(dirname_of "$f")/.egomat-zp-$$-$(basename -- "$f")"
    if zopflipng -y -q "$f" "$o" >/dev/null 2>&1 && [ -s "$o" ]; then
      mv -f -- "$o" "$f"
    fi
    rm -f -- "$o"
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
  local f=$1 level=$2 q="" o
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
    o="$(dirname_of "$f")/.egomat-jt-$$-$(basename -- "$f")"
    if jpegtran -optimize -progressive -copy none -outfile "$o" "$f" >/dev/null 2>&1 &&
       [ -s "$o" ]; then
      mv -f -- "$o" "$f"
    fi
    rm -f -- "$o"
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
      o="$(dirname_of "$f")/.egomat-wm-$$-$(basename -- "$f")"
      if webpmux -strip all "$f" -o "$o" >/dev/null 2>&1 && [ -s "$o" ]; then
        mv -f -- "$o" "$f"
      fi
      rm -f -- "$o"
    fi
    return 0
  fi

  have cwebp && have dwebp || return 0
  png="$(dirname_of "$f")/.egomat-wp-$$.png"
  o="$(dirname_of "$f")/.egomat-wp-$$.webp"
  if dwebp -quiet "$f" -o "$png" >/dev/null 2>&1; then
    if cwebp -quiet -mt -q "$q" "$png" -o "$o" >/dev/null 2>&1 && [ -s "$o" ]; then
      mv -f -- "$o" "$f"
    fi
  fi
  rm -f -- "$png" "$o"
  return 0
}

_opt_gif() {
  local f=$1 level=$2 o
  have gifsicle || return 0
  o="$(dirname_of "$f")/.egomat-gi-$$-$(basename -- "$f")"
  case $level in
    aggressive) gifsicle -O3 --careful --lossy=80 "$f" -o "$o" >/dev/null 2>&1 ;;
    *)          gifsicle -O3 --careful "$f" -o "$o" >/dev/null 2>&1 ;;
  esac
  if [ -s "$o" ]; then mv -f -- "$o" "$f"; fi
  rm -f -- "$o"
  return 0
}

_opt_svg() {
  local f=$1 o
  have svgo || return 0
  o="$(dirname_of "$f")/.egomat-sv-$$-$(basename -- "$f")"
  if svgo -i "$f" -o "$o" --multipass >/dev/null 2>&1 && [ -s "$o" ]; then
    mv -f -- "$o" "$f"
  fi
  rm -f -- "$o"
  return 0
}

_opt_generic() {
  local f=$1 level=$2 q ext o
  case $level in
    aggressive) q=70 ;;
    balanced)   q=85 ;;
    *)          q=95 ;;
  esac
  detect_magick >/dev/null 2>&1 || return 0
  ext=$(file_ext "$f")
  o="$(dirname_of "$f")/.egomat-gen-$$-$(basename -- "$f")"
  if [ "$ext" = tif ] || [ "$ext" = tiff ]; then
    im "$f" -strip -compress lzw "$o" >/dev/null 2>&1
  else
    im "$f" -strip -quality "$q" "$o" >/dev/null 2>&1
  fi
  if [ -s "$o" ]; then mv -f -- "$o" "$f"; fi
  rm -f -- "$o"
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
    *)        _opt_generic "$f" "$level" ;;
  esac
  return 0
}

# ---------------------------------------------------------------------------
# One file
# ---------------------------------------------------------------------------
backup_of() {
  local src=$1 b
  b=$(unique_path "$src.egomat-orig")
  cp -p -- "$src" "$b" && log_verbose "backup: $b"
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

  work="$(dirname_of "$src")/.egomat-opt-$$-$base"
  if ! cp -p -- "$src" "$work"; then
    log_error "cannot read: $src"
    EGOMAT_FAILED=$((EGOMAT_FAILED + 1))
    return 1
  fi

  before=$(fsize "$src")
  optimize_apply "$work" "$ext" "$level"

  after=$(fsize "$work")
  if [ "$after" -eq 0 ]; then
    rm -f -- "$work"
    log_error "optimization produced an empty file: $src"
    EGOMAT_FAILED=$((EGOMAT_FAILED + 1))
    return 1
  fi

  if [ "$target" = "$src" ]; then
    if [ "$after" -lt "$before" ] || [ "$OPT_FORCE" -eq 1 ]; then
      if [ "$OPT_BACKUP" -eq 1 ]; then backup_of "$src"; fi
      if ! mv -f -- "$work" "$target"; then
        rm -f -- "$work"
        log_error "cannot write: $target"
        EGOMAT_FAILED=$((EGOMAT_FAILED + 1))
        return 1
      fi
      track_sizes "$before" "$after"
      EGOMAT_OPTIMIZED=$((EGOMAT_OPTIMIZED + 1))
      log_info "$(basename -- "$src") $before -> $after bytes ($(human "$before") -> $(human "$after"))"
    else
      rm -f -- "$work"
      EGOMAT_OPTIMIZED=$((EGOMAT_OPTIMIZED + 1))
      log_info "$(basename -- "$src") is already optimal ($(human "$before"))"
    fi
  else
    if [ "$OPT_BACKUP" -eq 1 ]; then backup_of "$src"; fi
    if ! mv -f -- "$work" "$target"; then
      rm -f -- "$work"
      log_error "cannot write: $target"
      EGOMAT_FAILED=$((EGOMAT_FAILED + 1))
      return 1
    fi
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
  for f in "${files[@]}"; do
    optimize_one "$f" || rc=1
  done
  finish "$rc"
}

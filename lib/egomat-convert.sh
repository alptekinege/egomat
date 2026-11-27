# shellcheck shell=bash
# egomat — conversion engine.

EGOMAT_TARGETS="png jpg webp avif gif bmp tiff ico pdf"

norm_format() {
  local f
  f=$(printf '%s' "${1-}" | tr 'A-Z' 'a-z')
  f=${f#.}
  case $f in
    jpeg) f=jpg ;;
    tif)  f=tiff ;;
  esac
  printf '%s\n' "$f"
}

format_supported() {
  case " $EGOMAT_TARGETS " in
    *" $1 "*) return 0 ;;
  esac
  return 1
}

# Accept ImageMagick geometry: 1920, 1920x1080, 800x800!, 1920x>, x1080 ...
check_geometry() {
  local g=${1-} allowed='^[0-9xX!<>^%]+$'
  [[ $g =~ $allowed ]] || return 1
  case $g in x|X) return 1 ;; esac
}

# ---------------------------------------------------------------------------
# Backends. Each returns 0 on success and leaves a complete file at $2.
# ---------------------------------------------------------------------------

# Rasterise an SVG with a real renderer (better than ImageMagick's fallback).
rt_rasterize_svg() {
  local src=$1 out=$2 w=""
  case ${OPT_RESIZE-} in
    [0-9]*) w=${OPT_RESIZE%%[!0-9]*} ;;
  esac
  if have rsvg-convert; then
    if [ -n "$w" ]; then
      rsvg-convert -w "$w" -o "$out" "$src" >/dev/null 2>&1 && return 0
    else
      rsvg-convert -o "$out" "$src" >/dev/null 2>&1 && return 0
    fi
  fi
  if have inkscape; then
    inkscape "$src" --export-type=png --export-filename="$out" >/dev/null 2>&1 && return 0
  fi
  if have resvg; then
    resvg "$src" "$out" >/dev/null 2>&1 && return 0
  fi
  return 1
}

rt_try_im() {
  local src=$1 out=$2 fmt=$3
  local -a a=()
  detect_magick >/dev/null 2>&1 || return 1
  rm -f -- "$out" 2>/dev/null

  # Still formats get the first frame only, so exactly one file comes out.
  case $fmt in
    png|jpg|bmp|tiff|ico|pdf) a+=("${src}[0]") ;;
    *)                        a+=("$src") ;;
  esac
  # Formats without an alpha channel need the transparency flattened.
  case $fmt in
    jpg|bmp|pdf) a+=(-background white -alpha remove -alpha off) ;;
  esac
  if [ -n "${OPT_RESIZE-}" ]; then
    a+=(-resize "$OPT_RESIZE")
  fi
  if [ "${OPT_KEEP_METADATA:-0}" -eq 0 ]; then
    a+=(-strip)
  fi
  case $fmt in
    jpg)  a+=(-quality "${OPT_QUALITY:-88}" -interlace Plane) ;;
    webp) a+=(-define 'webp:method=6' -quality "${OPT_QUALITY:-82}") ;;
    avif) a+=(-quality "${OPT_QUALITY:-60}") ;;
    png)  a+=(-define 'png:compression-level=9') ;;
    tiff) a+=(-compress lzw) ;;
    ico)  a+=(-define 'icon:auto-resize=256,128,64,48,32,16') ;;
    pdf)  a+=(-quality "${OPT_QUALITY:-90}") ;;
  esac
  a+=("$out")
  im "${a[@]}" >/dev/null 2>&1
}

rt_try_specialist() {
  local src=$1 out=$2 fmt=$3 ext
  ext=$(file_ext "$src")
  rm -f -- "$out" 2>/dev/null
  case $fmt in
    webp)
      [ -z "${OPT_RESIZE-}" ] || return 1
      case $ext in png|jpg|tiff) ;; *) return 1 ;; esac
      have cwebp || return 1
      cwebp -quiet -mt -q "${OPT_QUALITY:-82}" "$src" -o "$out" >/dev/null 2>&1
      ;;
    avif)
      [ -z "${OPT_RESIZE-}" ] || return 1
      case $ext in png|jpg) ;; *) return 1 ;; esac
      have avifenc || return 1
      avifenc --min 0 --max 63 --speed 6 "$src" "$out" >/dev/null 2>&1
      ;;
    pdf)
      have img2pdf || return 1
      img2pdf "$src" -o "$out" >/dev/null 2>&1
      ;;
    *)
      return 1
      ;;
  esac
}

rt_try_ffmpeg() {
  local src=$1 out=$2 fmt=$3 sc
  local -a a=()
  have ffmpeg || return 1
  rm -f -- "$out" 2>/dev/null
  a+=(-nostdin -hide_banner -loglevel error -y -i "$src")
  if [ "${OPT_KEEP_METADATA:-0}" -eq 0 ]; then
    a+=(-map_metadata -1)
  fi
  sc=$(ffmpeg_scale "${OPT_RESIZE-}")
  if [ -n "$sc" ]; then
    a+=(-vf "$sc")
  fi
  case $fmt in
    jpg)  a+=(-q:v 3) ;;
    webp) a+=(-c:v libwebp -quality "${OPT_QUALITY:-82}") ;;
    avif) a+=(-c:v libaom-av1 -crf 32 -b:v 0) ;;
    gif)  a+=(-loop 0) ;;
    png)  : ;;
    *)    return 1 ;;
  esac
  a+=("$out")
  ffmpeg "${a[@]}" >/dev/null 2>&1
}

# Convert $1 into $2 as $3, trying every backend that could do the job.
rt_convert() {
  local src=$1 out=$2 fmt=$3 cleanup="" ext raster
  ext=$(file_ext "$src")

  case $ext in
    svg|svgz)
      raster="$(dirname_of "$out")/.egomat-raster-$$.png"
      if rt_rasterize_svg "$src" "$raster"; then
        src=$raster
        cleanup=$raster
      else
        rm -f -- "$raster"
        log_verbose "no dedicated SVG renderer found, using ImageMagick"
      fi
      ;;
  esac

  local rc=1
  if rt_try_im "$src" "$out" "$fmt"; then
    rc=0
  elif rt_try_specialist "$src" "$out" "$fmt"; then
    rc=0
  elif rt_try_ffmpeg "$src" "$out" "$fmt"; then
    rc=0
  fi

  if [ -n "$cleanup" ]; then
    rm -f -- "$cleanup"
  fi
  return $rc
}

# ---------------------------------------------------------------------------
# One file
# ---------------------------------------------------------------------------
convert_one() {
  local src=$1
  local fmt=$OPT_FORMAT
  local dir base out tmp before after

  if [ ! -f "$src" ]; then
    log_error "not a file: $src"
    EGOMAT_FAILED=$((EGOMAT_FAILED + 1))
    return 1
  fi

  dir=${OPT_OUTDIR:-$(dirname_of "$src")}
  base=$(file_stem "$src")
  out="$dir/$base$OPT_SUFFIX.$fmt"

  # Never let a conversion destroy its own source.
  if [ "$out" = "$src" ] || { [ -e "$out" ] && [ "$out" -ef "$src" ]; }; then
    out="$dir/$base$OPT_SUFFIX-egomat.$fmt"
  fi
  if [ -e "$out" ] && [ "$OPT_OVERWRITE" -eq 0 ]; then
    out=$(unique_path "$out")
  fi
  if [ -e "$out" ] && [ "$out" -ef "$src" ]; then
    log_error "refusing to overwrite the source file: $src"
    EGOMAT_FAILED=$((EGOMAT_FAILED + 1))
    return 1
  fi

  if ! mkdir -p -- "$dir" 2>/dev/null; then
    log_error "cannot create directory: $dir"
    EGOMAT_FAILED=$((EGOMAT_FAILED + 1))
    return 1
  fi

  # Keep the target extension on the temporary file so encoders can sniff it.
  tmp="$(dirname_of "$out")/.egomat-$$-$base.$fmt"
  before=$(fsize "$src")

  if ! rt_convert "$src" "$tmp" "$fmt" || [ ! -s "$tmp" ]; then
    rm -f -- "$tmp"
    log_error "could not convert: $src"
    EGOMAT_FAILED=$((EGOMAT_FAILED + 1))
    return 1
  fi
  if ! mv -f -- "$tmp" "$out"; then
    rm -f -- "$tmp"
    log_error "cannot write: $out"
    EGOMAT_FAILED=$((EGOMAT_FAILED + 1))
    return 1
  fi

  after=$(fsize "$out")
  track_sizes "$before" "$after"
  EGOMAT_CONVERTED=$((EGOMAT_CONVERTED + 1))
  log_info "$(basename -- "$src") -> $out ($(human "$before") -> $(human "$after"))"

  if [ "$OPT_DELETE_SOURCE" -eq 1 ] && [ "$src" != "$out" ]; then
    rm -f -- "$src"
  fi
  return 0
}

# ---------------------------------------------------------------------------
# Command
# ---------------------------------------------------------------------------
cmd_convert() {
  OPT_FORMAT=""
  OPT_QUALITY=""
  OPT_RESIZE=""
  OPT_OUTDIR=""
  OPT_SUFFIX=""
  OPT_OVERWRITE=0
  OPT_KEEP_METADATA=0
  OPT_DELETE_SOURCE=0
  local -a files=()

  while [ $# -gt 0 ]; do
    case $1 in
      -f|--format)
        [ $# -ge 2 ] || die "option $1 needs a value"
        OPT_FORMAT=$(norm_format "$2"); shift 2 ;;
      --format=*)
        OPT_FORMAT=$(norm_format "${1#*=}"); shift ;;
      -q|--quality)
        [ $# -ge 2 ] || die "option $1 needs a value"
        OPT_QUALITY=$2; shift 2 ;;
      --quality=*)
        OPT_QUALITY=${1#*=}; shift ;;
      -r|--resize|--size)
        [ $# -ge 2 ] || die "option $1 needs a value"
        OPT_RESIZE=$2; shift 2 ;;
      --resize=*|--size=*)
        OPT_RESIZE=${1#*=}; shift ;;
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
      --quiet)         EGOMAT_LOG_LEVEL=quiet; shift ;;
      --verbose)       EGOMAT_LOG_LEVEL=verbose; shift ;;
      --overwrite)     OPT_OVERWRITE=1; shift ;;
      --keep-metadata) OPT_KEEP_METADATA=1; shift ;;
      --delete-source) OPT_DELETE_SOURCE=1; shift ;;
      --)
        shift
        while [ $# -gt 0 ]; do files+=("$1"); shift; done
        ;;
      -*) die "convert: unknown option: $1" ;;
      *)  files+=("$1"); shift ;;
    esac
  done

  [ -n "$OPT_FORMAT" ] || die "convert: --format is required (one of: $EGOMAT_TARGETS)"
  format_supported "$OPT_FORMAT" ||
    die "convert: unsupported format '$OPT_FORMAT' (supported: $EGOMAT_TARGETS)"
  if [ -n "$OPT_RESIZE" ]; then
    check_geometry "$OPT_RESIZE" || die "convert: invalid size '$OPT_RESIZE'"
  fi
  if [ -n "$OPT_QUALITY" ]; then
    case $OPT_QUALITY in
      *[!0-9]*) die "convert: quality must be a number between 1 and 100" ;;
    esac
    if [ "$OPT_QUALITY" -lt 1 ] || [ "$OPT_QUALITY" -gt 100 ]; then
      die "convert: quality must be between 1 and 100"
    fi
  fi
  [ ${#files[@]} -gt 0 ] || die "convert: no input files"

  local f rc=0
  for f in "${files[@]}"; do
    convert_one "$f" || rc=1
  done
  finish "$rc"
}

# ---------------------------------------------------------------------------
# Resize: convert each file to its own format with a new pixel size.
# ---------------------------------------------------------------------------
cmd_resize() {
  local geo=${1-}
  [ $# -gt 0 ] && shift
  [ -n "$geo" ] || die "resize: a size is required, e.g. 1920 or 1920x1080"
  check_geometry "$geo" || die "resize: invalid size '$geo'"
  [ "${1-}" = "--" ] && shift

  local outdir="" suffix="-resized" overwrite=0
  local -a files=()
  while [ $# -gt 0 ]; do
    case $1 in
      -o|--outdir|--output-dir)
        [ $# -ge 2 ] || die "option $1 needs a value"
        outdir=$2; shift 2 ;;
      --outdir=*|--output-dir=*)
        outdir=${1#*=}; shift ;;
      -s|--suffix)
        [ $# -ge 2 ] || die "option $1 needs a value"
        suffix=$2; shift 2 ;;
      --suffix=*)
        suffix=${1#*=}; shift ;;
      --quiet)     EGOMAT_LOG_LEVEL=quiet; shift ;;
      --verbose)   EGOMAT_LOG_LEVEL=verbose; shift ;;
      --overwrite) overwrite=1; shift ;;
      -*) die "resize: unknown option: $1" ;;
      *)  files+=("$1"); shift ;;
    esac
  done
  [ ${#files[@]} -gt 0 ] || die "resize: no input files"

  OPT_QUALITY=""
  OPT_RESIZE=$geo
  OPT_OUTDIR=$outdir
  OPT_SUFFIX=$suffix
  OPT_OVERWRITE=$overwrite
  OPT_KEEP_METADATA=1
  OPT_DELETE_SOURCE=0

  local f rc=0
  for f in "${files[@]}"; do
    OPT_FORMAT=$(norm_format "$(file_ext "$f")")
    if [ -z "$OPT_FORMAT" ]; then
      log_error "cannot tell the format of $f"
      EGOMAT_FAILED=$((EGOMAT_FAILED + 1))
      rc=1
      continue
    fi
    convert_one "$f" || rc=1
  done
  finish "$rc"
}

# ---------------------------------------------------------------------------
# Info
# ---------------------------------------------------------------------------
cmd_info() {
  [ "${1-}" = "--" ] && shift
  [ $# -gt 0 ] || die "info: no input files"
  local f dims fmt sz
  for f in "$@"; do
    if [ ! -f "$f" ]; then
      log_warn "not a file: $f"
      continue
    fi
    dims=$(img_dims "$f")
    fmt=$(file_ext "$f")
    sz=$(fsize "$f")
    printf '%s\n' "$f"
    printf '  format : %s\n' "${fmt:-unknown}"
    printf '  pixels : %s\n' "${dims:-unknown}"
    printf '  size   : %s (%s)\n' "$sz" "$(human "$sz")"
  done
}

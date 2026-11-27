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

# ImageMagick 6 expands the wildcard characters *, ?, [, and ] in file
# names on its own, so a file literally named photo[1].jpg can silently
# read photo1.jpg instead — the wrong pixels, and with --delete-source the
# deletion of the real file. IM 7 dropped that behaviour, but the IM 6
# backend stays supported. Set the variable named by $1 to a
# wildcard-free path for IM to read: a temporary symlink when the path in
# $2 contains wildcard characters, the path unchanged otherwise. Runs in
# the calling shell on purpose: a command substitution would register the
# temporary in a subshell's own EGOMAT_TEMP_FILES copy, which the exit
# traps of the main shell never see. Requires the traps to be installed.
im_safe_source() {
  local var=$1 src=$2 dir
  case $src in
    *[?*]*|*'['*|*']'*) ;;
    *) printf -v "$var" '%s' "$src"; return 0 ;;
  esac
  dir=$(dirname_of "$src")
  case $dir in *[?*]*|*'['*|*']'*) dir=. ;; esac
  if ! egomat_temp_file "$dir" imsrc; then
    printf -v "$var" '%s' "$src"
    return 0
  fi
  if rm -f -- "$EGOMAT_TEMP_PATH" &&
     ln -s -- "$src" "$EGOMAT_TEMP_PATH" 2>/dev/null; then
    printf -v "$var" '%s' "$EGOMAT_TEMP_PATH"
  else
    egomat_forget_temp "$EGOMAT_TEMP_PATH"
    printf -v "$var" '%s' "$src"
  fi
  return 0
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
  f=$(safe_path "$f")
  im_safe_source f "$f"
  input=$f
  [ -z "$ext" ] || input="$(image_format "$ext"):$f"
  if m=$(detect_magick); then
    if [ "$m" = magick ]; then
      if dims=$(magick identify -quiet -format '%w %h' "$input" 2>/dev/null); then
        [[ $dims =~ ^[1-9][0-9]*[[:space:]]+[1-9][0-9]* ]] && return 0
      fi
    elif have identify; then
      if dims=$(identify -quiet -format '%w %h' "$input" 2>/dev/null); then
        [[ $dims =~ ^[1-9][0-9]*[[:space:]]+[1-9][0-9]* ]] && return 0
      fi
    else
      if dims=$(im "$input" -format '%w %h' info: 2>/dev/null); then
        [[ $dims =~ ^[1-9][0-9]*[[:space:]]+[1-9][0-9]* ]] && return 0
      fi
    fi
  fi

  if have ffprobe; then
    dims=$(ffprobe -v error -select_streams v:0 \
      -show_entries stream=width,height -of csv=p=0 "$f" 2>/dev/null)
    dims=${dims%%$'\n'*}
    dims=${dims//,/ }
    [[ $dims =~ ^[1-9][0-9]*[[:space:]]+[1-9][0-9]*$ ]] && return 0
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
  local src
  src=$(safe_path "$1")
  local level=$OPT_LEVEL
  local ext dir base stem sfx target work before after policy claimed tries

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

  local od="" note="" conflict_note=""
  if [ -z "$OPT_OUTDIR" ] && [ -z "$OPT_SUFFIX" ]; then
    target=$src
  else
    od=${OPT_OUTDIR:-$dir}
    target="$od/$stem$OPT_SUFFIX$sfx"
    # Never let an optimized copy replace its own source.
    if [ "$target" = "$src" ] || { [ -e "$target" ] && [ "$target" -ef "$src" ]; }; then
      target="$od/$stem$OPT_SUFFIX-egomat$sfx"
      note="renamed to keep the source name free"
    fi
    policy=$OPT_CONFLICT
    if [ -e "$target" ] || [ -L "$target" ]; then
      if [ "$policy" = ask ]; then
        if [ "$EGOMAT_DRY_RUN" -eq 1 ]; then
          policy= # the plan below reports that the decision is pending
          conflict_note="ask at run time (target exists)"
        else
          policy=$(conflict_ask "$target") || policy=skip
        fi
      fi
      case $policy in
        overwrite)
          conflict_note="overwrite existing"
          ;;
        skip)
          if [ "$EGOMAT_DRY_RUN" -eq 1 ]; then
            printf 'would skip: %s (target exists: %s)\n' "$src" "$target"
          else
            log_info "$(basename -- "$src") skipped (target exists: $target)"
            EGOMAT_SKIPPED=$((EGOMAT_SKIPPED + 1))
          fi
          return 0
          ;;
        rename)
          target=$(unique_path "$target")
          conflict_note="unique rename (target exists)"
          ;;
      esac
    fi
  fi

  if [ "$EGOMAT_DRY_RUN" -eq 1 ]; then
    local op="level $level" decision backup
    if [ "$target" = "$src" ]; then
      if [ "$OPT_FORCE" -eq 1 ]; then
        decision="replace in place, even if not smaller"
      else
        decision="replace in place only if the result is smaller"
      fi
    else
      decision="write optimized copy"
    fi
    if [ -n "$conflict_note" ]; then
      decision="$decision; $conflict_note"
    fi
    if [ -n "$note" ]; then
      decision="$decision; $note"
    fi
    if [ "$OPT_BACKUP" -eq 1 ]; then
      backup=$(unique_path "$src.egomat-orig")
      decision="backup as $backup first; $decision"
    fi
    if [ -n "$od" ] && [ ! -d "$od" ]; then
      decision="$decision; create directory $od"
    fi
    printf 'would optimize: %s -> %s (%s; %s)\n' "$src" "$target" "$op" "$decision"
    return 0
  fi

  if [ -n "$od" ] && ! mkdir -p -- "$od" 2>/dev/null; then
    log_error "cannot create directory: $od"
    EGOMAT_FAILED=$((EGOMAT_FAILED + 1))
    return 1
  fi

  # Claim a copy's output name before the (slow) optimization, for the same
  # reason convert claims its output: two parallel runs must not end up
  # writing over each other's unique rename. In-place optimization does not
  # claim (the target is the source itself); overwrite policy means the
  # clobber is what was asked for.
  claimed=0
  if [ "$target" != "$src" ] && [ "$policy" != overwrite ]; then
    tries=0
    while :; do
      if claim_path "$target"; then
        claimed=1
        EGOMAT_TEMP_FILES+=("$target")
        break
      fi
      if [ -e "$target" ] || [ -L "$target" ]; then
        target=$(unique_path "$target")
      else
        break
      fi
      tries=$((tries + 1))
      [ "$tries" -lt 100 ] || break
    done
  fi
  if [ "$claimed" -ne 1 ] && [ "$target" != "$src" ] &&
     [ "$policy" != overwrite ] && { [ -e "$target" ] || [ -L "$target" ]; }; then
    # The claim loop gave up on an existing target: writing now would
    # clobber a file this run never claimed.
    log_error "cannot reserve an output name for: $src"
    EGOMAT_FAILED=$((EGOMAT_FAILED + 1))
    return 1
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
    [ "$claimed" -eq 1 ] && egomat_remove_temp "$target"
    log_error "optimization produced an empty file: $src"
    EGOMAT_FAILED=$((EGOMAT_FAILED + 1))
    return 1
  fi

  if [ "$after" -ge "$before" ] && [ "$OPT_FORCE" -ne 1 ]; then
    egomat_remove_temp "$work"
    [ "$claimed" -eq 1 ] && egomat_remove_temp "$target"
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
    [ "$claimed" -eq 1 ] && egomat_remove_temp "$target"
    log_error "cannot verify optimized image is readable: $src"
    EGOMAT_FAILED=$((EGOMAT_FAILED + 1))
    return 1
  fi

  if [ "$OPT_BACKUP" -eq 1 ] && ! backup_of "$src"; then
    egomat_remove_temp "$work"
    [ "$claimed" -eq 1 ] && egomat_remove_temp "$target"
    EGOMAT_FAILED=$((EGOMAT_FAILED + 1))
    return 1
  fi
  if ! mv -f -- "$work" "$target"; then
    egomat_remove_temp "$work"
    [ "$claimed" -eq 1 ] && egomat_remove_temp "$target"
    log_error "cannot write: $target"
    EGOMAT_FAILED=$((EGOMAT_FAILED + 1))
    return 1
  fi
  egomat_forget_temp "$work"
  [ "$claimed" -eq 1 ] && egomat_forget_temp "$target"
  track_sizes "$before" "$after"
  EGOMAT_OPTIMIZED=$((EGOMAT_OPTIMIZED + 1))
  if [ "$target" = "$src" ]; then
    log_info "$(basename -- "$src") $before -> $after bytes ($(human "$before") -> $(human "$after"))"
  else
    log_info "$(basename -- "$src") -> $target ($(human "$before") -> $(human "$after"))"
  fi
  return 0
}

# ---------------------------------------------------------------------------
# Command
# ---------------------------------------------------------------------------
cmd_optimize() {
  if args_have_help_flag "$@"; then
    usage_optimize
    return 0
  fi
  OPT_LEVEL=balanced
  OPT_OUTDIR=""
  OPT_SUFFIX=""
  OPT_CONFLICT=rename
  OPT_BACKUP=0
  OPT_FORCE=0
  OPT_RECURSIVE=0
  local -a files=()

  while [ $# -gt 0 ]; do
    case $1 in
      -l|--level)
        [ $# -ge 2 ] && [ -n "$2" ] || die "option $1 needs a value"
        OPT_LEVEL=$(norm_level "$2"); shift 2 ;;
      --level=*)
        [ -n "${1#*=}" ] || die "option --level needs a value"
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
      --recursive) OPT_RECURSIVE=1; shift ;;
      --on-conflict)
        [ $# -ge 2 ] || die "option $1 needs a value"
        OPT_CONFLICT=$(norm_conflict "$2") ||
          die "optimize: --on-conflict must be one of: rename, skip, overwrite, ask"
        shift 2 ;;
      --on-conflict=*)
        OPT_CONFLICT=$(norm_conflict "${1#*=}") ||
          die "optimize: --on-conflict must be one of: rename, skip, overwrite, ask"
        shift ;;
      --dry-run) EGOMAT_DRY_RUN=1; shift ;;
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
  if [ -n "$OPT_SUFFIX" ]; then
    suffix_is_safe "$OPT_SUFFIX" || die "optimize: --suffix must not contain '/'"
  fi
  expand_inputs optimize "${files[@]}"
  if [ "$OPT_CONFLICT" = ask ] && ! conflict_ask_available; then
    die "optimize: --on-conflict ask needs an interactive session (a terminal or desktop dialogs); use rename, skip, or overwrite"
  fi

  optimizer_available ||
    die "optimize: no image optimizer found. Install one of oxipng, optipng, pngquant, jpegoptim, gifsicle, svgo, cwebp/webpmux or ImageMagick."

  local f rc=0
  egomat_install_temp_traps
  for f in "${EGOMAT_INPUT_FILES[@]}"; do
    optimize_one "$f" || rc=1
  done
  finish "$rc"
}

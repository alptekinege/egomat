# shellcheck shell=bash
# egomat — shared helpers: logging, path utilities, size accounting, reporting.
# Sourced by bin/egomat. Requires bash 4.2+.

EGOMAT_VERSION="1.0.0"
EGOMAT_NAME="egomat"

# ---------------------------------------------------------------------------
# Logging. Everything goes to stderr so that stdout stays machine-readable.
# ---------------------------------------------------------------------------
EGOMAT_LOG_LEVEL=${EGOMAT_LOG_LEVEL:-normal}

log_info() {
  [ "$EGOMAT_LOG_LEVEL" = quiet ] && return 0
  printf 'egomat: %s\n' "$*" >&2
}

log_verbose() {
  [ "$EGOMAT_LOG_LEVEL" = verbose ] || return 0
  printf 'egomat: %s\n' "$*" >&2
}

log_warn() {
  printf 'egomat: warning: %s\n' "$*" >&2
}

log_error() {
  printf 'egomat: error: %s\n' "$*" >&2
}

die() {
  log_error "$@"
  exit 1
}

# ---------------------------------------------------------------------------
# Dry-run mode. Commands that write files accept --dry-run and print their
# plan instead; nothing is created, replaced, or removed.
# ---------------------------------------------------------------------------
EGOMAT_DRY_RUN=${EGOMAT_DRY_RUN:-0}

# ---------------------------------------------------------------------------
# Capability probing
# ---------------------------------------------------------------------------
have() {
  command -v -- "$1" >/dev/null 2>&1
}

# True when -h/--help appears before any "--" separator. The separator
# matters: "info -- --help" names a file called --help, it is not a help
# request. Callers check this before any other argument validation so
# that "convert --help" works without a --format value.
args_have_help_flag() {
  local a
  for a in "$@"; do
    case $a in
      --) return 1 ;;
      -h|--help) return 0 ;;
    esac
  done
  return 1
}

# ---------------------------------------------------------------------------
# Path utilities
# ---------------------------------------------------------------------------

# Print the directory part of a path ("." when there is none).
dirname_of() {
  local d
  case $1 in
    */*)
      d=${1%/*}
      [ -n "$d" ] || d=/
      printf '%s\n' "$d"
      ;;
    *) printf '.\n' ;;
  esac
}

# Print the lowercase extension of a path, without the dot.
file_ext() {
  local b=$1
  b=${b##*/}
  case $b in
    *.*) printf '%s\n' "${b##*.}" | tr 'A-Z' 'a-z' ;;
    *) printf '' ;;
  esac
}

# Print the base name of a path without its last extension.
file_stem() {
  local b=$1
  b=${b##*/}
  case $b in
    *.*) b=${b%.*} ;;
  esac
  printf '%s\n' "$b"
}

# Print the size of a file in bytes (0 when it cannot be read).
fsize() {
  local n
  n=$(stat -c '%s' -- "$1" 2>/dev/null)
  if [ -z "$n" ]; then
    n=$(wc -c <"$1" 2>/dev/null | tr -d '[:space:]')
  fi
  printf '%s\n' "${n:-0}"
}

# Print $1 bytes in a human-readable unit.
human() {
  awk -v b="${1:-0}" 'BEGIN {
    split("B KiB MiB GiB TiB", u, " ")
    i = 1
    while (b >= 1024 && i < 5) { b /= 1024; i++ }
    if (i == 1) printf "%d %s\n", b, u[i]
    else        printf "%.1f %s\n", b, u[i]
  }'
}

# Print a path that does not exist yet, derived from $1.
unique_path() {
  local p=$1 n=1 dir base stem ext cand
  if [ ! -e "$p" ] && [ ! -L "$p" ]; then
    printf '%s\n' "$p"
    return 0
  fi
  dir=$(dirname_of "$p")
  base=${p##*/}
  case $base in
    *.*) ext=".${base##*.}"; stem=${base%.*} ;;
    *)   ext="";             stem=$base ;;
  esac
  while :; do
    cand="$dir/$stem-$n$ext"
    if [ ! -e "$cand" ] && [ ! -L "$cand" ]; then
      printf '%s\n' "$cand"
      return 0
    fi
    n=$((n + 1))
  done
}

# ---------------------------------------------------------------------------
# Conflict policy for existing outputs: rename (default), skip, overwrite,
# ask. Commands that write new files accept --on-conflict; "ask" is reserved
# for interactive sessions (a terminal or desktop dialogs).
# ---------------------------------------------------------------------------

# Print the normalized conflict policy. Returns non-zero for an unknown name.
norm_conflict() {
  local p
  p=$(printf '%s' "${1-}" | tr 'A-Z' 'a-z')
  case $p in
    rename|skip|overwrite|ask)
      printf '%s\n' "$p"
      ;;
    *)
      return 1
      ;;
  esac
}

# True when someone can answer a conflict prompt: a terminal on stdin, or
# desktop dialogs in an interactive session.
conflict_ask_available() {
  [ -t 0 ] && return 0
  if [ "${EGOMAT_INTERACTIVE:-0}" -eq 1 ] && { have kdialog || have zenity; }; then
    return 0
  fi
  return 1
}

# Ask what to do about an existing output file. Prints one of: rename,
# overwrite, skip. Cancelling or running out of input skips (the safe
# answer: nothing is written).
conflict_ask() {
  local out=$1 ans
  if [ "${EGOMAT_INTERACTIVE:-0}" -eq 1 ] && { have kdialog || have zenity; }; then
    ans=$(ui_choose "$EGOMAT_NAME" "${out##*/} already exists. What should I do?" \
      rename "Write to a new, unique name" \
      overwrite "Replace the existing file" \
      skip "Leave both files alone") || ans=skip
  elif [ -t 0 ]; then
    while :; do
      printf 'egomat: %s exists. [r]ename (default), [o]verwrite, [s]kip: ' \
        "${out##*/}" >&2
      IFS= read -r ans || { ans=skip; break; }
      case $ans in
        ''|r*|R*) ans=rename ;;
        o*|O*)    ans=overwrite ;;
        s*|S*)    ans=skip ;;
        *)        continue ;;
      esac
      break
    done
  else
    ans=skip
  fi
  case $ans in
    rename|overwrite|skip) printf '%s\n' "$ans" ;;
    *) printf 'skip\n' ;;
  esac
}

# ---------------------------------------------------------------------------
# Input expansion. With --recursive, directory arguments are walked and the
# image files inside are processed. Non-image files are skipped and counted
# as skipped inputs, reported separately from failures. Hidden entries (names
# starting with a dot) are ignored and directory symlinks are not followed.
# ---------------------------------------------------------------------------
EGOMAT_INPUT_FILES=()
EGOMAT_IMAGE_EXTS="png jpg jpeg jpe jfif webp avif gif bmp tif tiff ico svg svgz"

# True when a file name looks like an image Egomat can read.
is_image_name() {
  case " $EGOMAT_IMAGE_EXTS " in
    *" $(file_ext "$1") "*) return 0 ;;
  esac
  return 1
}

# Fill EGOMAT_INPUT_FILES from the input arguments. Regular files are kept
# as given (their contents are checked later, per file). Directories are
# walked only with OPT_RECURSIVE=1; without it they are a usage error that
# stops the batch before it starts. $1 names the calling command for the
# error message.
expand_inputs() {
  local cmd=$1 item f
  shift
  EGOMAT_INPUT_FILES=()
  for item in "$@"; do
    if [ -f "$item" ]; then
      EGOMAT_INPUT_FILES+=("$item")
    elif [ -d "$item" ]; then
      if [ "${OPT_RECURSIVE:-0}" -ne 1 ]; then
        die "$cmd: input is a directory (use --recursive): $item"
      fi
      while IFS= read -r -d '' f; do
        if [ -L "$f" ] && [ ! -f "$f" ]; then
          log_verbose "skipping (unusable link): $f"
          continue
        fi
        if is_image_name "$f"; then
          EGOMAT_INPUT_FILES+=("$f")
        else
          if [ "$EGOMAT_DRY_RUN" -eq 1 ]; then
            printf 'would skip: %s (not an image)\n' "$f"
          else
            log_info "skipping (not an image): $f"
          fi
          EGOMAT_SKIPPED_INPUTS=$((EGOMAT_SKIPPED_INPUTS + 1))
        fi
      # Hidden entries are pruned, and only regular files and symlinks are
      # candidates; -mindepth keeps the directory itself out of the prune.
      done < <(find -H "$item" -mindepth 1 \( -name '.*' -prune \) -o \
        \( \( -type f -o -type l \) -print0 \) | sort -z)
    else
      # Missing, or not a regular file: keep it so the per-file handler
      # reports the failure.
      EGOMAT_INPUT_FILES+=("$item")
    fi
  done
}

# ---------------------------------------------------------------------------
# Run accounting, used for the summary the menu actions show when they finish.
# ---------------------------------------------------------------------------
EGOMAT_CONVERTED=0
EGOMAT_OPTIMIZED=0
EGOMAT_SKIPPED=0
EGOMAT_SKIPPED_INPUTS=0
EGOMAT_FAILED=0
EGOMAT_BYTES_IN=0
EGOMAT_BYTES_OUT=0

track_sizes() {
  EGOMAT_BYTES_IN=$((EGOMAT_BYTES_IN + ${1:-0}))
  EGOMAT_BYTES_OUT=$((EGOMAT_BYTES_OUT + ${2:-0}))
}

saved_bytes() {
  local s=$((EGOMAT_BYTES_IN - EGOMAT_BYTES_OUT))
  if [ "$s" -gt 0 ]; then printf '%s\n' "$s"; else printf '0\n'; fi
}

report_text() {
  local t="" s
  if [ "$EGOMAT_CONVERTED" -gt 0 ]; then
    t="$t$(printf '%d file(s) converted' "$EGOMAT_CONVERTED")"$'\n'
  fi
  if [ "$EGOMAT_OPTIMIZED" -gt 0 ]; then
    s=$(saved_bytes)
    if [ "$s" -gt 0 ]; then
      t="$t$(printf '%d file(s) optimized, %s saved' "$EGOMAT_OPTIMIZED" "$(human "$s")")"$'\n'
    else
      t="$t$(printf '%d file(s) optimized' "$EGOMAT_OPTIMIZED")"$'\n'
    fi
  fi
  if [ "$EGOMAT_SKIPPED_INPUTS" -gt 0 ]; then
    t="$t$(printf '%d input(s) skipped (not an image)' "$EGOMAT_SKIPPED_INPUTS")"$'\n'
  fi
  if [ "$EGOMAT_SKIPPED" -gt 0 ]; then
    t="$t$(printf '%d file(s) skipped' "$EGOMAT_SKIPPED")"$'\n'
  fi
  if [ "$EGOMAT_FAILED" -gt 0 ]; then
    t="$t$(printf '%d file(s) failed' "$EGOMAT_FAILED")"$'\n'
  fi
  printf '%s' "$t"
}

# Show the accumulated result, then return the command's exit status.
finish() {
  local rc=${1:-0} body
  body=$(report_text)
  if [ -n "$body" ]; then
    if [ "${EGOMAT_INTERACTIVE:-0}" -eq 1 ]; then
      if [ "$rc" -ne 0 ]; then
        ui_error "$EGOMAT_NAME" "$body"
      else
        ui_msg "$EGOMAT_NAME" "$body"
      fi
    elif [ "$EGOMAT_LOG_LEVEL" != quiet ]; then
      printf '%s\n' "$body" >&2
    fi
  fi
  return "$rc"
}

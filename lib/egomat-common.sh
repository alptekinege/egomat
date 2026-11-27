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
# Capability probing
# ---------------------------------------------------------------------------
have() {
  command -v -- "$1" >/dev/null 2>&1
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
# Run accounting, used for the summary the menu actions show when they finish.
# ---------------------------------------------------------------------------
EGOMAT_CONVERTED=0
EGOMAT_OPTIMIZED=0
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
      printf '%s' "$body" >&2
    fi
  fi
  return "$rc"
}

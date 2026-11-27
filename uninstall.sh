#!/usr/bin/env bash
# egomat — uninstaller. Removes only paths recorded by install.sh.
#
# SPDX-License-Identifier: MIT

set -o pipefail

MODE=user
PREFIX_ARG=""
PREFIX_EXPLICIT=0
DRY=0

warn() { printf 'uninstall.sh: %s\n' "$*" >&2; }
say() { printf '%s\n' "$*"; }

usage() {
  cat <<'EOF'
Usage: ./uninstall.sh [options]

  --user              remove the current user's installation (default)
  --system            remove the /usr/local installation
  --prefix DIR        remove the installation under DIR
  -n, --dry-run       print what would be removed, change nothing
  -h, --help          show this text
EOF
}

while [ $# -gt 0 ]; do
  case $1 in
    --user)   MODE=user; shift ;;
    --system) MODE=system; shift ;;
    --prefix)
      [ $# -ge 2 ] || { warn "--prefix needs a value"; exit 2; }
      PREFIX_ARG=$2; PREFIX_EXPLICIT=1; shift 2 ;;
    --prefix=*)
      PREFIX_ARG=${1#*=}; PREFIX_EXPLICIT=1; shift ;;
    -n|--dry-run) DRY=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) warn "unknown option: $1"; usage >&2; exit 2 ;;
  esac
done

if [ "$MODE" = system ]; then
  PREFIX=${PREFIX_ARG:-/usr/local}
else
  PREFIX=${PREFIX_ARG:-$HOME/.local}
fi
PREFIX=${PREFIX%/}
[ -n "$PREFIX" ] || PREFIX=/
PREFIX=$(realpath -m -- "$PREFIX") || { warn "could not resolve install prefix"; exit 1; }

if [ "$MODE" = system ] || [ "$PREFIX_EXPLICIT" -eq 1 ]; then
  DATA_HOME="$PREFIX/share"
else
  DATA_HOME="${XDG_DATA_HOME:-$PREFIX/share}"
fi
CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
DATA_HOME=$(realpath -m -- "$DATA_HOME") || { warn "could not resolve data directory"; exit 1; }
CONFIG_HOME=$(realpath -m -- "$CONFIG_HOME") || { warn "could not resolve config directory"; exit 1; }

MANIFEST="$PREFIX/lib/egomat/.egomat-manifest"

path_within() {
  local path=$1 root=$2
  if [ "$root" = / ]; then
    [[ "$path" = /* ]]
  else
    [[ "$path" = "$root" || "$path" = "$root/"* ]]
  fi
}

safe_path() {
  local path=$1 parent base resolved_parent candidate root resolved_root
  case "$path" in
    /*) ;;
    *) return 1 ;;
  esac
  parent=${path%/*}
  base=${path##*/}
  [ -n "$parent" ] || parent=/
  case "$base" in
    ''|.|..) return 1 ;;
  esac
  resolved_parent=$(realpath -m -- "$parent") || return 1
  if [ "$resolved_parent" = / ]; then
    candidate="/$base"
  else
    candidate="$resolved_parent/$base"
  fi

  local -a roots=("$PREFIX")
  if [ "$MODE" = user ] && [ "$PREFIX_EXPLICIT" -eq 0 ]; then
    roots+=("$DATA_HOME" "$CONFIG_HOME")
  fi
  for root in "${roots[@]}"; do
    resolved_root=$(realpath -m -- "$root") || continue
    if path_within "$candidate" "$resolved_root"; then
      return 0
    fi
  done
  return 1
}

say "Uninstalling egomat from $PREFIX"
if [ ! -f "$MANIFEST" ] || [ -L "$MANIFEST" ]; then
  warn "no install manifest found at $MANIFEST; reinstall with install.sh before uninstalling"
  say "Done."
  exit 0
fi

declare -a files=() dirs=()
kind=""
path=""
while IFS= read -r -d '' kind && IFS= read -r -d '' path; do
  case "$kind" in
    F) files+=("$path") ;;
    D) dirs+=("$path") ;;
    *) warn "ignoring an unknown manifest record" ;;
  esac
done < "$MANIFEST"

remove_file() {
  local path=$1
  if [ ! -e "$path" ] && [ ! -L "$path" ]; then
    return 0
  fi
  if ! safe_path "$path"; then
    warn "skipping path outside the managed install roots: $path"
    return 1
  fi
  if [ "$DRY" -eq 1 ]; then
    printf '   - %s\n' "$path"
    return 0
  fi
  rm -f -- "$path" || { warn "could not remove file: $path"; return 1; }
}

remove_dir() {
  local path=$1
  if [ ! -d "$path" ]; then
    return 0
  fi
  if ! safe_path "$path"; then
    warn "skipping directory outside the managed install roots: $path"
    return 1
  fi
  if [ "$DRY" -eq 1 ]; then
    printf '   - %s/\n' "$path"
    return 0
  fi
  rmdir -- "$path" 2>/dev/null || :
}

clean=0
for path in "${files[@]}"; do
  [ "$path" = "$MANIFEST" ] && continue
  remove_file "$path" || clean=1
done
if [ "$clean" -eq 0 ]; then
  remove_file "$MANIFEST" || clean=1
fi
if [ "$clean" -eq 0 ] || [ "$DRY" -eq 1 ]; then
  for ((i=${#dirs[@]} - 1; i >= 0; i--)); do
    remove_dir "${dirs[i]}" || :
  done
elif [ "$DRY" -eq 0 ]; then
  warn "keeping the install manifest so uninstall can be retried"
fi

if [ "$DRY" -eq 0 ] && command -v update-desktop-database >/dev/null 2>&1; then
  if path_within "$DATA_HOME/applications" "$PREFIX" || { [ "$MODE" = user ] && [ "$PREFIX_EXPLICIT" -eq 0 ]; }; then
    update-desktop-database "$DATA_HOME/applications" >/dev/null 2>&1
  fi
fi

say "Done."

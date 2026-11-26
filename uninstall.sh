#!/usr/bin/env bash
# egomat — uninstaller. Removes what install.sh wrote, and nothing else.
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
    -h|--help)    usage; exit 0 ;;
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

BIN="$PREFIX/bin"
LIB="$PREFIX/lib/egomat"
EGOMAT="$BIN/egomat"

if [ "$MODE" = system ] || [ "$PREFIX_EXPLICIT" -eq 1 ]; then
  DATA_HOME="$PREFIX/share"
else
  DATA_HOME="${XDG_DATA_HOME:-$PREFIX/share}"
fi
CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"

remove() {
  local p=$1
  if [ ! -e "$p" ] && [ ! -L "$p" ]; then
    return 0
  fi
  if [ "$DRY" -eq 1 ]; then
    printf '   - %s\n' "$p"
    return 0
  fi
  rm -rf -- "$p"
}

say "Uninstalling egomat from $PREFIX"

remove "$EGOMAT"
remove "$LIB"
remove "$DATA_HOME/kio/servicemenus/egomat.desktop"
remove "$DATA_HOME/applications/egomat.desktop"
remove "$DATA_HOME/icons/hicolor/scalable/apps/egomat.svg"

remove "$DATA_HOME/nautilus/scripts/Egomat"
remove "$DATA_HOME/nemo/actions/egomat-menu.nemo_action"
remove "$DATA_HOME/nemo/actions/egomat-convert-webp.nemo_action"
remove "$DATA_HOME/nemo/actions/egomat-convert-jpeg.nemo_action"
remove "$DATA_HOME/nemo/actions/egomat-optimize-balanced.nemo_action"
remove "$DATA_HOME/Thunar/sendto/egomat-menu.desktop"
remove "$DATA_HOME/Thunar/sendto/egomat-convert-webp.desktop"
remove "$DATA_HOME/Thunar/sendto/egomat-convert-jpeg.desktop"
remove "$DATA_HOME/Thunar/sendto/egomat-optimize-balanced.desktop"
if [ "$MODE" = user ] && [ "$PREFIX_EXPLICIT" -eq 0 ]; then
  remove "$CONFIG_HOME/caja/scripts/Egomat"
fi

if [ "$DRY" -eq 0 ] && command -v update-desktop-database >/dev/null 2>&1; then
  update-desktop-database "$DATA_HOME/applications" >/dev/null 2>&1
fi

say "Done."

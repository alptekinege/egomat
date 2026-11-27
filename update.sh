#!/usr/bin/env bash
# Update this checkout from its upstream branch and reinstall Egomat.
# SPDX-License-Identifier: MIT

set -o pipefail

ROOT=$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)
PULL=1
DRY=0
MODE=user
PREFIX_EXPLICIT=0
INSTALL_ARGS=()

usage() {
  cat <<'EOF'
Usage: bash ./update.sh [options]

Fetches a fast-forward update for this Git checkout, then runs install.sh.
Install options are passed through unchanged.

  --no-fetch          reinstall from this checkout without contacting Git
  --dry-run           show install actions without fetching or writing files
  --user              install for the current user (default)
  --system            install into /usr/local (uses sudo when needed)
  --prefix DIR        install under DIR
  --no-kde            skip the KDE service menu
  --no-freedesktop    skip other file-manager actions
  --no-app            skip the application-menu entry and icon
  -h, --help          show this text

Commit or stash changes before fetching. Use the same install options used
for the original install, such as --system or --prefix DIR.
EOF
}

while [ $# -gt 0 ]; do
  case $1 in
    -h|--help)
      usage
      exit 0
      ;;
    --no-fetch)
      PULL=0
      shift
      ;;
    --dry-run|-n)
      DRY=1
      INSTALL_ARGS+=("$1")
      shift
      ;;
    --user)
      MODE=user
      INSTALL_ARGS+=("$1")
      shift
      ;;
    --system)
      MODE=system
      INSTALL_ARGS+=("$1")
      shift
      ;;
    --prefix)
      [ $# -ge 2 ] || { printf 'update.sh: --prefix needs a value\n' >&2; exit 2; }
      PREFIX_EXPLICIT=1
      INSTALL_ARGS+=("$1" "$2")
      shift 2
      ;;
    --prefix=*)
      PREFIX_EXPLICIT=1
      INSTALL_ARGS+=("$1")
      shift
      ;;
    *)
      INSTALL_ARGS+=("$1")
      shift
      ;;
  esac
done

if [ "$MODE" = system ] && [ "$(id -u)" -ne 0 ] && [ "$DRY" -eq 0 ] &&
   ! command -v sudo >/dev/null 2>&1; then
  printf 'update.sh: system install requires root or sudo\n' >&2
  exit 1
fi

run_git() {
  if [ "$(id -u)" -eq 0 ] && [ -n "${SUDO_USER:-}" ]; then
    command sudo -H -u "$SUDO_USER" git -C "$ROOT" "$@"
  else
    git -C "$ROOT" "$@"
  fi
}

if [ "$PULL" -eq 1 ] && [ "$DRY" -eq 0 ]; then
  if ! command -v git >/dev/null 2>&1; then
    printf 'update.sh: run this script from a Git checkout, or pass --no-fetch\n' >&2
    exit 1
  fi
  if [ "$(id -u)" -eq 0 ] && [ -n "${SUDO_USER:-}" ] &&
     ! command -v sudo >/dev/null 2>&1; then
    printf 'update.sh: sudo is needed to access the checkout as %s\n' "$SUDO_USER" >&2
    exit 1
  fi
  git_root=$(run_git rev-parse --show-toplevel) || {
    printf 'update.sh: run this script from a Git checkout, or pass --no-fetch\n' >&2
    exit 1
  }
  if [ "$(cd -P "$git_root" && pwd)" != "$ROOT" ]; then
    printf 'update.sh: this script is not at the root of its Git checkout\n' >&2
    exit 1
  fi

  status=$(run_git status --porcelain) || exit 1
  if [ -n "$status" ]; then
    printf 'update.sh: checkout has uncommitted changes; commit, stash, or use --no-fetch\n' >&2
    exit 1
  fi
  if ! run_git rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' >/dev/null 2>&1; then
    printf 'update.sh: current branch has no upstream; configure one or use --no-fetch\n' >&2
    exit 1
  fi

  printf 'Updating checkout from its upstream branch...\n'
  run_git pull --ff-only || exit $?
elif [ "$PULL" -eq 0 ]; then
  printf 'Using the current checkout (--no-fetch).\n'
fi

if [ "$MODE" = system ] && [ "$(id -u)" -ne 0 ] && [ "$DRY" -eq 0 ]; then
  exec sudo bash "$ROOT/install.sh" "${INSTALL_ARGS[@]}"
fi

if [ "$MODE" = user ] && [ "$PREFIX_EXPLICIT" -eq 0 ] &&
   [ "$(id -u)" -eq 0 ] && [ -n "${SUDO_USER:-}" ]; then
  exec sudo -H -u "$SUDO_USER" bash "$ROOT/install.sh" "${INSTALL_ARGS[@]}"
fi

exec bash "$ROOT/install.sh" "${INSTALL_ARGS[@]}"

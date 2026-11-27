#!/usr/bin/env bash
# egomat — installer.
#
# Installs the CLI into a private library directory, puts a link on PATH and
# writes the KDE service menu plus the freedesktop file-manager actions.
#
# SPDX-License-Identifier: MIT

set -o pipefail

SRC=$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)

MODE=user
PREFIX_ARG=""
PREFIX_EXPLICIT=0
DRY=0
DO_KDE=1
DO_FM=1
DO_APP=1
DO_GUI=0
DO_COMPLETIONS=1

have() { command -v -- "$1" >/dev/null 2>&1; }

say() { printf '%s\n' "$*"; }

warn() { printf 'install.sh: %s\n' "$*" >&2; }

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

usage() {
  cat <<'EOF'
Usage: ./install.sh [options]

  --user              install for the current user (default)
  --system            install into /usr/local (needs write access)
  --prefix DIR        install under DIR (DIR/bin, DIR/lib, DIR/share)
  --no-kde            skip the KDE/Dolphin service menu
  --no-freedesktop    skip the Nautilus, Nemo, Thunar and Caja actions
  --no-app            skip the application-menu entry and the icon
  --no-completions    skip the Bash, Zsh and Fish completions
  --gui               build and install the egomat-gui window and tray app (needs Go)
  -n, --dry-run       print what would be done, change nothing
  -h, --help          show this text

Uninstall with ./uninstall.sh and the same --user/--system/--prefix options.
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
    --no-kde)         DO_KDE=0; shift ;;
    --no-freedesktop) DO_FM=0; shift ;;
    --no-app)         DO_APP=0; shift ;;
    --no-completions) DO_COMPLETIONS=0; shift ;;
    --gui)            DO_GUI=1; shift ;;
    --no-gui)         DO_GUI=0; shift ;;
    -n|--dry-run)     DRY=1; shift ;;
    -h|--help)        usage; exit 0 ;;
    *) warn "unknown option: $1"; usage >&2; exit 2 ;;
  esac
done

# ---------------------------------------------------------------------------
# Layout
# ---------------------------------------------------------------------------
if [ "$MODE" = system ]; then
  PREFIX=${PREFIX_ARG:-/usr/local}
else
  PREFIX=${PREFIX_ARG:-$HOME/.local}
fi
PREFIX=${PREFIX%/}
[ -n "$PREFIX" ] || PREFIX=/

if [ "$MODE" = system ] || [ "$PREFIX_EXPLICIT" -eq 1 ]; then
  DATA_HOME="$PREFIX/share"
else
  DATA_HOME="${XDG_DATA_HOME:-$PREFIX/share}"
fi
CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"

PREFIX=$(realpath -m -- "$PREFIX") || { warn "could not resolve install prefix"; exit 1; }
DATA_HOME=$(realpath -m -- "$DATA_HOME") || { warn "could not resolve data directory"; exit 1; }
CONFIG_HOME=$(realpath -m -- "$CONFIG_HOME") || { warn "could not resolve config directory"; exit 1; }
BIN="$PREFIX/bin"
LIB="$PREFIX/lib/egomat"
EGOMAT="$BIN/egomat"
EGOMAT_GUI="$BIN/egomat-gui"
MANIFEST="$LIB/.egomat-manifest"

VERSION=$(sed -n 's/^EGOMAT_VERSION="\([^"]*\)".*/\1/p' "$SRC/lib/egomat-common.sh" 2>/dev/null | head -n 1)
[ -n "$VERSION" ] || VERSION=0.0.0

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
esc() { printf '%s' "$1" | sed 's/[&|\\]/\\&/g'; }

path_within() {
  local path=$1 root=$2
  if [ "$root" = / ]; then
    [[ "$path" = /* ]]
  else
    [[ "$path" = "$root" || "$path" = "$root/"* ]]
  fi
}

managed_path() {
  local path=$1
  path_within "$path" "$PREFIX" || path_within "$path" "$DATA_HOME" || path_within "$path" "$CONFIG_HOME"
}

manifest_has() {
  local wanted_kind=$1 wanted_path=$2 kind path
  [ -f "$MANIFEST" ] || return 1
  while IFS= read -r -d '' kind && IFS= read -r -d '' path; do
    [ "$kind" = "$wanted_kind" ] && [ "$path" = "$wanted_path" ] && return 0
  done < "$MANIFEST"
  return 1
}

record_path() {
  local kind=$1 path=$2 existing_kind existing_path
  [ "$DRY" -eq 1 ] && return 0
  if [ ! -e "$MANIFEST" ] && [ ! -L "$MANIFEST" ]; then
    : > "$MANIFEST" || return 1
    printf 'F\0%s\0' "$MANIFEST" >> "$MANIFEST" || return 1
  elif [ -L "$MANIFEST" ] || [ ! -f "$MANIFEST" ]; then
    warn "install manifest is not a regular file: $MANIFEST"
    return 1
  fi
  while IFS= read -r -d '' existing_kind && IFS= read -r -d '' existing_path; do
    [ "$existing_kind" = "$kind" ] && [ "$existing_path" = "$path" ] && return 0
  done < "$MANIFEST"
  printf '%s\0%s\0' "$kind" "$path" >> "$MANIFEST"
}

init_manifest() {
  [ "$DRY" -eq 1 ] && return 0
  if [ ! -e "$MANIFEST" ] && [ ! -L "$MANIFEST" ]; then
    : > "$MANIFEST" || return 1
    printf 'F\0%s\0' "$MANIFEST" >> "$MANIFEST" || return 1
  elif [ -L "$MANIFEST" ] || [ ! -f "$MANIFEST" ]; then
    warn "install manifest is not a regular file: $MANIFEST"
    return 1
  fi
  manifest_has F "$MANIFEST" || printf 'F\0%s\0' "$MANIFEST" >> "$MANIFEST"
}

ensure_dir() {
  local dir=$1 current=$1 parent path canonical i
  local -a missing=()
  while [ ! -d "$current" ]; do
    if [ -e "$current" ] || [ -L "$current" ]; then
      warn "not a directory: $current"
      return 1
    fi
    missing+=("$current")
    parent=$(dirname_of "$current")
    [ "$parent" != "$current" ] || break
    current=$parent
  done
  [ "$DRY" -eq 1 ] && return 0
  mkdir -p -- "$dir" || return 1
  for ((i=${#missing[@]} - 1; i >= 0; i--)); do
    path=${missing[i]}
    canonical=$(realpath -m -- "$path") || return 1
    if managed_path "$canonical"; then
      record_path D "$canonical" || return 1
    fi
  done
}

record_installed_file() {
  local path=$1
  record_path F "$path"
}

# inst SOURCE DEST [MODE]
inst() {
  local src=$1 dst=$2 mode=${3:-0644}
  if [ "$DRY" -eq 1 ]; then
    printf '   + %s\n' "$dst"
    return 0
  fi
  if [ ! -f "$src" ]; then
    warn "missing file: $src"
    return 1
  fi
  ensure_dir "$(dirname_of "$dst")" || return 1
  record_installed_file "$dst" || return 1
  cp -f -- "$src" "$dst" || return 1
  chmod "$mode" -- "$dst" || return 1
}

# render SOURCE DEST [MODE] [KEY=VALUE ...]
render() {
  local src=$1 dst=$2 mode=${3:-0644}
  shift 3
  if [ "$DRY" -eq 1 ]; then
    printf '   + %s\n' "$dst"
    return 0
  fi
  if [ ! -f "$src" ]; then
    warn "missing template: $src"
    return 1
  fi
  local -a sedargs=(
    -e "s|@EGOMAT@|$(esc "$EGOMAT")|g"
    -e "s|@EGOMAT_GUI@|$(esc "$EGOMAT_GUI")|g"
    -e "s|@LIBDIR@|$(esc "$LIB")|g"
    -e "s|@VERSION@|$(esc "$VERSION")|g"
  )
  local kv
  for kv in "$@"; do
    sedargs+=(-e "s|@${kv%%=*}@|$(esc "${kv#*=}")|g")
  done
  ensure_dir "$(dirname_of "$dst")" || return 1
  record_installed_file "$dst" || return 1
  sed "${sedargs[@]}" -- "$src" >"$dst" || return 1
  chmod "$mode" -- "$dst" || return 1
}

# ---------------------------------------------------------------------------
# Steps
# ---------------------------------------------------------------------------
step_payload() {
  say "  program files -> $LIB"
  ensure_dir "$LIB" || return 1
  init_manifest || return 1
  inst "$SRC/bin/egomat" "$LIB/bin/egomat" 0755 || return 1
  local f
  for f in "$SRC"/lib/*.sh; do
    inst "$f" "$LIB/lib/$(basename -- "$f")" 0644 || return 1
  done
  while IFS= read -r -d '' f; do
    inst "$f" "$LIB/share/${f#"$SRC/share/"}" 0644 || return 1
  done < <(find "$SRC/share" -type f -print0)
  inst "$SRC/install.sh"   "$LIB/install.sh"   0755 || return 1
  inst "$SRC/uninstall.sh" "$LIB/uninstall.sh" 0755 || return 1
  inst "$SRC/README.md"    "$LIB/README.md"    0644 || return 1
  inst "$SRC/LICENSE"      "$LIB/LICENSE"      0644 || return 1
}

step_link() {
  say "  launcher -> $EGOMAT"
  if [ "$DRY" -eq 1 ]; then
    printf '   + %s -> %s\n' "$EGOMAT" "$LIB/bin/egomat"
    return 0
  fi
  ensure_dir "$BIN" || return 1
  record_installed_file "$EGOMAT" || return 1
  if ln -sfn "$LIB/bin/egomat" "$EGOMAT" 2>/dev/null; then
    return 0
  fi
  {
    printf '#!/bin/sh\n'
    printf 'exec "%s" "$@"\n' "$LIB/bin/egomat"
  } >"$EGOMAT" || return 1
  chmod 0755 -- "$EGOMAT" || return 1
}

step_kde() {
  say "  KDE service menu -> $DATA_HOME/kio/servicemenus"
  render "$SRC/share/kio/egomat.desktop.in" \
    "$DATA_HOME/kio/servicemenus/egomat.desktop" 0644
}

step_app() {
  say "  application entry -> $DATA_HOME/applications"
  render "$SRC/share/applications/egomat.desktop.in" \
    "$DATA_HOME/applications/egomat.desktop" 0644 || return 1
  inst "$SRC/share/icons/egomat.svg" \
    "$DATA_HOME/icons/hicolor/scalable/apps/egomat.svg" 0644 || return 1
}

step_gui() {
  if ! have go; then
    warn "--gui needs Go to build egomat-gui; install Go and rerun, or drop --gui"
    return 1
  fi
  say "  egomat-gui -> $EGOMAT_GUI"
  local built="$SRC/build/egomat-gui"
  if [ "$DRY" -eq 1 ]; then
    printf '   + %s\n' "$EGOMAT_GUI"
    if [ "$DO_APP" -eq 1 ]; then
      printf '   + %s\n' "$DATA_HOME/applications/egomat-gui.desktop"
    fi
    return 0
  fi
  mkdir -p -- "$SRC/build" || return 1
  if ! (cd "$SRC" && go build -trimpath -ldflags='-s -w' -o "$built" ./cmd/egomat-gui); then
    warn "could not build egomat-gui"
    return 1
  fi
  inst "$built" "$EGOMAT_GUI" 0755
  if [ "$DO_APP" -eq 1 ]; then
    render "$SRC/share/applications/egomat-gui.desktop.in" \
      "$DATA_HOME/applications/egomat-gui.desktop" 0644
  fi
  return 0
}

step_filemanagers() {
  local id label action

  say "  Nautilus scripts -> $DATA_HOME/nautilus/scripts/Egomat"
  while IFS='|' read -r id label action; do
    [ -n "$id" ] || continue
    render "$SRC/share/nautilus/egomat-script.in" \
      "$DATA_HOME/nautilus/scripts/Egomat/$label" 0755 "ACTION=$action" || return 1
  done <<'ACTIONS'
menu|Egomat...|assistant
convert-webp|Convert to WebP|menu convert webp
convert-jpeg|Convert to JPEG|menu convert jpeg
optimize-balanced|Optimize (balanced)|menu optimize balanced
ACTIONS

  say "  Nemo actions -> $DATA_HOME/nemo/actions"
  while IFS='|' read -r id label action; do
    [ -n "$id" ] || continue
    render "$SRC/share/nemo/egomat.nemo_action.in" \
      "$DATA_HOME/nemo/actions/egomat-$id.nemo_action" 0644 \
      "NAME=Egomat: $label" "ACTION=$action" || return 1
  done <<'ACTIONS'
menu|Egomat...|assistant
convert-webp|Convert to WebP|menu convert webp
convert-jpeg|Convert to JPEG|menu convert jpeg
optimize-balanced|Optimize (balanced)|menu optimize balanced
ACTIONS

  say "  Thunar send-to -> $DATA_HOME/Thunar/sendto"
  while IFS='|' read -r id label action; do
    [ -n "$id" ] || continue
    render "$SRC/share/thunar/egomat-sendto.desktop.in" \
      "$DATA_HOME/Thunar/sendto/egomat-$id.desktop" 0644 \
      "NAME=Egomat: $label" "ACTION=$action" || return 1
  done <<'ACTIONS'
menu|Egomat...|assistant
convert-webp|Convert to WebP|menu convert webp
convert-jpeg|Convert to JPEG|menu convert jpeg
optimize-balanced|Optimize (balanced)|menu optimize balanced
ACTIONS

  # Caja scripts live in the user's XDG config, so only write them for a
  # normal per-user installation.
  if [ "$MODE" = user ] && [ "$PREFIX_EXPLICIT" -eq 0 ]; then
    say "  Caja scripts -> $CONFIG_HOME/caja/scripts/Egomat"
    while IFS='|' read -r id label action; do
      [ -n "$id" ] || continue
      render "$SRC/share/nautilus/egomat-script.in" \
        "$CONFIG_HOME/caja/scripts/Egomat/$label" 0755 "ACTION=$action" || return 1
    done <<'ACTIONS'
menu|Egomat...|assistant
convert-webp|Convert to WebP|menu convert webp
convert-jpeg|Convert to JPEG|menu convert jpeg
optimize-balanced|Optimize (balanced)|menu optimize balanced
ACTIONS
  fi
  return 0
}

step_completions() {
  say "  shell completions -> $DATA_HOME/{bash-completion/completions,zsh/site-functions,fish/vendor_completions.d}"
  inst "$SRC/share/completions/egomat.bash" \
    "$DATA_HOME/bash-completion/completions/egomat" 0644 || return 1
  inst "$SRC/share/completions/egomat.zsh" \
    "$DATA_HOME/zsh/site-functions/_egomat" 0644 || return 1
  inst "$SRC/share/completions/egomat.fish" \
    "$DATA_HOME/fish/vendor_completions.d/egomat.fish" 0644 || return 1
}

step_refresh() {
  [ "$DRY" -eq 1 ] && return 0
  if [ -d "$DATA_HOME/applications" ] && have update-desktop-database; then
    update-desktop-database "$DATA_HOME/applications" >/dev/null 2>&1
  fi
  if [ -d "$DATA_HOME/icons/hicolor" ] && have gtk-update-icon-cache; then
    gtk-update-icon-cache -q -t -f "$DATA_HOME/icons/hicolor" >/dev/null 2>&1
  fi
  return 0
}

# ---------------------------------------------------------------------------
# Go
# ---------------------------------------------------------------------------
if [ "$DRY" -eq 1 ]; then
  say "Dry run — nothing is written."
fi
say "Installing egomat $VERSION into $PREFIX"

step_payload      || { warn "payload installation failed"; exit 1; }
step_link         || { warn "could not create the launcher"; exit 1; }
if [ "$DO_KDE" -eq 1 ]; then step_kde || exit 1; fi
if [ "$DO_APP" -eq 1 ]; then step_app || exit 1; fi
if [ "$DO_GUI" -eq 1 ]; then step_gui || exit 1; fi
if [ "$DO_COMPLETIONS" -eq 1 ]; then step_completions || exit 1; fi
if [ "$DO_FM"  -eq 1 ]; then step_filemanagers || exit 1; fi
step_refresh

say ""
say "Done."
say "  command : $EGOMAT"
say "  library : $LIB"
if [ "$DO_KDE" -eq 1 ]; then
  say "  Dolphin : right-click an image -> Egomat"
  say "            (if the submenu does not appear, run kbuildsycoca6 or log out and back in)"
fi
case ":$PATH:" in
  *":$BIN:"*) ;;
  *) say ""
     say "Note: $BIN is not in your PATH. Add it, e.g.:"
     say "  echo 'export PATH=\"\$HOME/.local/bin:\$PATH\"' >> ~/.profile" ;;
esac
if [ "$DO_COMPLETIONS" -eq 1 ]; then
  say ""
  say "Completions: open a new shell to pick them up. For zsh, if _egomat"
  say "is not found, add the site-functions directory to your fpath first:"
  say "  echo 'fpath=($DATA_HOME/zsh/site-functions \$fpath)' >> ~/.zshrc"
fi

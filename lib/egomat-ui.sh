# shellcheck shell=bash
# egomat — user interaction. Uses kdialog, zenity or notify-send when there is
# a session to talk to, and plain text otherwise.

EGOMAT_INTERACTIVE=0

# Decide whether to talk through dialogs or plain text. Called once by
# bin/egomat after the global options have been parsed.
egomat_detect_ui() {
  EGOMAT_INTERACTIVE=0
  case ${EGOMAT_UI:-auto} in
    none) EGOMAT_INTERACTIVE=0 ;;
    dialog) EGOMAT_INTERACTIVE=1 ;;
    *)
      if [ -t 0 ] && [ -t 2 ]; then
        # Running in a terminal: text is friendlier than popups.
        EGOMAT_INTERACTIVE=0
      elif [ -n "${DISPLAY-}${WAYLAND_DISPLAY-}" ] && { have kdialog || have zenity; }; then
        EGOMAT_INTERACTIVE=1
      fi
      ;;
  esac
  return 0
}

# Show an informational message.
ui_msg() {
  local title=$1 body=$2
  if have kdialog; then
    kdialog --title "$title" --msgbox "$body" >/dev/null 2>&1
  elif have zenity; then
    zenity --info --title="$title" --text="$body" --no-wrap >/dev/null 2>&1
  elif have notify-send; then
    notify-send -a "$EGOMAT_NAME" "$title" "$body" >/dev/null 2>&1
  else
    printf '%s: %s\n' "$title" "$body" >&2
  fi
}

# Show an error message.
ui_error() {
  local title=$1 body=$2
  if have kdialog; then
    kdialog --title "$title" --error "$body" >/dev/null 2>&1
  elif have zenity; then
    zenity --error --title="$title" --text="$body" --no-wrap >/dev/null 2>&1
  elif have notify-send; then
    notify-send -a "$EGOMAT_NAME" -u critical "$title" "$body" >/dev/null 2>&1
  else
    printf '%s: %s\n' "$title" "$body" >&2
  fi
}

# Ask for a single line of text. Prints the answer; returns non-zero on cancel.
ui_prompt() {
  local title=$1 label=$2 default=${3-}
  if have kdialog; then
    kdialog --title "$title" --inputbox "$label" "$default" 2>/dev/null
  elif have zenity; then
    zenity --entry --title="$title" --text="$label" --entry-text="$default" 2>/dev/null
  else
    log_error "no dialog program found (install kdialog or zenity)"
    return 1
  fi
}

# Pick one entry from a value/label list. Arguments: title, prompt, then
# value label value label ... . Prints the chosen value; non-zero on cancel.
ui_choose() {
  local title=$1 prompt=$2
  shift 2
  local -a args=()
  while [ $# -gt 1 ]; do
    args+=("$1" "$2")
    shift 2
  done
  if have kdialog; then
    kdialog --title "$title" --menu "$prompt" "${args[@]}" 2>/dev/null
  elif have zenity; then
    zenity --list --title="$title" --text="$prompt" \
      --column=Key --column=Action --hide-column=1 --print-column=1 \
      "${args[@]}" 2>/dev/null
  else
    log_error "no dialog program found (install kdialog or zenity)"
    return 1
  fi
}

# Ask for one or more files. Prints one path per line; non-zero on cancel.
ui_pick_files() {
  local start=${1-${HOME:-/}}
  if have kdialog; then
    kdialog --title "$EGOMAT_NAME" --getopenfilename "$start" 'image/*' \
      --multiple --separate-output 2>/dev/null
  elif have zenity; then
    zenity --file-selection --multiple --separator=$'\n' \
      --title="$EGOMAT_NAME" \
      --file-filter='Images | *.png *.jpg *.jpeg *.jfif *.webp *.avif *.gif *.bmp *.tif *.tiff *.svg *.ico' 2>/dev/null
  else
    log_error "no dialog program found (install kdialog or zenity)"
    return 1
  fi
}

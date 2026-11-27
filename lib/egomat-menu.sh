# shellcheck shell=bash
# egomat — context-menu entry points and the interactive assistant.
# The .desktop actions in share/ all end up calling `egomat menu ...`.

usage() {
  cat <<EOF
$EGOMAT_NAME $EGOMAT_VERSION — convert and optimise images from the command
line or from your file manager's right-click menu.

Usage:
  $EGOMAT_NAME convert [options] FILE...
  $EGOMAT_NAME optimize [options] FILE...
  $EGOMAT_NAME resize GEOMETRY [options] FILE...
  $EGOMAT_NAME info FILE...
  $EGOMAT_NAME formats
  $EGOMAT_NAME assistant [FILE...]
  $EGOMAT_NAME menu ACTION [PARAM] FILE...
  $EGOMAT_NAME install [options]
  $EGOMAT_NAME uninstall [options]
  $EGOMAT_NAME completion SHELL
  $EGOMAT_NAME version | help [COMMAND]

Every command accepts -h/--help, and "help COMMAND" shows the same text:
  $EGOMAT_NAME help convert
  $EGOMAT_NAME convert --help
Run "$EGOMAT_NAME help COMMAND" for the options and examples of a command.

Convert options:
  -f, --format FMT     target format: $EGOMAT_TARGETS
  -q, --quality N      quality 1-100 for lossy formats
                       (defaults: jpg 88, webp 82, avif 60)
  -r, --resize GEOM    resize; e.g. 1920, 1920x1080, 800x800!
                       (full ImageMagick geometry syntax)
  -o, --outdir DIR     write results into DIR (default: next to the source)
  -s, --suffix SUFFIX  add SUFFIX to the new file name
      --on-conflict P  what to do when the output file exists: rename
                       (default; unique numbered name), skip, overwrite,
                       or ask (interactive sessions only)
      --overwrite      shorthand for --on-conflict overwrite
      --keep-metadata  do not strip EXIF/ICC data
      --delete-source  remove the source after a successful conversion
      --recursive      accept directories; process the image files inside
      --dry-run        show the plan and write nothing

Optimize options:
  -l, --level LEVEL    light | balanced | aggressive  (default: balanced)
  -o, --outdir DIR     write optimised copies into DIR instead of in place
  -s, --suffix SUFFIX  write to a new name instead of in place
      --on-conflict P  what to do when the output copy exists: rename
                       (default), skip, overwrite, or ask
      --backup         keep a copy of the original as FILE.egomat-orig
      --force          replace the file even when nothing got smaller
      --recursive      accept directories; process the image files inside
      --dry-run        show the plan and write nothing

Resize options:
  -o, --outdir DIR     write into DIR
  -s, --suffix SUFFIX  file-name suffix (default: -resized)
      --on-conflict P  what to do when the output file exists: rename
                       (default), skip, overwrite, or ask
      --overwrite      shorthand for --on-conflict overwrite
      --recursive      accept directories; process the image files inside
      --dry-run        show the plan and write nothing

Menu actions (used by the desktop entries):
  convert FORMAT | optimize LEVEL | resize GEOMETRY | info
  The words "custom" (FORMAT), "ask" (LEVEL) and "ask" (GEOMETRY) open a
  prompt instead.

Global options (before the command):
  --quiet   --verbose   --no-ui   --ui   --ui=none|auto|dialog
  (--quiet/--verbose also work after convert, optimize, and resize.)

Examples:
  $EGOMAT_NAME convert -f webp -q 80 -- *.png
  $EGOMAT_NAME convert -f avif -r 1920 -o "\$HOME/web" -- images/*.jpg
  $EGOMAT_NAME convert -f png --on-conflict skip -- *.jpg
  $EGOMAT_NAME convert -f webp --recursive -- photos/
  $EGOMAT_NAME optimize -l balanced --backup -- photo.jpg
  $EGOMAT_NAME resize 1600 -- photo.jpg
  $EGOMAT_NAME info -- shot.png

Conversion needs ImageMagick, ffmpeg, cwebp/avifenc or img2pdf.
Optimization needs any of oxipng, optipng, pngquant, jpegoptim, gifsicle,
svgo, cwebp/webpmux or ImageMagick. Run "$EGOMAT_NAME formats" to see what
this machine has.
EOF
}

usage_convert() {
  cat <<EOF
$EGOMAT_NAME convert — convert images to a different format.

Usage:
  $EGOMAT_NAME convert -f FORMAT [options] FILE...
  $EGOMAT_NAME convert [options] -- FILE...

Options:
  -f, --format FMT     target format, required: $EGOMAT_TARGETS
                       ("jpeg" means jpg, "tif" means tiff; a leading dot
                       such as ".webp" is accepted)
  -q, --quality N      quality 1-100 for lossy formats
                       (ImageMagick defaults: jpg 88, webp 82, avif 60,
                       pdf 90; other backends use their own scale)
  -r, --resize GEOM    resize while converting; e.g. 1920, 1920x1080,
      --size GEOM      800x800!, 1920x>, x1080 (ImageMagick geometry;
                       --size is accepted as an alias for --resize)
  -o, --outdir DIR     write results into DIR (default: next to the
      --output-dir DIR source); the directory is created if needed
  -s, --suffix SUFFIX  add SUFFIX to the new file name
      --on-conflict P  what to do when the output file already exists:
                       rename (default) writes a unique numbered name
                       (photo-1.webp, ...), skip writes nothing and
                       reports the file as skipped, overwrite replaces
                       the existing output (never the source), and ask
                       prompts for each file (interactive sessions
                       only: a terminal or desktop dialogs)
      --overwrite      shorthand for --on-conflict overwrite
      --keep-metadata  do not strip EXIF/ICC data where the backend
                       supports keeping it
      --delete-source  remove the source after a successful conversion
      --recursive      accept directories as inputs: each directory is
                       walked and every image file inside is converted;
                       files that do not look like images are skipped and
                       counted as skipped inputs, separately from
                       failures (hidden files and directories are
                       ignored; symlinks to directories are not followed)
      --dry-run        print the planned input, output, operation, and
                       conflict decision for each file and write nothing
      --quiet          print only errors
      --verbose        print backend decisions and errors
  -h, --help           show this help and exit

Behaviour:
  Conversion never writes over the source. Converting photo.jpg to WebP
  writes photo.webp next to it; converting to the same format writes
  photo-egomat.<fmt>. Existing outputs are handled by --on-conflict:
  unique rename by default, or skip, overwrite, or ask. Metadata is
  stripped by default where the backend supports it. With --recursive,
  a directory argument is an error without the flag; with it, nested
  images are converted and skipped non-images are reported in the final
  summary as skipped inputs, never as failures. Use "--" before
  file names that begin with a dash.

Examples:
  $EGOMAT_NAME convert -f webp photo.jpg
  $EGOMAT_NAME convert -f webp -q 80 -- *.png
  $EGOMAT_NAME convert -f avif -r 1920 -o "\$HOME/web" -- images/*.jpg
  $EGOMAT_NAME convert --format png --resize 1200x800 --outdir resized -- photo.jpg
  $EGOMAT_NAME convert -f jpg --keep-metadata photo.png
  $EGOMAT_NAME convert -f webp --on-conflict overwrite photo.jpg
  $EGOMAT_NAME convert -f webp --on-conflict skip -- *.jpg
  $EGOMAT_NAME convert -f webp --delete-source photo.jpg
  $EGOMAT_NAME convert --dry-run -f webp photo.jpg
  $EGOMAT_NAME convert -f webp --recursive -o web -- photos/
  $EGOMAT_NAME help convert
EOF
}

usage_optimize() {
  cat <<EOF
$EGOMAT_NAME optimize — shrink images in place or into new files.

Usage:
  $EGOMAT_NAME optimize [options] FILE...
  $EGOMAT_NAME optimize [options] -- FILE...

Options:
  -l, --level LEVEL    light | balanced | aggressive (default: balanced)
                       (aliases: lossless/fast, normal/mid,
                       max/heavy; light is lossless, balanced makes a
                       small quality trade, aggressive saves the most)
  -o, --outdir DIR     write optimised copies into DIR instead of in
      --output-dir DIR place
  -s, --suffix SUFFIX  write to a new name instead of in place
      --on-conflict P  what to do when the output copy exists: rename
                       (default; unique numbered name), skip, overwrite,
                       or ask (interactive sessions only)
      --backup         keep a copy of the original as FILE.egomat-orig
                       before writing;
                       if the backup fails, nothing is replaced
      --force          replace even when the candidate is not smaller
                       (the candidate must still be a readable image)
      --recursive      accept directories as inputs: each directory is
                       walked and every image file inside is optimized;
                       files that do not look like images are skipped and
                       counted as skipped inputs, separately from
                       failures (hidden files and directories are
                       ignored; symlinks to directories are not followed)
      --dry-run        print the planned input, output, and replacement
                       decision for each file and write nothing
      --quiet          print only errors
      --verbose        print backend decisions and errors
  -h, --help           show this help and exit

Behaviour:
  Each file is optimised on a temporary copy first. The source (or the
  requested output copy) is written only when the candidate is nonempty,
  still readable as an image, and smaller than the input. Without
  --force, an empty, unreadable, equal, or larger candidate is discarded
  and the source stays unchanged; with --outdir/--suffix no output file
  is written in that case. With --recursive, a directory argument is an
  error without the flag; with it, nested images are optimized and
  skipped non-images are reported as skipped inputs, never as failures.
  See "$EGOMAT_NAME help optimize" and the README for what each level
  does per format. Use "--" before file
  names that begin with a dash.

Examples:
  $EGOMAT_NAME optimize photo.jpg
  $EGOMAT_NAME optimize -l balanced --backup -- photo.jpg
  $EGOMAT_NAME optimize -l aggressive --force -- photo.png
  $EGOMAT_NAME optimize -l light -o optimized -- photo.jpg
  $EGOMAT_NAME optimize -l light --backup photo.png photo2.jpg
  $EGOMAT_NAME optimize --dry-run --backup photo.jpg
  $EGOMAT_NAME optimize -l light --recursive -o optimized -- photos/
  $EGOMAT_NAME help optimize
EOF
}

usage_resize() {
  cat <<EOF
$EGOMAT_NAME resize — write a resized copy in the source format.

Usage:
  $EGOMAT_NAME resize GEOMETRY [options] FILE...
  $EGOMAT_NAME resize GEOMETRY -- FILE...

GEOMETRY is ImageMagick size syntax, for example:
  1920       width of 1920 pixels, preserve aspect ratio
  1920x1080  fit within these dimensions
  800x800!   force these exact dimensions
  1920x>     shrink only
  x1080      height of 1080 pixels, preserve aspect ratio

Options:
  -o, --outdir DIR     write into DIR (default: next to the source)
      --output-dir DIR
  -s, --suffix SUFFIX  file-name suffix (default: -resized)
      --on-conflict P  what to do when the output file already exists:
                       rename (default) writes a unique numbered name,
                       skip writes nothing and reports the file as
                       skipped, overwrite replaces the existing output
                       (never the source), and ask prompts for each file
                       (interactive sessions only)
      --overwrite      shorthand for --on-conflict overwrite
      --recursive      accept directories as inputs: each directory is
                       walked and every image file inside is resized;
                       files that do not look like images are skipped and
                       counted as skipped inputs, separately from
                       failures (hidden files and directories are
                       ignored; symlinks to directories are not followed)
      --dry-run        print the planned input, output, and conflict
                       decision for each file and write nothing
      --quiet          print only errors
      --verbose        print backend decisions and errors
  -h, --help           show this help and exit

Behaviour:
  Resize writes a new file, e.g. photo.jpg resized to 1600 becomes
  photo-resized.jpg next to the source. Use --suffix to change the name
  and --outdir to change the folder. With --recursive, a directory
  argument is an error without the flag; with it, nested images are
  resized and skipped non-images are reported as skipped inputs, never
  as failures. The FFmpeg fallback translates
  numeric width/height and "!"; modifiers such as ">", "<", "^", and "%"
  may not be honoured by that backend. Use "--" before file names that
  begin with a dash.

Examples:
  $EGOMAT_NAME resize 1600 -- photo.jpg
  $EGOMAT_NAME resize 1920x1080 -- photo.jpg
  $EGOMAT_NAME resize 800x800! -- photo.png
  $EGOMAT_NAME resize 1920x\> -- photo.jpg
  $EGOMAT_NAME resize 200 -o thumbs -- photo.png
  $EGOMAT_NAME resize 200 --suffix -small -- photo.png
  $EGOMAT_NAME resize --dry-run 1600 -- photo.jpg
  $EGOMAT_NAME resize 200 --recursive -o thumbs -- photos/
  $EGOMAT_NAME help resize
EOF
}

usage_info() {
  cat <<EOF
$EGOMAT_NAME info — show format, dimensions, and size for images.

Usage:
  $EGOMAT_NAME info FILE...
  $EGOMAT_NAME info -- FILE...

Options:
  -h, --help           show this help and exit

Behaviour:
  Prints the path, format, pixel dimensions, and byte size for each
  file. Files that are not readable images are reported on stderr and
  skipped; info never modifies a file. Use "--" before file names that
  begin with a dash. Global --quiet/--verbose go before the command,
  e.g. "$EGOMAT_NAME --verbose info photo.png".

Examples:
  $EGOMAT_NAME info photo.png
  $EGOMAT_NAME info -- shot.png
  $EGOMAT_NAME info *.jpg
  $EGOMAT_NAME info -- -odd-image.png
  $EGOMAT_NAME help info
EOF
}

usage_formats() {
  cat <<EOF
$EGOMAT_NAME formats — list installed image tools and target formats.

Usage:
  $EGOMAT_NAME formats

Options:
  -h, --help           show this help and exit

Behaviour:
  Lists the target formats ($EGOMAT_TARGETS) and which known
  conversion, optimisation, and dialog tools are present on this
  machine. This is a tool inventory, not a probe: a tool being present
  does not guarantee it can encode every listed target. Run "optimize"
  or "convert" to see whether a concrete job works.

Examples:
  $EGOMAT_NAME formats
  $EGOMAT_NAME formats | grep -E "magick|ffmpeg"
  $EGOMAT_NAME help formats
EOF
}

usage_assistant() {
  cat <<EOF
$EGOMAT_NAME assistant — interactive wizard for file-manager use.

Usage:
  $EGOMAT_NAME assistant [FILE...]
  $EGOMAT_NAME assistant -- FILE...

Options:
  -h, --help           show this help and exit

Behaviour:
  Opens a dialog (kdialog or zenity, whichever is installed) offering
  convert, resize, optimize, and info actions for the given files, or
  a file picker when no files are given. It runs the same commands as
  the command line. "gui" is an alias for "assistant".

Examples:
  $EGOMAT_NAME assistant
  $EGOMAT_NAME assistant -- photo.jpg photo.png
  $EGOMAT_NAME assistant photo.jpg
  $EGOMAT_NAME help assistant
EOF
}

usage_menu() {
  cat <<EOF
$EGOMAT_NAME menu — entry point used by the desktop actions.

Usage:
  $EGOMAT_NAME menu ACTION [PARAM] FILE...

ACTION is one of:
  convert FORMAT | optimize LEVEL | resize GEOMETRY | info

For convert, FORMAT may be "custom" to be prompted for. For optimize,
LEVEL may be "ask" to be prompted for. For resize, GEOMETRY may be
"ask" to be prompted for. Prompts need kdialog or zenity. This command
is what the .desktop entries invoke; most people use convert, optimize,
resize, and info directly.

Options:
  -h, --help           show this help and exit

Examples:
  $EGOMAT_NAME menu convert webp photo.jpg
  $EGOMAT_NAME menu optimize light photo.jpg
  $EGOMAT_NAME menu resize 1920 photo.jpg
  $EGOMAT_NAME menu info photo.jpg
  $EGOMAT_NAME help menu
EOF
}

usage_install() {
  cat <<EOF
$EGOMAT_NAME install — install the command and desktop actions.

Usage:
  $EGOMAT_NAME install [options]

Options (passed to install.sh):
      --user           install for the current user (default):
                       ~/.local/bin/egomat, ~/.local/lib/egomat, and
                       the XDG data directory
      --system         install into /usr/local (needs write access)
      --prefix DIR     install under DIR (DIR/bin, DIR/lib, DIR/share)
      --no-kde         skip the KDE/Dolphin service menu
      --no-freedesktop skip the Nautilus, Nemo, Thunar, and Caja actions
      --no-app         skip the application-menu entry and the icon
      --no-completions skip the Bash, Zsh, and Fish completions
      --gui            also build and install egomat-gui (needs Go 1.23+)
      --no-gui         do not build egomat-gui (default)
  -n, --dry-run        print what would be done, change nothing
  -h, --help           show this help and exit

Examples:
  $EGOMAT_NAME install
  sudo $EGOMAT_NAME install --system
  $EGOMAT_NAME install --prefix "\$HOME/opt/egomat"
  $EGOMAT_NAME install --no-kde --no-freedesktop --no-app
  $EGOMAT_NAME install --gui
  $EGOMAT_NAME install --dry-run
  $EGOMAT_NAME help install
EOF
}

usage_uninstall() {
  cat <<EOF
$EGOMAT_NAME uninstall — remove an install recorded by install.sh.

Usage:
  $EGOMAT_NAME uninstall [options]

Options (passed to uninstall.sh):
      --user           remove the current user's installation (default)
      --system         remove the /usr/local installation
      --prefix DIR     remove the installation under DIR
  -n, --dry-run        print what would be removed, change nothing
  -h, --help           show this help and exit

Behaviour:
  Removes only files and directories recorded in the install manifest;
  unrelated files (for example other Nautilus/Caja Egomat scripts) are
  preserved. Use the same --user/--system/--prefix as the install.

Examples:
  $EGOMAT_NAME uninstall
  sudo $EGOMAT_NAME uninstall --system
  $EGOMAT_NAME uninstall --prefix "\$HOME/opt/egomat"
  $EGOMAT_NAME uninstall --dry-run
  $EGOMAT_NAME help uninstall
EOF
}

usage_version() {
  cat <<EOF
$EGOMAT_NAME version — print the Egomat version.

Usage:
  $EGOMAT_NAME version
  $EGOMAT_NAME --version
  $EGOMAT_NAME -V

Options:
  -h, --help           show this help and exit

Examples:
  $EGOMAT_NAME version
  $EGOMAT_NAME --version
  $EGOMAT_NAME help version
EOF
}

usage_completion() {
  cat <<EOF
$EGOMAT_NAME completion — print shell completion for Bash, Zsh, or Fish.

Usage:
  $EGOMAT_NAME completion SHELL

SHELL is one of:
  bash  zsh  fish

Options:
  -h, --help           show this help and exit

Behaviour:
  Prints a completion script on standard output. The script completes
  commands, options, format and optimization-level values, and file
  arguments. install.sh installs these automatically; use this command
  when installing by hand or to inspect the script.

Examples:
  $EGOMAT_NAME completion bash
  $EGOMAT_NAME completion bash > ~/.local/share/bash-completion/completions/egomat
  $EGOMAT_NAME completion zsh > ~/.zfunc/_egomat
  $EGOMAT_NAME completion fish > ~/.config/fish/completions/egomat.fish
  $EGOMAT_NAME help completion
EOF
}

usage_help() {
  cat <<EOF
$EGOMAT_NAME help — show help for Egomat or for one command.

Usage:
  $EGOMAT_NAME help [COMMAND]
  $EGOMAT_NAME COMMAND --help
  $EGOMAT_NAME COMMAND -h

COMMAND is one of:
  convert  optimize  resize  info  formats  assistant  menu
  install  uninstall  completion  version  help

With no COMMAND, the general help is shown. With a COMMAND, that
command's options and examples are shown. Both forms exit 0; an
unknown COMMAND exits non-zero.

Examples:
  $EGOMAT_NAME help
  $EGOMAT_NAME help convert
  $EGOMAT_NAME help optimize
  $EGOMAT_NAME convert --help
  $EGOMAT_NAME help help
EOF
}

# Print the help text for one command (aliases resolved to canonical names).
show_usage_for() {
  case ${1-} in
    convert) usage_convert ;;
    optimize) usage_optimize ;;
    resize) usage_resize ;;
    info) usage_info ;;
    formats|format) usage_formats ;;
    assistant|gui) usage_assistant ;;
    menu) usage_menu ;;
    install) usage_install ;;
    uninstall) usage_uninstall ;;
    completion) usage_completion ;;
    version|-V|--version) usage_version ;;
    help|-h|--help) usage_help ;;
    '') usage ;;
    *)
      log_error "unknown help topic: $1"
      printf "Try '%s help'.\n" "$EGOMAT_NAME" >&2
      return 2
      ;;
  esac
}

cmd_help() {
  show_usage_for "${1-}"
}

# ---------------------------------------------------------------------------
# completion — print the completion script for one shell
# ---------------------------------------------------------------------------
cmd_completion() {
  local shell=${1-} script
  if args_have_help_flag "$@"; then
    usage_completion
    return 0
  fi
  case $shell in
    bash) script=$EGOMAT_ROOT/share/completions/egomat.bash ;;
    zsh)  script=$EGOMAT_ROOT/share/completions/egomat.zsh ;;
    fish) script=$EGOMAT_ROOT/share/completions/egomat.fish ;;
    '')
      log_error "completion: missing shell (bash, zsh, or fish)"
      printf "Try '%s help completion'.\n" "$EGOMAT_NAME" >&2
      return 2
      ;;
    *)
      log_error "completion: unsupported shell: $shell"
      printf "Supported shells: bash zsh fish.\n" >&2
      return 2
      ;;
  esac
  if [ ! -r "$script" ]; then
    log_error "completion: script not found: $script"
    printf "Reinstall with '%s install'.\n" "$EGOMAT_NAME" >&2
    return 1
  fi
  cat "$script"
}

# ---------------------------------------------------------------------------
# menu — what the .desktop actions run
# ---------------------------------------------------------------------------
_menu_convert_custom() {
  local fmt
  fmt=$(ui_prompt "$EGOMAT_NAME" "Target format ($EGOMAT_TARGETS):" "webp") || exit 0
  [ -n "$fmt" ] || exit 0
  fmt=$(norm_format "$fmt")
  if ! format_supported "$fmt"; then
    ui_error "$EGOMAT_NAME" "Unsupported format: $fmt"
    exit 1
  fi
  cmd_convert -f "$fmt" -- "$@"
}

_menu_resize_ask() {
  local geo
  geo=$(ui_prompt "$EGOMAT_NAME" "New size (e.g. 1920, 1920x1080, 800x800!):" "") || exit 0
  [ -n "$geo" ] || exit 0
  if ! check_geometry "$geo"; then
    ui_error "$EGOMAT_NAME" "Invalid size: $geo"
    exit 1
  fi
  cmd_resize "$geo" -- "$@"
}

cmd_menu() {
  if args_have_help_flag "$@"; then
    usage_menu
    return 0
  fi
  local verb=${1-}
  [ $# -gt 0 ] && shift
  [ -n "$verb" ] || die "menu: no action given (try '$EGOMAT_NAME help')"

  local param=""
  case $verb in
    convert|optimize|resize)
      param=${1-}
      [ $# -gt 0 ] && shift
      ;;
  esac

  if [ $# -eq 0 ]; then
    ui_error "$EGOMAT_NAME" "No files selected."
    exit 1
  fi

  case $verb in
    convert)
      case $param in
        '')
          ui_error "$EGOMAT_NAME" "No target format given."
          exit 1
          ;;
        custom)
          _menu_convert_custom "$@"
          ;;
        *)
          param=$(norm_format "$param")
          if ! format_supported "$param"; then
            ui_error "$EGOMAT_NAME" "Unsupported format: $param"
            exit 1
          fi
          cmd_convert -f "$param" -- "$@"
          ;;
      esac
      ;;
    optimize)
      local level
      if [ "$param" = ask ] || [ -z "$param" ]; then
        level=balanced
        level=$(ui_choose "$EGOMAT_NAME" "How hard should I squeeze?" \
          light "Light — lossless, no quality change" \
          balanced "Balanced — small, invisible quality loss" \
          aggressive "Aggressive — largest savings") || exit 0
      else
        level=$(norm_level "$param")
      fi
      if [ -z "$level" ]; then
        ui_error "$EGOMAT_NAME" "Unknown optimization level: $param"
        exit 1
      fi
      cmd_optimize -l "$level" -- "$@"
      ;;
    resize)
      if [ -z "$param" ] || [ "$param" = ask ]; then
        _menu_resize_ask "$@"
      else
        if ! check_geometry "$param"; then
          ui_error "$EGOMAT_NAME" "Invalid size: $param"
          exit 1
        fi
        cmd_resize "$param" -- "$@"
      fi
      ;;
    info)
      cmd_info -- "$@"
      ;;
    *)
      die "menu: unknown action: $verb"
      ;;
  esac
}

# ---------------------------------------------------------------------------
# assistant — the file-manager wizard
# ---------------------------------------------------------------------------
cmd_assistant() {
  if args_have_help_flag "$@"; then
    usage_assistant
    return 0
  fi
  if ! have kdialog && ! have zenity; then
    die "assistant: needs kdialog or zenity. Use '$EGOMAT_NAME help' for the command line."
  fi
  [ "${1-}" = "--" ] && shift

  local -a files=()
  local line listing action fmt geo

  if [ $# -gt 0 ]; then
    files=("$@")
  else
    listing=$(ui_pick_files) || exit 0
    [ -n "$listing" ] || exit 0
    while IFS= read -r line; do
      [ -n "$line" ] && files+=("$line")
    done <<<"$listing"
    [ ${#files[@]} -gt 0 ] || exit 0
  fi

  action=$(ui_choose "$EGOMAT_NAME" "What should I do with ${#files[@]} file(s)?" \
    convert-webp "Convert to WebP" \
    convert-avif "Convert to AVIF" \
    convert-jpeg "Convert to JPEG" \
    convert-png "Convert to PNG" \
    convert-gif "Convert to GIF" \
    convert-pdf "Convert to PDF" \
    convert-custom "Convert to…" \
    resize "Resize…" \
    optimize-light "Optimize: light (lossless)" \
    optimize-balanced "Optimize: balanced" \
    optimize-aggressive "Optimize: aggressive" \
    info "Show image details") || exit 0
  [ -n "$action" ] || exit 0

  case $action in
    convert-webp)   cmd_convert -f webp -- "${files[@]}" ;;
    convert-avif)   cmd_convert -f avif -- "${files[@]}" ;;
    convert-jpeg)   cmd_convert -f jpg  -- "${files[@]}" ;;
    convert-png)    cmd_convert -f png  -- "${files[@]}" ;;
    convert-gif)    cmd_convert -f gif  -- "${files[@]}" ;;
    convert-pdf)    cmd_convert -f pdf  -- "${files[@]}" ;;
    convert-custom) _menu_convert_custom "${files[@]}" ;;
    resize)         _menu_resize_ask "${files[@]}" ;;
    optimize-light) cmd_optimize -l light -- "${files[@]}" ;;
    optimize-balanced) cmd_optimize -l balanced -- "${files[@]}" ;;
    optimize-aggressive) cmd_optimize -l aggressive -- "${files[@]}" ;;
    info)           cmd_info -- "${files[@]}" ;;
    *)              die "assistant: unknown action: $action" ;;
  esac
}

# ---------------------------------------------------------------------------
# formats — what this machine can actually do
# ---------------------------------------------------------------------------
cmd_formats() {
  if args_have_help_flag "$@"; then
    usage_formats
    return 0
  fi
  printf 'Target formats: %s\n\n' "$EGOMAT_TARGETS"

  printf 'Conversion backends:\n'
  _fmt_row magick          'ImageMagick 7 (recommended)'
  _fmt_row convert         'ImageMagick 6'
  _fmt_row ffmpeg          'ffmpeg'
  _fmt_row cwebp           'WebP encoder'
  _fmt_row avifenc         'AVIF encoder'
  _fmt_row img2pdf         'PDF from JPEG/PNG'
  _fmt_row rsvg-convert    'SVG renderer (librsvg)'
  _fmt_row inkscape        'SVG renderer (Inkscape)'
  _fmt_row resvg           'SVG renderer (resvg)'

  printf '\nOptimisation backends:\n'
  _fmt_row oxipng          'PNG, lossless'
  _fmt_row optipng         'PNG, lossless'
  _fmt_row zopflipng       'PNG, lossless'
  _fmt_row pngquant        'PNG, lossy quantiser'
  _fmt_row jpegoptim       'JPEG'
  _fmt_row jpegtran        'JPEG, lossless'
  _fmt_row gifsicle        'GIF'
  _fmt_row svgo            'SVG'
  _fmt_row webpmux         'WebP metadata'
  _fmt_row dwebp           'WebP decoder'

  printf '\nDialogs:\n'
  _fmt_row kdialog         'KDE dialogs'
  _fmt_row zenity          'GTK dialogs'
  _fmt_row notify-send     'Desktop notifications'
}

_fmt_row() {
  local tool=$1 note=$2 mark=no
  if have "$tool"; then mark=yes; fi
  printf '  %-14s %-3s %s\n' "$tool" "$mark" "$note"
}

cmd_install() {
  if args_have_help_flag "$@"; then
    usage_install
    return 0
  fi
  if [ ! -f "$EGOMAT_ROOT/install.sh" ]; then
    die "install: $EGOMAT_ROOT/install.sh is missing"
  fi
  exec "$EGOMAT_ROOT/install.sh" "$@"
}

cmd_uninstall() {
  if args_have_help_flag "$@"; then
    usage_uninstall
    return 0
  fi
  if [ ! -f "$EGOMAT_ROOT/uninstall.sh" ]; then
    die "uninstall: $EGOMAT_ROOT/uninstall.sh is missing"
  fi
  exec "$EGOMAT_ROOT/uninstall.sh" "$@"
}

#!/usr/bin/env bash
# egomat — end-to-end smoke test.
#
# Generates test images with ImageMagick and runs the commands the menu uses
# against them, inside a throw-away directory.
#
#   ./tests/smoke.sh
#
# Exits non-zero on the first failed check.

set -o pipefail

ROOT=$(cd -P "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
EGOMAT="$ROOT/bin/egomat"
export EGOMAT_UI=none

# Work whether or not the checked-out files carry the executable bit.
chmod +x "$EGOMAT" "$ROOT/install.sh" "$ROOT/uninstall.sh" 2>/dev/null || true

fails=0
checks=0

pass() { checks=$((checks + 1)); printf '  ok   %s\n' "$1"; }
fail() { checks=$((checks + 1)); fails=$((fails + 1)); printf '  FAIL %s\n' "$1"; }

check() {  # description, command...
  local what=$1
  shift
  if "$@" >/dev/null 2>&1; then pass "$what"; else fail "$what"; fi
}

if ! command -v magick >/dev/null 2>&1 && ! command -v convert >/dev/null 2>&1; then
  echo "smoke: ImageMagick is required to generate the test images" >&2
  exit 77
fi

TMP=$(mktemp -d "${TMPDIR:-/tmp}/egomat-smoke.XXXXXX") || exit 1
trap 'rm -rf -- "$TMP"' EXIT

echo "egomat smoke test in $TMP"

# --- fixtures --------------------------------------------------------------
if command -v magick >/dev/null 2>&1; then IM=magick; else IM=convert; fi
"$IM" -size 640x480 gradient:'#3366ff-#ff9933' "$TMP/photo.png" 2>/dev/null
"$IM" "$TMP/photo.png" -quality 92 "$TMP/photo.jpg" 2>/dev/null
"$IM" -size 300x300 gradient:'#00aa88-#004466' "$TMP/anim.png" 2>/dev/null
"$IM" "$TMP/anim.png" -set delay 10 "$TMP/anim.gif" 2>/dev/null
rm -f -- "$TMP/anim.png"
printf '%s\n' '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">
  <rect width="100" height="100" fill="#7a4dff"/>
  <circle cx="50" cy="50" r="30" fill="#ffffff"/>
</svg>' >"$TMP/logo.svg"

check "test fixtures created" test -s "$TMP/photo.png"
check "version runs" "$EGOMAT" version
check "help runs" "$EGOMAT" help
check "formats runs" "$EGOMAT" formats

# --- per-command help ------------------------------------------------------
check "help convert" "$EGOMAT" help convert
check "help optimize" "$EGOMAT" help optimize
check "help resize" "$EGOMAT" help resize
check "help info" "$EGOMAT" help info
check "help formats" "$EGOMAT" help formats
check "help assistant" "$EGOMAT" help assistant
check "help menu" "$EGOMAT" help menu
check "help install" "$EGOMAT" help install
check "help uninstall" "$EGOMAT" help uninstall
check "help version" "$EGOMAT" help version
check "help help" "$EGOMAT" help help
check "convert --help" "$EGOMAT" convert --help
check "convert -h" "$EGOMAT" convert -h
check "optimize --help" "$EGOMAT" optimize --help
check "optimize -h" "$EGOMAT" optimize -h
check "resize --help" "$EGOMAT" resize --help
check "info --help" "$EGOMAT" info --help
check "formats --help" "$EGOMAT" formats --help
check "assistant --help" "$EGOMAT" assistant --help
check "menu --help" "$EGOMAT" menu --help
check "install --help" "$EGOMAT" install --help
check "uninstall --help" "$EGOMAT" uninstall --help
check "version --help" "$EGOMAT" version --help
check "--help convert" "$EGOMAT" --help convert
check "help convert mentions --format" bash -c \
  "'$EGOMAT' help convert 2>/dev/null | grep -q -- '--format'"
check "help convert shows examples" bash -c \
  "'$EGOMAT' help convert 2>/dev/null | grep -q 'Examples:'"
check "help optimize shows examples" bash -c \
  "'$EGOMAT' help optimize 2>/dev/null | grep -q 'Examples:'"
check "convert --help shows examples" bash -c \
  "'$EGOMAT' convert --help 2>/dev/null | grep -q 'Examples:'"
check "resize --help shows geometry examples" bash -c \
  "'$EGOMAT' resize --help 2>/dev/null | grep -q '1920x1080'"
check "help unknown topic is refused" bash -c \
  "! '$EGOMAT' help nonsense-topic >/dev/null 2>&1"
check "help flag after -- is a filename, not help" bash -c \
  "cd '$TMP' && ! '$EGOMAT' convert -f webp -- --help >/dev/null 2>&1"

# --- shell completions -----------------------------------------------------
check "help completion" "$EGOMAT" help completion
check "completion --help" "$EGOMAT" completion --help
check "completion without a shell is refused" bash -c \
  "! '$EGOMAT' completion >/dev/null 2>&1"
check "completion with an unknown shell is refused" bash -c \
  "! '$EGOMAT' completion powershell >/dev/null 2>&1"
check "completion bash prints a script" bash -c \
  "'$EGOMAT' completion bash | grep -q 'complete -F _egomat_complete'"
check "completion zsh prints a script" bash -c \
  "'$EGOMAT' completion zsh | grep -q '#compdef egomat'"
check "completion fish prints a script" bash -c \
  "'$EGOMAT' completion fish | grep -q 'complete -c egomat'"
check "bash completion script is valid bash" bash -c \
  "'$EGOMAT' completion bash | bash -n"
check "bash completion suggests commands" bash -c "
  source '$ROOT/share/completions/egomat.bash'
  COMP_WORDS=(egomat con); COMP_CWORD=1
  _egomat_complete
  [[ \" \${COMPREPLY[*]} \" == *convert* ]]"
check "bash completion suggests formats" bash -c "
  source '$ROOT/share/completions/egomat.bash'
  COMP_WORDS=(egomat convert -f we); COMP_CWORD=3
  _egomat_complete
  [[ \" \${COMPREPLY[*]} \" == *webp* ]]"
check "bash completion suggests levels" bash -c "
  source '$ROOT/share/completions/egomat.bash'
  COMP_WORDS=(egomat optimize -l ag); COMP_CWORD=3
  _egomat_complete
  [[ \" \${COMPREPLY[*]} \" == *aggressive* ]]"
if command -v zsh >/dev/null 2>&1; then
  check "zsh completion script is valid zsh" bash -c \
    "'$EGOMAT' completion zsh >'$TMP/_egomat' && zsh -n '$TMP/_egomat'"
fi
if command -v fish >/dev/null 2>&1; then
  check "fish completion script is valid fish" bash -c \
    "'$EGOMAT' completion fish | fish -n"
  check "fish completion suggests commands" bash -c \
    "fish -c 'source \"$ROOT/share/completions/egomat.fish\"; complete -C\"egomat con\"' | grep -q convert"
fi
check "installer dry run lists completions" bash -c \
  "'$ROOT/install.sh' --prefix '$TMP/inst' --dry-run | grep -q 'vendor_completions.d'"
check "installer dry run can skip completions" bash -c \
  "! '$ROOT/install.sh' --prefix '$TMP/inst' --no-completions --dry-run | grep -q 'vendor_completions.d'"

# --- dry run ---------------------------------------------------------------
dry="$TMP/dry"
mkdir -p -- "$dry"
cp -- "$TMP/photo.png" "$dry/photo.png"

check "convert dry run shows the plan" bash -c \
  "'$EGOMAT' convert --dry-run -f webp '$dry/photo.png' | grep -q 'would convert'"
check "convert dry run names the output" bash -c \
  "'$EGOMAT' convert --dry-run -f webp '$dry/photo.png' | grep -q 'photo.webp'"
check "convert dry run shows the conflict decision" bash -c \
  "'$EGOMAT' convert --dry-run -f webp '$dry/photo.png' | grep -q 'new file'"
check "convert dry run shows the operation" bash -c \
  "'$EGOMAT' convert --dry-run -f webp -q 80 '$dry/photo.png' | grep -q 'quality 80'"
check "convert dry run writes nothing" bash -c \
  "! test -e '$dry/photo.webp'"
check "convert dry run leaves no temporaries" bash -c \
  "! compgen -G '$dry/.egomat-*' >/dev/null"
check "convert dry run does not create the outdir" bash -c \
  "'$EGOMAT' convert --dry-run -f webp -o '$dry/out' '$dry/photo.png' >/dev/null && ! test -e '$dry/out'"
check "dry run reports a rename when the output exists" bash -c \
  ": > '$dry/photo.webp' && '$EGOMAT' convert --dry-run -f webp '$dry/photo.png' | grep -q 'photo-1.webp'"
check "dry run reports the overwrite decision" bash -c \
  "'$EGOMAT' convert --dry-run -f webp --overwrite '$dry/photo.png' | grep -q 'overwrite existing'"
check "dry run reports the skip decision" bash -c \
  "'$EGOMAT' convert --dry-run -f webp --on-conflict skip '$dry/photo.png' | grep -q 'would skip'"
check "resize dry run shows the geometry" bash -c \
  "'$EGOMAT' resize 800 --dry-run '$dry/photo.png' | grep -q 'resize 800'"
check "resize dry run writes nothing" bash -c \
  "! test -e '$dry/photo-resized.png'"
check "optimize dry run shows the plan" bash -c \
  "'$EGOMAT' optimize --dry-run '$dry/photo.png' | grep -q 'would optimize'"
check "optimize dry run does not touch the source" bash -c \
  "sz=\$(wc -c < '$dry/photo.png') && '$EGOMAT' optimize --dry-run --backup '$dry/photo.png' >/dev/null && [ \"\$sz\" = \"\$(wc -c < '$dry/photo.png')\" ]"
check "optimize dry run mentions the backup" bash -c \
  "'$EGOMAT' optimize --dry-run --backup '$dry/photo.png' | grep -q 'egomat-orig'"
check "optimize dry run creates no backup" bash -c \
  "! compgen -G '$dry/photo.png.egomat-orig*' >/dev/null"
check "optimize dry run writes no copy or outdir" bash -c \
  "'$EGOMAT' optimize --dry-run -o '$dry/opt' '$dry/photo.png' >/dev/null && ! test -e '$dry/opt'"
check "dry run on a missing file fails" bash -c \
  "! '$EGOMAT' convert --dry-run -f webp '$dry/missing.png' >/dev/null 2>&1"
# --- conflict policies -----------------------------------------------------
conf="$TMP/conflict"
mkdir -p -- "$conf"
cp -- "$TMP/photo.png" "$conf/photo.png"

check "on-conflict rename is the default" bash -c \
  "'$EGOMAT' convert -f webp '$conf/photo.png' >/dev/null &&
   '$EGOMAT' convert -f webp '$conf/photo.png' >/dev/null &&
   test -s '$conf/photo.webp' && test -s '$conf/photo-1.webp'"
check "on-conflict rename is explicit" bash -c \
  "'$EGOMAT' convert -f webp --on-conflict rename '$conf/photo.png' >/dev/null &&
   test -s '$conf/photo-2.webp'"
check "on-conflict skip leaves the existing output alone" bash -c \
  "cp '$conf/photo.webp' '$conf/before.webp' &&
   '$EGOMAT' convert -f webp --on-conflict skip '$conf/photo.png' >/dev/null &&
   cmp -s '$conf/photo.webp' '$conf/before.webp'"
check "on-conflict skip writes no new output" bash -c \
  "! compgen -G '$conf/photo-3.webp' >/dev/null"
check "on-conflict skip exits successfully" \
  "$EGOMAT" convert -f webp --on-conflict skip "$conf/photo.png"
check "skipped files are counted separately" bash -c \
  "'$EGOMAT' convert -f webp --on-conflict skip '$conf/photo.png' 2>&1 | grep -q '1 file(s) skipped'"
check "on-conflict overwrite replaces the output" bash -c \
  "'$EGOMAT' convert -f webp --on-conflict overwrite -q 30 '$conf/photo.png' >/dev/null &&
   test -s '$conf/photo.webp' && ! cmp -s '$conf/photo.webp' '$conf/before.webp'"
check "on-conflict overwrite never replaces the source" bash -c \
  "'$EGOMAT' convert -f png --on-conflict overwrite '$conf/photo.png' >/dev/null &&
   test -s '$conf/photo-egomat.png'"
check "unknown conflict policy is refused" bash -c \
  "! '$EGOMAT' convert -f webp --on-conflict nonsense '$conf/photo.png' >/dev/null 2>&1"
check "on-conflict without a value is refused" bash -c \
  "! '$EGOMAT' convert -f webp --on-conflict >/dev/null 2>&1"
check "on-conflict ask is refused without an interactive session" bash -c \
  "! '$EGOMAT' convert -f webp --on-conflict ask '$conf/photo.png' >/dev/null 2>&1 </dev/null"

# Ask is exercised through a fake kdialog: EGOMAT_UI=dialog makes the
# session interactive and ui_choose consults the double, which answers
# with FAKE_DIALOG_ANSWER.
FAKEDIALOG="$TMP/fakedialogs"
mkdir -p -- "$FAKEDIALOG"
cat >"$FAKEDIALOG/kdialog" <<'EOF'
#!/usr/bin/env bash
for arg in "$@"; do
  case $arg in
    --menu) printf '%s\n' "${FAKE_DIALOG_ANSWER:-skip}"; exit 0 ;;
  esac
done
exit 0
EOF
chmod +x "$FAKEDIALOG/kdialog"

check "dry run with ask reports the pending decision" bash -c \
  "env EGOMAT_UI=dialog PATH='$FAKEDIALOG':\"\$PATH\" \
     '$EGOMAT' convert --dry-run -f webp --on-conflict ask '$conf/photo.png' | grep -q 'ask at run time'"
check "dry run with ask writes nothing" bash -c \
  "cp '$conf/photo.webp' '$conf/ask-snap.webp' &&
   env EGOMAT_UI=dialog PATH='$FAKEDIALOG':\"\$PATH\" \
     '$EGOMAT' convert --dry-run -f webp --on-conflict ask '$conf/photo.png' >/dev/null &&
   cmp -s '$conf/photo.webp' '$conf/ask-snap.webp'"
check "on-conflict ask honours the skip answer" bash -c \
  "cp '$conf/photo.webp' '$conf/ask-before.webp' &&
   env EGOMAT_UI=dialog FAKE_DIALOG_ANSWER=skip PATH='$FAKEDIALOG':\"\$PATH\" \
     '$EGOMAT' convert -f webp --on-conflict ask '$conf/photo.png' >/dev/null &&
   cmp -s '$conf/photo.webp' '$conf/ask-before.webp' &&
   ! compgen -G '$conf/photo-3.webp' >/dev/null"
check "on-conflict ask honours the rename answer" bash -c \
  "env EGOMAT_UI=dialog FAKE_DIALOG_ANSWER=rename PATH='$FAKEDIALOG':\"\$PATH\" \
     '$EGOMAT' convert -f webp --on-conflict ask '$conf/photo.png' >/dev/null &&
   test -s '$conf/photo-3.webp'"
check "on-conflict ask honours the overwrite answer" bash -c \
  "env EGOMAT_UI=dialog FAKE_DIALOG_ANSWER=overwrite PATH='$FAKEDIALOG':\"\$PATH\" \
     '$EGOMAT' convert -f webp -q 50 --on-conflict ask '$conf/photo.png' >/dev/null &&
   ! cmp -s '$conf/photo.webp' '$conf/ask-before.webp'"
check "resize honours on-conflict skip" bash -c \
  "'$EGOMAT' resize 200 '$conf/photo.png' >/dev/null &&
   '$EGOMAT' resize 200 --on-conflict skip '$conf/photo.png' >/dev/null &&
   test -s '$conf/photo-resized.png' &&
   ! compgen -G '$conf/photo-resized-1.png' >/dev/null"
check "optimize honours on-conflict skip" bash -c \
  "'$EGOMAT' optimize -l light --force -s -opt '$conf/photo.png' >/dev/null &&
   test -s '$conf/photo-opt.png' &&
   '$EGOMAT' optimize -l light --force -s -opt --on-conflict skip '$conf/photo.png' >/dev/null &&
   ! compgen -G '$conf/photo-opt-1.png' >/dev/null"

# --- hardening -------------------------------------------------------------
# An empty option value must be an error, not a silent default.
check "empty --format value is refused" bash -c \
  "! '$EGOMAT' convert --format= '$conf/photo.png' >/dev/null 2>&1"
check "empty --quality value is refused" bash -c \
  "! '$EGOMAT' convert -f webp --quality= '$conf/photo.png' >/dev/null 2>&1"
check "empty --level value is refused" bash -c \
  "! '$EGOMAT' optimize --level= '$conf/photo.png' >/dev/null 2>&1"

# A successful run must not leave egomat temporaries behind.
check "convert leaves no temporaries" bash -c \
  "! ls '$conf'/'.egomat-'* >/dev/null 2>&1"

# Two egomat runs racing for the same output name must both keep their
# output: the second one claims the next free name instead of clobbering.
conc="$TMP/concurrent"
mkdir -p -- "$conc"
cp "$conf/photo.png" "$conc/shared.png"
"$EGOMAT" convert -f webp "$conc/shared.png" >/dev/null 2>&1 &
p1=$!
"$EGOMAT" convert -f webp "$conc/shared.png" >/dev/null 2>&1 &
p2=$!
wait "$p1" "$p2"
check "concurrent converts keep both outputs" bash -c \
  "test -s '$conc/shared.webp' && test -s '$conc/shared-1.webp'"
check "concurrent convert leaves no temporaries" bash -c \
  "! ls '$conc'/'.egomat-'* >/dev/null 2>&1"

# --- conversion ------------------------------------------------------------
check "png -> webp" "$EGOMAT" convert -f webp "$TMP/photo.png"
check "webp exists" test -s "$TMP/photo.webp"

check "png -> jpg" "$EGOMAT" convert -f jpg "$TMP/photo.png"
check "jpg exists" test -s "$TMP/photo.jpg"

check "jpg -> png (no clobber)" "$EGOMAT" convert -f png "$TMP/photo.jpg"
check "jpg -> png wrote photo-1.png" test -s "$TMP/photo-1.png"

check "convert with resize" "$EGOMAT" convert -f webp -r 320 "$TMP/photo.png" -o "$TMP/out"
check "resized file exists" test -s "$TMP/out/photo.webp"

check "svg -> png" "$EGOMAT" convert -f png "$TMP/logo.svg"
check "svg raster exists" test -s "$TMP/logo.png"

check "same format does not overwrite" "$EGOMAT" convert -f png "$TMP/photo.png"
check "same format wrote -egomat" test -s "$TMP/photo-egomat.png"

check "batch conversion" "$EGOMAT" convert -f webp "$TMP/photo.png" "$TMP/photo.jpg"

check "unknown format is refused" bash -c "! '$EGOMAT' convert -f nonsense '$TMP/photo.png'"
check "bad geometry is refused" bash -c "! '$EGOMAT' convert -f png -r 'abc!' '$TMP/photo.png'"

# --- unusual paths ---------------------------------------------------------
mkdir -p -- "$TMP/space dir"
unusual="$TMP/space dir/odd [x] 'image'.png"
cp -- "$TMP/photo.png" "$unusual"
check "path with spaces and punctuation converts" "$EGOMAT" convert -f webp -- "$unusual"
check "converted unusual path exists" test -s "$TMP/space dir/odd [x] 'image'.webp"
dashdir="$TMP/leading-dash"
mkdir -p -- "$dashdir"
cp -- "$TMP/photo.png" "$dashdir/-odd image.png"
check "leading-dash filename is accepted after --" bash -c \
  "cd '$dashdir' && '$EGOMAT' info -- '-odd image.png'"
check "leading-dash filename converts" bash -c \
  "cd '$dashdir' && '$EGOMAT' convert -f webp -- '-odd image.png'"
check "converted leading-dash file exists" test -s "$dashdir/-odd image.webp"

# --- recursive directory input ---------------------------------------------
tree="$TMP/tree"
mkdir -p -- "$tree/sub/deep" "$tree/only-text" "$tree/.hidden" "$TMP/outside"
cp -- "$TMP/photo.png" "$tree/a.png"
cp -- "$TMP/photo.jpg" "$tree/sub/b.jpg"
cp -- "$TMP/photo.png" "$tree/sub/deep/c.png"
cp -- "$TMP/photo.png" "$tree/sub/with space [x].png"
nlname=$'nl\nname.png'
cp -- "$TMP/photo.png" "$tree/$nlname"
nlout="$TMP/tree-out/nl"$'\n'"name.webp"
printf 'notes\n'  >"$tree/notes.txt"
printf 'readme\n' >"$tree/sub/readme.md"
printf 'info\n'   >"$tree/only-text/info.txt"
cp -- "$TMP/photo.png" "$tree/.hidden/h.png"
cp -- "$TMP/photo.png" "$tree/.h.png"
cp -- "$TMP/photo.png" "$TMP/outside/escape.png"
ln -s -- "$TMP/outside" "$tree/linked-dir"

check "directory without --recursive is refused" bash -c \
  "! '$EGOMAT' convert -f webp '$tree' >/dev/null 2>&1"
check "directory refusal suggests --recursive" bash -c \
  "'$EGOMAT' convert -f webp '$tree' 2>&1 | grep -q 'use --recursive'"
check "recursive convert processes nested images" \
  "$EGOMAT" convert -f webp --recursive -o "$TMP/tree-out" "$tree"
check "recursive convert wrote the nested outputs" bash -c \
  "test -s '$TMP/tree-out/a.webp' && test -s '$TMP/tree-out/b.webp' &&
   test -s '$TMP/tree-out/c.webp' && test -s '$TMP/tree-out/with space [x].webp'"
check "recursive convert handles newlines in file names" test -s "$nlout"
check "recursive convert writes one output per image" bash -c \
  "n=0; for f in '$TMP/tree-out'/*; do [ -f \"\$f\" ] && n=\$((n+1)); done; [ \"\$n\" -eq 5 ]"
check "recursive convert reports skipped inputs in the summary" bash -c \
  "'$EGOMAT' convert -f webp --recursive -o '$TMP/tree-out2' '$tree' 2>&1 | grep -q '3 input(s) skipped'"
check "skipped inputs are reported separately from failures" bash -c \
  "! '$EGOMAT' convert -f webp --recursive -o '$TMP/tree-out3' '$tree' 2>&1 | grep -q 'failed'"
check "skip notices name the skipped file" bash -c \
  "'$EGOMAT' convert -f webp --recursive -o '$TMP/tree-out4' '$tree' 2>&1 | grep -q 'notes.txt'"
check "recursive walk ignores hidden entries" bash -c \
  "! test -e '$TMP/tree-out4/.h.webp' && ! test -e '$TMP/tree-out4/h.webp'"
check "recursive walk does not follow directory symlinks" bash -c \
  "! test -e '$TMP/tree-out4/escape.webp'"

# --- odd file names ---------------------------------------------------------
# Relative names that begin with a dash must not be parsed as options by the
# backends, and a dashed directory must still be walked with --recursive.
dashdir="$TMP/-dashed"
mkdir -p -- "$dashdir"
cp -- "$TMP/photo.png" "$dashdir/inner.png"
cp -- "$TMP/photo.png" "$TMP/-dash.png"
check "info reads a dashed file name" bash -c \
  "cd '$TMP' && '$EGOMAT' info -- -dash.png | grep -q 'pixels'"
check "convert handles a dashed file name" bash -c \
  "cd '$TMP' && '$EGOMAT' convert -f webp -- -dash.png && test -s -dash.webp"
check "optimize accepts a dashed file name" bash -c \
  "cd '$TMP' && '$EGOMAT' optimize -l light -- -dash.png && test -s -dash.png"
check "recursive convert walks a dashed directory" bash -c \
  "cd '$TMP' && '$EGOMAT' convert -f webp --recursive -- -dashed && test -s -dashed/inner.webp"
check "recursive optimize walks a dashed directory" bash -c \
  "cd '$TMP' && '$EGOMAT' optimize -l light --recursive -- -dashed && test -s -dashed/inner.png"
rm -f -- "$TMP/-dash.png" "$TMP/-dash.webp" "$TMP/-dashed/inner.webp"
check "recursive convert of an all-text directory succeeds" bash -c \
  "'$EGOMAT' convert -f webp --recursive -o '$TMP/tree-text' '$tree/only-text' 2>&1 | grep -q '1 input(s) skipped'"
check "explicit non-image file still fails" bash -c \
  "! '$EGOMAT' convert -f webp '$tree/notes.txt' >/dev/null 2>&1"
check "recursive dry run writes nothing" bash -c \
  "'$EGOMAT' convert --dry-run -f webp --recursive -o '$TMP/tree-dry' '$tree' >/dev/null 2>&1 &&
   ! test -e '$TMP/tree-dry'"
check "recursive dry run lists the plan and the skips" bash -c \
  "'$EGOMAT' convert --dry-run -f webp --recursive -o '$TMP/tree-dry' '$tree' | grep -q 'would convert' &&
   '$EGOMAT' convert --dry-run -f webp --recursive -o '$TMP/tree-dry' '$tree' | grep -q 'would skip'"
check "recursive resize processes nested images" bash -c \
  "'$EGOMAT' resize 100 --recursive -o '$TMP/tree-resized' '$tree' >/dev/null 2>&1 &&
   test -s '$TMP/tree-resized/b-resized.jpg' && test -s '$TMP/tree-resized/c-resized.png'"
check "recursive optimize accepts directories" \
  "$EGOMAT" optimize -l light --recursive -o "$TMP/tree-opt" -s -opt "$tree"
check "recursive optimize reports skipped inputs" bash -c \
  "'$EGOMAT' optimize -l light --recursive -o '$TMP/tree-opt2' -s -opt '$tree' 2>&1 | grep -q 'input(s) skipped'"

# --- optimisation ----------------------------------------------------------
if "$EGOMAT" formats 2>/dev/null | grep -q 'oxipng\s*yes\|optipng\s*yes\|pngquant\s*yes'; then
  cp -- "$TMP/photo.png" "$TMP/before.png"
  check "optimize png" "$EGOMAT" optimize -l balanced "$TMP/photo.png"
  check "png still readable after optimize" test -s "$TMP/photo.png"
  check "png did not grow" bash -c \
    "[ \$(stat -c %s '$TMP/photo.png') -le \$(stat -c %s '$TMP/before.png') ]"
else
  echo "  skip png optimisation (no PNG optimiser installed)"
fi

if command -v jpegoptim >/dev/null 2>&1 || command -v jpegtran >/dev/null 2>&1; then
  cp -- "$TMP/photo.jpg" "$TMP/before.jpg"
  check "optimize jpg" "$EGOMAT" optimize -l light "$TMP/photo.jpg"
  check "jpg did not grow" bash -c \
    "[ \$(stat -c %s '$TMP/photo.jpg') -le \$(stat -c %s '$TMP/before.jpg') ]"
else
  echo "  skip jpg optimisation (no JPEG optimiser installed)"
fi

if "$EGOMAT" formats 2>/dev/null | grep -q 'oxipng\s*yes\|optipng\s*yes\|zopflipng\s*yes\|pngquant\s*yes'; then
  check "optimize to outdir" "$EGOMAT" optimize -l light -o "$TMP/opt" "$TMP/photo.png"
  check "optimized copy exists" test -s "$TMP/opt/photo.png"
else
  echo "  skip optimize to outdir (no PNG optimiser installed)"
fi

if "$EGOMAT" formats 2>/dev/null | grep -q 'oxipng\s*yes\|optipng\s*yes\|zopflipng\s*yes\|pngquant\s*yes\|jpegoptim\s*yes\|jpegtran\s*yes\|gifsicle\s*yes\|svgo\s*yes\|cwebp\s*yes\|webpmux\s*yes\|ImageMagick\s*yes'; then
  cp -- "$TMP/photo.png" "$TMP/concurrent.png"
  "$EGOMAT" optimize -l light --force "$TMP/concurrent.png" >/dev/null 2>&1 &
  optimize_pid_1=$!
  "$EGOMAT" optimize -l light --force "$TMP/concurrent.png" >/dev/null 2>&1 &
  optimize_pid_2=$!
  if wait "$optimize_pid_1" && wait "$optimize_pid_2"; then
    pass "concurrent optimization completes"
  else
    fail "concurrent optimization completes"
  fi
  check "concurrently optimized image remains readable" "$EGOMAT" info "$TMP/concurrent.png"
  check "concurrent optimization leaves no temporary files" bash -c \
    "! compgen -G '$TMP/.egomat-*' >/dev/null"
else
  echo "  skip concurrent optimisation (no optimiser installed)"
fi

# Force the PNG optimizer path through controllable test doubles.
FAKEBIN="$TMP/fakebin"
mkdir -p -- "$FAKEBIN"
cat >"$FAKEBIN/oxipng" <<'EOF'
#!/usr/bin/env bash
file=${!#}
case ${OXIPNG_MODE:-success} in
  fail) exit 1 ;;
  empty) : >"$file" ;;
  invalid) printf 'not an image\n' >"$file" ;;
esac
EOF
chmod +x "$FAKEBIN/oxipng"
cat >"$FAKEBIN/cp" <<'EOF'
#!/usr/bin/env bash
for arg in "$@"; do
  case $arg in */.egomat-backup.*) exit 1 ;; esac
done
exec /bin/cp "$@"
EOF
chmod +x "$FAKEBIN/cp"

cp -- "$TMP/photo.png" "$TMP/failure.png"
check "optimizer failure preserves source" env PATH="$FAKEBIN:$PATH" OXIPNG_MODE=fail \
  "$EGOMAT" optimize -l light --force "$TMP/failure.png"
check "source remains readable after optimizer failure" "$EGOMAT" info "$TMP/failure.png"

for bad_output in empty invalid; do
  cp -- "$TMP/photo.png" "$TMP/$bad_output.png"
  if env PATH="$FAKEBIN:$PATH" OXIPNG_MODE="$bad_output" \
    "$EGOMAT" optimize -l light --force "$TMP/$bad_output.png" >/dev/null 2>&1; then
    fail "$bad_output optimizer output is rejected"
  else
    pass "$bad_output optimizer output is rejected"
  fi
  check "$bad_output output leaves original unchanged" cmp -s "$TMP/photo.png" "$TMP/$bad_output.png"
done

cp -- "$TMP/photo.png" "$TMP/no-backup.png"
if env PATH="$FAKEBIN:$PATH" OXIPNG_MODE=success \
  "$EGOMAT" optimize -l light --force --backup "$TMP/no-backup.png" >/dev/null 2>&1; then
  fail "backup write failure stops replacement"
else
  pass "backup write failure stops replacement"
fi
check "backup write failure preserves source" cmp -s "$TMP/photo.png" "$TMP/no-backup.png"

# --- resize ----------------------------------------------------------------
check "resize command" "$EGOMAT" resize 200 "$TMP/photo.png"
check "resized file exists" test -s "$TMP/photo-resized.png"

# --- info ------------------------------------------------------------------
check "info runs" "$EGOMAT" info "$TMP/photo.png"

# --- menu entry points -----------------------------------------------------
check "menu convert" "$EGOMAT" menu convert webp "$TMP/photo.png"
check "menu optimize" "$EGOMAT" menu optimize light "$TMP/photo.png"
check "menu info" "$EGOMAT" menu info "$TMP/photo.png"

# --- installer -------------------------------------------------------------
FAKE="$TMP/prefix"
mkdir -p -- "$FAKE/share/nautilus/scripts/Egomat"
printf 'keep me\n' >"$FAKE/share/nautilus/scripts/Egomat/custom-script"
check "install into a prefix" "$ROOT/install.sh" --prefix "$FAKE" --no-kde
check "installed launcher runs" "$FAKE/bin/egomat" version
check "installed launcher converts" "$FAKE/bin/egomat" convert -f webp "$TMP/photo.png" -o "$TMP/inst"
check "installer rendered the app entry" test -s "$FAKE/share/applications/egomat.desktop"
check "uninstall" "$ROOT/uninstall.sh" --prefix "$FAKE"
check "uninstall removed the launcher" test ! -e "$FAKE/bin/egomat"
check "uninstall preserved pre-existing Egomat script" test -s \
  "$FAKE/share/nautilus/scripts/Egomat/custom-script"

echo
if [ "$fails" -eq 0 ]; then
  echo "all $checks checks passed"
  exit 0
fi
echo "$fails of $checks checks failed"
exit 1

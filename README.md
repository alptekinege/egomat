# Egomat

Egomat is a Bash image converter and optimizer with a command-line interface and
right-click actions for KDE Dolphin and other freedesktop file managers. It can
convert, resize, optimize, and inspect image files. An optional Go companion,
`egomat-gui`, adds a small window and system-tray app on top of the same
commands.

## Install

Run the installer from a checkout:

```sh
bash ./install.sh
```

The default user install puts the command at `~/.local/bin/egomat`, the program
files under `~/.local/lib/egomat`, and desktop actions under the XDG data
directory (usually `~/.local/share`). Add `~/.local/bin` to `PATH` if needed.
Bash, Zsh, and Fish completions are installed into the standard completion
directories; open a new shell to pick them up.

For a system install, use `/usr/local` and its `share` directory:

```sh
sudo bash ./install.sh --system
```

Other installer options:

```sh
bash ./install.sh --prefix "$HOME/opt/egomat"
bash ./install.sh --dry-run
bash ./install.sh --no-kde --no-freedesktop --no-app
bash ./install.sh --no-completions
bash ./install.sh --gui
```

`--prefix DIR` places the program and its data under `DIR`. `--no-kde`,
`--no-freedesktop`, and `--no-app` skip the corresponding integrations, and
`--no-completions` skips the Bash, Zsh, and Fish completions. The
installer also accepts `--user` and `--system`. `--gui` additionally builds and
installs the `egomat-gui` window and tray app, which needs Go 1.23 or newer; see
[Desktop GUI and tray](#desktop-gui-and-tray).

To fetch the current branch's upstream changes and reinstall Egomat, run the
updater from a clean Git checkout:

```sh
bash ./update.sh
bash ./update.sh --system
bash ./update.sh --prefix "$HOME/opt/egomat"
```

It only fast-forwards the current branch and refuses to fetch when the checkout
has changes. Pass `--no-fetch` to reinstall the current local checkout instead.
Installer options such as `--no-kde` and `--no-freedesktop` are passed through;
repeat the options used for the original install. `--dry-run` skips fetching
and previews the install actions.

To remove an install, use the same install mode or prefix:

```sh
bash ./uninstall.sh
sudo bash ./uninstall.sh --system
bash ./uninstall.sh --prefix "$HOME/opt/egomat"
```

The installer records its managed files and directories in a manifest under
the Egomat library directory. Uninstall removes only listed files and removes
listed directories only when they are empty, so unrelated scripts in Nautilus
or Caja `Egomat` directories are preserved. A `--prefix` uninstall checks that
each removal stays within that prefix. For installations made before manifests
were introduced, run `install.sh` once with the same options before uninstalling
so it can record the installed paths.

If the Dolphin submenu does not appear right away, log out and back in, or run
`kbuildsycoca6` (Plasma 6) / `kbuildsycoca5` (Plasma 5).

## Desktop actions

The Egomat submenu and assistant provide these actions:

| Action | Result |
| --- | --- |
| Optimize: light, balanced, or aggressive | Optimizes in place by default; see [Optimization behavior](#optimization-behavior). |
| Convert to WebP, AVIF, JPEG, PNG, GIF, or PDF | Writes a new file next to the source. |
| Convert to… | Prompts for a target format. |
| Resize… | Prompts for ImageMagick-style geometry. |
| Show image details | Reports format, dimensions, and file size when a reader is available. |

## Desktop GUI and tray

`egomat-gui` is a small optional companion written in Go. It never edits images
itself: every job is delegated to the installed `egomat` command, so conversion
and optimization keep the same validation, backup, and replacement behavior as
the command line.

Build it from a checkout (Go 1.23+):

```sh
go build -o build/egomat-gui ./cmd/egomat-gui
```

Or install it alongside the CLI with `bash ./install.sh --gui`, which places it
at `~/.local/bin/egomat-gui` and adds an application-menu entry named
**Egomat Tray**. The binary looks for `egomat` next to itself first, then on
`PATH`, then at `~/.local/bin/egomat`.

The window offers:

- **Add images… / Add folder…** plus drag-and-drop, with a remove/clear list.
- **Convert** to any supported target with a quality slider, output folder, and
  suffix.
- **Optimize** at the `light`, `balanced`, or `aggressive` level, with an
  optional original backup.
- **Resize** using the same ImageMagick-style geometry as `egomat resize`.
- Live output and a desktop notification when a run finishes.

The tray icon gives quick access to show/hide the window, repeat the last
action, and quit. Closing the window keeps the app in the tray; use **Quit** in
the window or the tray menu to exit. Pass `--no-tray` to start with only the
window. Files given on the command line (`egomat-gui photo1.png photo2.jpg`) are
loaded into the list at startup. The last-used action and options are remembered
between runs.

## Command line

```sh
egomat convert -f webp -q 80 -- *.png
egomat convert -f avif -r 1920 -o "$HOME/web" -- images/*.jpg
egomat optimize -l balanced --backup -- photo.jpg
egomat optimize -l aggressive --force -- photo.png
egomat optimize -l light -o optimized -- photo.jpg
egomat resize 1600 -- photo.jpg
egomat info -- shot.png
egomat formats
egomat assistant
```

Use `--` before file names that begin with `-`. Run `egomat help` for the full
command synopsis and option list, `egomat help COMMAND` (for example
`egomat help convert` or `egomat help optimize`) or `egomat COMMAND --help`
(for example `egomat convert --help`) for a command's options and examples.

### Shell completions

The installer places Bash, Zsh, and Fish completions in the standard
completion directories. They cover commands, options, format and
optimization-level values, and file arguments. To install one by hand or to
inspect the script, print it with `egomat completion SHELL`:

```sh
egomat completion bash > ~/.local/share/bash-completion/completions/egomat
egomat completion zsh > ~/.zfunc/_egomat
egomat completion fish > ~/.config/fish/completions/egomat.fish
```

For Zsh, make sure the target directory is on your `fpath` before `compinit`
runs. `egomat help completion` shows the same instructions.

### Convert

Supported targets are `png`, `jpg`/`jpeg`, `webp`, `avif`, `gif`, `bmp`,
`tiff`/`tif`, `ico`, and `pdf`.

```sh
egomat convert --format webp --quality 80 photo.jpg
egomat convert --format png --resize 1200x800 --outdir resized -- photo.jpg
egomat convert --format jpg --keep-metadata photo.png
```

Conversion never writes over the source. By default it leaves the source in
place and writes a new file: `photo.jpg` converted to WebP becomes
`photo.webp`. Converting to the same format uses a `-egomat` name.

When the output name already exists, `--on-conflict POLICY` decides what
happens: `rename` (the default) writes a unique numbered name
(`photo-1.webp`, ...), `skip` writes nothing and reports the file as
skipped, `overwrite` replaces the existing output (never the source), and
`ask` prompts for each file. `ask` is reserved for interactive sessions —
a terminal or desktop dialogs — and is refused otherwise.
`--overwrite` is shorthand for `--on-conflict overwrite`.
`--delete-source` removes the source after a successful conversion.

`--dry-run` shows the plan instead of writing: one line per input with the
source, the planned output name (including any rename or overwrite decision),
the operation, and what would be created. Nothing is written — no outputs,
backups, or temporary files. `resize` and `optimize` accept `--dry-run` as
well.

Metadata is stripped by default where the selected backend supports it.
`--keep-metadata` asks the backend to retain metadata. Backend support varies.
Removing metadata can remove ICC color profiles and change how an image appears
in color-managed applications, even when its pixel data is unchanged.
The conversion command accepts a quality value from 1 to 100 for lossy
formats; the effect and defaults depend on the encoder. ImageMagick defaults
to quality 88 for JPEG, 82 for WebP, and 60 for AVIF. Egomat tries the
available ImageMagick, format-specific, and FFmpeg backends, whose quality
controls are not equivalent. A target can be listed even when this machine
lacks a backend capable of producing it. If all applicable backends fail,
Egomat reports an error and leaves the source and any existing output file
unchanged.

### Resize

Resize writes a new file in the source format, with `-resized` added to the
name by default. `--outdir`, `--suffix`, and `--on-conflict` control the
output; `--dry-run` previews the planned output name and geometry without
writing. Geometry examples include:

```text
1920       width of 1920 pixels, preserve aspect ratio
1920x1080  fit within these dimensions
800x800!   force these exact dimensions
1920x>     shrink only
```

ImageMagick accepts its full geometry syntax. The FFmpeg fallback translates
numeric width and height and `!`; modifiers such as `>`, `<`, `^`, and `%` may
not be honored by that backend.

### Optimization behavior

Optimization works on a temporary copy. Egomat replaces the source, or writes
an output copy, only when the candidate is nonempty, readable as an image, and
smaller than the input. `--force` bypasses only the smaller-file check: the
candidate still must be readable. Without `--force`, a result that is equal in
size or larger is discarded and the source stays unchanged; with `--outdir` or
`--suffix`, no output file is written in that case. When an output copy's name
already exists, `--on-conflict` applies as it does for `convert` (rename by
default). `--dry-run` previews the
plan — target name, level, whether the source would be replaced only if
smaller, and any backup name — and performs none of it.

`--backup` saves the original as `FILE.egomat-orig` before writing a result.
If the backup cannot be created, Egomat stops and does not replace the source
or write the requested output. No backup is made when the candidate is
discarded because it is not smaller.

Validation uses ImageMagick or FFprobe; SVGO can validate SVG output when those
readers are unavailable. If Egomat cannot verify a candidate, it reports an
error and leaves the original in place. Conversion does not use this separate
validation step: its backend must succeed and produce a nonempty output file.

Backend availability is format-specific. If no optimizer is installed at all,
`optimize` stops with an error. If an optimizer exists but none handles the
selected format or level, the candidate may be unchanged and is discarded by
the size check. `egomat formats` lists installed tools; it does not guarantee
that a tool supports every format or that a conversion delegate is available.
`--force` can write an unchanged or larger candidate, but it cannot add a
missing optimizer or reader.

### Optimization levels

The actual operation depends on the installed tools:

| Format | Light | Balanced | Aggressive |
| --- | --- | --- | --- |
| PNG | Lossless recompression if a PNG optimizer is installed | `pngquant` quality 70–95, if installed, then lossless recompression if available | `pngquant` quality 50–80, if installed, then lossless recompression if available |
| JPEG | Metadata stripping and progressive encoding; pixel data is preserved | `jpegoptim` quality 85; if only `jpegtran` is installed, the pass is lossless | `jpegoptim` quality 72; if only `jpegtran` is installed, the pass is lossless |
| WebP | Strip metadata with `webpmux` | Re-encode at quality 82 using `dwebp` and `cwebp` | Re-encode at quality 68 using `dwebp` and `cwebp` |
| GIF | `gifsicle -O3`, lossless | `gifsicle -O3`, lossless | `gifsicle -O3 --lossy=80` |
| SVG | `svgo --multipass` | `svgo --multipass` | `svgo --multipass` |
| Other ImageMagick-supported formats | Re-encode at quality 95; TIFF uses LZW compression | Re-encode at quality 85; TIFF uses LZW compression | Re-encode at quality 70; TIFF uses LZW compression |

`light` preserves pixel data in the PNG, JPEG, WebP, and GIF paths described as
lossless above. The generic ImageMagick path can re-encode pixels even at
`light`. `balanced` and `aggressive` can reduce quality when a lossy backend is
available; PNG only uses lossy quantization when `pngquant` is installed. Keep
`--backup` enabled when you may need to restore the original. Several
optimization backends strip metadata; removing an ICC profile can affect
color-managed display even when the pixel data is preserved.

## Dependencies and capabilities

Egomat requires Bash 4.2+ and common GNU/Linux command-line utilities. It does
not bundle image encoders. Install only the backends you need; `egomat formats`
shows which known commands are present. The optional `egomat-gui` app requires
Go 1.23+ to build and the [Fyne](https://fyne.io) toolkit, which is fetched by
`go build` automatically.

| Task | Optional tools |
| --- | --- |
| Read and re-encode images | ImageMagick 6 (`convert`) or 7 (`magick`) |
| Additional conversion | FFmpeg, `cwebp`, `avifenc`, `img2pdf` |
| Rasterize SVG input | `rsvg-convert`, Inkscape, or `resvg` |
| Optimize PNG | `oxipng`, `optipng`, `zopflipng`, `pngquant` |
| Optimize JPEG, WebP, GIF, SVG | `jpegoptim`, `jpegtran`, `dwebp`/`cwebp`, `webpmux`, `gifsicle`, `svgo` |
| Desktop dialogs | `kdialog` (KDE) or `zenity` (GTK) |

The `assistant` command needs `kdialog` or `zenity`. The `formats` report is a
tool inventory, not a probe of every codec and source/target combination.

## Tests

```sh
bash ./tests/smoke.sh
bash ./tests/real-images.sh                 # uses JPEGs in sample-images/
bash ./tests/real-images.sh /path/to/photos  # use another sample directory
```

The real-image test stages copies in a temporary directory, checks resized PNG
and optional AVIF conversion, and exercises all JPEG optimization levels. It
does not modify the sample files. ImageMagick is required; AVIF conversion and
JPEG optimization are skipped when their backends are unavailable.

## File managers

The installer can add actions for:

- **Dolphin / KDE** — service menu under the Egomat submenu.
- **Nautilus** — scripts under `Egomat` in *Scripts*.
- **Nemo** — actions in the context menu.
- **Thunar** — entries under *Send To*.
- **Caja** — scripts under `Egomat`.

The locations follow `XDG_DATA_HOME` and `XDG_CONFIG_HOME` where applicable.
Every action invokes the same `egomat` command.

## Repository layout

```text
bin/egomat              CLI entry point
lib/egomat-common.sh    logging, path utilities, and accounting
lib/egomat-tools.sh     backend discovery and image helpers
lib/egomat-ui.sh        dialog helpers
lib/egomat-convert.sh   conversion and resize engine
lib/egomat-optimize.sh  optimization engine
lib/egomat-menu.sh      assistant, usage, and format inventory
cmd/egomat-gui/         optional Go window and tray app
share/                  desktop, file-manager, and shell-completion templates
install.sh              installer
update.sh               checkout updater and installer
uninstall.sh            uninstaller
tests/smoke.sh          end-to-end smoke script
tests/real-images.sh    real-photo conversion and optimization checks
```

Run scripts with `bash <script>` if the checkout does not carry executable
bits.

## License

MIT. See [LICENSE](LICENSE).

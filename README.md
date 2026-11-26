# egomat

A right-click **image converter and optimizer** for KDE Plasma (Dolphin, Konqueror)
and other freedesktop file managers, with the same functionality on the command line.

Select images in Dolphin → right-click → **Egomat** → convert to WebP/AVIF/JPEG/PNG/GIF/PDF,
optimize, resize or inspect. It never guesses: every conversion and every optimization
runs on a temporary copy and only replaces your file when the result is valid and smaller.

```
~/.local/share/kio/servicemenus/egomat.desktop   the KDE context menu
~/.local/bin/egomat                              the command
~/.local/lib/egomat/                             the implementation
```

## Install

```sh
git clone <this repo> egomat
cd egomat
bash ./install.sh              # current user, ~/.local
sudo bash ./install.sh --system   # /usr/local, menus in /usr/share
bash ./install.sh --dry-run    # show what would happen
```

Options: `--prefix DIR`, `--no-kde`, `--no-freedesktop`, `--no-app`.
`bash ./uninstall.sh` (same options) removes exactly what was installed.

If the Dolphin submenu does not appear right away, log out and back in, or run
`kbuildsycoca6` (Plasma 6) / `kbuildsycoca5` (Plasma 5).

## What the menu gives you

Under **Egomat** in the context menu:

| Entry | Does |
| --- | --- |
| Optimize (light, lossless) | strips metadata, re-packs the bitstream; no quality change |
| Optimize (balanced) | small, visually invisible quality loss — the everyday choice |
| Optimize (aggressive) | largest savings, still reviewable by eye |
| Optimize… | asks for the level |
| Convert to WebP / AVIF / JPEG / PNG / GIF / PDF | writes a new file next to the original |
| Convert to… | asks for the format |
| Resize… | asks for the new size |
| Show image details | format, pixel size, file size |

Nothing is overwritten: converting `photo.jpg` to WebP produces `photo.webp`, and
`photo.webp` → WebP produces `photo-egomat.webp`.

## Command line

```sh
egomat convert -f webp -q 80 *.png
egomat convert -f avif -r 1920 -o ~/web images/*.jpg
egomat optimize -l aggressive *.png
egomat optimize -l balanced --backup photo.jpg     # keeps photo.jpg.egomat-orig
egomat resize 1600 *.jpg                           # -> *-resized.jpg
egomat info shot.png
egomat formats                                      # what this machine can do
egomat assistant                                    # the same wizard, from a shell
```

`resize GEOMETRY` takes ImageMagick geometry: `1920`, `1920x1080`, `800x800!`
(force), `1920x>` (shrink only).

Run `egomat help` for everything.

## Levels, per format

| Format | light | balanced | aggressive |
| --- | --- | --- | --- |
| PNG | oxipng/optipng, lossless | pngquant 70‑95 + lossless | pngquant 50‑80 + lossless |
| JPEG | jpegoptim; pixels untouched | jpegoptim `-m85`, progressive | jpegoptim `-m72`, progressive |
| WebP | metadata strip only | `cwebp -q 82` | `cwebp -q 68` |
| GIF | `gifsicle -O3` (lossless) | `gifsicle -O3` | `-O3 --lossy=80` |
| SVG | `svgo --multipass` | `svgo --multipass` | `svgo --multipass` |
| AVIF, BMP, TIFF, ICO | ImageMagick re-encode, kept only if smaller | ← | ← |

`light` never touches pixel data. `balanced` and `aggressive` do, on lossy formats.

## Dependencies

Nothing is required and nothing is vendored: egomat uses whatever it finds and says so
when a job cannot be done. `egomat formats` prints the full inventory.

- **Conversion** — ImageMagick 6/7 (`magick`/`convert`), or `ffmpeg`, or the
  format-specific `cwebp`, `avifenc`, `img2pdf`. SVG input is rasterised with
  `rsvg-convert`, Inkscape or `resvg` when available.
- **Optimization** — `oxipng`, `optipng`, `zopflipng`, `pngquant`, `jpegoptim`,
  `jpegtran`, `gifsicle`, `svgo`, `webpmux`, `dwebp`.
- **Dialogs** — `kdialog` (KDE) or `zenity` (GTK); `notify-send` as a fallback.

On Arch: `sudo pacman -S imagemagick oxipng pngquant jpegoptim gifsicle svgo libwebp libavif`
On Debian/Ubuntu: `sudo apt install imagemagick oxipng pngquant jpegoptim gifsicle svgo webp libavif-bin`

## Other file managers

`install.sh` also writes:

- **Nautilus** — `~/.local/share/nautilus/scripts/Egomat/` (a submenu in *Scripts*)
- **Nemo** — `~/.local/share/nemo/actions/egomat-*.nemo_action`
- **Thunar** — `~/.local/share/Thunar/sendto/egomat-*.desktop` (*Send To*)
- **Caja** — `~/.config/caja/scripts/Egomat/`
- a menu entry, `Egomat`, that opens the wizard

All of them call the same `egomat` binary.

## Layout

```
bin/egomat              entry point, option parsing, dispatch
lib/egomat-common.sh    logging, paths, size accounting, summary
lib/egomat-tools.sh     backend discovery (ImageMagick, ffmpeg, ...)
lib/egomat-ui.sh        kdialog/zenity helpers
lib/egomat-convert.sh   conversion engine
lib/egomat-optimize.sh  optimisation engine
lib/egomat-menu.sh      menu actions, wizard, usage, formats
share/kio/              KDE service menu template
share/applications/     .desktop template
share/{nautilus,nemo,thunar}/  file-manager templates
install.sh              installer (renders the templates)
uninstall.sh            remover
tests/smoke.sh          end-to-end check on generated test images
```

The scripts are ordinary bash; run them as `bash <script>` if your copy of the
repository does not carry the executable bit.

## License

MIT. See [LICENSE](LICENSE).

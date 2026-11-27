package main

// egomat-gui — a small window and system-tray companion for the egomat CLI.
// It never touches images itself: every job is delegated to the installed
// egomat command, so all of egomat's safety behavior stays in one place.
//
// SPDX-License-Identifier: MIT

import (
	"context"
	_ "embed"
	"errors"
	"os"
	"path/filepath"
	"strings"

	"fyne.io/fyne/v2"
	"fyne.io/fyne/v2/app"
	"fyne.io/fyne/v2/container"
	"fyne.io/fyne/v2/dialog"
	"fyne.io/fyne/v2/driver/desktop"
	"fyne.io/fyne/v2/storage"
	"fyne.io/fyne/v2/widget"
)

//go:embed icon.png
var iconPNG []byte

const appID = "com.github.alptekinege.egomat.gui"

var imageExts = map[string]bool{
	".png": true, ".jpg": true, ".jpeg": true, ".jfif": true,
	".webp": true, ".avif": true, ".gif": true, ".bmp": true,
	".tif": true, ".tiff": true, ".svg": true, ".svgz": true, ".ico": true,
}

type gui struct {
	app fyne.App
	win fyne.Window

	files     []string
	lastIndex int
	lastJob   *job
	cancel    context.CancelFunc
	running   bool
	trayOn    bool
	visible   bool

	filesList    *widget.List
	actionSelect *widget.Select
	formatSelect *widget.Select
	qualitySlide *widget.Slider
	qualityLabel *widget.Label
	levelSelect  *widget.Select
	geometry     *widget.Entry
	backupCheck  *widget.Check
	outdir       *widget.Entry
	suffix       *widget.Entry
	status       *widget.Label
	log          *widget.Entry
	runBtn       *widget.Button
	cancelBtn    *widget.Button
	trayShow     *fyne.MenuItem
	trayRepeat   *fyne.MenuItem
	trayMenu     *fyne.Menu

	convertPanel  *fyne.Container
	optimizePanel *fyne.Container
	resizePanel   *fyne.Container
}

func main() {
	noTray := false
	var files []string
	for _, arg := range os.Args[1:] {
		switch {
		case arg == "--no-tray":
			noTray = true
		case strings.HasPrefix(arg, "-"):
			// Unknown flags are ignored so the desktop entry can add extras.
		default:
			if p, err := filepath.Abs(arg); err == nil {
				files = append(files, p)
			}
		}
	}

	a := app.NewWithID(appID)
	a.SetIcon(fyne.NewStaticResource("icon.png", iconPNG))

	g := &gui{app: a, files: files}
	g.buildWindow()
	g.setupTray(!noTray)
	g.refreshFiles()
	g.showWindow()
	a.Run()
}

func (g *gui) buildWindow() {
	g.win = g.app.NewWindow("Egomat")
	g.win.SetIcon(fyne.NewStaticResource("icon.png", iconPNG))
	g.win.Resize(fyne.NewSize(580, 660))
	g.win.CenterOnScreen()

	g.filesList = widget.NewList(
		func() int { return len(g.files) },
		func() fyne.CanvasObject { return widget.NewLabel("template") },
		func(id widget.ListItemID, obj fyne.CanvasObject) {
			obj.(*widget.Label).SetText(g.files[id])
		},
	)
	g.filesList.OnSelected = func(id widget.ListItemID) { g.lastIndex = id }

	addBtn := widget.NewButton("Add images…", g.onAddFiles)
	addDirBtn := widget.NewButton("Add folder…", g.onAddFolder)
	removeBtn := widget.NewButton("Remove", g.onRemoveFile)
	clearBtn := widget.NewButton("Clear", g.onClearFiles)

	g.actionSelect = widget.NewSelect([]string{"Convert", "Optimize", "Resize"}, nil)
	g.actionSelect.Selected = "Convert"

	g.formatSelect = widget.NewSelect(
		[]string{"webp", "avif", "jpg", "png", "gif", "bmp", "tiff", "ico", "pdf"}, nil)
	g.formatSelect.Selected = "webp"
	g.formatSelect.OnChanged = func(string) { g.qualitySlide.SetValue(defaultQuality(g.formatSelect.Selected)) }

	g.qualitySlide = widget.NewSlider(1, 100)
	g.qualitySlide.Step = 1
	g.qualitySlide.SetValue(defaultQuality("webp"))
	g.qualityLabel = widget.NewLabel("82")
	g.qualitySlide.OnChanged = func(v float64) {
		g.qualityLabel.SetText(itoa(int(v)))
	}

	g.levelSelect = widget.NewSelect([]string{"light", "balanced", "aggressive"}, nil)
	g.levelSelect.Selected = "balanced"
	g.backupCheck = widget.NewCheck("Keep a backup of the original", nil)

	g.geometry = widget.NewEntry()
	g.geometry.SetPlaceHolder("1920, 1920x1080, 800x800! …")

	g.outdir = widget.NewEntry()
	g.outdir.SetPlaceHolder("next to the source file")
	browseBtn := widget.NewButton("…", g.onBrowseOutdir)

	g.suffix = widget.NewEntry()
	g.suffix.SetPlaceHolder("none")

	g.convertPanel = container.NewVBox(
		widget.NewForm(
			widget.NewFormItem("Format", g.formatSelect),
			widget.NewFormItem("Quality", container.NewBorder(nil, nil, nil, g.qualityLabel, g.qualitySlide)),
		),
	)
	g.optimizePanel = container.NewVBox(
		widget.NewForm(widget.NewFormItem("Level", g.levelSelect)),
		g.backupCheck,
	)
	g.resizePanel = container.NewVBox(
		widget.NewForm(widget.NewFormItem("Size", g.geometry)),
	)
	g.actionSelect.OnChanged = func(string) { g.showOptions() }

	g.status = widget.NewLabel("Ready.")
	g.log = widget.NewMultiLineEntry()
	g.log.Wrapping = fyne.TextWrapBreak
	g.log.Disable()

	g.runBtn = widget.NewButton("Run", g.onRun)
	g.runBtn.Importance = widget.HighImportance
	g.cancelBtn = widget.NewButton("Cancel", g.onCancel)
	g.cancelBtn.Disable()
	quitBtn := widget.NewButton("Quit", func() { g.quit() })

	top := container.NewVBox(
		container.NewBorder(nil, nil, widget.NewLabel("Action:"), g.actionSelect),
		g.convertPanel,
		container.NewBorder(nil, nil, nil, browseBtn, g.outdir),
		container.NewBorder(nil, nil, widget.NewLabel("Suffix:"), nil, g.suffix),
		container.NewHBox(addBtn, addDirBtn, removeBtn, clearBtn),
		widget.NewSeparator(),
	)
	center := container.NewVSplit(g.filesList, g.log)
	center.Offset = 0.55
	bottom := container.NewVBox(
		g.status,
		container.NewHBox(g.runBtn, g.cancelBtn, widget.NewLabel(""), quitBtn),
	)

	g.win.SetContent(container.NewBorder(top, bottom, nil, nil, center))
	g.win.SetOnDropped(func(_ fyne.Position, uris []fyne.URI) {
		for _, u := range uris {
			g.addPath(u.Path())
		}
	})

	pref := g.app.Preferences()
	g.actionSelect.Selected = pref.StringWithFallback("action", "Convert")
	g.formatSelect.Selected = pref.StringWithFallback("format", "webp")
	g.levelSelect.Selected = pref.StringWithFallback("level", "balanced")
	g.geometry.SetText(pref.StringWithFallback("geometry", ""))
	g.outdir.SetText(pref.StringWithFallback("outdir", ""))
	g.suffix.SetText(pref.StringWithFallback("suffix", ""))
	g.backupCheck.SetChecked(pref.BoolWithFallback("backup", false))
	g.qualitySlide.SetValue(defaultQuality(g.formatSelect.Selected))
	g.showOptions()
}

func (g *gui) setupTray(enabled bool) {
	desk, ok := g.app.(desktop.App)
	if !ok || !enabled {
		return
	}
	g.trayOn = true

	g.trayShow = fyne.NewMenuItem("Hide window", func() { g.toggleWindow() })
	g.trayRepeat = fyne.NewMenuItem("Repeat last action", func() { g.repeatLast() })
	g.trayRepeat.Disabled = true

	g.trayMenu = fyne.NewMenu("Egomat",
		g.trayShow,
		g.trayRepeat,
		fyne.NewMenuItemSeparator(),
		&fyne.MenuItem{Label: "Quit Egomat", IsQuit: true, Action: func() { g.quit() }},
	)
	desk.SetSystemTrayIcon(fyne.NewStaticResource("icon.png", iconPNG))
	desk.SetSystemTrayMenu(g.trayMenu)

	// Closing the window keeps the tray alive; quit comes from the tray menu
	// or the Quit button.
	g.win.SetCloseIntercept(func() {
		g.visible = false
		g.win.Hide()
		g.syncTray()
	})
}

func (g *gui) syncTray() {
	if g.trayShow == nil {
		return
	}
	if g.visible {
		g.trayShow.Label = "Hide window"
	} else {
		g.trayShow.Label = "Show window"
	}
	if g.trayRepeat != nil {
		g.trayRepeat.Disabled = g.lastJob == nil
	}
	g.trayShow.Action = func() { g.toggleWindow() }
	if g.trayMenu != nil {
		g.trayMenu.Refresh()
	}
}

func (g *gui) showWindow() {
	g.visible = true
	g.win.Show()
	g.win.RequestFocus()
	g.syncTray()
}

func (g *gui) toggleWindow() {
	if g.visible {
		g.visible = false
		g.win.Hide()
	} else {
		g.showWindow()
		return
	}
	g.syncTray()
}

func (g *gui) quit() {
	if g.cancel != nil {
		g.cancel()
	}
	g.app.Quit()
}

// ---------------------------------------------------------------------------
// File list
// ---------------------------------------------------------------------------

func (g *gui) onAddFiles() {
	d := dialog.NewFileOpen(func(rc fyne.URIReadCloser, err error) {
		if err != nil || rc == nil {
			return
		}
		defer rc.Close()
		g.addPath(rc.URI().Path())
	}, g.win)
	d.SetFilter(storage.NewExtensionFileFilter([]string{
		".png", ".jpg", ".jpeg", ".jfif", ".webp", ".avif",
		".gif", ".bmp", ".tif", ".tiff", ".svg", ".svgz", ".ico",
	}))
	d.Show()
}

func (g *gui) onAddFolder() {
	dialog.ShowFolderOpen(func(dir fyne.ListableURI, err error) {
		if err != nil || dir == nil {
			return
		}
		for _, p := range imagesIn(dir.Path()) {
			g.addPath(p)
		}
		g.refreshFiles()
	}, g.win)
}

func (g *gui) addPath(p string) {
	if p == "" {
		return
	}
	if st, err := os.Stat(p); err == nil && st.IsDir() {
		for _, f := range imagesIn(p) {
			g.addPath(f)
		}
		return
	}
	if !imageExts[strings.ToLower(filepath.Ext(p))] {
		return
	}
	for _, f := range g.files {
		if f == p {
			return
		}
	}
	g.files = append(g.files, p)
	g.refreshFiles()
}

func (g *gui) onRemoveFile() {
	if g.lastIndex < 0 || g.lastIndex >= len(g.files) {
		return
	}
	g.files = append(g.files[:g.lastIndex], g.files[g.lastIndex+1:]...)
	g.lastIndex = -1
	g.refreshFiles()
}

func (g *gui) onClearFiles() {
	g.files = nil
	g.lastIndex = -1
	g.refreshFiles()
}

func (g *gui) refreshFiles() {
	g.filesList.Refresh()
	g.status.SetText(itoa(len(g.files)) + " file(s) selected")
}

// ---------------------------------------------------------------------------
// Options
// ---------------------------------------------------------------------------

func (g *gui) showOptions() {
	g.convertPanel.Hide()
	g.optimizePanel.Hide()
	g.resizePanel.Hide()
	switch g.actionSelect.Selected {
	case "Optimize":
		g.optimizePanel.Show()
	case "Resize":
		g.resizePanel.Show()
	default:
		g.convertPanel.Show()
	}
	g.win.Content().Refresh()
}

func (g *gui) onBrowseOutdir() {
	dialog.ShowFolderOpen(func(dir fyne.ListableURI, err error) {
		if err != nil || dir == nil {
			return
		}
		g.outdir.SetText(dir.Path())
	}, g.win)
}

// ---------------------------------------------------------------------------
// Running jobs
// ---------------------------------------------------------------------------

func (g *gui) currentJob() (*job, string) {
	if len(g.files) == 0 {
		return nil, "add at least one image first"
	}
	j := &job{
		files:    append([]string(nil), g.files...),
		format:   g.formatSelect.Selected,
		quality:  int(g.qualitySlide.Value),
		level:    g.levelSelect.Selected,
		geometry: strings.TrimSpace(g.geometry.Text),
		outDir:   strings.TrimSpace(g.outdir.Text),
		suffix:   strings.TrimSpace(g.suffix.Text),
		backup:   g.backupCheck.Checked,
	}
	switch g.actionSelect.Selected {
	case "Convert":
		j.action = "convert"
	case "Optimize":
		j.action = "optimize"
	case "Resize":
		j.action = "resize"
		if j.geometry == "" {
			return nil, "enter a size first, for example 1920 or 1920x1080"
		}
		if !validGeometry(j.geometry) {
			return nil, "size may only contain digits, x, !, <, >, ^ and %"
		}
	default:
		return nil, "choose an action first"
	}
	return j, ""
}

func (g *gui) onRun() {
	if g.running {
		return
	}
	j, problem := g.currentJob()
	if problem != "" {
		g.status.SetText(problem)
		return
	}

	bin, err := findEgomat()
	if err != "" {
		g.status.SetText(err)
		g.log.SetText(err)
		return
	}

	g.savePrefs()
	g.lastJob = j
	g.log.SetText("")
	g.running = true
	g.runBtn.Disable()
	g.cancelBtn.Enable()
	g.status.SetText("Running egomat " + j.action + "…")

	ctx, cancel := context.WithCancel(context.Background())
	g.cancel = cancel

	go func() {
		err := runJob(ctx, bin, j, func(line string) {
			fyne.Do(func() { g.appendLog(line) })
		})
		fyne.Do(func() { g.finishJob(j, err) })
	}()
}

func (g *gui) repeatLast() {
	if g.lastJob == nil {
		return
	}
	if !g.visible {
		g.showWindow()
	}
	if !g.running {
		g.onRun()
	}
}

func (g *gui) onCancel() {
	if g.cancel != nil {
		g.status.SetText("Cancelling…")
		g.cancel()
	}
}

func (g *gui) finishJob(j *job, err error) {
	g.running = false
	g.cancel = nil
	g.runBtn.Enable()
	g.cancelBtn.Disable()

	text := "Done: " + j.action + " finished."
	if errors.Is(err, context.Canceled) {
		text = "Cancelled."
	} else if err != nil {
		text = "Failed: " + err.Error()
	}
	g.status.SetText(text)
	g.syncTray()

	title := "Egomat"
	if err != nil {
		title = "Egomat — failed"
	}
	g.app.SendNotification(fyne.NewNotification(title, text))
}

func (g *gui) appendLog(line string) {
	if g.log.Text == "" {
		g.log.SetText(line)
	} else {
		g.log.SetText(g.log.Text + "\n" + line)
	}
}

func (g *gui) savePrefs() {
	p := g.app.Preferences()
	p.SetString("action", g.actionSelect.Selected)
	p.SetString("format", g.formatSelect.Selected)
	p.SetString("level", g.levelSelect.Selected)
	p.SetString("geometry", g.geometry.Text)
	p.SetString("outdir", g.outdir.Text)
	p.SetString("suffix", g.suffix.Text)
	p.SetBool("backup", g.backupCheck.Checked)
}

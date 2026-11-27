package main

import (
	"bufio"
	"context"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"strings"
	"sync"
)

type job struct {
	action   string // convert | optimize | resize
	files    []string
	format   string
	quality  int
	level    string
	geometry string
	outDir   string
	suffix   string
	backup   bool
}

var geometryRe = regexp.MustCompile(`^[0-9xX!<>%^]+$`)

func validGeometry(g string) bool { return geometryRe.MatchString(g) }

func defaultQuality(format string) float64 {
	// Match the defaults documented for the CLI backends.
	switch strings.ToLower(format) {
	case "jpg", "jpeg":
		return 88
	case "avif":
		return 60
	default:
		return 82
	}
}

func itoa(i int) string { return fmt.Sprintf("%d", i) }

func findEgomat() (string, string) {
	if exe, err := os.Executable(); err == nil {
		dir := filepath.Dir(exe)
		for _, name := range []string{"egomat", "egomat.exe"} {
			cand := filepath.Join(dir, name)
			if st, err := os.Stat(cand); err == nil && !st.IsDir() {
				return cand, ""
			}
		}
	}
	if p, err := exec.LookPath("egomat"); err == nil {
		return p, ""
	}
	if home, err := os.UserHomeDir(); err == nil {
		cand := filepath.Join(home, ".local", "bin", "egomat")
		if st, err := os.Stat(cand); err == nil && !st.IsDir() {
			return cand, ""
		}
	}
	return "", "egomat is not on PATH. Install the CLI (./install.sh) or place egomat next to egomat-gui."
}

func imagesIn(dir string) []string {
	ents, err := os.ReadDir(dir)
	if err != nil {
		return nil
	}
	var out []string
	for _, e := range ents {
		if e.IsDir() {
			continue
		}
		p := filepath.Join(dir, e.Name())
		if imageExts[strings.ToLower(filepath.Ext(p))] {
			out = append(out, p)
		}
	}
	return out
}

func (j *job) args() []string {
	switch j.action {
	case "convert":
		args := []string{"convert", "-f", j.format}
		if j.quality > 0 {
			args = append(args, "-q", itoa(j.quality))
		}
		if j.outDir != "" {
			args = append(args, "-o", j.outDir)
		}
		if j.suffix != "" {
			args = append(args, "-s", j.suffix)
		}
		return append(args, append([]string{"--"}, j.files...)...)
	case "optimize":
		args := []string{"optimize"}
		if j.level != "" {
			args = append(args, "-l", j.level)
		}
		if j.backup {
			args = append(args, "--backup")
		}
		if j.outDir != "" {
			args = append(args, "-o", j.outDir)
		}
		if j.suffix != "" {
			args = append(args, "-s", j.suffix)
		}
		return append(args, append([]string{"--"}, j.files...)...)
	case "resize":
		// resize takes GEOMETRY first and only accepts "--" directly after
		// it; the GUI always supplies absolute file names, so no "--" is
		// needed before the file list.
		args := []string{"resize", j.geometry}
		if j.outDir != "" {
			args = append(args, "-o", j.outDir)
		}
		if j.suffix != "" {
			args = append(args, "-s", j.suffix)
		}
		return append(args, j.files...)
	default:
		return nil
	}
}

func runJob(ctx context.Context, bin string, j *job, emit func(string)) error {
	args := j.args()
	if len(args) == 0 {
		return errors.New("unknown action")
	}
	cmd := exec.CommandContext(ctx, bin, args...)
	cmd.Env = append(os.Environ(), "NO_COLOR=1")

	stdout, err := cmd.StdoutPipe()
	if err != nil {
		return err
	}
	stderr, err := cmd.StderrPipe()
	if err != nil {
		return err
	}

	if err := cmd.Start(); err != nil {
		return err
	}

	var wg sync.WaitGroup
	stream := func(r *bufio.Scanner) {
		defer wg.Done()
		for r.Scan() {
			emit(r.Text())
		}
	}

	outScan := bufio.NewScanner(stdout)
	errScan := bufio.NewScanner(stderr)
	outScan.Buffer(make([]byte, 64*1024), 1024*1024)
	errScan.Buffer(make([]byte, 64*1024), 1024*1024)
	wg.Add(2)
	go stream(outScan)
	go stream(errScan)
	wg.Wait()

	err = cmd.Wait()
	if errors.Is(ctx.Err(), context.Canceled) {
		return context.Canceled
	}
	if err != nil {
		return fmt.Errorf("egomat %s: %w", j.action, err)
	}
	return nil
}

package main

import (
	"context"
	"reflect"
	"strings"
	"testing"
	"time"
)

func TestJobArgs(t *testing.T) {
	tests := []struct {
		name string
		job  job
		want []string
	}{
		{
			name: "convert with quality and output",
			job: job{
				action: "convert", files: []string{"/tmp/a.png"},
				format: "webp", quality: 80, outDir: "/out", suffix: "-web",
			},
			want: []string{"convert", "-f", "webp", "-q", "80", "-o", "/out", "-s", "-web", "--", "/tmp/a.png"},
		},
		{
			name: "optimize with backup",
			job: job{
				action: "optimize", files: []string{"/tmp/a.jpg"},
				level: "balanced", backup: true,
			},
			want: []string{"optimize", "-l", "balanced", "--backup", "--", "/tmp/a.jpg"},
		},
		{
			name: "resize keeps geometry before files",
			job: job{
				action: "resize", files: []string{"/tmp/a.jpg"},
				geometry: "1920x1080", suffix: "-resized",
			},
			want: []string{"resize", "1920x1080", "-s", "-resized", "/tmp/a.jpg"},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := tt.job.args()
			if !reflect.DeepEqual(got, tt.want) {
				t.Errorf("args() = %v, want %v", got, tt.want)
			}
		})
	}
}

func TestJobArgsUnknownAction(t *testing.T) {
	if got := (&job{action: "nope"}).args(); got != nil {
		t.Errorf("args() = %v, want nil", got)
	}
}

func TestValidGeometry(t *testing.T) {
	valid := []string{"1920", "1920x1080", "1920X1080", "800x800!", "1920x>", "x1080", "50%"}
	for _, g := range valid {
		if !validGeometry(g) {
			t.Errorf("validGeometry(%q) = false, want true", g)
		}
	}
	invalid := []string{"", "abc", "1920;rm -rf /", "-1920"}
	for _, g := range invalid {
		if validGeometry(g) {
			t.Errorf("validGeometry(%q) = true, want false", g)
		}
	}
}

func TestDefaultQuality(t *testing.T) {
	if got := defaultQuality("jpg"); got != 88 {
		t.Errorf("defaultQuality(jpg) = %v, want 88", got)
	}
	if got := defaultQuality("AVIF"); got != 60 {
		t.Errorf("defaultQuality(AVIF) = %v, want 60", got)
	}
	if got := defaultQuality("webp"); got != 82 {
		t.Errorf("defaultQuality(webp) = %v, want 82", got)
	}
}

func TestRunJobReportsMissingBinary(t *testing.T) {
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	j := &job{action: "convert", files: []string{"/tmp/a.png"}, format: "webp"}
	var lines []string
	err := runJob(ctx, "/nonexistent/egomat", j, func(s string) { lines = append(lines, s) })
	if err == nil {
		t.Fatal("runJob() error = nil, want failure for missing binary")
	}
	if strings.Contains(strings.Join(lines, "\n"), "converted") {
		t.Errorf("runJob() emitted success text: %v", lines)
	}
}

// Package bindings finds the key binding files the game saves and reads
// TrailMate's frames from them. It only reads: it never edits the game's
// files.
package bindings

import (
	"os"
	"path/filepath"
	"regexp"
	"sort"
)

// Files are the binding files of every account and character under the
// game folder (_forever_): the account's own set and each character's.
func Files(game string) []string {
	var out []string
	for _, pattern := range []string{
		filepath.Join(game, "WTF", "Account", "*", "bindings-cache.wtf"),
		filepath.Join(game, "WTF", "Account", "*", "*", "*", "bindings-cache.wtf"),
	} {
		found, _ := filepath.Glob(pattern)
		out = append(out, found...)
	}
	sort.Strings(out)
	return out
}

var frameRe = regexp.MustCompile(`CLICK TrailMateCarrier_[0-9A-Za-z_]+:LeftButton`)

// Actions are the TrailMate frames in a binding file's text, in order.
func Actions(text string) []string {
	return frameRe.FindAllString(text, -1)
}

// Stable reads a file twice, a moment apart, and gives its text only if it
// did not change in between: the game may be writing it.
func Stable(path string, wait func()) (string, bool) {
	first, err := os.ReadFile(path)
	if err != nil {
		return "", false
	}
	wait()
	second, err := os.ReadFile(path)
	if err != nil || string(first) != string(second) {
		return "", false
	}
	return string(second), true
}

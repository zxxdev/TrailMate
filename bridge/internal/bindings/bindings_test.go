package bindings

import (
	"os"
	"path/filepath"
	"testing"
)

func TestFindsAccountAndCharacterFiles(t *testing.T) {
	game := t.TempDir()
	account := filepath.Join(game, "WTF", "Account", "ACCOUNT1")
	character := filepath.Join(account, "Realm", "Hunter")
	for _, dir := range []string{account, character} {
		if err := os.MkdirAll(dir, 0o755); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(filepath.Join(dir, "bindings-cache.wtf"), []byte("bind W MOVEFORWARD\n"), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	if got := Files(game); len(got) != 2 {
		t.Fatalf("Files = %v", got)
	}
}

func TestActionsAreOnlyTrailMateFrames(t *testing.T) {
	text := "bind W MOVEFORWARD\n" +
		"bind CTRL-ALT-SHIFT-F5 CLICK TrailMateCarrier_1A2B3C4D_000001_0001_000001_01_01_JVUG63DB_0A1B2C3D:LeftButton\n" +
		"bind CTRL-ALT-SHIFT-F12 CLICK WitchcraftCarrier_V1_X:LeftButton\n"
	got := Actions(text)
	if len(got) != 1 || got[0] != "CLICK TrailMateCarrier_1A2B3C4D_000001_0001_000001_01_01_JVUG63DB_0A1B2C3D:LeftButton" {
		t.Fatalf("Actions = %v", got)
	}
}

func TestStableRefusesAFileBeingWritten(t *testing.T) {
	path := filepath.Join(t.TempDir(), "bindings-cache.wtf")
	_ = os.WriteFile(path, []byte("a"), 0o644)
	if text, ok := Stable(path, func() {}); !ok || text != "a" {
		t.Fatalf("Stable = %q %v", text, ok)
	}
	if _, ok := Stable(path, func() { _ = os.WriteFile(path, []byte("ab"), 0o644) }); ok {
		t.Fatal("a file that changed while reading was taken")
	}
}

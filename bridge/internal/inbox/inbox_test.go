package inbox

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestQuoteKeepsUTF8AndEscapesTheRest(t *testing.T) {
	got := Quote("Ve a \"Grom'gol\"\n\\ ñ\x01")
	want := `"Ve a \"Grom'gol\"\n\\ ñ\001"`
	if got != want {
		t.Fatalf("Quote = %s, want %s", got, want)
	}
}

// testdata/example.lua is also loaded by the addon's tests
// (spec/link_spec.lua), so what the bridge writes is what the addon reads.
func TestLuaMatchesTheExampleTheAddonReads(t *testing.T) {
	e := Envelope{Session: "1A2B3C4D", Ack: 7, Thinking: true, Replies: []Reply{
		{ID: 1, Text: "Haz primero las misiones de Grom'gol: \"Hunt for Yenniku\" y los collares."},
		{ID: 2, Text: "Línea 1\nLínea 2"},
	}}
	want, err := os.ReadFile("testdata/example.lua")
	if err != nil {
		t.Fatal(err)
	}
	if got := Lua(e); got != string(want) {
		if os.Getenv("UPDATE") == "1" {
			_ = os.WriteFile("testdata/example.lua", []byte(got), 0o644)
		}
		t.Fatalf("Lua =\n%s\nwant\n%s", got, want)
	}
}

func TestInitThenWriteAWindow(t *testing.T) {
	dir := t.TempDir()
	if err := Init(dir, 10); err != nil {
		t.Fatal(err)
	}
	if n := Count(dir); n != 10 {
		t.Fatalf("Count = %d", n)
	}
	toc, _ := os.ReadFile(filepath.Join(dir, "TrailMate_Inbox_0003", "TrailMate_Inbox_0003.toc"))
	if !strings.Contains(string(toc), "## LoadOnDemand: 1") || !strings.Contains(string(toc), "## Interface: 16001") {
		t.Fatalf("toc = %s", toc)
	}
	if err := Write(dir, 8, 64, 10, Envelope{Session: "1A2B3C4D", Ack: 2}); err != nil {
		t.Fatal(err)
	}
	for slot, want := range map[string]bool{"TrailMate_Inbox_0007": false, "TrailMate_Inbox_0008": true,
		"TrailMate_Inbox_0010": true} {
		text, _ := os.ReadFile(filepath.Join(dir, slot, "Inbox.lua"))
		if got := strings.Contains(string(text), "ack = 2"); got != want {
			t.Errorf("%s holds the answer: %v, want %v", slot, got, want)
		}
	}
	if _, err := os.Stat(filepath.Join(dir, "TrailMate_Inbox_0011")); err == nil {
		t.Error("wrote past the last inbox")
	}
}

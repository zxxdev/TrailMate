package bridge

import (
	"context"
	"errors"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/zxxdev/trailmate/bridge/internal/companion"
	"github.com/zxxdev/trailmate/bridge/internal/inbox"
	"github.com/zxxdev/trailmate/bridge/internal/link"
)

// A game folder with TrailMate's inboxes and an account's binding file.
func game(t *testing.T) (string, string) {
	t.Helper()
	dir := t.TempDir()
	if err := inbox.Init(filepath.Join(dir, "Interface", "AddOns"), 100); err != nil {
		t.Fatal(err)
	}
	account := filepath.Join(dir, "WTF", "Account", "ACCOUNT1")
	if err := os.MkdirAll(account, 0o755); err != nil {
		t.Fatal(err)
	}
	return dir, filepath.Join(account, "bindings-cache.wtf")
}

// What the game saves when the addon puts these messages on the keys.
func save(t *testing.T, path string, slot int, msgs ...string) {
	t.Helper()
	lines := []string{"bind W MOVEFORWARD"}
	seq := 0
	for i, body := range msgs {
		count := (len(body) + link.MaxPayload - 1) / link.MaxPayload
		for part := 1; part <= count; part++ {
			seq++
			end := part * link.MaxPayload
			if end > len(body) {
				end = len(body)
			}
			f := link.Frame{Session: "1A2B3C4D", Seq: seq, Slot: slot, Msg: i + 1, Part: part, Count: count,
				Payload: []byte(body[(part-1)*link.MaxPayload : end])}
			lines = append(lines, "bind CTRL-ALT-SHIFT-F5 "+link.Action(f))
		}
	}
	if err := os.WriteFile(path, []byte(strings.Join(lines, "\n")+"\n"), 0o644); err != nil {
		t.Fatal(err)
	}
}

func inboxText(t *testing.T, dir string, slot int) string {
	t.Helper()
	text, _ := os.ReadFile(filepath.Join(dir, "Interface", "AddOns", inbox.Name(slot), "Inbox.lua"))
	return string(text)
}

type recorder struct {
	prompts []string
	fail    bool
	resets  int
}

func (r *recorder) Ask(_ context.Context, q string) (string, error) {
	r.prompts = append(r.prompts, q)
	if r.fail {
		return "", errors.New("Not logged in")
	}
	return "Haz las misiones de Grom'gol.", nil
}

func (r *recorder) Reset() { r.resets++ }

var _ companion.Companion = (*recorder)(nil)

func TestAQuestionWithItsContextGetsAnAnswerInTheInboxes(t *testing.T) {
	dir, bindings := game(t)
	r := &recorder{}
	b := New(dir, r, t.Logf)
	b.Pause = func() {}
	if b.Ring != 100 {
		t.Fatalf("Ring = %d", b.Ring)
	}
	save(t, bindings, 7, "CHunter level 34 (Horde), Stranglethorn Vale. Step: Pick up: Hunt for Yenniku",
		"M¿Qué hago ahora?")
	ctx := context.Background()
	if err := b.Step(ctx); err != nil {
		t.Fatal(err)
	}
	// Acknowledged at once, from the inbox the addon announced, while thinking.
	if got := inboxText(t, dir, 7); !strings.Contains(got, "ack = 4") || !strings.Contains(got, "thinking = true") {
		t.Fatalf("inbox 7 = %s", got)
	}
	if got := inboxText(t, dir, 6); strings.Contains(got, "ack") {
		t.Fatalf("inbox 6 was written: %s", got)
	}
	b.Settle()
	if err := b.Step(ctx); err != nil {
		t.Fatal(err)
	}
	got := inboxText(t, dir, 70)
	if !strings.Contains(got, `{ id = 1, text = "Haz las misiones de Grom'gol." }`) || strings.Contains(got, "thinking") {
		t.Fatalf("inbox 70 = %s", got)
	}
	if len(r.prompts) != 1 || !strings.Contains(r.prompts[0], "Stranglethorn Vale") ||
		!strings.HasSuffix(r.prompts[0], "Question: ¿Qué hago ahora?") {
		t.Fatalf("prompts = %q", r.prompts)
	}
	// Reading the same file again asks nothing new.
	b.files = map[string]string{}
	_ = b.Step(ctx)
	b.Settle()
	if len(r.prompts) != 1 {
		t.Fatalf("asked again: %q", r.prompts)
	}
}

func TestAnErrorReachesTheGame(t *testing.T) {
	dir, bindings := game(t)
	r := &recorder{fail: true}
	b := New(dir, r, t.Logf)
	b.Pause = func() {}
	save(t, bindings, 1, "Nnew", "Mhola")
	ctx := context.Background()
	_ = b.Step(ctx)
	b.Settle()
	_ = b.Step(ctx)
	if got := inboxText(t, dir, 1); !strings.Contains(got, `error = "Not logged in"`) {
		t.Fatalf("inbox 1 = %s", got)
	}
	if r.resets != 1 {
		t.Fatalf("resets = %d", r.resets)
	}
}

func TestShortenNeverCutsALetter(t *testing.T) {
	if got := shorten("ñññññ", 6); got != "ñ..." {
		t.Fatalf("shorten = %q", got)
	}
}

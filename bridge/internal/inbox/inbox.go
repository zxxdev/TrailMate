// Package inbox writes answers into the small load-on-demand addons that
// TrailMate loads one by one (TrailMate_Inbox_0001 to _1000). Each holds a
// single call with a table of plain data; TrailMate checks it before use.
package inbox

import (
	"fmt"
	"os"
	"path/filepath"
	"strconv"
	"strings"
)

// Name is an inbox addon's folder and addon name.
func Name(slot int) string {
	return fmt.Sprintf("TrailMate_Inbox_%04d", slot)
}

// Reply is one answer of the companion.
type Reply struct {
	ID   int
	Text string
}

// Envelope is everything an inbox tells the addon.
type Envelope struct {
	Session  string
	Ack      int
	Thinking bool
	Error    string
	Replies  []Reply
}

// Quote writes s as a Lua string literal. Bytes from 128 up (UTF-8) stay
// as they are; quotes, backslashes and control bytes are escaped.
func Quote(s string) string {
	var b strings.Builder
	b.WriteByte('"')
	for i := 0; i < len(s); i++ {
		c := s[i]
		switch {
		case c == '"' || c == '\\':
			b.WriteByte('\\')
			b.WriteByte(c)
		case c == '\n':
			b.WriteString(`\n`)
		case c < 32 || c == 127:
			b.WriteString(`\` + fmt.Sprintf("%03d", c))
		default:
			b.WriteByte(c)
		}
	}
	b.WriteByte('"')
	return b.String()
}

// Lua is the inbox file for an envelope.
func Lua(e Envelope) string {
	var b strings.Builder
	b.WriteString("-- Written by trailmate-bridge. Data only: TrailMate checks it before use.\n")
	b.WriteString("TrailMate_Inbox({ protocol = 1, session = " + Quote(e.Session) + ", ack = " + strconv.Itoa(e.Ack))
	if e.Thinking {
		b.WriteString(", thinking = true")
	}
	if e.Error != "" {
		b.WriteString(", error = " + Quote(e.Error))
	}
	b.WriteString(", replies = {")
	for _, r := range e.Replies {
		b.WriteString("\n  { id = " + strconv.Itoa(r.ID) + ", text = " + Quote(r.Text) + " },")
	}
	b.WriteString("\n} })\n")
	return b.String()
}

const empty = "-- Empty until trailmate-bridge writes here.\n"

func toc(slot int) string {
	return fmt.Sprintf(`## Interface: 16001
## Title: TrailMate inbox %04d
## Notes: Answers from trailmate-bridge for TrailMate. Made by "trailmate-bridge init"; remove them with TrailMate.
## Author: zxxdev
## LoadOnDemand: 1
## Dependencies: TrailMate

Inbox.lua
`, slot)
}

// Init makes the inbox addons 1 to ring in the AddOns folder. The game
// lists addons when it starts, so it must be restarted afterwards.
func Init(addons string, ring int) error {
	for slot := 1; slot <= ring; slot++ {
		dir := filepath.Join(addons, Name(slot))
		if err := os.MkdirAll(dir, 0o755); err != nil {
			return err
		}
		if err := os.WriteFile(filepath.Join(dir, Name(slot)+".toc"), []byte(toc(slot)), 0o644); err != nil {
			return err
		}
		if err := os.WriteFile(filepath.Join(dir, "Inbox.lua"), []byte(empty), 0o644); err != nil {
			return err
		}
	}
	return nil
}

// Count is how many inbox addons there are, from 1 without gaps.
func Count(addons string) int {
	n := 0
	for {
		if _, err := os.Stat(filepath.Join(addons, Name(n+1), "Inbox.lua")); err != nil {
			return n
		}
		n++
	}
}

// Write puts the envelope in the inboxes from slot `from`, `count` of them
// (no further than ring). The addon loads them one at a time and may have
// moved on since it said where it was, so several hold the same answer.
// Each file is replaced in one step, never half written.
func Write(addons string, from, count, ring int, e Envelope) error {
	text := []byte(Lua(e))
	for slot := from; slot < from+count && slot <= ring; slot++ {
		path := filepath.Join(addons, Name(slot), "Inbox.lua")
		tmp := path + ".tmp"
		if err := os.WriteFile(tmp, text, 0o644); err != nil {
			return err
		}
		if err := os.Rename(tmp, path); err != nil {
			return err
		}
	}
	return nil
}

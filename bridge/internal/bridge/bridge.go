// Package bridge joins the pieces: it reads the frames the addon saves in
// the key binding files, asks the companion each question with the
// character's context, and writes the answers into the inbox addons.
package bridge

import (
	"context"
	"path/filepath"
	"strings"
	"sync"
	"time"

	"github.com/zxxdev/trailmate/bridge/internal/bindings"
	"github.com/zxxdev/trailmate/bridge/internal/companion"
	"github.com/zxxdev/trailmate/bridge/internal/inbox"
	"github.com/zxxdev/trailmate/bridge/internal/link"
)

// Window is how many inboxes, from the one the addon announced, get each
// answer (the addon announces again before it runs past them).
const Window = 64

// KeepReplies is how many of the last answers every inbox repeats.
const KeepReplies = 4

// MaxReply is the longest answer the addon takes.
const MaxReply = 4000

type state struct {
	replies  []inbox.Reply
	nextID   int
	context  string
	queue    []string
	asking   bool
	err      string
	dirty    bool
	answered int
}

type answer struct {
	session string
	text    string
	err     error
	took    time.Duration
}

// Bridge is one running bridge for one game folder.
type Bridge struct {
	Game      string // the _forever_ folder
	Addons    string // its Interface/AddOns
	Ring      int    // inbox addons there
	Companion companion.Companion
	Log       func(format string, args ...any)
	Pause     func() // between the two reads of a binding file

	asm      *link.Assembler
	files    map[string]string
	sessions map[string]*state
	answers  chan answer
	inflight sync.WaitGroup
}

// New makes a bridge for a game folder.
func New(game string, c companion.Companion, log func(string, ...any)) *Bridge {
	addons := filepath.Join(game, "Interface", "AddOns")
	return &Bridge{
		Game: game, Addons: addons, Ring: inbox.Count(addons), Companion: c, Log: log,
		Pause:    func() { time.Sleep(150 * time.Millisecond) },
		asm:      link.NewAssembler(),
		files:    map[string]string{},
		sessions: map[string]*state{},
		answers:  make(chan answer, 8),
	}
}

func (b *Bridge) session(id string) *state {
	s := b.sessions[id]
	if s == nil {
		s = &state{nextID: 1}
		b.sessions[id] = s
		b.Log("new game session %s", id)
	}
	return s
}

// Step reads what changed, starts questions, takes answers and writes the
// inboxes that need it. Call it a few times a second.
func (b *Bridge) Step(ctx context.Context) error {
	for _, path := range bindings.Files(b.Game) {
		text, ok := bindings.Stable(path, b.Pause)
		if !ok || text == b.files[path] {
			continue
		}
		b.files[path] = text
		for _, action := range bindings.Actions(text) {
			f, ok := link.Parse(action)
			if !ok {
				continue
			}
			s := b.session(f.Session)
			for _, m := range b.asm.Add(f) {
				b.handle(ctx, s, m)
			}
			// New frames: acknowledge them where the addon now looks.
			s.dirty = true
		}
	}
	for {
		select {
		case a := <-b.answers:
			b.take(ctx, a)
			continue
		default:
		}
		break
	}
	for id, s := range b.sessions {
		if !s.dirty {
			continue
		}
		s.dirty = false
		replies := s.replies
		if len(replies) > KeepReplies {
			replies = replies[len(replies)-KeepReplies:]
		}
		e := inbox.Envelope{Session: id, Ack: b.asm.Ack(id), Thinking: s.asking, Error: s.err, Replies: replies}
		from := b.asm.Slot(id)
		if from < 1 {
			from = 1
		}
		if err := inbox.Write(b.Addons, from, Window, b.Ring, e); err != nil {
			return err
		}
	}
	return nil
}

func (b *Bridge) handle(ctx context.Context, s *state, m link.Message) {
	switch m.Kind {
	case 'C':
		s.context = m.Text
	case 'N':
		b.Companion.Reset()
		b.Log("new conversation")
	case 'M':
		s.queue = append(s.queue, m.Text)
		b.Log("question: %s", m.Text)
	}
	b.ask(ctx, m.Session, s)
}

// One question at a time: the companion keeps one conversation.
func (b *Bridge) ask(ctx context.Context, id string, s *state) {
	if s.asking || len(s.queue) == 0 {
		return
	}
	question := s.queue[0]
	s.queue = s.queue[1:]
	s.asking, s.err, s.dirty = true, "", true
	prompt := question
	if strings.TrimSpace(s.context) != "" {
		prompt = "The character right now (from TrailMate):\n" + s.context + "\n\nQuestion: " + question
	}
	b.inflight.Add(1)
	go func() {
		defer b.inflight.Done()
		start := time.Now()
		ask, cancel := context.WithTimeout(ctx, 3*time.Minute)
		defer cancel()
		text, err := b.Companion.Ask(ask, prompt)
		b.answers <- answer{session: id, text: text, err: err, took: time.Since(start)}
	}()
}

func (b *Bridge) take(ctx context.Context, a answer) {
	s := b.session(a.session)
	s.asking, s.dirty = false, true
	if a.err != nil {
		s.err = shorten(a.err.Error(), 280)
		b.Log("the companion did not answer: %v", a.err)
	} else {
		s.replies = append(s.replies, inbox.Reply{ID: s.nextID, Text: shorten(a.text, MaxReply)})
		s.nextID++
		s.answered++
		b.Log("answer %d in %.1f s", s.answered, a.took.Seconds())
	}
	b.ask(ctx, a.session, s)
}

// Settle waits for the questions in flight (for tests).
func (b *Bridge) Settle() {
	b.inflight.Wait()
}

func shorten(s string, max int) string {
	if len(s) <= max {
		return s
	}
	cut := max - 3
	for cut > 0 && s[cut]&0xC0 == 0x80 { // never in the middle of a UTF-8 letter
		cut--
	}
	return s[:cut] + "..."
}

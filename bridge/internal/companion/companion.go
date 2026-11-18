// Package companion asks the AI companion a question and gives back its
// answer as text. The companion has no tools and no files: it can only
// answer (decision D-44 of the project).
package companion

import (
	"bytes"
	"context"
	"crypto/rand"
	"encoding/json"
	"errors"
	"fmt"
	"os/exec"
	"strings"
	"sync"
)

// Companion answers questions within one conversation.
type Companion interface {
	Ask(ctx context.Context, question string) (string, error)
	// Reset starts a new conversation.
	Reset()
}

// SystemPrompt tells the companion who it is and what it may do.
const SystemPrompt = `You are TrailMate's companion: a friendly, cosy guide at the player's side in World of Warcraft: Forever, an official Blizzard edition of classic World of Warcraft (levels 1 to 60, client 1.60).
Each question comes with the character's current state, read from the game by the TrailMate addon. Use it; never invent quest names, places or numbers you were not given or do not know for classic WoW. When unsure, say so.
You only advise: you cannot act in the game, and you never claim to.
Answer in the language of the question (Spanish from Spain if the player writes in Spanish). The answer is shown in a small in-game window: plain text, no Markdown, no tables, at most six short lines.`

// Echo answers with the question: for checking the link without a model.
type Echo struct{}

// Ask gives the question back.
func (Echo) Ask(_ context.Context, question string) (string, error) {
	return "Eco: " + lastLine(question), nil
}

// Reset does nothing: Echo remembers nothing.
func (Echo) Reset() {}

func lastLine(s string) string {
	lines := strings.Split(strings.TrimSpace(s), "\n")
	return lines[len(lines)-1]
}

// Runner runs a program with stdin in a folder and returns its stdout.
type Runner func(ctx context.Context, dir, name string, args []string, stdin string) ([]byte, error)

// Run is the real Runner.
func Run(ctx context.Context, dir, name string, args []string, stdin string) ([]byte, error) {
	cmd := exec.CommandContext(ctx, name, args...)
	cmd.Dir = dir
	cmd.Stdin = strings.NewReader(stdin)
	var stderr bytes.Buffer
	cmd.Stderr = &stderr
	out, err := cmd.Output()
	if err != nil {
		return out, fmt.Errorf("%s: %w: %s", name, err, strings.TrimSpace(stderr.String()))
	}
	return out, nil
}

// Claude uses the player's own Claude Code (the "claude" program), signed
// in with their own account, in print mode: no tools, no MCP servers, no
// settings, skills or hooks of theirs, in an empty folder of its own.
type Claude struct {
	Program string // "claude" if empty
	Model   string // the CLI's default if empty
	Dir     string // where it runs: an empty folder
	Run     Runner

	mu      sync.Mutex // the conversation is read and changed from two goroutines
	session string
	started bool
	gen     int // grows on Reset: an answer from before it changes nothing
}

func (c *Claude) args(session string, started bool) []string {
	args := []string{"-p", "--output-format", "json", "--tools", "", "--strict-mcp-config", "--safe-mode",
		"--system-prompt", SystemPrompt}
	if c.Model != "" {
		args = append(args, "--model", c.Model)
	}
	if started {
		return append(args, "--resume", session)
	}
	return append(args, "--session-id", session)
}

type result struct {
	Result    string `json:"result"`
	IsError   bool   `json:"is_error"`
	SessionID string `json:"session_id"`
}

// Ask sends the question in the current conversation. It does not hold the
// lock while the model thinks, so Reset never waits for it.
func (c *Claude) Ask(ctx context.Context, question string) (string, error) {
	c.mu.Lock()
	if c.session == "" {
		c.session = newUUID()
	}
	session, started, gen := c.session, c.started, c.gen
	c.mu.Unlock()
	program := c.Program
	if program == "" {
		program = "claude"
	}
	run := c.Run
	if run == nil {
		run = Run
	}
	out, err := run(ctx, c.Dir, program, c.args(session, started), question)
	if err != nil {
		return "", err
	}
	var r result
	if err := json.Unmarshal(out, &r); err != nil {
		return "", fmt.Errorf("claude gave no answer: %w", err)
	}
	if r.IsError || strings.TrimSpace(r.Result) == "" {
		return "", errors.New("claude: " + firstLine(r.Result))
	}
	c.mu.Lock()
	if c.gen == gen { // no Reset meanwhile: this conversation goes on
		c.started = true
		if r.SessionID != "" {
			c.session = r.SessionID
		}
	}
	c.mu.Unlock()
	return strings.TrimSpace(r.Result), nil
}

// Reset starts a new conversation, even while a question is in flight.
func (c *Claude) Reset() {
	c.mu.Lock()
	c.session, c.started = "", false
	c.gen++
	c.mu.Unlock()
}

func firstLine(s string) string {
	s = strings.TrimSpace(s)
	if i := strings.IndexByte(s, '\n'); i >= 0 {
		return s[:i]
	}
	if s == "" {
		return "empty answer"
	}
	return s
}

func newUUID() string {
	var b [16]byte
	_, _ = rand.Read(b[:])
	b[6] = b[6]&0x0f | 0x40
	b[8] = b[8]&0x3f | 0x80
	return fmt.Sprintf("%x-%x-%x-%x-%x", b[0:4], b[4:6], b[6:8], b[8:10], b[10:16])
}

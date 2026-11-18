package companion

import (
	"context"
	"errors"
	"strings"
	"testing"
)

type call struct {
	dir, name string
	args      []string
	stdin     string
}

func fake(answers ...string) (*[]call, Runner) {
	calls := &[]call{}
	return calls, func(_ context.Context, dir, name string, args []string, stdin string) ([]byte, error) {
		*calls = append(*calls, call{dir, name, args, stdin})
		if len(*calls) > len(answers) {
			return nil, errors.New("no more answers")
		}
		return []byte(answers[len(*calls)-1]), nil
	}
}

func value(args []string, flag string) (string, bool) {
	for i, a := range args {
		if a == flag && i+1 < len(args) {
			return args[i+1], true
		}
	}
	return "", false
}

func TestClaudeHasNoToolsAndKeepsTheConversation(t *testing.T) {
	calls, run := fake(
		`{"type":"result","is_error":false,"result":"Haz las misiones de Grom'gol.","session_id":"s-1"}`,
		`{"type":"result","is_error":false,"result":"Después, Nesingwary.","session_id":"s-1"}`)
	c := &Claude{Dir: "/empty", Run: run}
	answer, err := c.Ask(context.Background(), "¿Qué hago?")
	if err != nil || answer != "Haz las misiones de Grom'gol." {
		t.Fatalf("Ask = %q, %v", answer, err)
	}
	first := (*calls)[0]
	if first.name != "claude" || first.dir != "/empty" || first.stdin != "¿Qué hago?" {
		t.Fatalf("first call = %+v", first)
	}
	// No tools at all, no MCP servers, none of the player's settings.
	if tools, ok := value(first.args, "--tools"); !ok || tools != "" {
		t.Fatalf("--tools = %q (%v)", tools, ok)
	}
	for _, flag := range []string{"--strict-mcp-config", "--safe-mode", "-p"} {
		if !strings.Contains(" "+strings.Join(first.args, " ")+" ", " "+flag+" ") {
			t.Errorf("missing %s in %v", flag, first.args)
		}
	}
	if _, ok := value(first.args, "--session-id"); !ok {
		t.Error("the first question does not start a conversation")
	}
	if _, err := c.Ask(context.Background(), "¿Y luego?"); err != nil {
		t.Fatal(err)
	}
	if id, ok := value((*calls)[1].args, "--resume"); !ok || id != "s-1" {
		t.Fatalf("the second question does not continue the conversation: %v", (*calls)[1].args)
	}
	c.Reset()
	_, _ = c.Ask(context.Background(), "otra")
	if _, ok := value((*calls)[2].args, "--resume"); ok {
		t.Fatal("Reset kept the old conversation")
	}
}

func TestClaudeErrorsAreErrors(t *testing.T) {
	_, run := fake(`{"type":"result","is_error":true,"result":"Not logged in\nPlease run /login"}`, `not json`)
	c := &Claude{Run: run}
	if _, err := c.Ask(context.Background(), "hola"); err == nil || !strings.Contains(err.Error(), "Not logged in") {
		t.Fatalf("err = %v", err)
	}
	if _, err := c.Ask(context.Background(), "hola"); err == nil {
		t.Fatal("an answer that is not JSON was taken")
	}
}

func TestEchoGivesTheQuestionBack(t *testing.T) {
	got, _ := Echo{}.Ask(context.Background(), "Character: hunter 34\n\nQuestion: hola")
	if got != "Eco: Question: hola" {
		t.Fatalf("Echo = %q", got)
	}
}

// "New conversation" pressed while Claude thinks: the answer that arrives
// afterwards must not bring the old conversation back.
func TestResetDuringAQuestionStartsANewConversation(t *testing.T) {
	var calls [][]string
	c := &Claude{}
	c.Run = func(_ context.Context, _, _ string, args []string, _ string) ([]byte, error) {
		calls = append(calls, args)
		if len(calls) == 1 {
			c.Reset() // the player starts a new conversation meanwhile
		}
		return []byte(`{"type":"result","is_error":false,"result":"ok","session_id":"old"}`), nil
	}
	if _, err := c.Ask(context.Background(), "uno"); err != nil {
		t.Fatal(err)
	}
	if _, err := c.Ask(context.Background(), "dos"); err != nil {
		t.Fatal(err)
	}
	if id, ok := value(calls[1], "--resume"); ok {
		t.Fatalf("the old conversation came back: --resume %s", id)
	}
}

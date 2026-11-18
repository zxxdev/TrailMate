// trailmate-bridge lets you talk to your AI companion from inside the game.
// It runs on the PC next to World of Warcraft: Forever, reads the questions
// TrailMate saves through the game's key bindings, asks the companion, and
// writes the answers into small inbox addons that TrailMate loads.
//
//	trailmate-bridge init --game "C:\...\World of Warcraft\_forever_"
//	trailmate-bridge run  --game "C:\...\World of Warcraft\_forever_" [--companion claude|echo]
package main

import (
	"context"
	"errors"
	"flag"
	"fmt"
	"os"
	"os/signal"
	"path/filepath"
	"time"

	"github.com/zxxdev/trailmate/bridge/internal/bindings"
	"github.com/zxxdev/trailmate/bridge/internal/bridge"
	"github.com/zxxdev/trailmate/bridge/internal/companion"
	"github.com/zxxdev/trailmate/bridge/internal/inbox"
)

// version is set by the release build.
var version = "dev"

const usage = `trailmate-bridge %s: talk to your AI companion from inside the game.

  trailmate-bridge init --game <folder> [--ring 1000]
      Makes the inbox addons TrailMate reads answers from. Once; then
      restart the game.
  trailmate-bridge run --game <folder> [--companion claude|echo] [--model <name>]
      Listens while you play. Stop it with Ctrl+C.
  trailmate-bridge version

<folder> is the game's _forever_ folder (the one with Interface and WTF).
The companion "claude" is your own Claude Code, signed in with your
account, with no tools. "echo" answers with your question, to check the link.
`

func main() {
	if err := run(os.Args[1:]); err != nil {
		fmt.Fprintln(os.Stderr, "trailmate-bridge:", err)
		os.Exit(1)
	}
}

func gameFolder(game string) (string, error) {
	if game == "" {
		return "", errors.New("say where the game is: --game <the _forever_ folder>")
	}
	if _, err := os.Stat(filepath.Join(game, "Interface", "AddOns")); err != nil {
		return "", fmt.Errorf("%s has no Interface\\AddOns: is it the _forever_ folder?", game)
	}
	return game, nil
}

func run(args []string) error {
	if len(args) == 0 {
		fmt.Printf(usage, version)
		return nil
	}
	switch args[0] {
	case "version":
		fmt.Println("trailmate-bridge", version)
		return nil
	case "init":
		fs := flag.NewFlagSet("init", flag.ContinueOnError)
		game := fs.String("game", "", "the game's _forever_ folder")
		ring := fs.Int("ring", 1000, "how many inbox addons")
		if err := fs.Parse(args[1:]); err != nil {
			return err
		}
		dir, err := gameFolder(*game)
		if err != nil {
			return err
		}
		if *ring < 10 || *ring > 9999 {
			return errors.New("--ring goes from 10 to 9999")
		}
		addons := filepath.Join(dir, "Interface", "AddOns")
		if _, err := os.Stat(filepath.Join(addons, "TrailMate")); err != nil {
			fmt.Println("Note: TrailMate is not in", addons, "yet; the inboxes need it.")
		}
		if err := inbox.Init(addons, *ring); err != nil {
			return err
		}
		fmt.Printf("Made %d inbox addons in %s.\nRestart the game so it sees them, then run: trailmate-bridge run --game %q\n",
			*ring, addons, dir)
		return nil
	case "run":
		fs := flag.NewFlagSet("run", flag.ContinueOnError)
		game := fs.String("game", "", "the game's _forever_ folder")
		which := fs.String("companion", "claude", "claude or echo")
		model := fs.String("model", "", "model for claude (its default if empty)")
		program := fs.String("claude", "claude", "the claude program")
		if err := fs.Parse(args[1:]); err != nil {
			return err
		}
		dir, err := gameFolder(*game)
		if err != nil {
			return err
		}
		var c companion.Companion
		switch *which {
		case "echo":
			c = companion.Echo{}
		case "claude":
			// An empty folder of its own: nothing there to read.
			cache, err := os.UserCacheDir()
			if err != nil {
				return err
			}
			work := filepath.Join(cache, "TrailMateBridge", "companion")
			if err := os.MkdirAll(work, 0o700); err != nil {
				return err
			}
			c = &companion.Claude{Program: *program, Model: *model, Dir: work}
		default:
			return fmt.Errorf("unknown companion %q: claude or echo", *which)
		}
		return listen(dir, c, *which)
	default:
		fmt.Printf(usage, version)
		return fmt.Errorf("unknown command %q", args[0])
	}
}

func listen(game string, c companion.Companion, name string) error {
	logf := func(format string, a ...any) {
		fmt.Printf("%s  %s\n", time.Now().Format("15:04:05"), fmt.Sprintf(format, a...))
	}
	b := bridge.New(game, c, logf)
	if b.Ring == 0 {
		return errors.New("no inbox addons: run trailmate-bridge init first, then restart the game")
	}
	files := bindings.Files(game)
	logf("listening: %d binding files, %d inboxes, companion %s. Ctrl+C stops.", len(files), b.Ring, name)
	if len(files) == 0 {
		logf("no bindings-cache.wtf yet: it appears when you open the chat in the game")
	}
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt)
	defer stop()
	tick := time.NewTicker(250 * time.Millisecond)
	defer tick.Stop()
	for {
		select {
		case <-ctx.Done():
			logf("stopped")
			return nil
		case <-tick.C:
			if err := b.Step(ctx); err != nil {
				logf("error: %v", err)
			}
		}
	}
}
